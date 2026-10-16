import AppKit
import ServiceManagement

/// State of the panel: page, search, selection, plus the settings that don't live in `AppSettings`.
@MainActor
final class PanelModel: ObservableObject {
    enum Page {
        case history, settings
    }

    @Published var page: Page = .history
    @Published var query = "" {
        didSet {
            selectedID = results.first?.id
            lastEdit = Date()
        }
    }
    @Published var selectedID: UUID?
    @Published var scrollTarget: UUID?
    @Published var focusToken = 0
    /// Bumped on every open so relative times are fresh.
    @Published var openedAt = Date()
    @Published var hasFullDiskAccess = false
    @Published var hasAccessibility = false

    @Published var launchAtLogin: Bool {
        didSet {
            let service = SMAppService.mainApp
            guard launchAtLogin != (service.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                launchAtLogin = service.status == .enabled
                onError(error)
            }
        }
    }

    var onCopy: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onClearHistory: () -> Void = {}
    var onOpenFullDiskAccessSettings: () -> Void = {}
    var onError: (Error) -> Void = { _ in }
    var onOpenURL: (URL) -> Void = { _ in }
    /// While a shortcut is being recorded the current one is switched off, so it can be typed.
    var onRecordingShortcut: (Bool) -> Void = { _ in }
    var onGrantAccessibility: () -> Void = {}

    let store: ClipboardStore
    private var lastKeyboardMove = Date.distantPast
    private var lastEdit = Date.distantPast
    private var lastSelectionMove = Date.distantPast

    /// Space opens Quick Look instead of typing when the search is empty, or when you've moved
    /// the selection (↑ ↓ or the pointer) since you last typed: "foo bar" still gets its space.
    var spaceOpensPreview: Bool {
        page == .history && selectedItem != nil && (query.isEmpty || lastSelectionMove > lastEdit)
    }

    init(store: ClipboardStore) {
        self.store = store
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Lifecycle

    func prepareForShow() {
        page = .history
        query = ""
        selectedID = store.items.first?.id
        scrollTarget = selectedID
        openedAt = Date()
        focusToken += 1
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasFullDiskAccess = ScreenshotWatcher.hasFullDiskAccess
        hasAccessibility = Paster.isTrusted
    }

    /// ⎋: leave Settings, then clear the search, then close.
    func escape() {
        if page == .settings {
            showHistory()
        } else if !query.isEmpty {
            query = ""
        } else {
            onClose()
        }
    }

    func showSettings() {
        hasFullDiskAccess = ScreenshotWatcher.hasFullDiskAccess
        hasAccessibility = Paster.isTrusted
        page = .settings
    }

    func showHistory() {
        page = .history
        focusToken += 1
    }

    // MARK: - History

    var results: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.items }
        return store.items.filter { item in
            [item.text, item.sourceAppName, item.isScreenshot ? "Screenshot" : nil]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var selectedItem: ClipItem? {
        let results = results
        return results.first { $0.id == selectedID } ?? results.first
    }

    func move(by delta: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + delta, 0), results.count - 1)
        selectedID = results[next].id
        scrollTarget = selectedID
        lastKeyboardMove = Date()
        lastSelectionMove = lastKeyboardMove
    }

    /// Like a menu, hovering selects — unless rows are moving under a still pointer because of
    /// the keyboard: scrolling with ↑ ↓, or results changing while you type.
    func hover(_ id: UUID) {
        let now = Date()
        guard now.timeIntervalSince(lastKeyboardMove) > 0.5, now.timeIntervalSince(lastEdit) > 0.5 else { return }
        selectedID = id
        lastSelectionMove = now
    }

    /// Selects an item from outside the list (Quick Look's own navigation) and scrolls to it.
    func select(_ id: UUID) {
        selectedID = id
        scrollTarget = id
        lastSelectionMove = Date()
    }

    func copy(_ item: ClipItem) {
        onCopy(item)
    }

    func copySelected() {
        if let item = selectedItem { copy(item) }
    }

    func delete(_ item: ClipItem) {
        let results = results
        if item.id == selectedItem?.id, let index = results.firstIndex(where: { $0.id == item.id }) {
            let neighbour = results.indices.contains(index + 1) ? index + 1 : index - 1
            selectedID = results.indices.contains(neighbour) ? results[neighbour].id : nil
        }
        store.delete(item)
    }

    func deleteSelected() {
        if let item = selectedItem { delete(item) }
    }
}
