//
//  StickTallyView.swift
//  Tapp
//
//  Custom tally-mark groups (four verticals + diagonal on five), matching app icon geometry.
//

import SwiftUI

// MARK: - Logic & layout (testable)

enum StickTallyLogic {
    /// Decomposes a positive count into groups of 1…5 marks.
    static func groups(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var remaining = count
        var result: [Int] = []
        while remaining > 0 {
            let n = min(5, remaining)
            result.append(n)
            remaining -= n
        }
        return result
    }

    static func groupCount(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + 4) / 5
    }

    /// Matches `Scripts/generate_app_icon.py` proportions.
    static func groupWidth(forHeight height: CGFloat) -> CGFloat {
        let stroke = strokeWidth(forHeight: height)
        let gap = stroke * StickTallyMetrics.gapRatio
        return 3 * gap + stroke
    }

    static func strokeWidth(forHeight height: CGFloat) -> CGFloat {
        height * (0.048 / 0.52)
    }
}

enum StickTallyMetrics {
    /// Center-to-center gap / stroke width (icon script `GAP_RATIO`).
    static let gapRatio: CGFloat = 1.55 * 1.5
    static let minGroupHeight: CGFloat = 14
    static let rowMaxGroupHeight: CGFloat = 22
    static let fullScreenMaxGroupHeight: CGFloat = 56
    static let groupSpacing: CGFloat = 3
    static let rowSpacing: CGFloat = 3
    static let overflowLabelWidth: CGFloat = 36
}

struct StickTallyLayoutResult: Equatable {
    let visibleGroupCount: Int
    let groupHeight: CGFloat
    let groupWidth: CGFloat
    let columns: Int
    let rows: Int
    let showArabicOverflow: Bool
    let totalGroupCount: Int
}

enum StickTallyLayout {
  static func fit(
        groupCount: Int,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxGroupHeight: CGFloat
    ) -> StickTallyLayoutResult {
        guard groupCount > 0 else {
            return StickTallyLayoutResult(
                visibleGroupCount: 0,
                groupHeight: StickTallyMetrics.minGroupHeight,
                groupWidth: 0,
                columns: 0,
                rows: 0,
                showArabicOverflow: false,
                totalGroupCount: 0
            )
        }

        let minH = StickTallyMetrics.minGroupHeight
        let maxH = min(maxGroupHeight, maxHeight)
        var bestPartial: StickTallyLayoutResult?

        var h = maxH
        while h >= minH {
            let gw = StickTallyLogic.groupWidth(forHeight: h)
            let cellW = gw + StickTallyMetrics.groupSpacing
            let cellH = h + StickTallyMetrics.rowSpacing
            let columns = max(1, Int(floor((maxWidth + StickTallyMetrics.groupSpacing) / cellW)))
            let rows = max(1, Int(floor((maxHeight + StickTallyMetrics.rowSpacing) / cellH)))
            let capacity = columns * rows

            if capacity >= groupCount {
                return StickTallyLayoutResult(
                    visibleGroupCount: groupCount,
                    groupHeight: h,
                    groupWidth: gw,
                    columns: columns,
                    rows: rows,
                    showArabicOverflow: false,
                    totalGroupCount: groupCount
                )
            }

            bestPartial = StickTallyLayoutResult(
                visibleGroupCount: capacity,
                groupHeight: h,
                groupWidth: gw,
                columns: columns,
                rows: rows,
                showArabicOverflow: true,
                totalGroupCount: groupCount
            )
            h -= 1
        }

        // Overflow: reserve space for Arabic label beside sticks.
        let stickMaxW = max(0, maxWidth - StickTallyMetrics.overflowLabelWidth)
        h = minH
        let gw = StickTallyLogic.groupWidth(forHeight: h)
        let cellW = gw + StickTallyMetrics.groupSpacing
        let cellH = h + StickTallyMetrics.rowSpacing
        let columns = max(1, Int(floor((stickMaxW + StickTallyMetrics.groupSpacing) / cellW)))
        let rows = max(1, Int(floor((maxHeight + StickTallyMetrics.rowSpacing) / cellH)))
        let capacity = min(groupCount, columns * rows)

        return StickTallyLayoutResult(
            visibleGroupCount: capacity,
            groupHeight: h,
            groupWidth: gw,
            columns: columns,
            rows: rows,
            showArabicOverflow: capacity < groupCount,
            totalGroupCount: groupCount
        )
    }
}

// MARK: - Views

struct StickTallyStyle: Equatable {
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let maxGroupHeight: CGFloat

