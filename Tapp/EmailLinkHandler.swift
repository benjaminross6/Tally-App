//
//  EmailLinkHandler.swift
//  Tapp
//
//  Centralizes the action-code URL and persistence used by Firebase Email-Link auth.
//

import Foundation
import FirebaseAuth

/// Marker payload remembered between "Send link" and "Open link", since the
/// receiving installation may be the same device or a different one.
struct PendingSignup: Codable {
    var name: String
    var username: String
    var email: String
}

enum EmailLinkConfig {
    /// Fill this in with your Firebase Hosting / web action URL.
    /// See README "Email-Link Auth Setup".
    static let actionURL = "https://tapp-97904.firebaseapp.com/__/auth/action"

    /// Bundle ID that matches the iOS app entry in the Firebase console.
    static var iOSBundleID: String {
        Bundle.main.bundleIdentifier ?? "com.example.tapp"
    }
}

enum EmailLinkStore {
    private static let pendingSignupKey = "tapp.pendingSignup"
    private static let pendingLoginEmailKey = "tapp.pendingLoginEmail"

    static func savePendingSignup(_ signup: PendingSignup) {
        if let encoded = try? JSONEncoder().encode(signup) {
            UserDefaults.standard.set(encoded, forKey: pendingSignupKey)
            UserDefaults.standard.set(signup.email, forKey: pendingLoginEmailKey)
        }
    }

    static func savePendingLoginEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: pendingLoginEmailKey)
    }

    static var pendingSignup: PendingSignup? {
        guard let data = UserDefaults.standard.data(forKey: pendingSignupKey) else { return nil }
        return try? JSONDecoder().decode(PendingSignup.self, from: data)
    }

    static var pendingLoginEmail: String? {
        UserDefaults.standard.string(forKey: pendingLoginEmailKey)
    }

    static func clearPendingSignup() {
        UserDefaults.standard.removeObject(forKey: pendingSignupKey)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: pendingSignupKey)
        UserDefaults.standard.removeObject(forKey: pendingLoginEmailKey)
    }
}

enum EmailLinkHandler {
    /// Returns `true` if the URL looks like a Firebase email-link sign-in URL.
    static func canHandle(_ url: URL) -> Bool {
        Auth.auth().isSignIn(withEmailLink: url.absoluteString)
    }

    /// Builds the standard `ActionCodeSettings` used by both signup and login.
    static func actionCodeSettings() -> ActionCodeSettings {
        let settings = ActionCodeSettings()
        settings.url = URL(string: EmailLinkConfig.actionURL)
        settings.handleCodeInApp = true
        settings.setIOSBundleID(EmailLinkConfig.iOSBundleID)
        return settings
    }
}
