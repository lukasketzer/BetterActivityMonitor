import SwiftUI

/// Grid of dashboard cards laid out in a single pass. Nested HStacks/VStacks (and ViewThatFits) measure
/// every child several times per frame, which made live window resizing cost 50–90 ms per frame.
/// Here each card is asked for its height once at its final width, then placed at an exact size.
///
/// Cards declare their row (`dashboardRow`) and either a relative width (`dashboardWeight`) or a fixed
/// one (`dashboardFixedWidth`). Rows grow to share any spare height of `viewportHeight`; when the cards
/// need more than that, the layout reports its full height so an enclosing ScrollView scrolls.
struct DashboardLayout: Layout {
    var viewportHeight: CGFloat
    var spacing: CGFloat = 10
    var rowSpacing: CGFloat = 12
    var padding: CGFloat = 12

    struct Cache {
        var width: CGFloat = -1
        var frames: [CGRect] = []
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 800
        cache.width = -1  // card contents may have changed since the last pass; always re-measure here
        compute(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        compute(width: bounds.width, subviews: subviews, cache: &cache)
        for (subview, frame) in zip(subviews, cache.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
        cache.width = -1
    }

    private func compute(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        // placeSubviews directly follows sizeThatFits for the same width; reuse that measurement.
        if cache.width == width, cache.frames.count == subviews.count { return }
        let rows = Dictionary(grouping: subviews.indices, by: { subviews[$0][DashboardRow.self] })
            .sorted { $0.key < $1.key }.map(\.value)
        let inner = max(width - 2 * padding, 1)

        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var rowHeights: [CGFloat] = []
        for row in rows {
            let fixed = row.compactMap { subviews[$0][DashboardFixedWidth.self] }.reduce(0, +)
            let weights = row.filter { subviews[$0][DashboardFixedWidth.self] == nil }
                .map { subviews[$0][DashboardWeight.self] }.reduce(0, +)
            let flexible = max(inner - fixed - spacing * CGFloat(row.count - 1), 0)
            var x = padding
            var height: CGFloat = 0
            for index in row {
                let w = subviews[index][DashboardFixedWidth.self] ?? flexible * subviews[index][DashboardWeight.self] / max(weights, 0.001)
                // The one measurement per card: its natural height at its final width.
                let h = subviews[index].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
                frames[index] = CGRect(x: x, y: 0, width: w, height: h)
                height = max(height, h)
                x += w + spacing
            }
            rowHeights.append(height)
        }

        let natural = rowHeights.reduce(0, +) + rowSpacing * CGFloat(max(rows.count - 1, 0)) + 2 * padding
        // Share spare viewport height between rows in proportion to their natural height.
        let extra = max(viewportHeight - natural, 0)
        let total = max(rowHeights.reduce(0, +), 1)
        var y = padding
        for (row, base) in zip(rows, rowHeights) {
            let h = base + extra * base / total
            for index in row {
                frames[index].origin.y = y
                frames[index].size.height = h
            }
            y += h + rowSpacing
        }
        cache.width = width
        cache.frames = frames
        cache.height = max(natural, viewportHeight)
    }
}

private struct DashboardRow: LayoutValueKey { static let defaultValue = 0 }
private struct DashboardWeight: LayoutValueKey { static let defaultValue: CGFloat = 1 }
private struct DashboardFixedWidth: LayoutValueKey { static let defaultValue: CGFloat? = nil }

extension View {
    func dashboardRow(_ row: Int, weight: CGFloat = 1, fixedWidth: CGFloat? = nil) -> some View {
        layoutValue(key: DashboardRow.self, value: row)
            .layoutValue(key: DashboardWeight.self, value: weight)
            .layoutValue(key: DashboardFixedWidth.self, value: fixedWidth)
    }
}
