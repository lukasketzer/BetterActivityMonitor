import AppIntents
import SystemKit
import WidgetKit

/// How often a widget asks to be updated. Set per widget via right-click → Edit Widget.
enum RefreshInterval: String, AppEnum {
    case twoSeconds, tenSeconds, thirtySeconds, oneMinute, fiveMinutes, fifteenMinutes

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Update Speed"
    static let caseDisplayRepresentations: [RefreshInterval: DisplayRepresentation] = [
        .twoSeconds: "Every 2 seconds",
        .tenSeconds: "Every 10 seconds",
        .thirtySeconds: "Every 30 seconds",
        .oneMinute: "Every minute",
        .fiveMinutes: "Every 5 minutes",
        .fifteenMinutes: "Every 15 minutes",
    ]

    var seconds: TimeInterval {
        switch self {
        case .twoSeconds: 2
        case .tenSeconds: 10
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        }
    }
}

/// Settings for the widgets whose only option is how often they update.
struct RefreshIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Widget Settings"
    static let description = IntentDescription(
        "Choose how often the widget updates. Fast speeds only hold while Better Activity Monitor is open; otherwise macOS updates widgets less often."
    )

    @Parameter(title: "Update", default: .oneMinute)
    var interval: RefreshInterval
}

/// The next update after `interval`, noted for the app so it can push reloads at that pace while it runs.
func refreshPolicy(_ interval: RefreshInterval, kind: String) -> TimelineReloadPolicy {
    WidgetRefreshBoard.record(kind: kind, seconds: interval.seconds)
    return .after(.now.addingTimeInterval(interval.seconds))
}

/// Shared by the widgets that show a `SystemEntry` and have only the update setting.
struct SystemProvider: AppIntentTimelineProvider {
    var kind: String

    func placeholder(in context: Context) -> SystemEntry { .placeholder }

    func snapshot(for configuration: RefreshIntent, in context: Context) async -> SystemEntry {
        context.isPreview ? .placeholder : .sample()
    }

    func timeline(for configuration: RefreshIntent, in context: Context) async -> Timeline<SystemEntry> {
        Timeline(entries: [.sample()], policy: refreshPolicy(configuration.interval, kind: kind))
    }
}
