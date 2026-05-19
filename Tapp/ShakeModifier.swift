//
//  ShakeModifier.swift
//  Tapp
//
//  Small horizontal shake animation. Driven by an Int that increments to trigger
//  a new shake; used as the "view-only tap" feedback per the design doc.
//

import SwiftUI

struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * shakesPerUnit),
                y: 0
            )
        )
    }
}

extension View {
    /// Apply with an `Int` that increments to trigger a new shake. Wrap the
    /// increment in `withAnimation(.linear(duration: 0.3))` to play once.
    func shake(times: Int) -> some View {
        self.modifier(Shake(animatableData: CGFloat(times)))
    }
}
