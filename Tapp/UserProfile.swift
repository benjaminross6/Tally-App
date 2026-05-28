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
    /// `arabic` | `roman` | `stick`
    var numberType: String?
    /// `system` | `light` | `dark`
    var theme: String?
    /// Hex color for avatar background (e.g. `ED4545`).
    var avatarColor: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case username = "Username"
        case email = "Email"
        case joined = "Joined"
        case tallies = "Tallies"
        case friends = "Friends"
        case numberType = "NumberType"
        case theme = "Theme"
        case avatarColor = "AvatarColor"
    }

    var tallyRefs: [DocumentReference] { tallies ?? [] }
    var friendRefs: [DocumentReference] { friends ?? [] }
    var displayUsername: String { username ?? "" }
    var resolvedNumberType: String { numberType ?? UserNumberType.arabic }
    var resolvedTheme: String { theme ?? UserTheme.system }
}

enum UserNumberType {
    static let arabic = "arabic"
    static let roman = "roman"
    static let stick = "stick"
}

enum UserTheme {
    static let system = "system"
    static let light = "light"
    static let dark = "dark"
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
            && lhs.numberType == rhs.numberType
            && lhs.theme == rhs.theme
            && lhs.avatarColor == rhs.avatarColor
    }
}
