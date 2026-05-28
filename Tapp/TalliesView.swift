//
//  TalliesView.swift
//  Tapp
//
//  Home page. Scrollable list of tallies under a gear + add + sort button
//  triplet. Long-press a row to open the Full Screen Tally. Tap a row to
//  increment (or shake, when view-only).
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TalliesView: View {
    let profile: UserProfile

    @State private var store: TallyStore
    @State private var friendsStore: FriendsStore
    @State private var directory: UserDirectory

    @State private var showingAddTally: Bool = false
    @State private var openTally: Tally?
    @State private var openSettings: Bool = false
    @State private var errorMessage: String?

    @State private var sortLabelVisible = false
    @State private var didRunLandingEffects = false
    @State private var updaterFlashByTallyId: [String: String] = [:]
    @State private var updaterFlashOpacity: [String: Double] = [:]
    @State private var landingFireworksTallyIds: Set<String> = []
    @State private var incrementFireworksPulse: [String: Int] = [:]

    private var lastSeenStore: TallyLastSeenStore {
        TallyLastSeenStore(userId: store.currentUid)
    }

    private var numberType: String { profile.resolvedNumberType }

    init(profile: UserProfile) {
        self.profile = profile
        let uid = profile.id ?? Auth.auth().currentUser?.uid ?? ""
        _store = State(initialValue: TallyStore(userId: uid))
        _friendsStore = State(initialValue: FriendsStore(userId: uid))
        _directory = State(initialValue: UserDirectory())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: TappDesignMetrics.headerToContentSpacing) {
                    headerButtons
                        .padding(.horizontal, TappDesignMetrics.tallyRowHorizontalMargin)
                        .padding(.top, TappDesignMetrics.grid)

                    if store.isLoading {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else if store.tallies.isEmpty {
                        Spacer()
                        Text("No tallies yet. Tap + to make one.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    } else {
                        tallyList
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $openSettings) {
                SettingsView(
                    profile: profile,
                    friendsStore: friendsStore,
                    directory: directory
                )
            }
        }
        .fullScreenCover(item: $openTally) { tally in
            FullScreenTallyView(
                profile: profile,
                initialTally: tally,
                store: store,
                friendsStore: friendsStore,
                directory: directory,
                onDismiss: { openTally = nil }
            )
        }
        .sheet(isPresented: $showingAddTally) {
            AddTallySheet(store: store, friendsStore: friendsStore, directory: directory)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            didRunLandingEffects = false
        }
        .task {
            await prewarmDirectory()
        }
        .task(id: store.isLoading) {
            guard !store.isLoading, !store.tallies.isEmpty else { return }
            guard !didRunLandingEffects else { return }
            await runLandingEffects()
        }
    }

    // MARK: - Header

    private var headerButtons: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button {
                    openSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: TappDesignMetrics.circularControlIconSize, weight: .semibold))
                        .frame(width: TappDesignMetrics.circularControlSize, height: TappDesignMetrics.circularControlSize)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.toggleSort()
                        }
                        showSortLabel()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: TappDesignMetrics.circularControlIconSize, weight: .semibold))
                            .frame(width: TappDesignMetrics.circularControlSize, height: TappDesignMetrics.circularControlSize)
                            .background(store.sortEnabled ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(store.sortEnabled ? Color.white : Color.primary)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Sort")
                    .accessibilityValue(store.sortEnabled ? "Last updated" : "Created")

                    Text(store.sortEnabled ? "Last updated" : "Created")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(sortLabelVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.35), value: sortLabelVisible)
                        .accessibilityHidden(true)
                }

                Button {
                    showingAddTally = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .frame(height: TappDesignMetrics.addTallyHeight)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: TappDesignMetrics.addTallyCornerRadius, style: .continuous))
                }
                .accessibilityLabel("Add Tally")
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Tally list

    private var tallyList: some View {
        ScrollView {
            VStack(spacing: TappDesignMetrics.tallyListRowSpacing) {
                ForEach(store.tallies) { tally in
                    TallyRow(
                        tally: tally,
                        numberType: numberType,
                        currentUid: store.currentUid,
                        directory: directory,
                        updaterFlashUid: tally.id.flatMap { updaterFlashByTallyId[$0] },
                        updaterFlashOpacity: tally.id.flatMap { updaterFlashOpacity[$0] } ?? 0,
                        showLandingFireworks: tally.id.map { landingFireworksTallyIds.contains($0) } ?? false,
                        incrementFireworksPulse: tally.id.flatMap { incrementFireworksPulse[$0] } ?? 0,
                        onLandingFireworksFinished: { finishLandingFireworks(for: tally) },
                        onTap: { handleRowTap(tally) },
                        onLongPress: { handleRowLongPress(tally) }
                    )
                    .id(tally.id)
                }
            }
            .padding(.horizontal, TappDesignMetrics.tallyRowHorizontalMargin)
            .padding(.vertical, TappDesignMetrics.grid)
        }
    }

    // MARK: - Actions

    private func handleRowTap(_ tally: Tally) {
        guard tally.role(for: store.currentUid).canIncrement else { return }
        Task {
            do {
                try await store.increment(tally)
                if tally.effectiveFireworksEnabled, let id = tally.id {
                    incrementFireworksPulse[id, default: 0] += 1
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleRowLongPress(_ tally: Tally) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openTally = tally
    }

    private func prewarmDirectory() async {
        let ownerRefs = store.tallies.map(\.owner)
        await directory.prefetch(ownerRefs)
        await directory.prefetch(friendsStore.friendRefs)
    }

    private func showSortLabel() {
        sortLabelVisible = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                sortLabelVisible = false
            }
        }
    }

    private func runLandingEffects() async {
        didRunLandingEffects = true

        var flashEntries: [(tallyId: String, updaterUid: String, tally: Tally)] = []
        for tally in store.tallies {
            guard let tallyId = tally.id,
                  lastSeenStore.hasUnseenPeerUpdate(tally: tally, currentUid: store.currentUid),
                  let updaterUid = tally.lastUpdatedBy?.documentID else {
                continue
            }
            flashEntries.append((tallyId, updaterUid, tally))
        }

        guard !flashEntries.isEmpty else { return }

        await directory.prefetchUids(flashEntries.map(\.updaterUid))

        var opacity: [String: Double] = [:]
        var flashUids: [String: String] = [:]
        var fireworksIds = Set<String>()

        for entry in flashEntries {
            flashUids[entry.tallyId] = entry.updaterUid
            opacity[entry.tallyId] = 1
            lastSeenStore.markSeen(entry.tally)

            if entry.tally.effectiveFireworksEnabled, FireworksLimiter.tryAcquire() {
                fireworksIds.insert(entry.tallyId)
            }
        }

        updaterFlashByTallyId = flashUids
        updaterFlashOpacity = opacity
        landingFireworksTallyIds = fireworksIds

        withAnimation(.easeOut(duration: 2)) {
            for tallyId in flashUids.keys {
                updaterFlashOpacity[tallyId] = 0
            }
        }

        try? await Task.sleep(for: .seconds(2))
        updaterFlashByTallyId = [:]
        updaterFlashOpacity = [:]
    }

    private func finishLandingFireworks(for tally: Tally) {
        guard let id = tally.id else { return }
        landingFireworksTallyIds.remove(id)
        FireworksLimiter.release()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

// MARK: - Row

private struct TallyBarView: View {
    let tally: Tally
    let numberType: String
    let currentUid: String
    let directory: UserDirectory
    let updaterFlashUid: String?
    let updaterFlashOpacity: Double

    private var role: TallyRole { tally.role(for: currentUid) }
    private let colorObserver = LocalTallyColorsObserver.shared

    private var countText: String {
        CountFormatter.string(for: tally.count, numberType: numberType)
    }

    private var isStick: Bool { numberType == UserNumberType.stick }

    private let stickCountAreaWidth: CGFloat = 148
    private let stickCountAreaHeight: CGFloat = 36

    var body: some View {
        let ownerUid = tally.owner.documentID
        let ownerSummary = directory.cached(uid: ownerUid)
        let updaterSummary = updaterFlashUid.flatMap { directory.cached(uid: $0) }
        let _ = colorObserver.version

        ZStack(alignment: .topLeading) {
            LocalTallyColors.backgroundTint(for: tally.id ?? "")
                .clipShape(RoundedRectangle(cornerRadius: TappDesignMetrics.tallyRowCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: isStick ? .top : .firstTextBaseline) {
                    Text(tally.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if isStick {
                        StickTallyView(
                            count: tally.count,
                            style: .row(
                                maxWidth: stickCountAreaWidth,
                                maxHeight: stickCountAreaHeight
                            )
                        )
                        .frame(width: stickCountAreaWidth, height: stickCountAreaHeight, alignment: .topTrailing)
                    } else {
                        Text(countText)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                HStack(spacing: 6) {
                    AvatarBadge(summary: ownerSummary, size: TappDesignMetrics.ownerAvatarRowSize)
                    Text(ownerSummary?.displayUsername ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if role.hasLock {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("View only")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let updaterSummary {
                AvatarBadge(summary: updaterSummary, size: TappDesignMetrics.updaterAvatarSize)
                    .opacity(updaterFlashOpacity)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityLabel("Recently updated by \(updaterSummary.displayUsername)")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: TappDesignMetrics.tallyRowHeight)
        .task {
            await directory.fetch(uid: ownerUid)
            if let updaterFlashUid {
                await directory.fetch(uid: updaterFlashUid)
            }
        }
    }
}

private struct TallyRow: View {
    let tally: Tally
    let numberType: String
    let currentUid: String
    let directory: UserDirectory
    let updaterFlashUid: String?
    let updaterFlashOpacity: Double
    let showLandingFireworks: Bool
    let incrementFireworksPulse: Int
    let onLandingFireworksFinished: () -> Void
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var nudge: Int = 0
    @State private var pressed: Bool = false
    @State private var fireworksPlayback = FireworksPlayback()
    @State private var landingFireworksPending = false

    private var role: TallyRole { tally.role(for: currentUid) }

    private var rowAccessibilityLabel: String {
        let ownerUsername = directory.cached(uid: tally.owner.documentID)?.displayUsername ?? "unknown"
        return TallyAccessibility.rowLabel(
            name: tally.name,
            count: tally.count,
            numberType: numberType,
            ownerUsername: ownerUsername,
            isViewOnly: role.hasLock
        )
    }

    var body: some View {
        ZStack {
            TallyBarView(
                tally: tally,
                numberType: numberType,
                currentUid: currentUid,
                directory: directory,
                updaterFlashUid: updaterFlashUid,
                updaterFlashOpacity: updaterFlashOpacity
            )

            FireworksOverlay(playback: fireworksPlayback)
                .clipShape(RoundedRectangle(cornerRadius: TappDesignMetrics.tallyRowCornerRadius, style: .continuous))
        }
        .onAppear {
            fireworksPlayback.onFinished = {
                if landingFireworksPending {
                    landingFireworksPending = false
                    onLandingFireworksFinished()
                }
            }
            if showLandingFireworks {
                landingFireworksPending = true
                fireworksPlayback.trigger()
            }
        }
        .onChange(of: showLandingFireworks) { _, active in
            guard active else { return }
            landingFireworksPending = true
            fireworksPlayback.trigger()
        }
        .onChange(of: incrementFireworksPulse) { old, new in
            if new > old {
                fireworksPlayback.trigger()
            }
        }
        .scaleEffect(pressed ? 0.98 : 1.0)
        .shake(times: nudge)
        .contentShape(Rectangle())
        .onTapGesture {
            if role.canIncrement {
                onTap()
            } else {
                withAnimation(.linear(duration: 0.3)) { nudge &+= 1 }
            }
        }
        .modifier(TallyRowAccessibilityModifier(
            label: rowAccessibilityLabel,
            canIncrement: role.canIncrement,
            onIncrement: onTap,
            onOpenFullScreen: onLongPress
        ))
        .onLongPressGesture(minimumDuration: TappDesignMetrics.longPressDuration, maximumDistance: 30, pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                pressed = isPressing
            }
        }, perform: {
            onLongPress()
        })
    }
}

// MARK: - Add Tally sheet

private struct AddTallySheet: View {
    let store: TallyStore
    let friendsStore: FriendsStore
    let directory: UserDirectory

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var table: PermissionsTable = .init(friendUids: [], permissions: [:])
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("e.g. Push-ups", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share with")
                            .font(.headline)
                        PermissionsTableEditor(table: $table, directory: directory)
                            .frame(minHeight: 220)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .navigationTitle("New Tally")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { submit() }
                        .bold()
                        .disabled(!isValid || isSubmitting)
                }
            }
        }
        .task {
            table = PermissionsTable(friendUids: friendsStore.friendUids, permissions: [:])
            await directory.prefetch(friendsStore.friendRefs)
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        Task {
            do {
                _ = try await store.addTally(
                    name: String(trimmed.prefix(40)),
                    initialPermissions: table.permissions
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    TalliesView(profile: UserProfile(
        id: "preview",
        name: "Ben",
        username: "ben",
        email: "ben@example.com",
        joined: .now,
        tallies: [],
        friends: []
    ))
    .environment(AuthStore())
}
