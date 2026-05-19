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
    @Environment(AuthStore.self) private var authStore
    let profile: UserProfile

    @State private var store: TallyStore
    @State private var friendsStore: FriendsStore
    @State private var directory: UserDirectory

    @State private var showingAddTally: Bool = false
    @State private var openTally: Tally?
    @State private var openSettings: Bool = false
    @State private var errorMessage: String?

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

                VStack(spacing: 16) {
                    headerButtons
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

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
        .task {
            await prewarmDirectory()
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
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }

            HStack(spacing: 12) {
                Button {
                    // Sort cycle deferred to a later phase; this is a placeholder.
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Sort")
                .disabled(true)
                .opacity(0.4)

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
                    .frame(height: 44)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Add tally")
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Tally list

    private var tallyList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.tallies) { tally in
                    TallyRow(
                        tally: tally,
                        currentUid: store.currentUid,
                        directory: directory,
                        onTap: { handleRowTap(tally) },
                        onLongPress: { handleRowLongPress(tally) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func handleRowTap(_ tally: Tally) {
        guard tally.role(for: store.currentUid).canIncrement else { return }
        Task {
            do {
                try await store.increment(tally)
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

// MARK: - Row

private struct TallyRow: View {
    let tally: Tally
    let currentUid: String
    let directory: UserDirectory
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var nudge: Int = 0
    @State private var pressed: Bool = false
    private let colorObserver = LocalTallyColorsObserver.shared

    private var role: TallyRole { tally.role(for: currentUid) }

    var body: some View {
        let ownerUid = tally.owner.documentID
        let ownerSummary = directory.cached(uid: ownerUid)
        let _ = colorObserver.version // observe local color changes

        ZStack(alignment: .topLeading) {
            LocalTallyColors.backgroundTint(for: tally.id ?? "")
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tally.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(tally.count)")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    AvatarBadge(summary: ownerSummary, size: 20)
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
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
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
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 30, pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                pressed = isPressing
            }
        }, perform: {
            onLongPress()
        })
        .task {
            await directory.fetch(uid: ownerUid)
        }
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
