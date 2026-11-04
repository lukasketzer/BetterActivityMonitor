#if WIDGETS
import Foundation
import SystemKit
import WidgetKit

/// Keeps the desktop widgets fresh while the app runs: reloads each kind of widget at the fastest update speed
/// one of them is set to (right-click → Edit Widget). A widget's own timeline is only a hint WidgetKit stretches.
/// Only in the Xcode build, which embeds the widget extension.
@MainActor
enum WidgetFeed {
    private static var lastReload: [String: Date] = [:]

    static func tick(_ now: Date) {
        for (kind, interval) in WidgetRefreshBoard.intervals(now: now) {
            // Half a second of slack so a 2 s speed isn't missed by ticks landing just short of it.
            if lastReload[kind].map({ now.timeIntervalSince($0) >= interval - 0.5 }) ?? true {
                lastReload[kind] = now
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }
}
#endif
