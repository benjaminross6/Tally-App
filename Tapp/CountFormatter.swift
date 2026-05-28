//
//  CountFormatter.swift
//  Tapp
//
//  Renders tally counts in the user's chosen NumberType (account-wide).
//

import Foundation

enum CountFormatter {
    static func string(for count: Int, numberType: String) -> String {
        switch numberType {
        case UserNumberType.roman:
            return roman(for: count)
        case UserNumberType.stick:
            return String(count)
        default:
            return String(count)
        }
    }

    /// Groups of 1…5 marks for stick rendering (`StickTallyView`).
    static func stickGroups(for count: Int) -> [Int] {
        StickTallyLogic.groups(for: abs(count))
    }

    static func stickGroupCount(for count: Int) -> Int {
        StickTallyLogic.groupCount(for: abs(count))
    }

    // MARK: - Roman

    private static func roman(for count: Int) -> String {
        if count == 0 { return "N" }
        if count < 0 { return "-" + roman(for: -count) }

        if count <= 3999 {
            return romanMagnitude(count)
        }

        let thousands = count / 1000
        let remainder = count % 1000
        let upper = applyVinculum(romanMagnitude(thousands))
        if remainder == 0 { return upper }
        return upper + romanMagnitude(remainder)
    }

    private static func romanMagnitude(_ value: Int) -> String {
        guard value > 0 else { return "" }
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var n = value
        var out = ""
        for (amount, symbol) in table {
            while n >= amount {
                out += symbol
                n -= amount
            }
        }
        return out
    }

    /// Vinculum: overline means ×1000 (design doc).
    private static func applyVinculum(_ roman: String) -> String {
        roman.unicodeScalars.map { "\($0)\u{0305}" }.joined()
    }

}
