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

@Observable
final class AuthStore {
    enum State {
        case loading
        case signedOut
        case awaitingEmailLink(email: String, isSignup: Bool)
        case signedIn(UserProfile)
    }

    private(set) var state: State = .loading

    /// Set by `EmailLinkHandler` callers after a sign-in error so the UI can surface it.
    var lastLinkError: String?

    private var authListener: AuthStateDidChangeListenerHandle?
    private var isCompletingLink = false

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

    // MARK: - Signup / Login (Email-Link)

    /// Sends a sign-up email link. Validates and reserves intent locally; the actual
    /// user doc + username claim happen when the link is opened.
    func sendSignupLink(name: String, username: String, email: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanUsername = UsernameClaim.sanitize(username)

        guard !trimmedName.isEmpty else { throw AuthError.invalidName }
        guard UsernameClaim.isWellFormed(cleanUsername) else { throw UsernameClaimError.invalidFormat }
        guard isValidEmail(trimmedEmail) else { throw AuthError.invalidEmail }

        if let existingUid = try await UsernameClaim.ownerUid(of: cleanUsername),
           existingUid != Auth.auth().currentUser?.uid {
            throw UsernameClaimError.alreadyTaken
        }

        try await Auth.auth().sendSignInLink(
            toEmail: trimmedEmail,
            actionCodeSettings: EmailLinkHandler.actionCodeSettings()
        )

        EmailLinkStore.savePendingSignup(
            PendingSignup(name: trimmedName, username: cleanUsername, email: trimmedEmail)
        )

        state = .awaitingEmailLink(email: trimmedEmail, isSignup: true)
    }

    /// Sends a returning-user login link.
    func sendLoginLink(email: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(trimmedEmail) else { throw AuthError.invalidEmail }

        try await Auth.auth().sendSignInLink(
            toEmail: trimmedEmail,
            actionCodeSettings: EmailLinkHandler.actionCodeSettings()
        )

        EmailLinkStore.savePendingLoginEmail(trimmedEmail)
        state = .awaitingEmailLink(email: trimmedEmail, isSignup: false)
    }

    /// Completes sign-in from a link pasted out of the email. Use this when
    /// Universal Links aren't available (e.g. free Apple Personal Team).
    @MainActor
    func completeSignIn(withPastedLink raw: String) async {
        lastLinkError = nil
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard !trimmed.isEmpty else {
            lastLinkError = "Paste the full link from your email."
            return
        }
        guard Auth.auth().isSignIn(withEmailLink: trimmed) else {
            lastLinkError = "That doesn't look like a sign-in link from your email."
            return
        }
        guard let url = URL(string: trimmed) else {
            lastLinkError = "Couldn't read that link."
            return
        }
        await completeSignIn(with: url)
    }

    /// Completes sign-in for an opened email link.
    @MainActor
    func completeSignIn(with url: URL) async {
        let linkString = url.absoluteString
        guard Auth.auth().isSignIn(withEmailLink: linkString) else {
            lastLinkError = "That doesn't look like a sign-in link from your email."
            return
        }
        guard let email = EmailLinkStore.pendingLoginEmail else {
            lastLinkError = "We couldn't find the email this link was sent to on this device."
            return
        }

        let awaitingContext: (email: String, isSignup: Bool)? = {
            if case .awaitingEmailLink(let e, let s) = state { return (e, s) }
            return nil
        }()

        isCompletingLink = true
        defer { isCompletingLink = false }

        do {
            try await withTimeout(seconds: 30) { [self] in
                let result = try await Auth.auth().signIn(withEmail: email, link: linkString)
                let uid = result.user.uid

                if let pending = EmailLinkStore.pendingSignup,
                   pending.email.lowercased() == email.lowercased() {
                    try await ensureUserDoc(
                        uid: uid,
                        name: pending.name,
                        username: pending.username,
                        email: pending.email
                    )
                    try await claimUsername(pending.username, for: uid)
                    EmailLinkStore.clearPendingSignup()
                }

                let profile = try await loadProfile(uid: uid)
                state = .signedIn(profile)
            }
        } catch is TimeoutError {
            lastLinkError = "Sign-in timed out. Check your connection, tap Cancel, request a fresh link, and try again."
            if let awaitingContext {
                state = .awaitingEmailLink(
                    email: awaitingContext.email,
                    isSignup: awaitingContext.isSignup
                )
            }
        } catch {
            lastLinkError = error.localizedDescription
            if let awaitingContext {
                state = .awaitingEmailLink(
                    email: awaitingContext.email,
                    isSignup: awaitingContext.isSignup
                )
            } else {
                state = .signedOut
            }
        }
    }

