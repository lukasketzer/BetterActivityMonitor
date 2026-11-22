import AppKit
import Observation
import SwiftUI

/// The menu bar item, as a plain `NSStatusItem` with a popover.
///
/// It used to be a SwiftUI `MenuBarExtra`. That cost about 2 % of a core at a 1 s refresh: every new label
/// image made AppKit redraw the item's copy on each display, each redraw set the button's appearance, and
/// `MenuBarExtra` observed that through KVO and pushed the label to the button again. Here the image is
/// rendered once per visible change and handed to the button only when it is a different image.
@MainActor
final class StatusItemController: NSObject {
    private let store: SystemStore
    private var item: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        return popover
    }()

    init(store: SystemStore) {
        self.store = store
        super.init()
        // Defaults change from inside SwiftUI layout too (pages store their expanded state): rendering right there
        // re-entered SwiftUI's text measurement and crashed, so both callbacks only schedule an update.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleUpdate() }
        }
        settingsChanged()
        track()
    }

    private var updateScheduled = false

    /// Coalesces settings and appearance changes into one update on the next turn of the main run loop.
    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateScheduled = false
            settingsChanged()
        }
    }

    private var wanted: Bool { UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarExtra) }

    /// Shows or removes the item, and redraws it for changed menu bar settings.
    private func settingsChanged() {
        if wanted, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.imagePosition = .imageOnly
            item.button?.setAccessibilityLabel("BetterActivityMonitor")
            // Only the colored style depends on the menu bar's light or dark look; templates are tinted by AppKit.
            appearanceObservation = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleUpdate() }
            }
            self.item = item
        } else if !wanted, let item {
            popover.performClose(nil)
            appearanceObservation = nil
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
        render()
    }

    /// Re-renders whenever the sampled values the item shows change.
    private func track() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func render() {
        let defaults = UserDefaults.standard
        let items = MenuBarItems(rawValue: defaults.string(forKey: SettingsKey.menuBarItems) ?? "") ?? MenuBarItems.default
        // Read the values even while the item is hidden, so observation keeps running and showing it is instant.
        let readings = store.menuBarReadings(items.enabled, fahrenheit: defaults.bool(forKey: SettingsKey.fahrenheit))
        guard let button = item?.button else { return }
        let glyph = MenuBarGlyph(readings: readings,
                                 style: MenuBarStyle(rawValue: defaults.string(forKey: SettingsKey.menuBarStyle) ?? "") ?? .rings,
                                 colored: defaults.bool(forKey: SettingsKey.menuBarColored),
                                 symbols: defaults.bool(forKey: SettingsKey.menuBarSymbols),
                                 theme: Theme.named(defaults.string(forKey: SettingsKey.theme) ?? Theme.system.id))
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let image = MenuBarRenderer.image(glyph, scale: scale, colorScheme: dark ? .dark : .light)
            ?? NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: nil)
        // The renderer returns the same image while nothing visible changed; setting it again would still redraw.
        if button.image !== image { button.image = image }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Built for each opening and dropped on close: SwiftUI keeps updating a hosting view that is off screen.
            let host = NSHostingController(rootView: MenuBarView(close: { [weak self] in self?.popover.performClose(nil) })
                .environment(store))
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}
