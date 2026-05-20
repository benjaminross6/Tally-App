//
//  TallyStore.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import Foundation
import Observation
import FirebaseFirestore

@Observable
final class TallyStore {
    private(set) var tallies: [Tally] = []
    private(set) var isLoading: Bool = true
    private(set) var loadError: String?

    let userRef: DocumentReference
    var currentUid: String { userRef.documentID }

    var sortEnabled: Bool { preferences.sortEnabled }

    private var preferences: TallyListPreferences
    private var tallyById: [String: Tally] = [:]
    private var userListener: ListenerRegistration?
    private var tallyListeners: [String: ListenerRegistration] = [:]

    init(userId: String) {
        precondition(!userId.isEmpty, "TallyStore requires a non-empty user id")
        self.userRef = Firestore.firestore().collection("users").document(userId)
        self.preferences = TallyListPreferences(userId: userId)
        startListening()
    }

    func isPinned(_ tallyId: String) -> Bool {
        preferences.isPinned(tallyId)
    }

    /// Toggles "sort by most recently updated" and reorders once. List order stays
    /// stable on tally updates until this is toggled again.
    func toggleSort() {
        preferences.sortEnabled.toggle()
        rebuildDisplayOrder()
    }

    func togglePin(tallyId: String) {
        preferences.togglePin(tallyId)
        rebuildDisplayOrder()
    }

    /// Reorders ids for preview or commit. Pinned tallies cannot cross into the unpinned section.
    func reorderedIds(draggedId: String, toIndex rawDestination: Int) -> [String]? {
        guard !sortEnabled else { return nil }
        var ids = tallies.compactMap(\.id)
        guard let fromIndex = ids.firstIndex(of: draggedId) else { return nil }

        let draggedPinned = preferences.isPinned(draggedId)
        ids.remove(at: fromIndex)

        var dest = rawDestination
        if fromIndex < dest { dest -= 1 }
        dest = max(0, min(dest, ids.count))

        let pinnedCount = ids.filter { preferences.isPinned($0) }.count
        if draggedPinned {
            dest = min(dest, pinnedCount)
        } else {
            dest = max(dest, pinnedCount)
        }

        ids.insert(draggedId, at: dest)
        return ids
    }

    func talliesPreview(draggedId: String, toIndex rawDestination: Int) -> [Tally] {
        guard let ids = reorderedIds(draggedId: draggedId, toIndex: rawDestination) else {
            return tallies
        }
        return ids.compactMap { tallyById[$0] }
    }

    /// Maps a drop slot in the list-without-dragged to the `toIndex` expected by `reorderedIds`.
    func fullListInsertionIndex(draggedId: String, insertionWithoutDragged: Int) -> Int {
        guard let from = tallies.firstIndex(where: { $0.id == draggedId }) else {
            return insertionWithoutDragged
        }
        var ids = tallies.compactMap(\.id)
        let dragged = ids.remove(at: from)
        let slot = min(max(0, insertionWithoutDragged), ids.count)
        ids.insert(dragged, at: slot)
        guard let finalIndex = ids.firstIndex(of: dragged) else { return from }
        return finalIndex > from ? finalIndex + 1 : finalIndex
    }

    func moveTally(draggedId: String, toIndex rawDestination: Int) {
        guard let ids = reorderedIds(draggedId: draggedId, toIndex: rawDestination) else { return }
        preferences.pinnedIds = ids.filter { preferences.isPinned($0) }
        preferences.setManualOrder(ids.filter { !preferences.isPinned($0) })
        tallies = ids.compactMap { tallyById[$0] }
    }

    deinit {
        userListener?.remove()
        tallyListeners.values.forEach { $0.remove() }
    }

    // MARK: - Writes

