import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let historySizes = [50, 100, 200, 500]

    private let defaults = UserDefaults.standard

    /// When true the history is saved to disk and survives restarts and shutdowns.
    @Published var persistHistory: Bool {
        didSet { defaults.set(persistHistory, forKey: Keys.persistHistory) }
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    /// When true screenshots (⌘⇧3/4/5) are copied to the clipboard and added to the history.
    @Published var screenshotToClipboard: Bool {
        didSet { defaults.set(screenshotToClipboard, forKey: Keys.screenshotToClipboard) }
    }

    /// Leaves the system floating thumbnail on. Instant copies then need Full Disk Access.
    @Published var keepFloatingThumbnail: Bool {
        didSet { defaults.set(keepFloatingThumbnail, forKey: Keys.keepFloatingThumbnail) }
    }

    /// Looks for a new release on GitHub at launch and once a day.
    @Published var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: Keys.checkForUpdates) }
    }

    /// Opens the quick paste panel from any app. nil: no shortcut.
    @Published var quickPasteShortcut: Shortcut? {
        didSet {
            // An empty value remembers "no shortcut", a missing one means the default
            let data = quickPasteShortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
            defaults.set(data, forKey: Keys.quickPasteShortcut)
        }
    }

    private enum Keys {
        static let persistHistory = "persistHistory"
        static let maxItems = "maxItems"
        static let screenshotToClipboard = "screenshotToClipboard"
        static let keepFloatingThumbnail = "keepFloatingThumbnail"
        static let checkForUpdates = "checkForUpdates"
        static let quickPasteShortcut = "quickPasteShortcut"
    }

    init() {
        defaults.register(defaults: [
            Keys.persistHistory: true,
            Keys.maxItems: 100,
            Keys.screenshotToClipboard: true,
            Keys.checkForUpdates: true,
        ])
        persistHistory = defaults.bool(forKey: Keys.persistHistory)
        screenshotToClipboard = defaults.bool(forKey: Keys.screenshotToClipboard)
        keepFloatingThumbnail = defaults.bool(forKey: Keys.keepFloatingThumbnail)
        checkForUpdates = defaults.bool(forKey: Keys.checkForUpdates)
        if let data = defaults.data(forKey: Keys.quickPasteShortcut) {
            quickPasteShortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        } else {
            quickPasteShortcut = .quickPasteDefault
        }
        // Snap to the closest size offered in Settings
        let stored = defaults.integer(forKey: Keys.maxItems)
        maxItems = Self.historySizes.min { abs($0 - stored) < abs($1 - stored) } ?? 100
    }
}
