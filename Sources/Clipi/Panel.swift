import AppKit
import Quartz
import SwiftUI

/// A panel that takes keyboard focus without activating Clipi, like Spotlight:
/// the app you were in stays frontmost, so ⌘V right after copying pastes there.
///
/// It's built like the system's menu windows (NSPopupMenuWindow): a borderless window holding
/// menu-flavored Liquid Glass, with the menus' soft shadow.
final class FloatingPanel: NSPanel {
    /// Handles ⌘ shortcuts. Return true when the event was used.
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var escapeHandler: (() -> Void)?
    /// Handles Space before the search field gets it. Return true when it opened Quick Look.
    var spaceHandler: (() -> Bool)?
    /// Handles keys in panels without a text field (↑ ↓ ↩). Return true when the key was used.
    var keyDownHandler: ((NSEvent) -> Bool)?
    /// Sees clicks first. Return true when the click was used.
    var mouseDownHandler: ((NSEvent) -> Bool)?
    /// Drives the Quick Look panel, which looks for a controller in the key window's responder chain.
    var quickLook: QuickLookController?

    init(contentSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // What NSPopupMenuWindow tells the window server: rounded corners, so the border and the shadow
    // follow the glass instead of a square window (which shows as dark corners), and the menus'
    // soft shadow. (Private AppKit hooks: ignored if they ever go away.)
    @objc func _cornerRadius() -> CGFloat { PanelController.cornerRadius }
    @objc func _shadowRadius() -> NSSize { NSSize(width: 8, height: 8) }
    @objc func _shadowOffset() -> NSSize { NSSize(width: 0, height: 4) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        escapeHandler?()
    }

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, event.keyCode == 49, modifiers.isEmpty, spaceHandler?() == true {
            return
        }
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown, mouseDownHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }


    /// Hosts SwiftUI content on the menus' Liquid Glass.
    func setContent<Content: View>(_ rootView: Content) {
        contentView = Self.makeGlass(containing: NSHostingView(rootView: rootView))
    }

    /// The Liquid Glass of system menus (and of Mousip's menu), holding `content`.
    static func makeGlass(containing content: NSView) -> NSView {
        let radius = PanelController.cornerRadius
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            // What NSPopupMenuWindow sets on its glass: the lighter "menu" look and its bright rim.
            if glass.responds(to: NSSelectorFromString("set_subvariant:")) {
                glass.setValue("menu", forKey: "_subvariant")
            }
            if glass.responds(to: NSSelectorFromString("set_adaptiveAppearance:")) {
                glass.setValue(1, forKey: "_adaptiveAppearance")
            }
            glass.contentView = content
            return glass
        }
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        background.maskImage?.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        background.maskImage?.resizingMode = .stretch
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return background
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        quickLook != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLook?.beginControl(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLook?.endControl(panel)
    }
}

/// Shows the panel under the status item and hides it on outside clicks.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 360, height: 560)
    /// The corner radius of menus.
    static let cornerRadius: CGFloat = 12

    let panel = FloatingPanel(contentSize: PanelController.size)
    var onShow: () -> Void = {}
    var onHide: () -> Void = {}
    private var clickMonitor: Any?
    private var lastHide = Date.distantPast

    var isVisible: Bool { panel.isVisible }
    var wasHiddenRecently: Bool { Date().timeIntervalSince(lastHide) < 0.5 }

    init<Content: View>(rootView: Content) {
        super.init()
        panel.delegate = self

        panel.setContent(rootView)
    }

    func toggle(below button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHide) > 0.3 {
            // A click on the status item first hides the panel (it loses focus): don't reopen it.
            show(below: button)
        }
    }

    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = Self.size
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let y = anchor.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)

        onShow()
        panel.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.quickLook?.close()
        panel.orderOut(nil)
        lastHide = Date()
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        onHide()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Quick Look takes the keyboard while it previews: that isn't leaving the panel.
        guard !QuickLookController.isVisible else { return }
        hide()
    }
}