    /// Writes `usernames/{name}` after the full user doc exists. Uses a plain write
    /// instead of a transaction on first signup to avoid long retry loops.
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

    /// Reset the in-progress link state, e.g. after the user backs out of
    /// "Check your email."
    func cancelPendingLink() {
        EmailLinkStore.clearAll()
        state = .signedOut
    }

    // MARK: - Account mutations

    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// Updates the user's display name on the `users/{uid}` doc.
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

    /// Atomically renames the user, releasing the old `usernames/{oldName}` claim.
    func changeUsername(_ newUsername: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw AuthError.notSignedIn }
        guard case .signedIn(var profile) = state else { throw AuthError.notSignedIn }

        let clean = UsernameClaim.sanitize(newUsername)
        guard UsernameClaim.isWellFormed(clean) else { throw UsernameClaimError.invalidFormat }
        guard clean != profile.displayUsername else { return }

        try await UsernameClaim.rename(from: profile.displayUsername, to: clean, uid: uid)
        profile.username = clean
        state = .signedIn(profile)
    }

    /// Asks Firebase to send a verification link to the new address. The address
    /// only changes on Firebase Auth's side after the user clicks the link. We
    /// optimistically write the new address to the user doc so the UI updates
    /// immediately.
    func changeEmail(_ newEmail: String) async throws {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(trimmed) else { throw AuthError.invalidEmail }
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }

        try await user.sendEmailVerification(beforeUpdatingEmail: trimmed)

        try await Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .updateData(["Email": trimmed])

        if case .signedIn(var profile) = state {
            profile.email = trimmed
            state = .signedIn(profile)
        }
    }

    /// Cascades the deletion: removes ownership of every owned tally (deleting docs
    /// and pulling the ref out of each shared friend's `Tallies`), removes the user
    /// from every shared tally, removes the user from every friend's `Friends`,
    /// releases the username claim, deletes the user doc, and finally deletes the
    /// Firebase Auth user.
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
        EmailLinkStore.clearAll()
    }

    // MARK: - Internal

    private func handleAuthChange(_ user: User?) async {
        if isCompletingLink { return }

        guard let user else {
            state = .signedOut
            return
        }

        do {
            let profile = try await loadProfile(uid: user.uid)
            state = .signedIn(profile)
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

        // Re-fetch after any backfill so decode sees the latest fields.
        let fresh = try await userRef.getDocument()
        guard fresh.exists else {
            throw AuthError.profileNotFound
        }
        var profile = try fresh.data(as: UserProfile.self)
        // @DocumentID is not populated automatically when using custom CodingKeys.
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

    private func isValidEmail(_ email: String) -> Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }
}

enum AuthError: LocalizedError {
    case profileNotFound
    case invalidName
    case invalidEmail
    case notSignedIn
    case timedOut

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Couldn't find your account. Please sign up again."
        case .invalidName:
            return "Please enter your name (up to 40 characters)."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .notSignedIn:
            return "You're not signed in."
        case .timedOut:
            return "That took too long. Check your connection and try again."
        }
    }
}

private struct TimeoutError: Error {}

/// Runs `operation` on the main actor, failing with `TimeoutError` if it exceeds `seconds`.
@MainActor
private func withTimeout(seconds: TimeInterval, operation: @MainActor @escaping () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { @MainActor in
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        try await group.next()
        group.cancelAll()
    }
}
