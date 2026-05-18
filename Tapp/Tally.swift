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
    var sharedWith: [DocumentReference]
    @ServerTimestamp var created: Date?
    var change: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name = "Name"
        case count = "Count"
        case owner = "Owner"
        case sharedWith = "Shared With"
        case created = "Created"
        case change = "Change"
    }
}
