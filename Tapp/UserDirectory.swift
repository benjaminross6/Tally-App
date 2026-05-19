//
//  UserDirectory.swift
//  Tapp
//
//  An app-wide cache of uid -> (username, name) used to label tally owners,
//  friend rows, and the per-tally permissions table. Reads are async and
//  deduplicated; results are remembered for the life of the process.
//

import Foundation
import Observation
import FirebaseFirestore

struct UserSummary: Equatable {
    var uid: String
    var name: String
    var username: String

    var displayUsername: String {
        username.isEmpty ? "user" : "@\(username)"
    }

    var avatarInitial: String {
        let source = name.isEmpty ? username : name
        return source.first.map { String($0).uppercased() } ?? "?"
    }
}

@Observable
final class UserDirectory {
    private(set) var summaries: [String: UserSummary] = [:]
    private var inFlight: Set<String> = []

    /// Returns the cached summary if any. Does not trigger a fetch.
    func cached(uid: String) -> UserSummary? {
        summaries[uid]
    }

    /// Cached or fetched. Returns nil only if the document is missing or unreadable.
    @discardableResult
    func fetch(uid: String) async -> UserSummary? {
        if let hit = summaries[uid] { return hit }
        if inFlight.contains(uid) {
            // Another caller is already fetching; just return what's there (possibly nil).
            return summaries[uid]
        }
        inFlight.insert(uid)
        defer { inFlight.remove(uid) }

        do {
            let snap = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .getDocument()
            guard snap.exists else { return nil }
            let name = (snap.data()?["Name"] as? String) ?? ""
            let username = (snap.data()?["Username"] as? String) ?? ""
            let summary = UserSummary(uid: uid, name: name, username: username)
            summaries[uid] = summary
            return summary
        } catch {
            return nil
        }
    }

    /// Convenience for `DocumentReference`.
    @discardableResult
    func fetch(_ ref: DocumentReference) async -> UserSummary? {
        await fetch(uid: ref.documentID)
    }

    /// Pre-warms the cache for a batch of refs. Returns once all fetches complete.
    func prefetch(_ refs: [DocumentReference]) async {
        for ref in refs where summaries[ref.documentID] == nil {
            _ = await fetch(ref)
        }
    }

    /// Pre-warms the cache for a batch of uids.
    func prefetchUids(_ uids: [String]) async {
        for uid in uids where summaries[uid] == nil {
            _ = await fetch(uid: uid)
        }
    }

    /// Updates the cache after a friend renames themselves, etc.
    func updateLocal(_ summary: UserSummary) {
        summaries[summary.uid] = summary
    }
}

extension UserSummary {
    /// Deterministic SwiftUI-friendly hue from uid, for the avatar background.
    var avatarHue: Double {
        var hasher = Hasher()
        hasher.combine(uid)
        let raw = abs(hasher.finalize())
        return Double(raw % 360) / 360.0
    }
}
