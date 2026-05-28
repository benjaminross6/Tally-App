//
//  ColorContrast.swift
//  Tapp
//
//  WCAG 2.x contrast helpers for palette validation (AA normal text ≥ 4.5:1).
//

import SwiftUI
import UIKit

enum ColorContrast {
    static let aaNormalTextMinimum: CGFloat = 4.5

    static func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
        let fg = relativeLuminance(foreground)
        let bg = relativeLuminance(background)
        let lighter = max(fg, bg)
        let darker = min(fg, bg)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func meetsAANormalText(foreground: UIColor, background: UIColor) -> Bool {
        contrastRatio(foreground: foreground, background: background) >= aaNormalTextMinimum
    }

    /// Alpha-composites `overlay` on top of `base` in sRGB.
    static func blended(overlay: UIColor, alpha: CGFloat, base: UIColor) -> UIColor {
        var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        overlay.getRed(&or, green: &og, blue: &ob, alpha: &oa)
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let a = alpha * oa
        let inv = 1 - a
        return UIColor(
            red: or * a + br * inv,
            green: og * a + bg * inv,
            blue: ob * a + bb * inv,
            alpha: 1
        )
    }

    static func relativeLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// Tally row tint: swatch at 18% over system background.
    static func tallyRowBackground(swatch: UIColor, colorScheme: ColorScheme) -> UIColor {
        let base: UIColor = colorScheme == .dark ? .black : .white
        return blended(overlay: swatch, alpha: 0.18, base: base)
    }

    /// Validates every palette swatch for primary text on a tinted row (light + dark).
    static func paletteSwatchesMeetAAOnTintedRows() -> Bool {
        let lightOK = TallyColorPalette.uiSwatches.allSatisfy { swatch in
            let bg = tallyRowBackground(swatch: swatch, colorScheme: .light)
            return meetsAANormalText(foreground: .black, background: bg)
        }
        let darkOK = TallyColorPalette.uiSwatches.allSatisfy { swatch in
            let bg = tallyRowBackground(swatch: swatch, colorScheme: .dark)
            return meetsAANormalText(foreground: .white, background: bg)
        }
        return lightOK && darkOK
    }
}

extension TallyColorPalette {
    static var uiSwatches: [UIColor] {
        swatches.map { UIColor($0) }
    }
}
