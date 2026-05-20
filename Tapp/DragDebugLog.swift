//
//  DragDebugLog.swift
//  Tapp
//
//  On-device drag/reorder debug log. Remove or gate behind a flag when done debugging.
//

import Foundation
import Observation

@Observable
final class DragDebugLog {
    static let shared = DragDebugLog()

    private(set) var lines: [String] = []
    var isPanelVisible: Bool = true

    /// When true, logs go to console + buffer only (no SwiftUI refresh during active drag).
    var pausesLivePanelUpdates: Bool = false
    private var pendingLines: [String] = []

    private let maxLines = 100
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withTime, .withColonSeparatorInTime]
        return f
    }()

    private init() {}

    func log(_ message: String) {
        let stamp = isoFormatter.string(from: Date())
        let line = "[\(stamp)] \(message)"
        #if DEBUG
        print("DragDebug \(line)")
        #endif
        if pausesLivePanelUpdates {
            pendingLines.append(line)
            if pendingLines.count > maxLines {
                pendingLines.removeFirst(pendingLines.count - maxLines)
            }
        } else {
            appendToPanel(line)
        }
    }

    func flushPendingToPanel() {
        guard !pendingLines.isEmpty else { return }
        for line in pendingLines {
            appendToPanel(line)
        }
        pendingLines.removeAll()
    }

    func clear() {
        lines.removeAll()
        pendingLines.removeAll()
        log("log cleared")
    }

    private func appendToPanel(_ line: String) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
