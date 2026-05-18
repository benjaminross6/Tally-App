//
//  TalliesView.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import SwiftUI

struct TalliesView: View {
    @Environment(AuthStore.self) private var authStore
    let profile: UserProfile

    @State private var store: TallyStore

    @State private var showingAddAlert = false
    @State private var newTallyName = ""

    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    @State private var showingSignOutConfirm = false

    init(profile: UserProfile) {
        self.profile = profile
        _store = State(initialValue: TallyStore(userId: profile.id ?? ""))
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.tallies.isEmpty {
                    ContentUnavailableView {
                        Label("No tallies yet", systemImage: "plus.circle")
                    } description: {
                        Text("Tap + to create your first tally.")
                    }
                } else {
                    List {
                        ForEach(store.tallies) { tally in
                            TallyRow(tally: tally) {
                                increment(tally)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tapp")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirm = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newTallyName = ""
                        showingAddAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityLabel("Add tally")
                }
            }
            .alert("New Tally", isPresented: $showingAddAlert) {
                TextField("Tally name", text: $newTallyName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {
                    newTallyName = ""
                }
                Button("Add") {
                    submitNewTally()
                }
            } message: {
                Text("Name your new tally.")
            }
            .alert("Couldn't add tally", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Sign out of this device?",
                isPresented: $showingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    try? authStore.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This account is tied to this device. Signing out cannot be undone.")
            }
        }
    }

    private func submitNewTally() {
        let trimmed = newTallyName.trimmingCharacters(in: .whitespaces)
        newTallyName = ""
        guard !trimmed.isEmpty else { return }

        Task {
            do {
                try await store.addTally(name: trimmed)
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    private func increment(_ tally: Tally) {
        Task {
            do {
                try await store.increment(tally)
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
}

private struct TallyRow: View {
    let tally: Tally
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(tally.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(tally.count)")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    TalliesView(profile: UserProfile(
        id: "preview",
        name: "Ben",
        email: "ben@example.com",
        joined: .now,
        tallies: []
    ))
    .environment(AuthStore())
}
