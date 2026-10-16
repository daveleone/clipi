import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

/// The small panel opened by the global shortcut: the last few copies, pasted into the app in front.
@MainActor
final class QuickPasteModel: ObservableObject {
    static let count = 5

    @Published private(set) var items: [ClipItem] = []
    @Published var selectedID: UUID?
    @Published private(set) var openedAt = Date()
    /// The panel sits below the pointer, so its tab points up; above it, the tab points down.
    @Published var tabOnTop = true
    var onPaste: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}

    let imagesDir: URL

    init(imagesDir: URL) {
        self.imagesDir = imagesDir
    }

    func prepare(with items: [ClipItem]) {
        self.items = Array(items.prefix(Self.count))
        selectedID = self.items.first?.id
        openedAt = Date()
    }

    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? -1
        selectedID = items[min(max(current + delta, 0), items.count - 1)].id
    }

    func pasteSelected() {
        if let item = items.first(where: { $0.id == selectedID }) { onPaste(item) }
    }

    /// ↑ ↓ choose, ↩ pastes, ⎋ closes.
    func handle(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_UpArrow: move(by: -1)
        case kVK_DownArrow: move(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: pasteSelected()
        case kVK_Escape: onClose()
        default: return false
        }
        return true
    }
}

struct QuickPasteView: View {
    @ObservedObject var model: QuickPasteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paste")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 15)
                .padding(.top, 9)
                .padding(.bottom, 4)

