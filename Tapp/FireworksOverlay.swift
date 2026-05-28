//
//  FireworksOverlay.swift
//  Tapp
//
//  Brief burst animation for increments and home landing. Honors Reduce Motion.
//  Rapid taps extend visibility (0.5s after last tap) without restarting glitches.
//

import SwiftUI

@MainActor
enum FireworksLimiter {
    private static var activeCount = 0
    private static let maxConcurrent = 3

    static func tryAcquire() -> Bool {
        guard activeCount < maxConcurrent else { return false }
        activeCount += 1
        return true
    }

    static func release() {
        activeCount = max(0, activeCount - 1)
    }
}

/// Drives a single on/off fireworks burst. Call `trigger()` on each tap; visibility stays
/// until the burst finishes and at least 0.5s has passed since the latest tap.
@Observable
@MainActor
final class FireworksPlayback {
    private(set) var isActive = false
    private(set) var burstStartedAt: Date?

    var burstDuration: TimeInterval = 1.5
    var tapTailDuration: TimeInterval = 0.5
    var onFinished: (() -> Void)?

    private var hideTask: Task<Void, Never>?

    func trigger() {
        let now = Date()
        if burstStartedAt == nil {
            burstStartedAt = now
            isActive = true
        }
        scheduleHide(lastTap: now)
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
        isActive = false
        burstStartedAt = nil
    }

    private func scheduleHide(lastTap: Date) {
        hideTask?.cancel()
        let burstStart = burstStartedAt ?? lastTap
        hideTask = Task { @MainActor in
            let animationEnd = burstStart.addingTimeInterval(burstDuration)
            let tapTailEnd = lastTap.addingTimeInterval(tapTailDuration)
            let hideAt = max(animationEnd, tapTailEnd)
            let delay = hideAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            isActive = false
            burstStartedAt = nil
            onFinished?()
        }
    }
}

struct FireworksOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var playback: FireworksPlayback

    @State private var sparkleOpacity: Double = 0
    @State private var sparkleTask: Task<Void, Never>?

    var body: some View {
        Group {
            if playback.isActive {
                if reduceMotion {
                    sparkleView
                } else {
                    burstView
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { applyReduceMotionDuration() }
        .onChange(of: reduceMotion) { _, _ in applyReduceMotionDuration() }
        .onChange(of: playback.isActive) { _, active in
            if active && reduceMotion {
                runSparkle()
            } else {
                sparkleTask?.cancel()
            }
        }
    }

    private var burstView: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playback.isActive)) { timeline in
            Canvas { context, size in
                guard playback.isActive, let start = playback.burstStartedAt else { return }
                let elapsed = timeline.date.timeIntervalSince(start)
                let duration = playback.burstDuration
                let progress = min(1, elapsed / duration)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let particles = particleOffsets(start: start, time: timeline.date, count: 28)
                for (index, offset) in particles.enumerated() {
                    let fade = max(0, 1 - progress)
                    let point = CGPoint(
                        x: center.x + offset.dx * CGFloat(progress) * 2.2,
                        y: center.y + offset.dy * CGFloat(progress) * 2.2
                    )
                    let hue = Double(index % 7) / 7
                    let path = Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
                    context.fill(
                        path,
                        with: .color(Color(hue: hue, saturation: 0.75, brightness: 0.95).opacity(Double(fade)))
                    )
                }
            }
        }
    }

    private var sparkleView: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: cos(Double(index) / 8 * .pi * 2) * 24,
                        y: sin(Double(index) / 8 * .pi * 2) * 24
                    )
                    .opacity(sparkleOpacity)
            }
        }
    }

    private func particleOffsets(start: Date, time: Date, count: Int) -> [CGVector] {
        let elapsed = time.timeIntervalSince(start)
        return (0..<count).map { index in
            let angle = Double(index) / Double(count) * .pi * 2 + elapsed * 0.4
            let radius = 40.0 + Double(index % 5) * 8
            return CGVector(dx: cos(angle) * radius, dy: sin(angle) * radius)
        }
    }

    private func applyReduceMotionDuration() {
        playback.burstDuration = reduceMotion ? 1.2 : 1.5
    }

    private func runSparkle() {
        sparkleTask?.cancel()
        sparkleOpacity = 0
        sparkleTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.6)) {
                sparkleOpacity = 1
            }
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                sparkleOpacity = 0
            }
        }
    }
}
