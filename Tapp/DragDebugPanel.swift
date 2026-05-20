//
//  DragDebugPanel.swift
//  Tapp
//
//  Floating panel showing recent DragDebugLog lines.
//

import SwiftUI

struct DragDebugPanel: View {
    @Bindable var log = DragDebugLog.shared

    var body: some View {
        if log.isPanelVisible {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Drag debug")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Button("Clear") { log.clear() }
                        .font(.caption2)
                    Button("Hide") { log.isPanelVisible = false }
                        .font(.caption2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.75))

                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .onChange(of: log.lines.count) { _, _ in
                            if let last = log.lines.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(Color.black.opacity(0.82))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        } else {
            Button("Show drag log") {
                log.isPanelVisible = true
                log.log("panel reopened")
            }
            .font(.caption2)
            .padding(8)
            .background(Color.black.opacity(0.6))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}
