//
//  FriendsStore.swift
//  Tapp
//
//  Live-syncs the signed-in user's `Friends` array and exposes Add/Remove flows.
//

import Foundation
import Observation
import FirebaseFirestore

enum FriendError: LocalizedError {
    case unknownUsername
    case cantAddSelf

    var errorDescription: String? {
        switch self {
        case .unknownUsername: return "No user with that username."
        case .cantAddSelf: return "You can't add yourself."
        }
    }
}

@Observable
final class FriendsStore {
    private(set) var friendRefs: [DocumentReference] = []
    private(set) var isLoading: Bool = true

    private let userRef: DocumentReference
    private var listener: ListenerRegistration?

    var currentUid: String { userRef.documentID }

    init(userId: String) {
        precondition(!userId.isEmpty, "FriendsStore requires a non-empty user id")
        self.userRef = Firestore.firestore().collection("users").document(userId)
        listen()
    }

    deinit {
        listener?.remove()
    }

    private func listen() {
        listener = userRef.addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let refs = (snap?.data()?["Friends"] as? [DocumentReference]) ?? []
                self.friendRefs = refs
                self.isLoading = false
            }
        }
    }

    var friendUids: [String] { friendRefs.map(\.documentID) }

    func isFriend(_ uid: String) -> Bool {
        friendUids.contains(uid)
    }

    /// Looks up the username in `usernames/{name}` and, if found, mutually adds
    /// the two users to each other's `Friends` arrays. Idempotent: re-adding an
    /// existing friend succeeds with no-op.
    func addFriend(username rawUsername: String) async throws {
        let username = UsernameClaim.sanitize(rawUsername)
        guard UsernameClaim.isWellFormed(username) else {
            throw UsernameClaimError.invalidFormat
        }

        guard let otherUid = try await UsernameClaim.ownerUid(of: username) else {
            throw FriendError.unknownUsername
        }
        guard otherUid != currentUid else {
            throw FriendError.cantAddSelf
        }
        if friendUids.contains(otherUid) { return }

        let db = Firestore.firestore()
        let otherRef = db.collection("users").document(otherUid)

        try await userRef.updateData([
            "Friends": FieldValue.arrayUnion([otherRef])
        ])
        try await otherRef.updateData([
            "Friends": FieldValue.arrayUnion([userRef])
        ])
    }

    /// Mutually removes the friendship and pulls the removed user out of any
    /// tally they currently share with the current user (in either direction).
    func removeFriend(uid: String) async throws {
        let db = Firestore.firestore()
        let otherRef = db.collection("users").document(uid)

        try await userRef.updateData([
            "Friends": FieldValue.arrayRemove([otherRef])
        ])
        try await otherRef.updateData([
            "Friends": FieldValue.arrayRemove([userRef])
        ])

        try await cascadeOutOfSharedTallies(otherUid: uid)
    }

    /// For each tally owned by the current user that lists the other in `Shared With`,
    /// remove the other; and for each tally owned by the other user that lists the
    /// current user, remove the current user. Both sides also lose the tally from
    /// their `Tallies` array.
    private func cascadeOutOfSharedTallies(otherUid: String) async throws {
        let db = Firestore.firestore()
        let otherRef = db.collection("users").document(otherUid)

        let myTallyRefs = try await tallyRefs(forUserRef: userRef)
        for tallyRef in myTallyRefs {
            let snap = try await tallyRef.getDocument()
            guard snap.exists else { continue }
            let owner = snap.data()?["Owner"] as? DocumentReference
            guard owner?.documentID == currentUid else { continue }
            let shared = (snap.data()?["Shared With"] as? [DocumentReference]) ?? []
            guard shared.contains(where: { $0.documentID == otherUid }) else { continue }

            var perms = (snap.data()?["Permissions"] as? [String: String]) ?? [:]
            perms.removeValue(forKey: otherUid)
            let newShared = shared.filter { $0.documentID != otherUid }
            try? await tallyRef.updateData([
                "Permissions": perms,
                "Shared With": newShared
            ])
            try? await otherRef.updateData([
                "Tallies": FieldValue.arrayRemove([tallyRef])
            ])
        }

        let theirTallyRefs = try await tallyRefs(forUserRef: otherRef)
        for tallyRef in theirTallyRefs {
            let snap = try await tallyRef.getDocument()
            guard snap.exists else { continue }
            let owner = snap.data()?["Owner"] as? DocumentReference
            guard owner?.documentID == otherUid else { continue }
            let shared = (snap.data()?["Shared With"] as? [DocumentReference]) ?? []
            guard shared.contains(where: { $0.documentID == currentUid }) else { continue }

            var perms = (snap.data()?["Permissions"] as? [String: String]) ?? [:]
            perms.removeValue(forKey: currentUid)
            let newShared = shared.filter { $0.documentID != currentUid }
            try? await tallyRef.updateData([
                "Permissions": perms,
                "Shared With": newShared
            ])
            try? await userRef.updateData([
                "Tallies": FieldValue.arrayRemove([tallyRef])
            ])
        }
    }

    private func tallyRefs(forUserRef ref: DocumentReference) async throws -> [DocumentReference] {
        let snap = try await ref.getDocument()
        return (snap.data()?["Tallies"] as? [DocumentReference]) ?? []
    }
}
