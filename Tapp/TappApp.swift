//
//  TappApp.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import SwiftUI
import FirebaseCore

@main
struct TappApp: App {
    @State private var authStore: AuthStore

    init() {
        FirebaseApp.configure()
        _authStore = State(initialValue: AuthStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
                .onOpenURL { url in
                    guard EmailLinkHandler.canHandle(url) else { return }
                    Task { await authStore.completeSignIn(with: url) }
                }
        }
    }
}

private struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        switch authStore.state {
        case .loading:
            ProgressView()
        case .signedOut:
            SignupView()
        case .awaitingEmailLink(let email, let isSignup):
            AwaitingLinkView(email: email, isSignup: isSignup)
        case .signedIn(let profile):
            TalliesView(profile: profile)
        }
    }
}
