import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater

    var body: some View {
        ZStack {
            switch model.page {
            case .history:
                HistoryPage(model: model, store: store, updater: updater)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .settings:
                SettingsPage(model: model, settings: settings, updater: updater)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: model.page)
    }
}

// MARK: - History

private struct HistoryPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore
    @ObservedObject var updater: Updater

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clipi").font(.headline)
                        Text(store.items.count == 1 ? "1 item" : "\(store.items.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    IconButton(systemName: "gearshape", help: "Settings (⌘,)") { model.showSettings() }
                }

                if let release = updater.state.release {
                    UpdateBanner(release: release, state: updater.state,
                                 install: { Task { await updater.install() } },
                                 openNotes: { model.onOpenURL(release.notesURL) })
                }

                SearchBar(text: $model.query,
                          focusToken: model.focusToken,
                          onMove: { model.move(by: $0) },
                          onSubmit: { model.copySelected() },
                          onDelete: { model.deleteSelected() },
                          onEscape: { model.escape() })
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            Group {
                if results.isEmpty {
                    emptyState
                } else {
                    list(results)
                }
            }
            .frame(maxHeight: .infinity)

            Divider().padding(.horizontal, 12)

            HStack {
                Button("Clear History…", action: model.onClearHistory)
                    .disabled(store.items.isEmpty)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(FooterButtonStyle())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if store.items.isEmpty {
            ContentUnavailableView {
                Label("Nothing Copied Yet", systemImage: "clipboard")
            } description: {
                Text("Text, images, files and screenshots you copy appear here.")
            }
        } else {
            ContentUnavailableView.search(text: model.query)
        }
    }

    private func list(_ results: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { item in
                        ClipRow(item: item,
                                isSelected: item.id == model.selectedItem?.id,
                                imagesDir: store.imagesDir,
                                now: model.openedAt,
                                onDelete: { model.delete(item) })
                            .id(item.id)
                            .onHover { if $0 { model.hover(item.id) } }
                            .onTapGesture { model.copy(item) }
                            .contextMenu {
                                Button("Copy") { model.copy(item) }
                                if item.kind == .files {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs)
                                    }
                                }
                                Divider()
                                Button("Delete") { model.delete(item) }
                            }
                    }
                }
                // Same insets as the search box above, so rows and box line up
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .background(OverlayScrollers())
            }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target)
                model.scrollTarget = nil
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let isSelected: Bool
    let imagesDir: URL
    let now: Date
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            let icon = ClipIcons.shared.image(for: item, imagesDir: imagesDir)
            Image(nsImage: icon)
                .renderingMode(icon.isTemplate ? .template : .original)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: ClipIcons.size.width, height: ClipIcons.size.height)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(item.subtitle(now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if isSelected, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.borderless)
                .help("Delete (⌘⌫)")
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 9)  // like the search box's content
        .padding(.vertical, 5)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlAccentColor))
            }
        }
        .contentShape(Rectangle())
        .help(item.tooltip ?? "")
    }
}

// MARK: - Settings

