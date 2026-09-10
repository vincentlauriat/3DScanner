# 3D Scanner 1.0.0

First release. Scan a room with the iPhone's LiDAR (Apple RoomPlan) and get a dimensioned 2D plan and a 3D model you can open anywhere.

## iPhone (iOS 18, iPhone Pro with LiDAR)
- Guided room scan, automatic room naming, library of rooms (rename, delete, re-export).
- Dimensioned 2D plan (walls, doors, windows, centimetre dimensions, m² area) with pinch-zoom.
- Viewer: 3D orbit, 2D top-down, AR placement of a scale model (1:20, 1:50) or 1:1 overlay.
- Measurements: area, perimeter, ceiling height, every wall, door, window and detected object.

## Whole house (multi-room)
- Capture several adjoining rooms in one session on the iPhone: the AR session is kept between rooms, so every room shares one world reference.
- Rooms are grouped into stories automatically by floor height; the library has a Rooms section and a Houses section on both platforms.
- House area is the union of the rooms of a story (overlaps counted once), stories added together.
- Room names are composed from every RoomPlan section of the capture ("Dining room / Kitchen").
- 2D plan: one PDF page per story, stacked PNG, a floor tint per room.
- 3D viewer: pick the story to display.
- Houses are stored as a self-contained `.housescan` package and sync through iCloud Drive like rooms.

## Mac (macOS 15)
- Sidebar library, 2D plan, 3D viewer, measurements — the same engine as the iPhone.
- File › Export (⌘E, per-format submenu), Print (⌘P), Reveal in Finder, drag the plan into another app, Open With…, double-click `.roomscan`.
- Automatic updates with Sparkle.

## Exports (both platforms)
- 2D: PDF (A4 landscape, to scale, title block), PNG, SVG (millimetres, layers), DXF R12 (metres, layers).
- 3D: USDZ (parametric, or raw scan mesh), OBJ, STL, PLY.
- Data: structured plan JSON, ZIP of everything with a README.
- Share sheet, Save As…, Save to iCloud Drive (`Exports/<Room>/`).

## iCloud Drive
- Rooms and exports live in the "3D Scanner" folder of iCloud Drive, visible in Files and the Finder and shared between iPhone and Mac; offline fallback to local storage; conflict copies never lose a scan.

## Languages
- French and English.