            if model.items.isEmpty {
                Text("Nothing copied yet")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.items) { item in
                        ClipRow(item: item,
                                isSelected: item.id == model.selectedID,
                                imagesDir: model.imagesDir,
                                now: model.openedAt)
                            .onHover { if $0 { model.selectedID = item.id } }
                            .onTapGesture { model.onPaste(item) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        // Room for the tab, on the side it points from
        .padding(model.tabOnTop ? .top : .bottom, Callout.tabHeight)
        .frame(width: QuickPasteController.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The quick paste panel's shape: a rounded rectangle with a small tab pointing at the pointer.
@MainActor
enum Callout {
    static let tabHeight: CGFloat = 9
    static let tabWidth: CGFloat = 22
    /// The tab never gets closer than this to a side, so it stays clear of the rounded corners.
    static let tabInset: CGFloat = PanelController.cornerRadius + tabWidth / 2 + 4

    /// Gives the glass the callout shape (Liquid Glass only: a private hook, skipped if missing).
    static func shape(_ glass: NSView, size: CGSize, tipX: CGFloat, tabOnTop: Bool) {
        let selector = NSSelectorFromString("_setPath:")
        guard glass.responds(to: selector) else { return }
        var path = path(size: size, tipX: tipX)
        if !tabOnTop {
            var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
            path = path.copy(using: &flip) ?? path
        }
        _ = glass.perform(selector, with: path)
    }

    /// The tab on top, in view coordinates (y up).
    private static func path(size: CGSize, tipX: CGFloat) -> CGPath {
        let radius = PanelController.cornerRadius
        let body = CGRect(x: 0, y: 0, width: size.width, height: size.height - tabHeight)
        let path = CGMutablePath()
        path.addRoundedRect(in: body, cornerWidth: radius, cornerHeight: radius)

        // Soft shoulders into a rounded tip, like a popover's arrow
        let base = body.maxY - 0.5
        let top = base + tabHeight
        let half = tabWidth / 2
        let tab = CGMutablePath()
        tab.move(to: CGPoint(x: tipX - half - 4, y: base))
        tab.addCurve(to: CGPoint(x: tipX - 3, y: top - 1.5),
                     control1: CGPoint(x: tipX - half + 3, y: base),
                     control2: CGPoint(x: tipX - 6, y: top - 4))
        tab.addQuadCurve(to: CGPoint(x: tipX + 3, y: top - 1.5), control: CGPoint(x: tipX, y: top + 0.5))
        tab.addCurve(to: CGPoint(x: tipX + half + 4, y: base),
                     control1: CGPoint(x: tipX + 6, y: top - 4),
                     control2: CGPoint(x: tipX + half - 3, y: base))
        tab.closeSubpath()
        path.addPath(tab)
        return path
    }
}

/// Shows the quick paste panel at the pointer, with its tab pointing at it.
@MainActor
final class QuickPasteController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 320
    /// Room around the glass for the shadow it draws itself: any less and the window cuts it off.
    private static let margin: CGFloat = 40

    let model: QuickPasteModel
    private let panel = FloatingPanel(contentSize: NSSize(width: width, height: 100))
    private let container = NSView()
    private let glass: NSView
    /// Measures the content's height for the current items.
    private let measuringHost: NSHostingView<QuickPasteView>
    private var clickMonitor: Any?
    private var isClosing = false

    var isVisible: Bool { panel.isVisible && !isClosing }

    init(model: QuickPasteModel) {
        self.model = model
        measuringHost = NSHostingView(rootView: QuickPasteView(model: model))
        glass = FloatingPanel.makeGlass(containing: NSHostingView(rootView: QuickPasteView(model: model)))
        super.init()
        panel.delegate = self
        // The window's own shadow is a rectangle: the glass draws one that follows the tab too.
        panel.hasShadow = false
        container.wantsLayer = true
        container.addSubview(glass)
        panel.contentView = container
        panel.keyDownHandler = { [weak model] in model?.handle($0) ?? false }
        // A click in the transparent margin around the glass is a click outside the panel
        panel.mouseDownHandler = { [weak self] event in
            guard let self, !glass.frame.contains(event.locationInWindow) else { return false }
            hide(animated: true)
            return true
        }
        panel.escapeHandler = { [weak self] in self?.hide(animated: true) }
    }

    /// `anchor`: what to point at, in screen coordinates. By default the pointer.
    func show(anchor: NSRect? = nil) {
        isClosing = false
        let anchor = anchor ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(anchor.origin) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let gap: CGFloat = 4

        measuringHost.rootView = QuickPasteView(model: model)
        let size = NSSize(width: Self.width, height: measuringHost.fittingSize.height)
        // Below the pointer, or above it when there's no room
        let below = anchor.minY - gap - size.height >= visible.minY
        model.tabOnTop = below
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = below ? anchor.minY - gap - size.height : min(anchor.maxY + gap, visible.maxY - size.height)
        let tipX = min(max(anchor.midX - x, Callout.tabInset), size.width - Callout.tabInset)

        let m = Self.margin
        glass.frame = NSRect(x: m, y: m, width: size.width, height: size.height)
        Callout.shape(glass, size: size, tipX: tipX, tabOnTop: below)
        panel.setFrame(NSRect(x: x - m, y: y - m, width: size.width + 2 * m, height: size.height + 2 * m), display: true)

        appear(from: CGPoint(x: m + tipX, y: below ? m + size.height : m))
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(animated: true) }
        }
    }

    /// Animated: fades out (⎋, a click elsewhere). Not animated: gone at once, before pasting.
    func hide(animated: Bool = false) {
        guard panel.isVisible, !isClosing else { return }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        isClosing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                guard self.isClosing else { return }
                self.isClosing = false
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide(animated: true)
    }

    /// Grows out of the tab's tip while fading in, like a popover.
    private func appear(from tip: CGPoint) {
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        guard let layer = container.layer else { return }
        // Layer-backed views anchor at (0, 0): scale around the tip by moving it there and back.
        var start = CATransform3DMakeTranslation(tip.x, tip.y, 0)
        start = CATransform3DScale(start, 0.9, 0.9, 1)
        start = CATransform3DTranslate(start, -tip.x, -tip.y, 0)
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = 0.24
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)  // quick, soft landing
        layer.add(grow, forKey: "appear")
    }
}

/// Pastes into the app in front by sending it ⌘V, which needs the Accessibility permission.
@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings › Privacy & Security › Accessibility.
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func pasteIntoFrontApp() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
