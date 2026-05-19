//
//  UserProfile.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var username: String?
    var email: String
    @ServerTimestamp var joined: Date?
    var tallies: [DocumentReference]?
    var friends: [DocumentReference]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case username = "Username"
        case email = "Email"
        case joined = "Joined"
        case tallies = "Tallies"
        case friends = "Friends"
    }

    var tallyRefs: [DocumentReference] { tallies ?? [] }
    var friendRefs: [DocumentReference] { friends ?? [] }
    var displayUsername: String { username ?? "" }
}

extension UserProfile: Equatable {
    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.username == rhs.username
            && lhs.email == rhs.email
            && lhs.joined == rhs.joined
            && lhs.tallyRefs.map(\.path) == rhs.tallyRefs.map(\.path)
            && lhs.friendRefs.map(\.path) == rhs.friendRefs.map(\.path)
    }
}
