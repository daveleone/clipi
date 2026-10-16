import AppKit
import Quartz

/// Shows the selected history item in the system Quick Look panel, like Space in Finder.
/// ↑ ↓ keep moving the selection while the preview is open, and the preview follows it.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var items: () -> [ClipItem] = { [] }
    var selectedID: () -> UUID? = { nil }
    var onMove: (Int) -> Void = { _ in }
    /// Called when Quick Look's own ‹ › buttons (or ← →) show another item.
    var onSelect: (UUID) -> Void = { _ in }
    /// Called when the preview closes, to give the keyboard back to Clipi's panel.
    var onEnd: () -> Void = {}

    private let imagesDir: URL
    private let textDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipiPreview", isDirectory: true)
    private var previewItems: [UUID: PreviewItem] = [:]
    private var shownItems: [ClipItem] = []
    private var indexObservation: NSKeyValueObservation?

    init(imagesDir: URL) {
        self.imagesDir = imagesDir
    }

    static var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle() {
        if Self.isVisible {
            close()
        } else {
            // Quick Look finds us through the key window's responder chain (FloatingPanel).
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        if Self.isVisible { QLPreviewPanel.shared().orderOut(nil) }
    }

    /// Follows the selection while the preview is open.
    func selectionDidChange() {
        guard Self.isVisible, let index = selectedIndex else { return }
        let panel = QLPreviewPanel.shared()!
        if panel.currentPreviewItemIndex != index {
            panel.currentPreviewItemIndex = index
        }
    }

    private var selectedIndex: Int? {
        guard let id = selectedID() else { return nil }
        return shownItems.firstIndex { $0.id == id }
    }

    // MARK: - Panel control (from FloatingPanel's responder methods)

    func beginControl(_ panel: QLPreviewPanel) {
        shownItems = items()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = selectedIndex ?? 0
        indexObservation = panel.observe(\.currentPreviewItemIndex) { [weak self] panel, _ in
            let index = panel.currentPreviewItemIndex
            DispatchQueue.main.async {
                guard let self, self.shownItems.indices.contains(index), self.selectedIndex != index else { return }
                self.onSelect(self.shownItems[index].id)
            }
        }
        // Above Clipi's panel, which floats at menu level
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    }

    func endControl(_ panel: QLPreviewPanel) {
        indexObservation = nil
        panel.dataSource = nil
        panel.delegate = nil
        shownItems = []
        previewItems = [:]
        try? FileManager.default.removeItem(at: textDir)
        onEnd()
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { shownItems.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard shownItems.indices.contains(index) else { return nil }
            return previewItem(for: shownItems[index])
        }
    }

    // MARK: - QLPreviewPanelDelegate

    /// ↑ ↓ move Clipi's selection; the preview follows.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        return MainActor.assumeIsolated {
            switch keyCode {
            case 126: onMove(-1)  // ↑
            case 125: onMove(1)   // ↓
            default: return false
            }
            selectionDidChange()
            return true
        }
    }

    // MARK: - Items

    private func previewItem(for item: ClipItem) -> PreviewItem? {
        if let cached = previewItems[item.id] { return cached }
        let url: URL?
        switch item.kind {
        case .image:
            url = item.imageFile.map { imagesDir.appendingPathComponent($0) }
        case .files:
            url = item.fileURLs.first
        case .text:
            // Quick Look previews files: the text goes in a temporary one.
            try? FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)
            let file = textDir.appendingPathComponent("\(item.id.uuidString).txt")
            url = (try? (item.text ?? "").write(to: file, atomically: true, encoding: .utf8)) != nil ? file : nil
        }
        guard let url else { return nil }
        let title = item.kind == .files ? url.lastPathComponent : String(item.title.prefix(80))
        let previewItem = PreviewItem(url: url, title: title)
        previewItems[item.id] = previewItem
        return previewItem
    }
}

private final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}
