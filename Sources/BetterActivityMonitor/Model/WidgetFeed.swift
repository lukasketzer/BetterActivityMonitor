#if WIDGETS
import Foundation
import WidgetKit

/// Keeps the desktop widgets fresh while the app runs: asks WidgetKit to reload them every few minutes.
/// Only in the Xcode build, which embeds the widget extension.
@MainActor
enum WidgetFeed {
    private static var lastReload: Date?

    static func tick(_ now: Date) {
        if lastReload.map({ now.timeIntervalSince($0) >= 5 * 60 }) ?? true {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
#endif