    static func row(maxWidth: CGFloat, maxHeight: CGFloat = 36) -> StickTallyStyle {
        StickTallyStyle(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            maxGroupHeight: StickTallyMetrics.rowMaxGroupHeight
        )
    }

    static func fullScreen(maxWidth: CGFloat, maxHeight: CGFloat = 220) -> StickTallyStyle {
        StickTallyStyle(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            maxGroupHeight: StickTallyMetrics.fullScreenMaxGroupHeight
        )
    }
}

struct StickTallyView: View {
    let count: Int
    let style: StickTallyStyle

    private var isNegative: Bool { count < 0 }
    private var positiveCount: Int { abs(count) }
    private var groups: [Int] { StickTallyLogic.groups(for: positiveCount) }
    private var layout: StickTallyLayoutResult {
        StickTallyLayout.fit(
            groupCount: groups.count,
            maxWidth: style.maxWidth,
            maxHeight: style.maxHeight,
            maxGroupHeight: style.maxGroupHeight
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if isNegative {
                Text("-")
                    .font(.system(size: layout.groupHeight * 0.55, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, layout.groupHeight * 0.1)
            }

            if positiveCount == 0 {
                StickZeroDot(size: max(6, layout.groupHeight * 0.22))
            } else {
                stickGrid
            }

            if layout.showArabicOverflow {
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: style.maxWidth, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count)")
    }

    @ViewBuilder
    private var stickGrid: some View {
        let visible = min(layout.visibleGroupCount, groups.count)
        let columns = max(1, layout.columns)
        let gridColumns = Array(
            repeating: GridItem(.fixed(layout.groupWidth), spacing: StickTallyMetrics.groupSpacing),
            count: columns
        )

        LazyVGrid(columns: gridColumns, alignment: .trailing, spacing: StickTallyMetrics.rowSpacing) {
            ForEach(0..<visible, id: \.self) { index in
                StickGroupView(marks: groups[index], height: layout.groupHeight)
                    .frame(width: layout.groupWidth, height: layout.groupHeight)
            }
        }
        .frame(
            width: gridWidth(columns: columns),
            height: gridHeight(rows: rowCount(visible: visible, columns: columns)),
            alignment: .trailing
        )
    }

    private func gridWidth(columns: Int) -> CGFloat {
        CGFloat(columns) * layout.groupWidth
            + CGFloat(max(0, columns - 1)) * StickTallyMetrics.groupSpacing
    }

    private func rowCount(visible: Int, columns: Int) -> Int {
        guard visible > 0, columns > 0 else { return 0 }
        return (visible + columns - 1) / columns
    }

    private func gridHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * layout.groupHeight
            + CGFloat(max(0, rows - 1)) * StickTallyMetrics.rowSpacing
    }
}

private struct StickZeroDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.primary)
            .frame(width: size, height: size)
    }
}

/// One tally group: 1–4 vertical strokes, or 5 with a diagonal slash on top.
struct StickGroupView: View {
    let marks: Int
    let height: CGFloat

    private var width: CGFloat { StickTallyLogic.groupWidth(forHeight: height) }

    var body: some View {
        Canvas { context, size in
            let stroke = StickTallyLogic.strokeWidth(forHeight: height)
            let gap = stroke * StickTallyMetrics.gapRatio
            let centerY = size.height / 2
            let centerX = size.width / 2
            let stickH = size.height
            let top = centerY - stickH / 2
            let color = GraphicsContext.Shading.color(.primary)

            let markCount = min(4, max(1, marks == 5 ? 4 : marks))
            let xOffsets: [CGFloat] = marks == 5
                ? [-1.5, -0.5, 0.5, 1.5].map { $0 * gap }
                : (0..<markCount).map { CGFloat($0) * gap - CGFloat(markCount - 1) * gap / 2 }

            for x in xOffsets {
                let rect = CGRect(
                    x: centerX + x - stroke / 2,
                    y: top,
                    width: stroke,
                    height: stickH
                )
                let path = Path(roundedRect: rect, cornerRadius: stroke / 2)
                context.fill(path, with: color)
            }

            if marks == 5, let first = xOffsets.first, let last = xOffsets.last {
                let p1 = CGPoint(x: centerX + first - stroke / 2, y: top + stickH)
                let p2 = CGPoint(x: centerX + last + stroke / 2, y: top)
                var slash = Path()
                slash.move(to: p1)
                slash.addLine(to: p2)
                context.stroke(
                    slash,
                    with: color,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
