//
//  FullScreenTallyView.swift
//  Tapp
//
//  Per-tally screen: huge tap area for incrementing, plus inline editors for
//  name and count, plus the bottom button row (Color, Friends and Permissions,
//  Delete). Owner-only buttons are hidden for non-owners; view-only users get
//  a shake on tap.
//

import SwiftUI
import FirebaseFirestore

struct FullScreenTallyView: View {
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

    @State private var showingColor: Bool = false
    @State private var showingPermissions: Bool = false
    @State private var showingDeleteConfirm: Bool = false

    @State private var backgroundTint: Color = .accentColor.opacity(0.18)
    @State private var errorMessage: String?

    @FocusState private var nameFieldFocused: Bool
    @FocusState private var countFieldFocused: Bool

    private var currentTally: Tally {
        store.tallies.first(where: { $0.id == initialTally.id }) ?? initialTally
    }

    private var role: TallyRole {
        currentTally.role(for: store.currentUid)
    }

    private var tallyId: String { currentTally.id ?? "" }

    var body: some View {
        ZStack {
            backgroundTint
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                nameView
                    .padding(.bottom, 12)
                countView
                    .padding(.bottom, 12)
                Spacer(minLength: 0)
                bottomButtonRow
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleIncrementTap()
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
                .onLongPressGesture(minimumDuration: 0.4) {
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
        } else {
            Text("\(currentTally.count)")
                .font(.system(size: 120, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .shake(times: nudge)
                .onLongPressGesture(minimumDuration: 0.4) {
                    guard role.canEditCount else {
                        triggerShake()
                        return
                    }
                    impactLight()
                    isEditingCount = true
                }
        }
    }

    private func commitCount() {
        let trimmed = draftCount.trimmingCharacters(in: .whitespacesAndNewlines)
        countFieldFocused = false
        isEditingCount = false
        guard let value = Int(trimmed), value != currentTally.count else { return }
        Task {
            do {
                try await store.setCount(currentTally, to: value)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Bottom buttons

    private var bottomButtonRow: some View {
        HStack(spacing: 24) {
            circleButton(systemImage: "paintpalette.fill", label: "Color") {
                showingColor = true
            }

            if role.isOwner {
                circleButton(systemImage: "person.2.fill", label: "Friends and Permissions") {
                    showingPermissions = true
                }
            }

            circleButton(systemImage: "trash.fill", label: deleteAccessibilityLabel) {
                showingDeleteConfirm = true
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 48, height: 48)
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel(label)
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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
