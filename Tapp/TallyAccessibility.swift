//
//  TallyAccessibility.swift
//  Tapp
//
//  Shared VoiceOver labels and count descriptions.
//

import Foundation
import SwiftUI

enum TallyAccessibility {
    static func countDescription(count: Int, numberType: String) -> String {
        switch numberType {
        case UserNumberType.roman:
            return CountFormatter.string(for: count, numberType: UserNumberType.roman)
        case UserNumberType.stick:
            return "\(count)"
        default:
            return "\(count)"
        }
    }

    static func rowLabel(name: String, count: Int, numberType: String, ownerUsername: String, isViewOnly: Bool) -> String {
        var parts = [name, "count \(countDescription(count: count, numberType: numberType))", "owned by \(ownerUsername)"]
        if isViewOnly {
            parts.append("view only")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - View modifiers

struct TallyRowAccessibilityModifier: ViewModifier {
    let label: String
    let canIncrement: Bool
    let onIncrement: () -> Void
    let onOpenFullScreen: () -> Void

    func body(content: Content) -> some View {
        if canIncrement {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityHint("Double tap to increment.")
                .accessibilityAction(named: "Open Full Screen Tally", onOpenFullScreen)
                .accessibilityAction(named: "Increment", onIncrement)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityHint("View only. Cannot increment.")
                .accessibilityAction(named: "Open Full Screen Tally", onOpenFullScreen)
        }
    }
}
