import AppKit

/// Watches the folders where macOS saves screenshots and reports every new screenshot.
///
/// Two sources:
/// - the save folders (configured location + Desktop). Screenshots are recognised by the
///   kMDItemIsScreenCapture extended attribute, so it works whatever the system language is.
///   With the floating thumbnail on, the file only lands here once the thumbnail goes away.
/// - optionally, the temporary folder the floating thumbnail writes to right away
///   ($TMPDIR/TemporaryItems/NSIRD_screencaptureui_*). It is protected: reading it needs Full Disk Access.
@MainActor
final class ScreenshotWatcher {
    private enum Kind {
        /// A folder screenshots are saved to.
        case saveFolder
        /// $TMPDIR/TemporaryItems: new screencaptureui subfolders appear here.
        case temporaryRoot
        /// One screencaptureui subfolder holding the screenshot behind a floating thumbnail.
        case temporaryCapture
    }

    /// Also watch the floating thumbnail's temporary folder (when Full Disk Access allows it).
    var watchesTemporaryItems = false {
        didSet { if isRunning { syncWatchedDirectories() } }
    }

    private let handler: (URL) -> Void
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var kinds: [URL: Kind] = [:]
    private var seen: [URL: Set<String>] = [:]
    /// Folders being opened in the background.
    private var pending: [URL: Kind] = [:]
    private var directoryCheckTimer: Timer?
    private var isRunning: Bool { directoryCheckTimer != nil }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp"]
    /// Fallback when the attribute is missing: default screenshot names in common languages.
    private static let namePrefixes = ["Screenshot", "Screen Shot", "Istantanea", "Schermata",
                                       "Bildschirmfoto", "Capture d", "Captura de pantalla"]

    static let temporaryItems = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("TemporaryItems", isDirectory: true).standardizedFileURL

