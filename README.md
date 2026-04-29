# SwiftCull

A native macOS photo management app built with SwiftUI. Designed for photographers who need to quickly cull, rate, tag, and delete photos from SD cards and large directories.

## Features

- **Photo Scanning** — Read and identify photos (JPG, NEF/RAW, MOV) from SD cards or any directory
- **Smart Filtering** — Filter by filename, rating, file type (JPG/RAW/RAW+JPG/MOV), and Finder tags
- **Rating System** — 1-5 star ratings with batch operations
- **macOS Finder Tags** — Full integration with macOS native tag system, auto-discovers your custom tag names and colors
- **Quick Look Preview** — Press Space to preview photos, just like Finder
- **Keyboard Navigation** — Arrow keys to navigate, Space to preview, Delete to remove
- **Batch Operations** — Select multiple photos and batch set ratings, tags, or delete
- **One-Click Delete** — Remove both JPG and RAW (NEF) files simultaneously
- **File Type Badges** — Visual indicators for RAW/RAW+JPG/JPG/MOV on each photo
- **Thumbnail Caching** — Two-level cache (memory + disk) for fast loading, even with 10GB+ directories
- **Sort Options** — Sort by name, date, rating, or size in ascending/descending order

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later

## Build & Run

1. Clone the repository:
   ```bash
   git clone git@github.com:SAN-SHIa/SwiftCull.git
   cd SwiftCull
   ```

2. Generate the Xcode project (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)):
   ```bash
   brew install xcodegen
   xcodegen generate
   ```

3. Open and run:
   ```bash
   open SwiftCull.xcodeproj
   ```

   Or build from command line:
   ```bash
   xcodebuild -project SwiftCull.xcodeproj -scheme SwiftCull -configuration Debug build
   ```

## Usage

1. Launch SwiftCull — it will automatically load photos from the configured path
2. Click **Open Folder** or press `⌘O` to select a different directory
3. Click a photo to select it, press **Space** for Quick Look preview
4. Use **arrow keys** to navigate between photos
5. Click **Select** button to enter batch selection mode
6. In selection mode, use the toolbar to batch set ratings, tags, or delete

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Quick Look preview / close preview |
| `↑ ↓ ← →` | Navigate between photos |
| `⌘O` | Open folder |
| `⌘1-5` | Set rating |
| `⌘0` | Clear rating |
| `⌘Delete` | Move to trash |
| `A` | Select all (when not in text field) |

## Architecture

```
SwiftCull/
├── App/
│   └── PhotoFilterApp.swift      # App entry, keyboard monitoring
├── Models/
│   ├── PhotoEntry.swift          # Photo data model, FinderTagService
│   └── FilterOptions.swift       # Filter & sort options
├── Services/
│   ├── FileService.swift         # File system scanning & deletion
│   ├── RatingService.swift       # Rating persistence (UserDefaults)
│   ├── TagService.swift          # macOS Finder tag read/write (xattr)
│   └── ThumbnailService.swift    # Async thumbnail generation & caching
├── ViewModels/
│   └── PhotoStore.swift          # Central state management
└── Views/
    ├── ContentView.swift         # Main layout (NavigationSplitView)
    ├── FilterSidebar.swift       # Filter & sort panel
    ├── PhotoGridView.swift       # Photo grid with selection
    ├── PhotoDetailView.swift     # Photo detail & Quick Look
    ├── AsyncThumbnailView.swift  # Async thumbnail loading
    └── RatingView.swift          # Star rating component
```

## Tag System

SwiftCull integrates with macOS's native Finder tag system. On launch, it scans your Desktop, Documents, and Downloads folders to discover your custom tag names and their associated colors. Tags written by SwiftCull are fully compatible with Finder — you'll see the same colors and names in both apps.

macOS color index mapping:

| Index | Color |
|-------|-------|
| 1 | Gray |
| 2 | Green |
| 3 | Purple |
| 4 | Blue |
| 5 | Yellow |
| 6 | Red |
| 7 | Orange |

## License

MIT
