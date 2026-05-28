//
//  SettingsView.swift
//  Tapp
//
//  Account settings, friends list, and the destructive Log Out / Delete Account
//  actions.
//

import SwiftUI
import UIKit
import FirebaseFirestore

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore

    let profile: UserProfile
    let friendsStore: FriendsStore
    let directory: UserDirectory

    @State private var showingAddFriend: Bool = false
    @State private var showingLogOutConfirm: Bool = false
    @State private var showingDeleteFirstConfirm: Bool = false
    @State private var showingDeleteFinalConfirm: Bool = false
    @State private var toastMessage: String?

    @State private var editingField: EditableField?

    private enum EditableField: String, Identifiable {
        case username, name, email, password
        var id: String { rawValue }
    }

    private var currentProfile: UserProfile {
        if case .signedIn(let p) = authStore.state { return p }
        return profile
    }

    var body: some View {
        List {
            accountSection
            friendsSection
            preferencesSection
            logOutSection
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddFriend) {
            AddFriendSheet(friendsStore: friendsStore)
        }
        .sheet(item: $editingField) { field in
            editorSheet(for: field)
        }
        .confirmationDialog(
            "Log out of Tapp?",
            isPresented: $showingLogOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                try? authStore.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete account?", isPresented: $showingDeleteFirstConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                showingDeleteFinalConfirm = true
            }
        } message: {
            Text("This deletes your account, every tally you own, and every friendship.")
        }
        .alert("Are you absolutely sure?", isPresented: $showingDeleteFinalConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) {
                Task {
                    do {
                        try await authStore.deleteAccount()
                    } catch {
                        toastMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("There is no undo.")
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            withAnimation { self.toastMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: toastMessage)
        .task {
            await directory.prefetch(friendsStore.friendRefs)
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            settingRow(label: "Username", value: "@" + (currentProfile.displayUsername.isEmpty ? "—" : currentProfile.displayUsername)) {
                editingField = .username
            }
            settingRow(label: "Name", value: currentProfile.name) {
                editingField = .name
            }
            settingRow(label: "Email", value: currentProfile.email) {
                editingField = .email
            }
            settingRow(label: "Password", value: "••••••••") {
                editingField = .password
            }
        }
    }

    private var friendsSection: some View {
        Section {
            if friendsStore.friendRefs.isEmpty {
                Text("No friends yet. Tap **Add Friend** to add one by username.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(friendsStore.friendRefs, id: \.path) { ref in
                    FriendRow(uid: ref.documentID, directory: directory) { uid in
                        Task {
                            do {
                                try await friendsStore.removeFriend(uid: uid)
                            } catch {
                                toastMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Friends")
                Spacer()
                Button("Add Friend") {
                    showingAddFriend = true
                }
                .font(.subheadline)
                .textCase(nil)
            }
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            preferenceCycleRow(
                label: "Numbers",
                value: UserPreferences.numberTypeLabel(currentProfile.resolvedNumberType)
            ) {
                Task {
                    do {
                        try await authStore.cycleNumberType()
                    } catch {
                        toastMessage = error.localizedDescription
                    }
                }
            }
            .accessibilityHint("Cycles Arabic, Roman, and Stick number formats.")

            preferenceCycleRow(
                label: "Theme",
                value: UserPreferences.themeLabel(currentProfile.resolvedTheme)
            ) {
                Task {
                    do {
                        try await authStore.cycleTheme()
                    } catch {
                        toastMessage = error.localizedDescription
                    }
                }
            }
            .accessibilityHint("Cycles System, Light, and Dark appearance.")
        }
    }

    private var logOutSection: some View {
        Section {
            Button("Log Out") {
                showingLogOutConfirm = true
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var deleteSection: some View {
        Group {
            Section {
                Color.clear
                    .frame(height: 96)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteFirstConfirm = true
                } label: {
                    Text("Delete Account")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.red.opacity(0.1))
        }
    }

    // MARK: - Helpers

    private func preferenceCycleRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingRow(label: String, value: String, change: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Change") { change() }
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func editorSheet(for field: EditableField) -> some View {
        switch field {
        case .username:
            InlineEditorSheet(
                title: "Change username",
                placeholder: "lowercase, 3-20 chars",
                initial: currentProfile.displayUsername,
                helpText: "Letters, numbers, and underscores only.",
                sanitize: UsernameClaim.sanitize
            ) { newValue in
                try await authStore.changeUsername(newValue)
            }
        case .name:
            InlineEditorSheet(
                title: "Change name",
                placeholder: "Your name",
                initial: currentProfile.name,
                helpText: "Up to 40 characters."
            ) { newValue in
                try await authStore.changeName(newValue)
            }
        case .email:
            InlineEditorSheet(
                title: "Change email",
                placeholder: "you@example.com",
                initial: currentProfile.email,
                helpText: "Used for sign-in with Firebase Auth.",
                keyboardType: .emailAddress
            ) { newValue in
                try await authStore.changeEmail(newValue)
            }
        case .password:
            PasswordEditorSheet { currentPassword, newPassword in
                try await authStore.changePassword(current: currentPassword, new: newPassword)
            }
        }
    }
}

// MARK: - Friend row

private struct FriendRow: View {
    let uid: String
    let directory: UserDirectory
    let onRemove: (String) -> Void

    @State private var showingRemoveConfirm: Bool = false

    var body: some View {
        let summary = directory.cached(uid: uid)
        HStack(spacing: 12) {
            AvatarBadge(summary: summary, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary?.displayUsername ?? "@…")
                    .font(.subheadline)
                if let name = summary?.name, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showingRemoveConfirm = true
            } label: {
                Label("Remove", systemImage: "person.fill.xmark")
            }
        }
        .alert("Remove friend?", isPresented: $showingRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onRemove(uid)
            }
        } message: {
            Text("You'll both lose access to tallies you shared with each other.")
        }
        .task {
            await directory.fetch(uid: uid)
        }
    }
}

// MARK: - Add Friend sheet

private struct AddFriendSheet: View {
    let friendsStore: FriendsStore

    @Environment(\.dismiss) private var dismiss
    @State private var username: String = ""
    @State private var status: Status = .idle
    @State private var isSubmitting: Bool = false

    private enum Status { case idle, success, error(String) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter the username of the person you'd like to add. They'll become your friend instantly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: username) { _, new in
                        username = UsernameClaim.sanitize(new)
                    }

                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Add Friend")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(UsernameClaim.isWellFormed(username) ? Color.accentColor : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .disabled(!UsernameClaim.isWellFormed(username) || isSubmitting)

                switch status {
                case .idle: EmptyView()
                case .success:
                    Text("Success!")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                case .error(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        status = .idle
        Task {
            do {
                try await friendsStore.addFriend(username: username)
                status = .success
                username = ""
            } catch {
                status = .error("Error: " + error.localizedDescription)
            }
            isSubmitting = false
        }
    }
}

// MARK: - Inline editor sheet

private struct InlineEditorSheet: View {
    let title: String
    let placeholder: String
    let initial: String
    let helpText: String?
    let keyboardType: UIKeyboardType
    let sanitize: ((String) -> String)?
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String = ""
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

    init(
        title: String,
        placeholder: String,
        initial: String,
        helpText: String? = nil,
        keyboardType: UIKeyboardType = .default,
        sanitize: ((String) -> String)? = nil,
        onSave: @escaping (String) async throws -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.initial = initial
        self.helpText = helpText
        self.keyboardType = keyboardType
        self.sanitize = sanitize
        self.onSave = onSave
        _value = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .onChange(of: value) { _, newValue in
                        if let sanitize { value = sanitize(newValue) }
                    }

                if let helpText {
                    Text(helpText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(isSaving || value.isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await onSave(value)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct PasswordEditorSheet: View {
    let onSave: (_ currentPassword: String, _ newPassword: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                SecureField("Current password", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("New password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("At least 6 characters.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(isSaving || !isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !currentPassword.isEmpty && password.count >= 6 && password == confirmPassword
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await onSave(currentPassword, password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
