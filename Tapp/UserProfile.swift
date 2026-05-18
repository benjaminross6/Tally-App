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
    var email: String
    @ServerTimestamp var joined: Date?
    var tallies: [DocumentReference]

    enum CodingKeys: String, CodingKey {
        case id
        case name = "Name"
        case email = "Email"
        case joined = "Joined"
        case tallies = "Tallies"
    }
}