    /// Creates a new tally owned by the current user.
    /// `initialPermissions` maps friend uid -> "view" | "edit". Friends in this map are also
    /// added to `Shared With` and to that friend's `Tallies` array.
    @discardableResult
    func addTally(name: String, initialPermissions: [String: String] = [:]) async throws -> DocumentReference {
        let db = Firestore.firestore()
        let newTallyRef = db.collection("tallies").document()

        let sharedRefs: [DocumentReference] = initialPermissions.keys
            .filter { !$0.isEmpty }
            .map { db.collection("users").document($0) }

        let data: [String: Any] = [
            "Name": name,
            "Count": 0,
            "Owner": userRef,
            "Shared With": sharedRefs,
            "Permissions": initialPermissions,
            "Created": FieldValue.serverTimestamp(),
            "LastUpdated": FieldValue.serverTimestamp(),
            "LastUpdatedBy": userRef
        ]
        try await newTallyRef.setData(data)

        // Add to owner's tally list.
        try await userRef.updateData([
            "Tallies": FieldValue.arrayUnion([newTallyRef])
        ])

        // Add to each shared friend's tally list.
        for friendRef in sharedRefs {
            try await friendRef.updateData([
                "Tallies": FieldValue.arrayUnion([newTallyRef])
            ])
        }

        return newTallyRef
    }

    func increment(_ tally: Tally) async throws {
        guard let id = tally.id else { return }
        try await Firestore.firestore()
            .collection("tallies")
            .document(id)
            .updateData([
                "Count": FieldValue.increment(Int64(1)),
                "LastUpdated": FieldValue.serverTimestamp(),
                "LastUpdatedBy": userRef
            ])
    }

    func setCount(_ tally: Tally, to newCount: Int) async throws {
        guard let id = tally.id else { return }
        try await Firestore.firestore()
            .collection("tallies")
            .document(id)
            .updateData([
                "Count": newCount,
                "LastUpdated": FieldValue.serverTimestamp(),
                "LastUpdatedBy": userRef
            ])
    }

    func rename(_ tally: Tally, to newName: String) async throws {
        guard let id = tally.id else { return }
        try await Firestore.firestore()
            .collection("tallies")
            .document(id)
            .updateData([
                "Name": newName,
                "LastUpdated": FieldValue.serverTimestamp(),
                "LastUpdatedBy": userRef
            ])
    }

    /// Replaces the tally's `Shared With` array and `Permissions` map.
    /// Also adds/removes the tally ref from each affected friend's `Tallies` list.
    func setPermissions(_ tally: Tally, permissions newPermissions: [String: String]) async throws {
        guard let id = tally.id else { return }
        let db = Firestore.firestore()
        let tallyRef = db.collection("tallies").document(id)

        let oldUids = Set(tally.perms.keys).union(tally.sharedRefs.map(\.documentID))
        let newUids = Set(newPermissions.keys)

        let added = newUids.subtracting(oldUids)
        let removed = oldUids.subtracting(newUids)

        let newSharedRefs = newUids.map { db.collection("users").document($0) }

        try await tallyRef.updateData([
            "Permissions": newPermissions,
            "Shared With": newSharedRefs,
            "LastUpdated": FieldValue.serverTimestamp(),
            "LastUpdatedBy": userRef
        ])

        for uid in added {
            let ref = db.collection("users").document(uid)
            try await ref.updateData([
                "Tallies": FieldValue.arrayUnion([tallyRef])
            ])
        }

        for uid in removed {
            let ref = db.collection("users").document(uid)
            try await ref.updateData([
                "Tallies": FieldValue.arrayRemove([tallyRef])
            ])
        }
    }

    /// Owner-only: deletes the tally document and removes the ref from owner's and every
    /// shared friend's `Tallies` array.
    func deleteTally(_ tally: Tally) async throws {
        guard let id = tally.id else { return }
        let db = Firestore.firestore()
        let tallyRef = db.collection("tallies").document(id)

        for ref in tally.sharedRefs {
            try await ref.updateData([
                "Tallies": FieldValue.arrayRemove([tallyRef])
            ])
        }
        try await userRef.updateData([
            "Tallies": FieldValue.arrayRemove([tallyRef])
        ])
        try await tallyRef.delete()
    }

