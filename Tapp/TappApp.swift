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
        }
    }
}

private struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    private var preferredColorScheme: ColorScheme? {
        if case .signedIn(let profile) = authStore.state {
            return UserPreferences.colorScheme(for: profile.resolvedTheme)
        }
        return nil
    }

    var body: some View {
        Group {
            switch authStore.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignupView()
            case .signedIn(let profile):
                TalliesView(profile: profile)
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }
}
