//
//  Tally.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import Foundation
import FirebaseFirestore

struct Tally: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var count: Int
    var owner: DocumentReference
    var sharedWith: [DocumentReference]?
    @ServerTimestamp var created: Date?
    var lastUpdated: Date?
    var lastUpdatedBy: DocumentReference?
    /// `uid -> "view" | "edit"`. The owner is implicit and is not present in this map.
    var permissions: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case count = "Count"
        case owner = "Owner"
        case sharedWith = "Shared With"
        case created = "Created"
        case lastUpdated = "LastUpdated"
        case lastUpdatedBy = "LastUpdatedBy"
        case permissions = "Permissions"
    }

    var sharedRefs: [DocumentReference] { sharedWith ?? [] }
    var perms: [String: String] { permissions ?? [:] }
}

extension Tally: Equatable {
    static func == (lhs: Tally, rhs: Tally) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.count == rhs.count
            && lhs.owner.path == rhs.owner.path
            && lhs.sharedRefs.map(\.path) == rhs.sharedRefs.map(\.path)
            && lhs.created == rhs.created
            && lhs.lastUpdated == rhs.lastUpdated
            && lhs.lastUpdatedBy?.path == rhs.lastUpdatedBy?.path
            && lhs.perms == rhs.perms
    }
}

enum TallyRole: Equatable {
    case owner
    case edit
    case view
    case none

    var canIncrement: Bool {
        switch self {
        case .owner, .edit: return true
        case .view, .none: return false
        }
    }

    var canRename: Bool { canIncrement }
    var canEditCount: Bool { canIncrement }
    var isOwner: Bool { self == .owner }
    var hasLock: Bool { self == .view }
}

extension Tally {
    func role(for uid: String) -> TallyRole {
        if owner.documentID == uid {
            return .owner
        }
        switch perms[uid] {
        case "edit": return .edit
        case "view": return .view
        default:
            return sharedRefs.contains(where: { $0.documentID == uid }) ? .view : .none
        }
    }
}
