//
//  TallyListPreferences.swift
//  Tapp
//
//  Per-user home-screen list preferences stored in UserDefaults:
//  manual order, pinned tally ids, and whether "sort by last updated" is active.
//

import Foundation

struct TallyListPreferences {
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    private var sortKey: String { "tapp.sortEnabled.\(userId)" }
    private var manualOrderKey: String { "tapp.manualOrder.\(userId)" }
    private var pinnedKey: String { "tapp.pinned.\(userId)" }

    var sortEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: sortKey) }
        set { UserDefaults.standard.set(newValue, forKey: sortKey) }
    }

    var manualOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: manualOrderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: manualOrderKey) }
    }

    var pinnedIds: [String] {
        get { UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: pinnedKey) }
    }

    func isPinned(_ tallyId: String) -> Bool {
        pinnedIds.contains(tallyId)
    }

    mutating func togglePin(_ tallyId: String) {
        if isPinned(tallyId) {
            pinnedIds = pinnedIds.filter { $0 != tallyId }
        } else {
            pinnedIds = pinnedIds + [tallyId]
        }
    }

    /// Inserts a brand-new tally at the front of the manual (unpinned) order.
    mutating func registerNewTally(_ tallyId: String) {
        var order = manualOrder.filter { $0 != tallyId }
        order.insert(tallyId, at: 0)
        manualOrder = order
    }

    mutating func removeTally(_ tallyId: String) {
        manualOrder = manualOrder.filter { $0 != tallyId }
        pinnedIds = pinnedIds.filter { $0 != tallyId }
    }

    mutating func setManualOrder(_ ids: [String]) {
        manualOrder = ids
    }
}
