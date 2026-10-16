<div align="center">

<img src="Resources/icon.png" width="160" alt="Clipi icon">

# Clipi

**Clipboard history in your menu bar, with screenshots ready to paste.**

![macOS 14.4+](https://img.shields.io/badge/macOS-14.4%2B-black?logo=apple&logoColor=white)
![No Xcode required](https://img.shields.io/badge/Xcode-not%20required-6A3DF0)
![Menu bar app](https://img.shields.io/badge/lives%20in-the%20menu%20bar-2B5BFF)

</div>

---

## ✨ Features

- **Clipboard history.** Text, images and files you copy, with the app they came from.
  Search as you type, pick with ↑ ↓ and ↩, then ⌘V where you were: Clipi never steals focus.
- **Screenshots on the clipboard.** ⌘⇧3, ⌘⇧4 and ⌘⇧5 save the file as usual *and* put the
  screenshot on the clipboard, ready to paste.
- **Keep the floating thumbnail** *(optional).* With Full Disk Access, screenshots are copied
  right away even while the thumbnail is showing.
- **Private.** Passwords copied from password managers are never recorded. History can be kept
  across restarts or cleared when you quit.
- **Updates itself** from GitHub Releases.

## 🚀 Install

```sh
curl -fsSL https://raw.githubusercontent.com/daveleone/clipi/main/scripts/install.sh | sh
```

It downloads the [latest release](https://github.com/daveleone/clipi/releases/latest), installs it
in `/Applications` and launches it. After that Clipi updates itself: it checks at launch and once a
day, and **Install & Relaunch** in the panel swaps in the new version.

## 🛠 Build from source

```sh
./build.sh run       # build and launch build/Clipi.app
./build.sh install   # build, copy to /Applications and launch
```

The app icon is generated from `Resources/icon.png` (1024×1024) at build time.

Run `scripts/make-signing-cert.sh` once to create a local signing certificate: `build.sh` then
signs with it, and macOS keeps Clipi's Accessibility permission (needed by Quick Paste) across
rebuilds. Without it, builds are signed ad-hoc and the permission has to be granted again each time.

## 📦 Releasing

The version lives in `Resources/Info.plist` (`CFBundleShortVersionString`) for local builds; in
CI it comes from the tag. To publish a release:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The **Build** workflow builds a universal app, packages `Clipi.zip` (what the updater downloads)
and `Clipi.dmg`, and publishes them in a GitHub release with generated notes.

Releases are signed ad-hoc unless these repository secrets are set, in which case they're signed
with a Developer ID and notarized: `MACOS_CERTIFICATE` (base64 .p12), `MACOS_CERTIFICATE_PASSWORD`,
`APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`.
