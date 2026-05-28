//
//  TallyListPreferences.swift
//  Tapp
//
//  Per-user home-screen list preferences stored in UserDefaults.
//

import Foundation

struct TallyListPreferences {
    private let userId: String

    init(userId: String) {
        self.userId = userId
        clearLegacyKeys()
    }

    private var sortKey: String { "tapp.sortEnabled.\(userId)" }

    /// When true, the home list is ordered by `LastUpdated` (descending).
    /// When false, the list is ordered by `Created` (descending).
    var sortEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: sortKey) }
        set { UserDefaults.standard.set(newValue, forKey: sortKey) }
    }

    mutating func removeTally(_ tallyId: String) {
        _ = tallyId
    }

    private func clearLegacyKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "tapp.manualOrder.\(userId)")
        defaults.removeObject(forKey: "tapp.pinned.\(userId)")
    }
}
