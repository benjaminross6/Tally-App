//
//  UserPreferences.swift
//  Tapp
//
//  Account-wide NumberType and Theme cycling (Settings).
//

import Foundation
import SwiftUI

enum UserPreferences {
    static func nextNumberType(after current: String) -> String {
        switch current {
        case UserNumberType.arabic: return UserNumberType.roman
        case UserNumberType.roman: return UserNumberType.stick
        default: return UserNumberType.arabic
        }
    }

    static func numberTypeLabel(_ type: String) -> String {
        switch type {
        case UserNumberType.roman: return "Roman"
        case UserNumberType.stick: return "Stick"
        default: return "Arabic"
        }
    }

    static func nextTheme(after current: String) -> String {
        switch current {
        case UserTheme.system: return UserTheme.light
        case UserTheme.light: return UserTheme.dark
        default: return UserTheme.system
        }
    }

    static func themeLabel(_ theme: String) -> String {
        switch theme {
        case UserTheme.light: return "Light"
        case UserTheme.dark: return "Dark"
        default: return "System"
        }
    }

    static func colorScheme(for theme: String) -> ColorScheme? {
        switch theme {
        case UserTheme.light: return .light
        case UserTheme.dark: return .dark
        default: return nil
        }
    }
}
