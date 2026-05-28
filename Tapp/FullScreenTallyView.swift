//
//  FullScreenTallyView.swift
//  Tapp
//
//  Per-tally screen: huge tap area for incrementing, plus inline editors for
//  name and count, plus the bottom button row (Color, Friends, Resets,
//  Fireworks, Delete). Owner-only buttons are hidden for non-owners.
//

import SwiftUI
import FirebaseFirestore

struct FullScreenTallyView: View {
    let profile: UserProfile
    let initialTally: Tally
    let store: TallyStore
    let friendsStore: FriendsStore
    let directory: UserDirectory
    let onDismiss: () -> Void

    @State private var draftName: String = ""
    @State private var draftCount: String = ""
    @State private var isEditingName: Bool = false
    @State private var isEditingCount: Bool = false
    @State private var nudge: Int = 0
    @State private var fireworksPlayback = FireworksPlayback()

    @State private var showingColor: Bool = false
    @State private var showingPermissions: Bool = false
    @State private var showingResets: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var isTogglingFireworks: Bool = false

    @State private var backgroundTint: Color = .accentColor.opacity(0.18)
    @State private var errorMessage: String?

    @FocusState private var nameFieldFocused: Bool
    @FocusState private var countFieldFocused: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var arabicCountFontSize: CGFloat = 120
    @ScaledMetric(relativeTo: .title) private var stickDisplayMaxHeight: CGFloat = 220

    private var currentTally: Tally {
        store.tallies.first(where: { $0.id == initialTally.id }) ?? initialTally
    }

    private var role: TallyRole {
        currentTally.role(for: store.currentUid)
    }

    private var tallyId: String { currentTally.id ?? "" }

    private var numberType: String { profile.resolvedNumberType }

    private var countDisplayText: String {
        CountFormatter.string(for: currentTally.count, numberType: numberType)
    }

    private var isStickCount: Bool { numberType == UserNumberType.stick }

