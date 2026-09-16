<p align="center">
  <img src="screenshots/smart-care.png" alt="PureMac Smart Care - storage overview and cleanup review" width="820">
</p>

<h1 align="center">PureMac: Golden Gate Edition</h1>

<p align="center">
  <b>Reclaim your Mac in Style.</b><br>
  Free, open-source Mac care with an exclusive <b>Liquid Glass UI</b> tailored for macOS 27 Golden Gate.
</p>

<p align="center">
  <a href="https://github.com/buddhi-art/PureMac/releases/latest"><img src="https://img.shields.io/github/v/release/buddhi-art/PureMac?style=flat-square&label=Download" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/UI-Liquid%20Glass-purple?style=flat-square" alt="Liquid Glass UI">
  <img src="https://img.shields.io/badge/telemetry-none-success?style=flat-square" alt="No telemetry">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/buddhi-art/PureMac?style=flat-square" alt="MIT License"></a>
</p>

---

## ✨ What's New in this Fork?

This is a custom fork of PureMac that features a **complete visual overhaul** focusing on modern aesthetics:
- **Liquid Glass UI**: Ultra-thin materials, ambient mesh gradient backdrops, and translucent sidebars.
- **Edge-to-Edge Layout**: Maximizes screen space with hidden title bars.
- **Golden Gate Ready**: Designed for macOS 27 design patterns.
- **Unsigned DMG Releases**: Fast automated builds via GitHub Actions for testing.

## 🚀 Install

Download the latest `.dmg` from [Releases](https://github.com/buddhi-art/PureMac/releases/latest) and drag PureMac into `/Applications`. 

> **Note**: Because this is a custom unsigned build, macOS Gatekeeper will block it by default. 
> To open it: Go to `/Applications` in Finder, **Right-Click** on PureMac, and select **Open**. Click **Open** again in the prompt.

### Build from source

If you want to build it yourself (requires Xcode):

```bash
brew install xcodegen
git clone https://github.com/buddhi-art/PureMac.git
cd PureMac
xcodegen generate
xcodebuild -project PureMac.xcodeproj -scheme PureMac -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/PureMac.app
```

## 🛡 Our Promise

A Mac cleaner asks for the deepest permission macOS grants - Full Disk Access - and then deletes your files. That demands a level of trust. Here's the contract PureMac holds itself to:

- **Deletion behavior is explicit.** Review selections carefully.
- **No telemetry, ever.** No analytics, no crash reporting, no "anonymous usage stats." The app doesn't know you exist.
- **No fake urgency.** No dramatized "47 GB of junk detected!" badges. We show you neutral facts and let you decide.
- **No overpromising.** We don't claim to "reclaim purgeable space" or "boost RAM". 
- **Auditable.** It's MIT licensed. Read the code. 

## 🧹 What it does

### App Uninstaller
Discovers everything in `/Applications` and `~/Applications`, then uses a heuristic matching engine to find related files on your disk. Apple system apps are excluded.

### Orphan Finder
Walks `~/Library` and surfaces files left behind by apps that no longer exist on disk. 

### System Cleaner
Smart Scan checks each category in sequence:
- **System Junk** - system caches, logs, temp files
- **User Cache** - dynamically discovered
- **Trash Bins** - empties all bins, including external volumes
- **Large & Old Files** - >100 MB or older than 1 year (never auto-selected)

### Storage and File Review
- **Space Explorer**: Measures the allocated space inside a folder you choose.
- **Duplicate Finder**: Groups files with matching sizes and SHA-256 content hashes.
- **Similar Photos**: Compares image thumbnails using perceptual hashes.

## 🔒 Permissions

PureMac needs **Full Disk Access** to read the locations macOS hides from every app by default - Mail downloads, Safari data, the TCC database, protected app containers. Without it, some cleanup categories and app-container scans will be incomplete. 

## 🛠 Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to get started.

## 📄 License

MIT. See [LICENSE](LICENSE). Use it, fork it, ship it under your own name if you want - the only thing the license asks is that the notice stays.
