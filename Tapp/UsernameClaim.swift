//
//  UsernameClaim.swift
//  Tapp
//
//  Owns the `usernames/{username}` collection, which enforces username uniqueness
//  across all users. Each document holds `{ uid: String }` and is the source of truth
//  for "is this username taken?" lookups (the Add Friend flow also reads from here).
//

import Foundation
import FirebaseFirestore

enum UsernameClaimError: LocalizedError {
    case invalidFormat
    case alreadyTaken
    case notOwned

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Usernames are 3-20 characters, lowercase letters, digits, or underscores."
        case .alreadyTaken:
            return "That username is already taken."
        case .notOwned:
            return "That username isn't yours to release."
        }
    }
}

enum UsernameClaim {
    nonisolated static let collectionName = "usernames"
    nonisolated private static let pattern = "^[a-z0-9_]{3,20}$"

    /// Validates `[a-z0-9_]{3,20}`. Trims whitespace and lowercases first.
    nonisolated static func sanitize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func isWellFormed(_ username: String) -> Bool {
        let sanitized = sanitize(username)
        return sanitized.range(of: pattern, options: .regularExpression) != nil
    }

    /// Returns the uid that currently owns the given username, or nil if it's free.
    /// Does not perform validation; call `isWellFormed` first.
    static func ownerUid(of username: String) async throws -> String? {
        let sanitized = sanitize(username)
        let snapshot = try await Firestore.firestore()
            .collection(collectionName)
            .document(sanitized)
            .getDocument()
        guard snapshot.exists else { return nil }
        return snapshot.data()?["uid"] as? String
    }

    /// Atomically:
    ///   1. asserts `usernames/{username}` does not exist (or is already owned by `uid`),
    ///   2. writes `{ uid }` into it,
    ///   3. writes `Username` onto `users/{uid}`.
    /// Throws `.invalidFormat` or `.alreadyTaken` on conflict.
    static func claim(_ rawUsername: String, for uid: String) async throws {
        guard isWellFormed(rawUsername) else { throw UsernameClaimError.invalidFormat }
        let username = sanitize(rawUsername)

        let db = Firestore.firestore()
        let usernameRef = db.collection(collectionName).document(username)
        let userRef = db.collection("users").document(uid)

        _ = try await db.runTransaction({ txn, errorPtr -> Any? in
            let usernameSnap: DocumentSnapshot
            do {
                usernameSnap = try txn.getDocument(usernameRef)
            } catch let fetchErr as NSError {
                errorPtr?.pointee = fetchErr
                return nil
            }

            if usernameSnap.exists, (usernameSnap.data()?["uid"] as? String) != uid {
                let err = NSError(
                    domain: "UsernameClaim",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: UsernameClaimError.alreadyTaken.errorDescription ?? ""]
                )
                errorPtr?.pointee = err
                return nil
            }

            txn.setData(["uid": uid], forDocument: usernameRef)
            txn.setData(["Username": username], forDocument: userRef, merge: true)
            return nil
        })
    }

    /// Releases a username claim previously held by `uid`. No-op if the username
    /// doesn't exist or is owned by someone else.
    static func release(_ rawUsername: String, ownedBy uid: String) async throws {
        let username = sanitize(rawUsername)
        guard !username.isEmpty else { return }

        let db = Firestore.firestore()
        let usernameRef = db.collection(collectionName).document(username)

        _ = try await db.runTransaction({ txn, errorPtr -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(usernameRef)
            } catch let fetchErr as NSError {
                errorPtr?.pointee = fetchErr
                return nil
            }
            guard snap.exists, (snap.data()?["uid"] as? String) == uid else {
                return nil
            }
            txn.deleteDocument(usernameRef)
            return nil
        })
    }

    /// Convenience for renaming: atomically releases `oldUsername` (if owned) and
    /// claims `newUsername`. Both updates land in a single transaction.
    static func rename(from oldUsername: String, to newUsername: String, uid: String) async throws {
        guard isWellFormed(newUsername) else { throw UsernameClaimError.invalidFormat }
        let oldName = sanitize(oldUsername)
        let newName = sanitize(newUsername)
        guard oldName != newName else { return }

        let db = Firestore.firestore()
        let oldRef = db.collection(collectionName).document(oldName)
        let newRef = db.collection(collectionName).document(newName)
        let userRef = db.collection("users").document(uid)

        _ = try await db.runTransaction({ txn, errorPtr -> Any? in
            do {
                let newSnap = try txn.getDocument(newRef)
                if newSnap.exists, (newSnap.data()?["uid"] as? String) != uid {
                    let err = NSError(
                        domain: "UsernameClaim",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: UsernameClaimError.alreadyTaken.errorDescription ?? ""]
                    )
                    errorPtr?.pointee = err
                    return nil
                }

                if !oldName.isEmpty {
                    let oldSnap = try txn.getDocument(oldRef)
                    if oldSnap.exists, (oldSnap.data()?["uid"] as? String) == uid {
                        txn.deleteDocument(oldRef)
                    }
                }

                txn.setData(["uid": uid], forDocument: newRef)
                txn.setData(["Username": newName], forDocument: userRef, merge: true)
            } catch let fetchErr as NSError {
                errorPtr?.pointee = fetchErr
            }
            return nil
        })
    }
}
