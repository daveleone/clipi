import AppKit

// MARK: - Text

extension ClipItem {
    /// One line with collapsed whitespace.
    var title: String {
        switch kind {
        case .text:
            return (text ?? "").prefix(300).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .image:
            return isScreenshot ? "Screenshot" : "Image"
        case .files:
            let urls = fileURLs
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) Files"
        }
    }

    func subtitle(now: Date) -> String {
        var parts: [String] = []
        switch kind {
        case .text:
            if let sourceAppName { parts.append(sourceAppName) }
        case .image:
            if let imageWidth, let imageHeight { parts.append("\(imageWidth) × \(imageHeight)") }
            if !isScreenshot, let sourceAppName { parts.append(sourceAppName) }
        case .files:
            if let folder = fileURLs.first?.deletingLastPathComponent().path {
                parts.append((folder as NSString).abbreviatingWithTildeInPath)
            }
        }
        parts.append(Self.relativeTime(date, now: now))
        return parts.joined(separator: " · ")
    }

    var tooltip: String? {
        switch kind {
        case .text: return String((text ?? "").prefix(1000))
        case .files: return text
        case .image: return nil
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeTime(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        if elapsed > 2 * 86_400 {
            return date.formatted(.dateTime.locale(Locale(identifier: "en_US")).month(.abbreviated).day())
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Icons

/// Row images: thumbnail, app icon or file icon. All the same size so titles line up.
@MainActor
final class ClipIcons {
    static let shared = ClipIcons()
    static let size = NSSize(width: 36, height: 26)

    private let thumbnails = NSCache<NSURL, NSImage>()
    private var appIcons: [String: NSImage] = [:]

    func image(for item: ClipItem, imagesDir: URL) -> NSImage {
        switch item.kind {
        case .image:
            if let file = item.imageFile, let thumb = thumbnail(for: imagesDir.appendingPathComponent(file)) {
                return thumb
            }
            return symbol("photo")
        case .files:
            let url = item.fileURLs.first
            let icon = url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? NSWorkspace.shared.icon(forFile: $0.path) : nil }
            return leading(icon ?? NSWorkspace.shared.icon(for: .data))
        case .text:
            if let icon = appIcon(bundleID: item.sourceBundleID) {
                return leading(icon)
            }
            return symbol("doc.plaintext")
        }
    }

    private func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let image = NSImage(size: Self.size, flipped: false) { rect in
            guard let glyph else { return false }
            let size = glyph.size
            glyph.draw(in: NSRect(x: rect.minX + 12 - size.width / 2, y: rect.midY - size.height / 2,
                                  width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true  // follows the text color, also when the row is selected
        return image
    }

    /// App and file icons sit at the leading edge, in line with thumbnails and the search field's magnifying glass.
    private func leading(_ icon: NSImage) -> NSImage {
        NSImage(size: Self.size, flipped: false) { rect in
            let side: CGFloat = 24
            icon.draw(in: NSRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side))
            return true
        }
    }

    private func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    private func thumbnail(for url: URL) -> NSImage? {
        if let cached = thumbnails.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 120,
              ] as CFDictionary) else { return nil }

        let image = NSImage(size: Self.size, flipped: false) { rect in
            let frame = rect.insetBy(dx: 0.5, dy: 0.5)
            let clip = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4)
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            // Aspect fill
            let scale = max(frame.width / CGFloat(cg.width), frame.height / CGFloat(cg.height))
            let drawn = NSSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
            NSImage(cgImage: cg, size: drawn).draw(in: NSRect(x: frame.midX - drawn.width / 2,
                                                              y: frame.midY - drawn.height / 2,
                                                              width: drawn.width, height: drawn.height))
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            clip.lineWidth = 0.5
            clip.stroke()
            return true
        }
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }
}
