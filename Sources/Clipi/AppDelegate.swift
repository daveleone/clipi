import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var store = ClipboardStore(settings: settings)
    private lazy var model = PanelModel(store: store)
    private lazy var updater = Updater(settings: settings)
    private lazy var quickLook = QuickLookController(imagesDir: store.imagesDir)
    private lazy var quickPaste = QuickPasteController(model: QuickPasteModel(imagesDir: store.imagesDir))
    private lazy var hotKey = HotKey { [weak self] in self?.toggleQuickPaste() }
    private var panel: PanelController!
    private var watcher: ScreenshotWatcher!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    /// macOS 27+: lets the menu bar show the icon as open while the panel is up.
    private var expandedInterface: AnyObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipi")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        panel = PanelController(rootView: PanelView(model: model, store: store, settings: settings, updater: updater))
        panel.onShow = { [weak self] in self?.model.prepareForShow() }
        panel.panel.keyEquivalentHandler = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
        panel.panel.escapeHandler = { [weak self] in self?.model.escape() }
        setUpExpandedInterface()
        setUpQuickLook()
        setUpQuickPaste()

        model.onCopy = { [weak self] item in
            self?.store.copy(item)
            self?.panel.hide()
        }
        model.onClose = { [weak self] in self?.panel.hide() }
        model.onClearHistory = { [weak self] in self?.confirmClearHistory() }
        model.onOpenFullDiskAccessSettings = { [weak self] in
            self?.panel.hide()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
        model.onError = { [weak self] in self?.show($0) }
        model.onOpenURL = { [weak self] url in
            self?.panel.hide()
            NSWorkspace.shared.open(url)
        }

        store.start()

        watcher = ScreenshotWatcher { [weak self] url in
            self?.store.addScreenshot(at: url)
        }
        Publishers.CombineLatest(settings.$screenshotToClipboard, settings.$keepFloatingThumbnail)
            .sink { [weak self] enabled, keepThumbnail in
                self?.applyScreenshotSettings(enabled: enabled, keepThumbnail: keepThumbnail)
            }
            .store(in: &cancellables)

        updater.startAutomaticChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.handleTermination()
        ScreenCapturePreferences.restoreFloatingThumbnail()
    }

    private func applyScreenshotSettings(enabled: Bool, keepThumbnail: Bool) {
        guard enabled else {
            watcher.stop()
            ScreenCapturePreferences.restoreFloatingThumbnail()
            return
        }
        if keepThumbnail {
            ScreenCapturePreferences.restoreFloatingThumbnail()
        } else {
            ScreenCapturePreferences.disableFloatingThumbnail()
        }
        watcher.watchesTemporaryItems = keepThumbnail
        watcher.start()
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.hide()
            showStatusMenu()
        } else if expandedInterface != nil {
            // The menu bar opens the panel through the expanded interface session: this is a safety net.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, !panel.isVisible, !panel.wasHiddenRecently else { return }
                panel.show(below: button)
            }
        } else {
            panel.toggle(below: button)
        }
    }

    /// On macOS 27 the menu bar opens and closes the panel like a menu, keeping the icon highlighted
    /// while it's open. Earlier versions toggle it from the button's action.
    private func setUpExpandedInterface() {
        #if compiler(>=6.4)  // Xcode 27: the macOS 27 SDK
        if #available(macOS 27.0, *) {
            let bridge = ExpandedInterfaceBridge()
            bridge.onBegin = { [weak self] in
                guard let self, let button = statusItem.button, !panel.isVisible else { return }
                panel.show(below: button)
            }
            bridge.onEnd = { [weak self] in self?.panel.hide() }
            statusItem.expandedInterfaceDelegate = bridge
            panel.onHide = { [weak bridge] in bridge?.cancel() }
            expandedInterface = bridge
        }
        #endif
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Clipi", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() {
        if let button = statusItem.button { panel.show(below: button) }
    }

    @objc private func openSettings() {
        openPanel()
        model.showSettings()
    }

    // MARK: - Quick Paste

    private func setUpQuickPaste() {
        quickPaste.model.onPaste = { [weak self] in self?.paste($0) }
        quickPaste.model.onClose = { [weak self] in self?.quickPaste.hide(animated: true) }
        model.onRecordingShortcut = { [weak self] recording in
            guard let self else { return }
            recording ? hotKey.unregister() : hotKey.register(settings.quickPasteShortcut)
        }
        model.onGrantAccessibility = { [weak self] in
            self?.panel.hide()
            Paster.requestAccess()
            Paster.openAccessibilitySettings()
        }
        settings.$quickPasteShortcut
            .sink { [weak self] in self?.hotKey.register($0) }
            .store(in: &cancellables)
    }

    private func toggleQuickPaste() {
        if quickPaste.isVisible {
            quickPaste.hide(animated: true)
            return
        }
        panel.hide()
        quickPaste.model.prepare(with: store.items)
        quickPaste.show()
    }

    /// Puts the item on the clipboard and sends ⌘V to the app in front (Clipi never took focus).
    private func paste(_ item: ClipItem) {
        quickPaste.hide()
        store.copy(item)
        guard Paster.isTrusted else {
            // Copied anyway: ⌘V works. Ask once for the permission that pastes directly.
            Paster.requestAccess()
            return
        }
        // Give the keyboard back to the app before typing into it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Paster.pasteIntoFrontApp()
        }
    }

    // MARK: - Quick Look

    private func setUpQuickLook() {
        quickLook.items = { [weak self] in self?.model.results ?? [] }
        quickLook.selectedID = { [weak self] in self?.model.selectedItem?.id }
        quickLook.onMove = { [weak self] in self?.model.move(by: $0) }
        quickLook.onSelect = { [weak self] in self?.model.select($0) }
        quickLook.onEnd = { [weak self] in
            // Back to the search field, if the panel is still open
            guard let self, panel.isVisible else { return }
            panel.panel.makeKeyAndOrderFront(nil)
        }
        panel.panel.quickLook = quickLook
        panel.panel.spaceHandler = { [weak self] in
            guard let self, model.spaceOpensPreview else { return false }
            quickLook.toggle()
            return true
        }
        // Hovering another row while previewing shows that one
        model.$selectedID
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.quickLook.selectionDidChange() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Keyboard

    /// ⌘Y Quick Look, ⌘, settings, ⌘W closes, ⌘Q quits; ⌘X/C/V/A edit the search field
    /// (there's no Edit menu to route them, since Clipi has no menu bar of its own).
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        let editing: [String: Selector] = [
            "x": #selector(NSText.cut(_:)),
            "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)),
            "a": #selector(NSText.selectAll(_:)),
        ]
        switch key {
        case "y":
            if model.page == .history, model.selectedItem != nil { quickLook.toggle() }
        case ",":
            model.showSettings()
        case "w":
            panel.hide()
        case "q":
            NSApp.terminate(nil)
        default:
            guard let action = editing[key] else { return false }
            return NSApp.sendAction(action, to: nil, from: self)
        }
        return true
    }

    // MARK: - Alerts

    private func confirmClearHistory() {
        panel.hide()
        let count = store.items.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This permanently removes \(count == 1 ? "1 item" : "\(count) items")."
        alert.addButton(withTitle: "Clear History").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    private func show(_ error: Error) {
        panel.hide()
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}

#if compiler(>=6.4)
@available(macOS 27.0, *)
@MainActor
private final class ExpandedInterfaceBridge: NSObject, @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    private var session: NSStatusItemExpandedInterfaceSession?

    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        self.session = session
        onBegin()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        session = nil
        onEnd()
    }

    /// The panel closed on its own (copy, ⎋, click elsewhere): end the session too.
    func cancel() {
        session?.cancel()
    }
}
#endif