private struct SettingsPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(systemName: "chevron.left", help: "Back (⎋)") { model.showHistory() }
                Text("Settings").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card(title: "History") {
                        SettingRow(icon: "clock.arrow.circlepath", tint: .blue, title: "Keep After Restart",
                                   subtitle: "Otherwise cleared when you quit or shut down",
                                   isOn: $settings.persistHistory)
                        CardDivider()
                        HStack(spacing: 10) {
                            RowIcon(name: "list.number", tint: .indigo)
                            Text("History Size")
                            Spacer(minLength: 8)
                            SegmentPicker(options: AppSettings.historySizes, selection: $settings.maxItems)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Card(title: "Screenshots") {
                            SettingRow(icon: "camera.viewfinder", tint: .purple, title: "Copy to Clipboard",
                                       subtitle: "⌘⇧3, ⌘⇧4 and ⌘⇧5 are ready to paste",
                                       isOn: $settings.screenshotToClipboard)
                            if settings.screenshotToClipboard {
                                CardDivider()
                                SettingRow(icon: "rectangle.inset.bottomtrailing.filled", tint: .pink,
                                           title: "Keep Floating Thumbnail",
                                           subtitle: thumbnailSubtitle,
                                           isOn: $settings.keepFloatingThumbnail)
                            }
                        }
                        if settings.screenshotToClipboard, settings.keepFloatingThumbnail, !model.hasFullDiskAccess {
                            Banner(message: "Allow Clipi in Full Disk Access to copy screenshots while the thumbnail is showing.",
                                   buttonTitle: "Open Privacy Settings…",
                                   action: model.onOpenFullDiskAccessSettings)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Card(title: "Quick Paste") {
                            HStack(spacing: 10) {
                                RowIcon(name: "keyboard", tint: .orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Shortcut")
                                    Text("Your last \(QuickPasteModel.count) copies, to paste where you’re typing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                ShortcutRecorder(shortcut: $settings.quickPasteShortcut,
                                                 onRecordingChange: model.onRecordingShortcut)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        if settings.quickPasteShortcut != nil, !model.hasAccessibility {
                            Banner(message: "Allow Clipi in Accessibility to paste right away. Until then the item is copied and you paste it with ⌘V.",
                                   buttonTitle: "Grant Access…",
                                   action: model.onGrantAccessibility)
                        }
                    }

                    Card(title: "General") {
                        SettingRow(icon: "power", tint: .green, title: "Launch at Login", isOn: $model.launchAtLogin)
                        CardDivider()
                        SettingRow(icon: "arrow.triangle.2.circlepath", tint: .teal, title: "Check for Updates",
                                   subtitle: "At launch and once a day", isOn: $settings.checkForUpdates)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(OverlayScrollers())
            }

            Divider().padding(.horizontal, 12)

            HStack(spacing: 8) {
                if updater.state == .checking {
                    ProgressView().controlSize(.mini)
                }
                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(versionHelp)
                Spacer()
                // Side by side: each button's own padding is the gap
                HStack(spacing: 0) {
                    Button {
                        Task { await updater.check() }
                    } label: {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                    .disabled(updater.state == .checking || updater.state.isInstalling)
                    .help("Check for Updates")
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                }
            }
            .buttonStyle(FooterButtonStyle())
            .padding(.leading, 16)
            .padding(.trailing, 9)
            .padding(.vertical, 6)
        }
    }

    private var versionText: String {
        switch updater.state {
        case .checking: "Checking for updates…"
        case .upToDate: "Clipi \(Updater.currentVersion) is up to date"
        case .checkFailed: "Couldn’t check for updates"
        case .available(let release), .installing(let release), .installFailed(let release, _):
            "Clipi \(release.version) is available"
        case .idle: "Clipi \(Updater.currentVersion)"
        }
    }

    private var versionHelp: String {
        if case .checkFailed(let message) = updater.state { message } else { "" }
    }

    private var thumbnailSubtitle: String {
        if !settings.keepFloatingThumbnail { return "Off: screenshots are copied instantly" }
        return model.hasFullDiskAccess ? "Copied instantly with Full Disk Access" : "Needs Full Disk Access"
    }
}

// MARK: - Search

/// A search box in the card style. The text field keeps focus and forwards ↑ ↓ ↩ ⎋ ⌘⌫ to the list.
private struct SearchBar: View {
    @Binding var text: String
    let focusToken: Int
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onDelete: () -> Void
    let onEscape: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            SearchTextField(text: $text, focusToken: focusToken, onMove: onMove,
                            onSubmit: onSubmit, onDelete: onDelete, onEscape: onEscape)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onDelete: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        var focusToken = -1

        init(parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.deleteToBeginningOfLine(_:)) where parent.text.isEmpty:
                parent.onDelete()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
            default:
                return false
            }
            return true
        }
    }
}
