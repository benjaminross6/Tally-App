//
//  AuthStore.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import Foundation
import Observation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

/// Firebase Auth requires an email address. We synthesize one from the username so
/// users only ever see username + password in the UI.
enum AuthCredentials {
    static let emailDomain = "tapp.users"

    static func email(for username: String) -> String {
        "\(UsernameClaim.sanitize(username))@\(emailDomain)"
    }
}

@Observable
final class AuthStore {
    enum State {
        case loading
        case signedOut
        case signedIn(UserProfile)
    }

    private(set) var state: State = .loading

    private var authListener: AuthStateDidChangeListenerHandle?
    private var isPerformingAccountSetup = false

    init() {
        guard FirebaseApp.app() != nil else {
            state = .signedOut
            return
        }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                await self?.handleAuthChange(user)
            }
        }
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    // MARK: - Signup / Login

    func signUp(name: String, username: String, password: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = UsernameClaim.sanitize(username)
        let authEmail = AuthCredentials.email(for: cleanUsername)

        guard !trimmedName.isEmpty else { throw AuthError.invalidName }
        guard UsernameClaim.isWellFormed(cleanUsername) else { throw UsernameClaimError.invalidFormat }
        guard isValidPassword(password) else { throw AuthError.invalidPassword }

        if let existingUid = try await UsernameClaim.ownerUid(of: cleanUsername),
           existingUid != Auth.auth().currentUser?.uid {
            throw UsernameClaimError.alreadyTaken
        }

        isPerformingAccountSetup = true
        defer { isPerformingAccountSetup = false }

        let result = try await Auth.auth().createUser(withEmail: authEmail, password: password)
        let uid = result.user.uid

        try await ensureUserDoc(
            uid: uid,
            name: trimmedName,
            username: cleanUsername,
            email: authEmail
        )
        try await claimUsername(cleanUsername, for: uid)

        let profile = try await loadProfile(uid: uid)
        state = .signedIn(profile)
    }

    func signIn(username: String, password: String) async throws {
        let cleanUsername = UsernameClaim.sanitize(username)
        guard UsernameClaim.isWellFormed(cleanUsername) else { throw UsernameClaimError.invalidFormat }
        guard !password.isEmpty else { throw AuthError.invalidPassword }

        let syntheticEmail = AuthCredentials.email(for: cleanUsername)
        do {
            _ = try await Auth.auth().signIn(withEmail: syntheticEmail, password: password)
            return
        } catch {
            guard let uid = try await UsernameClaim.ownerUid(of: cleanUsername) else {
                throw AuthError.wrongCredentials
            }
            let profile = try await loadProfile(uid: uid)
            guard !profile.email.isEmpty else { throw AuthError.wrongCredentials }
            _ = try await Auth.auth().signIn(withEmail: profile.email, password: password)
        }
    }

    // MARK: - Account mutations

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func changeName(_ newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw AuthError.invalidName }
        guard let uid = Auth.auth().currentUser?.uid else { throw AuthError.notSignedIn }

        try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .updateData(["Name": trimmed])

        if case .signedIn(var profile) = state {
            profile.name = trimmed
            state = .signedIn(profile)
        }
    }

    func changeUsername(_ newUsername: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        guard case .signedIn(var profile) = state else { throw AuthError.notSignedIn }

        let clean = UsernameClaim.sanitize(newUsername)
        guard UsernameClaim.isWellFormed(clean) else { throw UsernameClaimError.invalidFormat }
        guard clean != profile.displayUsername else { return }

        try await UsernameClaim.rename(from: profile.displayUsername, to: clean, uid: user.uid)

        let newEmail = AuthCredentials.email(for: clean)
        try? await user.updateEmail(to: newEmail)

        try await Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .updateData(["Username": clean, "Email": newEmail])

        profile.username = clean
        profile.email = newEmail
        state = .signedIn(profile)
    }

    func changePassword(_ newPassword: String) async throws {
        guard isValidPassword(newPassword) else { throw AuthError.invalidPassword }
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        try await user.updatePassword(to: newPassword)
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        let uid = user.uid
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)

        let profileSnap = try await userRef.getDocument()
        let tallyRefs = (profileSnap.data()?["Tallies"] as? [DocumentReference]) ?? []
        let friendRefs = (profileSnap.data()?["Friends"] as? [DocumentReference]) ?? []
        let username = profileSnap.data()?["Username"] as? String ?? ""

        for tallyRef in tallyRefs {
            let tallySnap = try await tallyRef.getDocument()
            guard tallySnap.exists else { continue }
            let owner = tallySnap.data()?["Owner"] as? DocumentReference
            let sharedRefs = (tallySnap.data()?["Shared With"] as? [DocumentReference]) ?? []

            if owner?.documentID == uid {
                for ref in sharedRefs {
                    try? await ref.updateData([
                        "Tallies": FieldValue.arrayRemove([tallyRef])
                    ])
                }
                try? await tallyRef.delete()
            } else {
                var perms = (tallySnap.data()?["Permissions"] as? [String: String]) ?? [:]
                perms.removeValue(forKey: uid)
                let newShared = sharedRefs.filter { $0.documentID != uid }
                try? await tallyRef.updateData([
                    "Permissions": perms,
                    "Shared With": newShared
                ])
            }
        }

        for friendRef in friendRefs {
            try? await friendRef.updateData([
                "Friends": FieldValue.arrayRemove([userRef])
            ])
        }

        if !username.isEmpty {
            try? await UsernameClaim.release(username, ownedBy: uid)
        }

        try? await userRef.delete()
        try await user.delete()
    }

    // MARK: - Internal

    private func handleAuthChange(_ user: User?) async {
        guard let user else {
            state = .signedOut
            return
        }

        do {
            let profile = try await loadProfile(uid: user.uid)
            state = .signedIn(profile)
        } catch AuthError.profileNotFound where isPerformingAccountSetup {
            return
        } catch {
            try? Auth.auth().signOut()
            state = .signedOut
        }
    }

    private func loadProfile(uid: String) async throws -> UserProfile {
        let userRef = Firestore.firestore().collection("users").document(uid)
        let snapshot = try await userRef.getDocument()

        guard snapshot.exists else {
            throw AuthError.profileNotFound
        }

        var data = snapshot.data() ?? [:]
        var needsBackfill: [String: Any] = [:]
        if data["Friends"] == nil {
            needsBackfill["Friends"] = [DocumentReference]()
            data["Friends"] = [DocumentReference]()
        }
        if data["Tallies"] == nil {
            needsBackfill["Tallies"] = [DocumentReference]()
            data["Tallies"] = [DocumentReference]()
        }
        if !needsBackfill.isEmpty {
            try? await userRef.updateData(needsBackfill)
        }

        let fresh = try await userRef.getDocument()
        guard fresh.exists else {
            throw AuthError.profileNotFound
        }
        var profile = try fresh.data(as: UserProfile.self)
        if profile.id == nil {
            profile.id = fresh.documentID
        }
        return profile
    }

    private func ensureUserDoc(uid: String, name: String, username: String, email: String) async throws {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)
        let snap = try await userRef.getDocument()
        if snap.exists {
            try await userRef.setData([
                "Name": name,
                "Username": username,
                "Email": email
            ], merge: true)
            return
        }

        try await userRef.setData([
            "Name": name,
            "Username": username,
            "Email": email,
            "Joined": FieldValue.serverTimestamp(),
            "Tallies": [DocumentReference](),
            "Friends": [DocumentReference]()
        ])
    }

    private func claimUsername(_ rawUsername: String, for uid: String) async throws {
        let username = UsernameClaim.sanitize(rawUsername)
        let db = Firestore.firestore()
        let usernameRef = db.collection("usernames").document(username)
        let existing = try await usernameRef.getDocument()
        if existing.exists, (existing.data()?["uid"] as? String) != uid {
            throw UsernameClaimError.alreadyTaken
        }
        try await usernameRef.setData(["uid": uid])
    }

    private func isValidPassword(_ password: String) -> Bool {
        password.count >= 6
    }
}

enum AuthError: LocalizedError {
    case profileNotFound
    case invalidName
    case invalidPassword
    case wrongCredentials
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Couldn't find your account. Please sign up again."
        case .invalidName:
            return "Please enter your name (up to 40 characters)."
        case .invalidPassword:
            return "Passwords must be at least 6 characters."
        case .wrongCredentials:
            return "That username or password isn't right."
        case .notSignedIn:
            return "You're not signed in."
        }
    }
}
