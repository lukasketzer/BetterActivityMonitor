import SwiftUI

/// Developer aid behind `BAM_SNAPSHOT_DIR`: cards report their frames so the snapshot run can flag
/// layout bugs (cards overlapping each other, content spilling out of its card, cards cut off by the window).
/// Disabled otherwise, so normal runs pay nothing.
@MainActor
enum LayoutAudit {
    static let enabled = ProcessInfo.processInfo.environment["BAM_SNAPSHOT_DIR"] != nil

    struct Entry {
        var name: String
        /// Set by onAppear. Views that are only measured (e.g. ViewThatFits' unused variants) report
        /// geometry but never appear, so they must not count.
        var onScreen = false
        var card: CGRect = .null
        var content: CGRect = .null
    }

    private static var entries: [String: Entry] = [:]

    /// `key` identifies one view instance; `name` is what reports show. Instances of the same card can
    /// briefly coexist (e.g. when a layout switches variants), so they must not share a key.
    static func record(_ key: String, name: String, card: CGRect? = nil, content: CGRect? = nil) {
        if let card { entries[key, default: Entry(name: name)].card = card }
        if let content { entries[key, default: Entry(name: name)].content = content }
    }

    static func appeared(_ key: String, name: String) { entries[key, default: Entry(name: name)].onScreen = true }
    static func remove(_ id: String) { entries[id] = nil }
    /// Number of cards currently reporting; a screen with cards that reports none means the audit is blind.
    static var cardNames: [String] { entries.values.filter { $0.onScreen && !$0.card.isNull }.map(\.name).sorted() }

    /// Problems in the current layout. `visible` is the window's content area in the same (global) space.
    static func issues(visible: CGRect) -> [String] {
        let tolerance: CGFloat = 1.5
        let cards = entries.values.filter { $0.onScreen && !$0.card.isNull }.sorted { $0.name < $1.name }
        var result: [String] = []
        for e in cards {
            let id = e.name
            let card = e.card.insetBy(dx: -tolerance, dy: -tolerance)
            if !e.content.isNull, !card.contains(e.content) {
                result.append("\(id): content \(describe(e.content)) spills out of card \(describe(e.card))")
            }
            // Cards scrolled out of view vertically are fine; horizontal clipping never is.
            if e.card.minX < visible.minX - tolerance || e.card.maxX > visible.maxX + tolerance {
                result.append("\(id): card \(describe(e.card)) is cut off horizontally (window \(describe(visible)))")
            }
        }
        for (i, a) in cards.enumerated() {
            for b in cards[(i + 1)...] {
                let overlap = a.card.intersection(b.card)
                if !overlap.isNull, overlap.width > tolerance, overlap.height > tolerance {
                    result.append("\(a.name) overlaps \(b.name) by \(describe(overlap))")
                }
            }
        }
        return result
    }

    private static func describe(_ r: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0f×%.0f)", r.minX, r.minY, r.width, r.height)
    }
}

extension View {
    /// Reports this view's global frame to `LayoutAudit` as the card (or its content) named `name`.
    /// `key` must be unique per card instance and shared by its card and content (e.g. a `@State` UUID).
    @ViewBuilder
    func layoutAudit(_ name: String, key: UUID, content: Bool = false) -> some View {
        if LayoutAudit.enabled {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                LayoutAudit.record(key.uuidString, name: name, card: content ? nil : frame, content: content ? frame : nil)
            }
            .onAppear { LayoutAudit.appeared(key.uuidString, name: name) }
            .onDisappear { LayoutAudit.remove(key.uuidString) }
        } else {
            self
        }
    }
}
