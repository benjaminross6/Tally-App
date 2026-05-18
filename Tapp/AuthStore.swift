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
        case signedIn(UserProfile)
    }

    private(set) var state: State = .loading

    private var authListener: AuthStateDidChangeListenerHandle?
    private var isSigningUp = false

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

    func signUp(name: String, email: String) async throws {
        isSigningUp = true
        defer { isSigningUp = false }

        let result = try await Auth.auth().signInAnonymously()
        let uid = result.user.uid

        let userDoc = Firestore.firestore().collection("users").document(uid)
        try await userDoc.setData([
            "Name": name,
            "Email": email,
            "Joined": FieldValue.serverTimestamp(),
            "Tallies": [DocumentReference]()
        ])

        let profile = try await loadProfile(uid: uid)
        state = .signedIn(profile)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private func handleAuthChange(_ user: User?) async {
        if isSigningUp { return }

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
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument()

        guard snapshot.exists else {
            throw AuthError.profileNotFound
        }
        return try snapshot.data(as: UserProfile.self)
    }
}

enum AuthError: LocalizedError {
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Couldn't find your account. Please sign up again."
        }
    }
}
