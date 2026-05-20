//
//  LocalTallyColors.swift
//  Tapp
//
//  Per-device, per-tally color picker storage. The doc spec says color is local:
//  only this user, only on this device. Nothing here ever touches Firestore.
//

import SwiftUI
import Observation

/// `@Observable` bump value that views read to re-tint when any tally color changes.
/// `LocalTallyColors.setSwatchIndex` increments `version` on each write, which
/// invalidates any view that observed `LocalTallyColorsObserver.shared.version`.
@Observable
final class LocalTallyColorsObserver {
    static let shared = LocalTallyColorsObserver()
    private(set) var version: Int = 0
    fileprivate func bump() { version &+= 1 }
}

/// 12 fixed swatches plus "Default" (the app accent). Index 0 is "Default".
enum TallyColorPalette {
    static let swatches: [Color] = [
        Color(red: 0.93, green: 0.27, blue: 0.27), // red
        Color(red: 0.95, green: 0.55, blue: 0.18), // orange
        Color(red: 0.95, green: 0.78, blue: 0.18), // yellow
        Color(red: 0.55, green: 0.78, blue: 0.32), // lime
        Color(red: 0.27, green: 0.69, blue: 0.39), // green
        Color(red: 0.27, green: 0.69, blue: 0.69), // teal
        Color(red: 0.27, green: 0.55, blue: 0.85), // blue
        Color(red: 0.42, green: 0.36, blue: 0.85), // indigo
        Color(red: 0.62, green: 0.36, blue: 0.85), // purple
        Color(red: 0.85, green: 0.36, blue: 0.62), // pink
        Color(red: 0.55, green: 0.42, blue: 0.32), // brown
        Color(red: 0.50, green: 0.50, blue: 0.55)  // gray
    ]
}

enum LocalTallyColors {
    private static let prefix = "tapp.tallyColorIndex."

    /// Reads the swatch index stored for this tally. Returns nil for "Default".
    static func storedSwatchIndex(for tallyId: String) -> Int? {
        let key = prefix + tallyId
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let raw = UserDefaults.standard.integer(forKey: key)
        guard raw >= 0, raw < TallyColorPalette.swatches.count else { return nil }
        return raw
    }

    /// nil = Default (accent).
    static func setSwatchIndex(_ index: Int?, for tallyId: String) {
        let key = prefix + tallyId
        if let index, (0..<TallyColorPalette.swatches.count).contains(index) {
            UserDefaults.standard.set(index, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        LocalTallyColorsObserver.shared.bump()
    }

    /// Returns the SwiftUI color to render. Falls back to `.accentColor`.
    static func color(for tallyId: String) -> Color {
        guard let idx = storedSwatchIndex(for: tallyId) else {
            return .accentColor
        }
        return TallyColorPalette.swatches[idx]
    }

    /// Soft, tinted background suitable for a row or full-screen background.
    static func backgroundTint(for tallyId: String) -> Color {
        color(for: tallyId).opacity(0.18)
    }

    /// Palette preview matching the muted tint used on tally rows.
    static func previewSwatchColor(for index: Int?) -> Color {
        guard let index else { return Color.accentColor.opacity(0.18) }
        return TallyColorPalette.swatches[index].opacity(0.18)
    }
}