    var body: some View {
        ZStack {
            backgroundTint
                .ignoresSafeArea()

            FireworksOverlay(playback: fireworksPlayback)

            VStack(spacing: 0) {
                topBar
                incrementArea
                bottomButtonRow
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 60 && abs(value.translation.width) < 80 {
                        onDismiss()
                    }
                }
        )
        .sheet(isPresented: $showingColor) {
            ColorPickerSheet(tallyId: tallyId) {
                backgroundTint = LocalTallyColors.backgroundTint(for: tallyId)
            }
        }
        .onAppear {
            backgroundTint = LocalTallyColors.backgroundTint(for: tallyId)
        }
        .sheet(isPresented: $showingPermissions) {
            permissionsSheet
        }
        .sheet(isPresented: $showingResets) {
            TallyResetSheet(tally: currentTally, store: store)
        }
        .alert(deleteAlertTitle, isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(deleteAlertButton, role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var incrementArea: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            nameView
                .padding(.bottom, 12)
            countView
                .padding(.bottom, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Increment")
        .accessibilityValue(TallyAccessibility.countDescription(count: currentTally.count, numberType: numberType))
        .accessibilityHint(role.canIncrement ? "Double tap to add one." : "View only.")
        .onTapGesture {
            handleIncrementTap()
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Back")
            Spacer()
            ownerBadge
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var ownerBadge: some View {
        let ownerUid = currentTally.owner.documentID
        let summary = directory.cached(uid: ownerUid)
        HStack(spacing: 6) {
            AvatarBadge(summary: summary, size: 24)
            Text(summary?.displayUsername ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task {
            await directory.fetch(uid: ownerUid)
        }
    }

    // MARK: - Name

    @ViewBuilder
    private var nameView: some View {
        if isEditingName {
            TextField("Name", text: $draftName)
                .focused($nameFieldFocused)
                .multilineTextAlignment(.center)
                .font(.title.bold())
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .onSubmit { commitName() }
                .onAppear {
                    draftName = currentTally.name
                    nameFieldFocused = true
                }
        } else {
            Text(currentTally.name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Edit Name") {
                    guard role.canRename else {
                        triggerShake()
                        return
                    }
                    impactLight()
                    isEditingName = true
                }
                .onLongPressGesture(minimumDuration: TappDesignMetrics.longPressDuration) {
                    guard role.canRename else {
                        triggerShake()
                        return
                    }
                    impactLight()
                    isEditingName = true
                }
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        nameFieldFocused = false
        isEditingName = false
        guard !trimmed.isEmpty, trimmed != currentTally.name else { return }
        Task {
            do {
                try await store.rename(currentTally, to: String(trimmed.prefix(40)))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Count

    @ViewBuilder
    private var countView: some View {
        if isEditingCount {
            TextField("Count", text: $draftCount)
                .focused($countFieldFocused)
                .multilineTextAlignment(.center)
                .font(.system(size: 96, weight: .bold).monospacedDigit())
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitCount() }
                .onAppear {
                    draftCount = String(currentTally.count)
                    countFieldFocused = true
                }
        } else if isStickCount {
            GeometryReader { geometry in
                StickTallyView(
                    count: currentTally.count,
                    style: .fullScreen(
                        maxWidth: geometry.size.width,
                        maxHeight: stickDisplayMaxHeight
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80, maxHeight: stickDisplayMaxHeight)
            .padding(.horizontal, 8)
            .shake(times: nudge)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Edit Count") {
                beginEditingCount()
            }
            .onLongPressGesture(minimumDuration: TappDesignMetrics.longPressDuration) {
                beginEditingCount()
            }
        } else {
            Text(countDisplayText)
                .font(.system(size: arabicCountFontSize, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.35)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .shake(times: nudge)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Edit Count") {
                    beginEditingCount()
                }
                .onLongPressGesture(minimumDuration: TappDesignMetrics.longPressDuration) {
                    beginEditingCount()
                }
        }
    }

    private func beginEditingCount() {
        guard role.canEditCount else {
            triggerShake()
            return
        }
        impactLight()
        isEditingCount = true
    }

    private func commitCount() {
        let trimmed = draftCount.trimmingCharacters(in: .whitespacesAndNewlines)
        countFieldFocused = false
        isEditingCount = false
        guard let value = Int(trimmed), value != currentTally.count else { return }
        Task {
            do {
                try await store.setCount(currentTally, to: value)
                triggerFireworksIfEnabled()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Bottom buttons

    private var bottomButtonRow: some View {
        HStack(spacing: 12) {
            circleButton(systemImage: "paintpalette.fill", label: "Color") {
                showingColor = true
            }

            if role.isOwner {
                circleButton(systemImage: "person.2.fill", label: "Friends and Permissions") {
                    showingPermissions = true
                }

                circleButton(systemImage: "clock.fill", label: "One-time or scheduled resets") {
                    showingResets = true
                }

                fireworksButton
            }

            circleButton(systemImage: "trash.fill", label: deleteAccessibilityLabel) {
                showingDeleteConfirm = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fireworksButton: some View {
        let enabled = currentTally.effectiveFireworksEnabled
        return Button {
            toggleFireworks()
        } label: {
            ZStack {
                Circle()
                    .fill(enabled ? Color.accentColor : Color(.tertiarySystemBackground))
                    .frame(width: TappDesignMetrics.circularControlSize, height: TappDesignMetrics.circularControlSize)
                Image(systemName: "sparkles")
                    .font(.system(size: TappDesignMetrics.circularControlIconSize, weight: .semibold))
                    .foregroundStyle(enabled ? Color.white : Color.primary)
            }
        }
        .disabled(isTogglingFireworks)
        .accessibilityLabel("Fireworks")
        .accessibilityValue(enabled ? "On" : "Off")
        .accessibilityHint("Double tap to toggle fireworks on increments")
    }

    @ViewBuilder
    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: TappDesignMetrics.circularControlSize, height: TappDesignMetrics.circularControlSize)
                Image(systemName: systemImage)
                    .font(.system(size: TappDesignMetrics.circularControlIconSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel(label)
    }

    private func toggleFireworks() {
        guard role.isOwner else { return }
        isTogglingFireworks = true
        let next = !currentTally.effectiveFireworksEnabled
        Task {
            do {
                try await store.setFireworksEnabled(currentTally, enabled: next)
            } catch {
                errorMessage = error.localizedDescription
            }
            isTogglingFireworks = false
        }
    }

    // MARK: - Permissions sheet

    private var permissionsSheet: some View {
        PerTallyPermissionsSheet(
            tally: currentTally,
            store: store,
            friendsStore: friendsStore,
            directory: directory
        )
    }

    // MARK: - Increment

    private func handleIncrementTap() {
        guard !isEditingName, !isEditingCount else { return }
        guard role.canIncrement else {
            triggerShake()
            return
        }
        Task {
            do {
                try await store.increment(currentTally)
                triggerFireworksIfEnabled()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func triggerFireworksIfEnabled() {
        guard currentTally.effectiveFireworksEnabled else { return }
        fireworksPlayback.trigger()
    }

    private func triggerShake() {
        withAnimation(.linear(duration: 0.3)) {
            nudge &+= 1
        }
    }

    private func impactLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Delete

    private var deleteAccessibilityLabel: String {
        role.isOwner ? "Delete tally" : "Remove from my list"
    }

    private var deleteAlertTitle: String {
        role.isOwner ? "Delete tally?" : "Remove from your list?"
    }

    private var deleteAlertButton: String {
        role.isOwner ? "Delete" : "Remove"
    }

    private var deleteAlertMessage: String {
        if role.isOwner {
            return "This deletes the tally for you and every friend you've shared it with."
        } else {
            return "The owner and other friends keep the tally on their lists."
        }
    }

    private func performDelete() async {
        do {
            if role.isOwner {
                try await store.deleteTally(currentTally)
            } else {
                try await store.removeFromMyList(currentTally)
            }
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

// MARK: - Per-tally permissions sheet (owner-only)

private struct PerTallyPermissionsSheet: View {
    let tally: Tally
    let store: TallyStore
    let friendsStore: FriendsStore
    let directory: UserDirectory

    @Environment(\.dismiss) private var dismiss

    @State private var table: PermissionsTable = .init(friendUids: [], permissions: [:])
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Share with")
                    .font(.headline)

                PermissionsTableEditor(table: $table, directory: directory)
                    .frame(maxHeight: 360)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .navigationTitle(tally.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(isSaving)
                }
            }
        }
        .task {
            table = PermissionsTable(
                friendUids: friendsStore.friendUids,
                permissions: tally.perms
            )
            await directory.prefetch(friendsStore.friendRefs)
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await store.setPermissions(tally, permissions: table.permissions)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