    /// Non-owner: removes the tally from the current user's list and strips this user
    /// from `Shared With` + `Permissions` on the tally.
    func removeFromMyList(_ tally: Tally) async throws {
        guard let id = tally.id else { return }
        let db = Firestore.firestore()
        let tallyRef = db.collection("tallies").document(id)
        let uid = currentUid

        var newPerms = tally.perms
        newPerms.removeValue(forKey: uid)

        let newShared = tally.sharedRefs.filter { $0.documentID != uid }

        try await tallyRef.updateData([
            "Permissions": newPerms,
            "Shared With": newShared,
            "LastUpdated": FieldValue.serverTimestamp(),
            "LastUpdatedBy": userRef
        ])
        try await userRef.updateData([
            "Tallies": FieldValue.arrayRemove([tallyRef])
        ])
    }

    // MARK: - Reads

    private func startListening() {
        userListener = userRef.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                self?.handleUserSnapshot(snapshot, error: error)
            }
        }
    }

    private func handleUserSnapshot(_ snapshot: DocumentSnapshot?, error: Error?) {
        if let error {
            loadError = error.localizedDescription
            isLoading = false
            return
        }

        let refs = ((snapshot?.data()?["Tallies"] as? [DocumentReference]) ?? [])
            .filter { !$0.documentID.isEmpty }
        syncTallyListeners(for: refs)
        isLoading = false
    }

    private func syncTallyListeners(for refs: [DocumentReference]) {
        let currentIds = Set(tallyListeners.keys)
        let newIds = Set(refs.map(\.documentID))

        for id in currentIds.subtracting(newIds) {
            tallyListeners[id]?.remove()
            tallyListeners.removeValue(forKey: id)
            tallyById.removeValue(forKey: id)
            preferences.removeTally(id)
            tallies.removeAll { $0.id == id }
        }

        for ref in refs where !currentIds.contains(ref.documentID) {
            let listener = ref.addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    self?.handleTallySnapshot(snapshot)
                }
            }
            tallyListeners[ref.documentID] = listener
        }
    }

    private func handleTallySnapshot(_ snapshot: DocumentSnapshot?) {
        guard let snapshot, snapshot.exists,
              var tally = try? snapshot.data(as: Tally.self) else {
            return
        }
        if tally.id == nil {
            tally.id = snapshot.documentID
        }

        guard let id = tally.id else { return }
        let isNew = tallyById[id] == nil
        tallyById[id] = tally

        if isNew {
            if !preferences.manualOrder.contains(id) && !preferences.isPinned(id) {
                preferences.registerNewTally(id)
            }
            rebuildDisplayOrder()
        } else if let idx = tallies.firstIndex(where: { $0.id == id }) {
            tallies[idx] = tally
        } else {
            rebuildDisplayOrder()
        }
    }

    private func rebuildDisplayOrder() {
        let allIds = Set(tallyById.keys)
        preferences.manualOrder = preferences.manualOrder.filter { allIds.contains($0) }
        preferences.pinnedIds = preferences.pinnedIds.filter { allIds.contains($0) }

        for id in allIds where !preferences.isPinned(id) && !preferences.manualOrder.contains(id) {
            preferences.registerNewTally(id)
        }

        if preferences.sortEnabled {
            tallies = allIds
                .compactMap { tallyById[$0] }
                .sorted(by: sortComparator)
        } else {
            let pinned = preferences.pinnedIds.compactMap { tallyById[$0] }
            let unpinned = preferences.manualOrder
                .filter { !preferences.isPinned($0) && allIds.contains($0) }
                .compactMap { tallyById[$0] }
            let known = Set(preferences.pinnedIds + preferences.manualOrder)
            let orphans = allIds.subtracting(known).compactMap { tallyById[$0] }
            tallies = pinned + unpinned + orphans
        }
    }

    private func sortComparator(_ lhs: Tally, _ rhs: Tally) -> Bool {
        let lhsUpdated = lhs.lastUpdated ?? lhs.created ?? .distantPast
        let rhsUpdated = rhs.lastUpdated ?? rhs.created ?? .distantPast
        if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
        let lhsCreated = lhs.created ?? .distantPast
        let rhsCreated = rhs.created ?? .distantPast
        return lhsCreated > rhsCreated
    }
}
