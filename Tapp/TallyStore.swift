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

    private let userRef: DocumentReference
    private var userListener: ListenerRegistration?
    private var tallyListeners: [String: ListenerRegistration] = [:]

    init(userId: String) {
        self.userRef = Firestore.firestore().collection("users").document(userId)
        startListening()
    }

    deinit {
        userListener?.remove()
        tallyListeners.values.forEach { $0.remove() }
    }

    func addTally(name: String) async throws {
        let db = Firestore.firestore()
        let newTallyRef = db.collection("tallies").document()

        let data: [String: Any] = [
            "Name": name,
            "Count": 0,
            "Owner": userRef,
            "Shared With": [DocumentReference](),
            "Created": FieldValue.serverTimestamp(),
            "Change": 0
        ]
        try await newTallyRef.setData(data)
        try await userRef.updateData([
            "Tallies": FieldValue.arrayUnion([newTallyRef])
        ])
    }

    func increment(_ tally: Tally) async throws {
        guard let id = tally.id else { return }
        try await Firestore.firestore()
            .collection("tallies")
            .document(id)
            .updateData([
                "Count": FieldValue.increment(Int64(1))
            ])
    }

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

        let refs = (snapshot?.data()?["Tallies"] as? [DocumentReference]) ?? []
        syncTallyListeners(for: refs)
        isLoading = false
    }

    private func syncTallyListeners(for refs: [DocumentReference]) {
        let currentIds = Set(tallyListeners.keys)
        let newIds = Set(refs.map(\.documentID))

        for id in currentIds.subtracting(newIds) {
            tallyListeners[id]?.remove()
            tallyListeners.removeValue(forKey: id)
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
              let tally = try? snapshot.data(as: Tally.self) else {
            return
        }

        if let idx = tallies.firstIndex(where: { $0.id == tally.id }) {
            tallies[idx] = tally
        } else {
            tallies.append(tally)
        }
        tallies.sort { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }
}
