import AppKit
import SwiftUI

// Building blocks shared by the panel's pages, in the same style as Mousip.

/// A rounded group of rows with a title above.
struct Card<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
        }
    }
}

struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, 44)
    }
}

struct RowIcon: View {
    var name: String
    var tint: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// An icon, a title and a switch. Clicking anywhere on the row flips the switch.
struct SettingRow: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(name: icon, tint: tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle(title, isOn: $isOn)
                .toggleStyle(PanelSwitchStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// A hand-drawn switch: the system one renders gray in a panel that never activates the app.
struct PanelSwitchStyle: ToggleStyle {
    var width: CGFloat = 28
    var height: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.12))
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 0.5, y: 0.5)
                    .padding(1.5)
            }
            .frame(width: width, height: height)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}

/// A hand-drawn segmented control, for the same reason as `PanelSwitchStyle`.
struct SegmentPicker: View {
    var options: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Text("\(option)")
                    .font(.caption.weight(selected ? .medium : .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }
}

struct Banner: View {
    var message: String
    var buttonTitle: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle, action: action)
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25))
        )
    }
}

/// Shown when a new release is out: install it in place or read what's new.
struct UpdateBanner: View {
    var release: Updater.Release
    var state: Updater.State
    var install: () -> Void
    var openNotes: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("Clipi \(release.version) is available").font(.callout.weight(.medium))

                if case .installFailed(_, let message) = state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if state.isInstalling {
                        ProgressView().controlSize(.small)
                        Text("Installing…").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(state.isFailedInstall ? "Try Again" : "Install & Relaunch", action: install)
                            .controlSize(.small)
                        Button("What’s New", action: openNotes)
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25))
        )
    }
}

/// A round, borderless icon button with a hover background.
struct IconButton: View {
    var systemName: String
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The small buttons at the bottom of the panel: secondary text, a rounded highlight on hover.
struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterButton(configuration: configuration)
    }

    private struct FooterButton: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let highlighted = hovering && isEnabled
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(highlighted ? Color.primary : Color.secondary)
                .opacity(isEnabled ? 1 : 0.5)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : highlighted ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: highlighted)
        }
    }
}

/// Puts the enclosing scroll view on overlay scrollers: a thin knob over the content while
/// scrolling, never a track. (With "always show" scroll bars the track draws as a dark stripe
/// on the glass.) The scroller also flashes when the panel opens, to show the list scrolls.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.apply()
    }

    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            apply()
            guard let window else { return }
            // The scroll view resets its style when the system preference changes: set it again after.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.apply() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.apply()
                }
                // After SwiftUI has laid out the freshly opened panel
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.enclosingScrollView?.flashScrollers()
                }
            })
        }

        func apply() {
            guard let scrollView = enclosingScrollView else { return }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            scrollView.autohidesScrollers = true
        }
    }
}

/// Click, then type a shortcut. ⎋ cancels, the ✕ removes it. It needs ⌘, ⌥ or ⌃.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var onRecordingChange: (Bool) -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(recording ? "Type Shortcut…" : shortcut?.display ?? "None")
                .font(.system(size: 12, weight: recording ? .regular : .medium))
                .foregroundStyle(recording || shortcut == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if shortcut != nil, !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove Shortcut")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minWidth: 70)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(recording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(hovering ? 0.1 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(recording ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { recording ? stop() : start() }
        .onDisappear { stop() }
        .help("Click to record a new shortcut")
    }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // ⎋
                stop()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onRecordingChange(false)
    }
}
