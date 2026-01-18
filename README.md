//
//  README.md
//  Griddy
//
//  Created by Thomas Minzenmay on 20.04.25. 
//

![Griddy App Icon](img/Icon.png)

# Griddy - Tile Mapper

## A Simple macOS Tool for Creating Collision and Tile Property Maps

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Latest-brightgreen.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

![Griddy App Screenshot](img/Griddy.png)

Griddy is a straightforward macOS application designed for **Sega Mega Drive / Genesis developers** (and other retro platforms) who need to visually create data maps based on image layouts. It overlays an **8×8** grid on top of a PNG and lets you “paint” tile properties (0–9) into each cell. You can then export the result to formats ready for your game tools and engines.

---

## Features

- **Open PNG Files:** Works with standard PNG images.  
  **Important:** Image dimensions must be **multiples of 8** pixels.

- **8×8 Grid Overlay:** Matches common tile size on the Mega Drive.

- **Tile Value Painting:**
  - 10 tools: **0** (“No Value” / erase) and **1–9** color indices.
  - Click to paint a cell; click-drag to paint rectangles.
  - Cells render semi-transparent so your map stays visible.

- **Multiple Documents (Tabs):** Work on many maps at once.

- **Zoom & Pan:** Pinch-to-zoom and smooth panning; custom scrollbars.

- **Drag & Drop:** Drop `.png` or `.griddy` files on the window or Dock icon.

- **Project Saving (`.griddy`):** Save image + grid data together.  
  Griddy preserves **original PNG bytes** (when available) so palette/index info can be reused for exports.

- **Data Import/Export:**
  - **C/H Export:** Generate `const u16 NAME[ROWS][COLS]` data for SGDK (or similar) with a matching header guard.
  - **CSV Export/Import:** Export 0–9 grid as CSV; import CSV with comma separators.
  - **Tiled Export (TMX/TSX/PNG):**
    - Creates a **TMX map** (CSV layer), an external **TSX tileset**, and a **PNG8 tileset atlas**.
    - The tileset atlas is built by **deduplicating** unique 8×8 tiles from the source image and packing them in a grid.
    - **Palette/indexed PNGs remain untouched:** the exported tileset PNG preserves **exact palette indices** from the source (no quantization).
    - **Transparent color** in TSX is set from a chosen palette index (default: index 0).
    - Output references the external TSX and tileset PNG so you can open the TMX directly in **Tiled**.

---

## Installation

**1) Pre-built Application (Recommended)**

- See **[Releases](https://github.com/mintho/Griddy/releases)**.
- Download the latest `Griddy_vX.Y.Z.zip`.
- Unzip and drag `Griddy.app` to `/Applications`.
- First launch: Right-click → **Open** → **Open** (macOS Gatekeeper).

**2) Build from Source**

- Requires macOS 14.0+, Xcode 15.0+, Git.
- `git clone https://github.com/mintho/Griddy.git`
- `cd Griddy`
- Open `Griddy.xcodeproj`, select the **Griddy** scheme, and run (⌘R).

---

## How to Use

1. **Open a Map PNG:** `File > Open PNG…` (⌘O) or drag a PNG onto the window.  
   **Must be an indexed PNG** for TMX export (see notes below), and both width & height must be multiples of **8**.

2. **Paint Values:**
   - Pick **0–9** in the right toolbar.
   - Click to paint; click-drag for rectangles.
   - Undo/Redo as usual (⌘Z / ⇧⌘Z).

3. **Save Projects (`.griddy`):**
   - `File > Save Project` (⌘S) or `Save Project As…` (⇧⌘S).
   - Keeps your grid data and (when possible) **original PNG bytes** intact.

4. **Export Options:**
   - **C/H Source…** `File > Export C/H Source…` (⌘E)  
     Produces `name.c` + `name.h` with `const u16 NAME[H][W]`.
   - **CSV…** `File > Export CSV…` (⇧⌘E)  
     A standard CSV (0–9 values) for custom tooling.
   - **NEW: TMX/TSX/PNG…** `File > Export TMX/TSX/PNG…` (⇧⌘T)  
     - Choose an output directory and **base name**.
     - Griddy writes:
       - `base.tmx` – Tiled map (CSV layer, 1-based GIDs).
       - `base_tileset.tsx` – External tileset (references the PNG).
       - `base_tiles.png` – **PNG8** tileset atlas (deduplicated 8×8 tiles).
     - Open the `.tmx` directly in **Tiled**.

---

## Notes on TMX/TSX/PNG Export

- **Source Image Requirements (for exact palette preservation):**
  - Must be **indexed (paletted)** PNG (color type 3).
  - Bit depth **1 / 2 / 4 / 8** supported.
  - **No interlacing** (Adam7 not supported).
  - Griddy reads the original PNG bytes (from the file or from `.griddy`) to rebuild the tileset atlas with the **same palette & indices**.

- **Tile Size:** Fixed at **8×8** (matches Griddy’s grid).

- **Deduplication:** Identical 8×8 tiles are merged; the TMX layer uses 1-based GIDs pointing into the atlas.

- **Transparent Color:** The tileset’s transparent color is derived from a palette index (defaults to **0**).  
  You can tweak this in code if your pipeline needs a different index.

- **Tiled Compatibility:**  
  The TMX uses `<data encoding="csv">` with **width × height** values, separated by commas and line breaks.  
  The TSX references the PNG tileset via a relative filename. Open the TMX in Tiled and it should resolve automatically if all files are kept together.

---

## File Formats

- **`.griddy`** – JSON project file: original PNG bytes (when available) + current grid array.
- **`.c` / `.h`** – C source/header with `const u16 NAME[ROWS][COLS]`.
- **`.csv`** – Comma-separated grid values (0–9) row by row.
- **`.tmx` / `.tsx` / `.png`** – Tiled map + external tileset + PNG8 tileset atlas.

---

## Troubleshooting

- **“Invalid Dimensions” when opening PNG**  
  Make sure the image size is an exact multiple of **8×8**.

- **TMX won’t open in Tiled / “Corrupt layer data”**  
  Ensure all three exported files (`.tmx`, `.tsx`, `.png`) are together and that the TMX references the TSX and PNG by **matching filenames**.  
  If you hand-edit the TSX/TMX, keep `width/height/tilewidth/tileheight` in sync with your source image and Griddy’s grid.

- **Palette looks wrong in tileset PNG**  
  Verify your source PNG is **indexed** (paletted) and not true-color; Griddy preserves the original palette & per-pixel indices.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
