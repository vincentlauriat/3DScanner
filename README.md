# 3D Scanner

Scan the rooms of your house with the iPhone LiDAR, get **dimensioned 2D floor plans** and
**3D models**, and share them with any 2D (PDF, SVG, DXF/CAD) or 3D (USDZ, OBJ, STL, PLY) application.
A **Mac companion app** (same codebase) shows the plans, 3D models and measurements on the big screen,
exports, prints and drag-and-drops them into your Mac tools. **iCloud Drive** keeps iPhone and Mac in sync
and exposes a "3D Scanner" folder in Files and Finder that any 2D/3D app can read.

> Status: **design validated, implementation in progress** (2026-09-05). Landing page: https://vincentlauriat.github.io/3DScanner/
> See [`docs/superpowers/specs/2026-09-05-3dscanner-design.md`](docs/superpowers/specs/2026-09-05-3dscanner-design.md) for the full specification (French).

## Requirements

- iPhone **Pro** model with LiDAR (12 Pro or later; developed against iPhone 15/16/17 Pro), iOS **18.0**+ — scanning happens only on iPhone (RoomPlan does not exist on macOS)
- Mac with **macOS 15.0**+ for the companion app (Apple Silicon or Intel)
- An iCloud account signed in on both devices (optional — the apps fall back to local storage)
- Xcode 27, `xcodegen` (`brew install xcodegen`)

The iOS Simulator cannot run RoomPlan (no LiDAR). The conversion/export engine is fully
unit-tested on the simulator from JSON fixtures; the scan screen is tested on device only.

## Features

| Feature | v1 | Notes |
|---|---|---|
| Guided LiDAR room scan (Apple RoomPlan) | ✅ built (device validation pending) | Apple `RoomCaptureView`, coaching enabled |
| Automatic room naming (Living room, Bedroom…) | ✅ built | from RoomPlan `Section.label` |
| Dimensioned 2D floor plan (walls, doors, windows, cm dimensions, m² area) | ✅ built | Core Graphics renderer |
| Interactive viewer (SwiftUI `RealityView`): **3D orbit**, **2D top-down**, **AR** on iPhone (scale model on a table at 1:20/1:50, or 1:1 overlay in the real room) | ✅ built (AR on device pending) | parametric scene built from the plan; QuickLook kept as secondary quick preview |
| Measurements list (area, perimeter, ceiling height, every wall/door/window, detected objects) | ✅ built | with confidence indicator |
| Export 2D: PDF (A4 landscape), PNG, SVG, DXF R12 | ✅ built | hand-written writers, no dependencies |
| Export 3D: USDZ (parametric or raw scan mesh), OBJ, STL, PLY | ✅ built (device validation pending) | USDZ from RoomPlan; OBJ/STL/PLY from the plan mesh, or from the scan mesh via Model I/O |
| Export data: structured plan JSON, ZIP of everything | ✅ JSON built · ZIP planned | |
| Share sheet (AirDrop, Files, Mail, any installed app), Save As…, copy to `Exports/` | ✅ built | `ShareLink`, `fileExporter` |
| Room library, rename, delete, re-export without rescanning | ✅ built | `.roomscan` packages |
| **iCloud Drive sync** iPhone ↔ Mac, "3D Scanner" folder in Files & Finder, "Save to iCloud Drive" for exports, offline fallback, conflict-safe | ✅ planned | ubiquity container, `NSMetadataQuery`, `NSFileCoordinator` |
| **Mac companion app**: sidebar library, 2D plan, 3D viewer (mouse/trackpad orbit), measurements, File › Export (⌘E), Print (⌘P), drag & drop to other apps, Open With…, Reveal in Finder, double-click `.roomscan` | ✅ planned | shared codebase, `RoomScannerMac` target |
| **Sparkle auto-update** on Mac (signed DMG, notarized) | ✅ planned | `appcast.xml` on `main` |
| French / English UI | ✅ planned | |
| Whole-house merge (multi-room, multi-story) | 🔜 v2 | RoomPlan `StructureBuilder`; v1 model (`House`), viewer and exporters are already house-ready |
| glTF / GLB export | 🔜 v2 | Model I/O cannot write glTF; custom writer |
| Compass / north on plan, imperial units, manual edits | 🔜 v2 | |

## Build

```bash
xcodegen generate
# iOS (simulator: everything except the RoomPlan scan itself)
xcodebuild -scheme RoomScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build test
# macOS (same code, same tests)
xcodebuild -scheme RoomScannerMac -destination 'platform=macOS' build test
```
Run on device from Xcode (⌘R) with automatic signing. Mac release DMG: `Scripts/release.sh` (Developer ID + notarization).

## Project layout

```
RoomScanner/            Shared app source (SwiftUI, iOS 18+ / macOS 15+)
  App/  Scan/ (iOS)  Domain/  Viewer/  Export/  Storage/  Sync/  UI/  MacUI/ (macOS)  Resources/
RoomScannerTests/       Unit tests + CapturedRoom JSON fixtures
docs/                   Landing page (GitHub Pages) + docs/superpowers/specs/ design specifications
Scripts/release.sh      Mac release: build, Developer ID signing, notarization, DMG, Sparkle appcast
project.yml             XcodeGen project definition (the .xcodeproj is generated, not versioned)
```

## Architecture

See [`ARCHITECTURE_EN.md`](ARCHITECTURE_EN.md) (English, source of truth) / [`ARCHITECTURE.md`](ARCHITECTURE.md) (French mirror).

## Roadmap

- [x] Phase 0 — Bootstrap (public repo, two targets iOS 18 + macOS 15, plists, entitlements, tests target, landing page)
- [x] Phase 1 — Domain model `FloorPlan` + measurements (TDD)
- [x] Phase 2 — Local storage (`.roomscan`) + iOS scan screen
- [x] Phase 3 — 2D renderer + measurements UI
- [x] Phase 4 — RealityKit viewer (3D orbit, 2D top-down, AR placement on iPhone)
- [x] Phase 5 — 2D exports (PDF, PNG, SVG, DXF)
- [x] Phase 6 — 3D exports (USDZ, OBJ, STL, PLY)
- [ ] Phase 7 — iCloud Drive sync (`.roomscan` packages, Exports folder, offline fallback, conflicts)
- [ ] Phase 8 — Mac companion app (split view, menus, print, drag & drop, Open With)
- [ ] Phase 9 — Library, ZIP, settings, icons, localization, Sparkle integration
- [ ] Phase 10 — v1.0.0 release (iOS + notarized Mac DMG with Sparkle appcast)
- [ ] v2 — whole-house merge, glTF, compass, imperial units

## License

MIT — see [LICENSE](LICENSE).
