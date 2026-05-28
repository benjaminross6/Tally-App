//
//  AvatarColorAssignment.swift
//  Tapp
//
//  Fixed 12-color palette for user avatars (design doc). Assigned at signup from uid.
//

import Foundation
import SwiftUI

enum AvatarColorAssignment {
  /// Hex colors for `users/{uid}.AvatarColor` (no leading `#` in Firestore).
  static let paletteHex: [String] = [
    "ED4545", "F28C2E", "F2C72E", "8CC752", "45B064", "45B0B0",
    "458CDB", "6B5CD9", "9F5CD9", "D95C9E", "8C6B52", "80808C",
  ]

  static func hex(for uid: String) -> String {
    let index = paletteIndex(for: uid)
    return paletteHex[index]
  }

  static func color(for uid: String) -> Color {
    color(for: uid, hex: hex(for: uid))
  }

  static func color(for uid: String, hex: String) -> Color {
    Color(hex: hex) ?? Color(hex: Self.hex(for: uid)) ?? .gray
  }

  private static func paletteIndex(for uid: String) -> Int {
    var hasher = Hasher()
    hasher.combine(uid)
    let raw = abs(hasher.finalize())
    return raw % paletteHex.count
  }
}

private extension Color {
  init?(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    self.init(red: r, green: g, blue: b)
  }
}