    /// Whether Clipi can read the floating thumbnail's temporary folder.
    static var hasFullDiskAccess: Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: temporaryItems.path) {
            return (try? fm.contentsOfDirectory(atPath: temporaryItems.path)) != nil
        }
        // The folder doesn't exist yet: probe another location Full Disk Access unlocks.
        let tcc = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        return fm.isReadableFile(atPath: tcc.path)
    }

    init(handler: @escaping (URL) -> Void) {
        self.handler = handler
    }

    func start() {
        guard !isRunning else { return }
        directoryCheckTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            // The location can change (⌘⇧5 › Options) and Full Disk Access can be granted at any time.
            MainActor.assumeIsolated { self?.syncWatchedDirectories() }
        }
        syncWatchedDirectories()
    }

    func stop() {
        directoryCheckTimer?.invalidate()
        directoryCheckTimer = nil
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        kinds.removeAll()
        seen.removeAll()
        pending.removeAll()
    }

    // MARK: - Folders

    /// The configured screenshot location plus the Desktop, which macOS uses when none is set.
    static func screenshotDirectories() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []
        for key in ["location", "location-last"] {
            if let path = ScreenCapturePreferences.string(for: key) {
                dirs.append(URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true))
            }
        }
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            dirs.append(desktop)
        }
        var unique: [URL] = []
        for dir in dirs.map(\.standardizedFileURL) where !unique.contains(dir) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                unique.append(dir)
            }
        }
        return unique
    }

    private func syncWatchedDirectories() {
        var wanted: [URL: Kind] = [:]
        for dir in Self.screenshotDirectories() {
            wanted[dir] = .saveFolder
        }
        if watchesTemporaryItems, Self.hasFullDiskAccess {
            wanted[Self.temporaryItems] = .temporaryRoot
            // Keep capture folders that still exist
            for (dir, kind) in kinds where kind == .temporaryCapture
                && FileManager.default.fileExists(atPath: dir.path) {
                wanted[dir] = kind
            }
        }
        for dir in sources.keys where wanted[dir] == nil {
            unwatch(dir)
        }
        for (dir, kind) in wanted where sources[dir] == nil {
            watch(dir, kind: kind, markExistingAsSeen: true)
        }
        // Drop folders no longer wanted while they were being opened (capture folders come and go on their own)
        pending = pending.filter { wanted[$0.key] != nil || $0.value == .temporaryCapture }
    }

    private func watch(_ dir: URL, kind: Kind, markExistingAsSeen: Bool) {
        guard sources[dir] == nil, pending[dir] == nil else { return }
        pending[dir] = kind
        // open() blocks while macOS asks for access to Desktop or Documents: never on the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fd = open(dir.path, O_EVTONLY)
            let existing = markExistingAsSeen ? (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] : []
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.pending.removeValue(forKey: dir) != nil, fd >= 0 else {
                        if fd >= 0 { close(fd) } else { NSLog("Clipi: cannot watch \(dir.path)") }
                        return
                    }
                    self.install(fd: fd, for: dir, kind: kind, seen: Set(existing))
                    if !markExistingAsSeen {
                        self.scan(dir)  // the screenshot may already be there
                    }
                }
            }
        }
    }

    private func install(fd: Int32, for dir: URL, kind: Kind, seen existing: Set<String>) {
        seen[dir] = existing
        kinds[dir] = kind
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                               eventMask: [.write, .rename, .link, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan(dir) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources[dir] = source
    }

    private func unwatch(_ dir: URL) {
        sources.removeValue(forKey: dir)?.cancel()
        kinds.removeValue(forKey: dir)
        seen.removeValue(forKey: dir)
    }

    private func contents(of dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    // MARK: - Detection

    private func scan(_ dir: URL) {
        guard let kind = kinds[dir] else { return }
        guard FileManager.default.fileExists(atPath: dir.path) else {
            unwatch(dir)  // a capture folder goes away with its thumbnail
            return
        }
        for name in contents(of: dir) where !(seen[dir]?.contains(name) ?? true) {
            seen[dir]?.insert(name)
            // macOS writes a hidden temporary file first, then renames it
            guard !name.hasPrefix(".") else { continue }
            let url = dir.appendingPathComponent(name)

            switch kind {
            case .temporaryRoot:
                if name.contains("screencaptureui") {
                    watch(url.standardizedFileURL, kind: .temporaryCapture, markExistingAsSeen: false)
                }
            case .temporaryCapture:
                guard Self.isImage(url) else { continue }
                whenStable(url) { [weak self] in self?.handler(url) }
            case .saveFolder:
                guard Self.isImage(url) else { continue }
                checkScreenshot(url, attempt: 0)
            }
        }
    }

    private func checkScreenshot(_ url: URL, attempt: Int) {
        if Self.hasScreenCaptureAttribute(url) {
            handler(url)
        } else if attempt < 6 {
            // The attribute can land a moment after the file
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                MainActor.assumeIsolated { self?.checkScreenshot(url, attempt: attempt + 1) }
            }
        } else if Self.namePrefixes.contains(where: url.lastPathComponent.hasPrefix) {
            handler(url)
        }
    }

    /// Calls `action` once the file has stopped growing.
    private func whenStable(_ url: URL, lastSize: Int = -1, attempt: Int = 0, _ action: @escaping @MainActor () -> Void) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 0, size == lastSize {
            action()
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                MainActor.assumeIsolated { self?.whenStable(url, lastSize: size, attempt: attempt + 1, action) }
            }
        }
    }

    private static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func hasScreenCaptureAttribute(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }
}

/// Reads and tweaks the system screenshot preferences (com.apple.screencapture).
enum ScreenCapturePreferences {
    private static let domain = "com.apple.screencapture" as CFString
    private static let thumbnailKey = "show-thumbnail" as CFString
    /// Where we remember the user's original floating-thumbnail setting.
    private static let savedThumbnailKey = "savedShowThumbnail"

    static func string(for key: String) -> String? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain) as? String
    }

    /// With the floating thumbnail on, macOS only writes the file once the thumbnail goes away
    /// (or never, if you click it). Turning it off makes the file — and the clipboard — instant.
    static func disableFloatingThumbnail() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: savedThumbnailKey) == nil {
            CFPreferencesAppSynchronize(domain)
            let current = CFPreferencesCopyAppValue(thumbnailKey, domain) as? Bool
            defaults.set(current.map { $0 ? "true" : "false" } ?? "unset", forKey: savedThumbnailKey)
        }
        write(false)
    }

    static func restoreFloatingThumbnail() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.string(forKey: savedThumbnailKey) else { return }
        switch saved {
        case "unset": write(nil)
        case "false": write(false)
        default: write(true)
        }
        defaults.removeObject(forKey: savedThumbnailKey)
    }

    private static func write(_ value: Bool?) {
        let cfValue: CFPropertyList? = value.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
        CFPreferencesSetAppValue(thumbnailKey, cfValue, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
