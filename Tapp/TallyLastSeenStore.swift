//
//  TallyLastSeenStore.swift
//  Tapp
//
//  Per-device last-seen `LastUpdated` timestamps for home-page landing effects.
//

import Foundation
import FirebaseFirestore

struct TallyLastSeenStore {
    let userId: String

    private var keyPrefix: String { "tapp.lastSeenTallyUpdates.\(userId)." }

    func lastSeen(for tallyId: String) -> Date? {
        let key = keyPrefix + tallyId
        guard let raw = UserDefaults.standard.object(forKey: key) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: raw)
    }

    func markSeen(_ tally: Tally) {
        guard let id = tally.id else { return }
        let stamp = tally.lastUpdated ?? Date()
        UserDefaults.standard.set(stamp.timeIntervalSince1970, forKey: keyPrefix + id)
    }

    /// Someone else updated this tally since we last recorded a visit.
    func hasUnseenPeerUpdate(tally: Tally, currentUid: String) -> Bool {
        guard let tallyId = tally.id,
              let updated = tally.lastUpdated,
              let updatedBy = tally.lastUpdatedBy?.documentID,
              updatedBy != currentUid else {
            return false
        }
        guard let seen = lastSeen(for: tallyId) else { return true }
        return updated > seen
    }
}
