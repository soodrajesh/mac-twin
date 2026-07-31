# DupeFinder

A native macOS duplicate-file finder. Pure Swift + SwiftUI, no Xcode, zero
third-party dependencies. Offline and private — every scan and hash happens
locally; nothing leaves your Mac.

DupeFinder's companion app [DiskSweeper](https://github.com/soodrajesh/mac-cleanup)
reclaims space from caches and junk; DupeFinder reclaims space differently —
same-content files you genuinely meant to keep, just more than once.

## Safety model

- **Duplicates go to Trash, never `removeItem`** — recoverable until you
  empty it, matching DiskSweeper's model exactly.
- **You always review before anything moves.** Scanning only selects
  suggested copies to trash (everything but the oldest in each set); nothing
  is trashed until you confirm in the deletion sheet.
- **Content-based, not name-based.** Two files are only ever called
  duplicates if their bytes match exactly (same size, then a full SHA-256)
  — never by filename or "looks similar."

## Build & run

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/soodrajesh/mac-dupes.git
cd mac-dupes
./build.sh
open /Applications/DupeFinder.app
```

`build.sh` compiles the sources, renders the app icon from an SF Symbol,
bundles `DupeFinder.app`, and installs it to `/Applications`.

## How it works

1. **Pick folders** — quick-select Downloads, Pictures, Desktop, Documents,
   Movies, or choose any custom folder.
2. **Pick file types (optional)** — defaults to "All File Types". Turn that
   off to scan only Images, Videos, Audio, and/or Documents (each a preset
   extension list), plus a free-text box for anything else (`psd, sketch`).
   The filter narrows which files are even considered — it doesn't change
   how duplicates are found, so two files with identical bytes but different
   extensions still correctly group together when no filter is set.
3. **Scan** — recursively walks the chosen folders. Files are first bucketed
   by size (a free `stat`, no content read) to eliminate anything that can't
   possibly have a duplicate; only size-collision survivors get a full
   streamed SHA-256 hash, computed concurrently across your CPU's cores.
4. **Review** — each duplicate set shows a Quick Look thumbnail (images,
   PDFs, videos — anything Quick Look renders) per copy, with the oldest
   copy suggested as the keeper (ties broken by shortest path) and every
   other copy pre-checked for Trash. Paths are truncated to fit the card —
   hover for the full path, or right-click to Copy Path or Reveal in Finder.
   Double-click a thumbnail to reveal it directly.
5. **Confirm** — one sheet shows the count and total size, then moves the
   checked copies to Trash.

## Testing

The grouping algorithm — size/hash bucketing, keeper selection, sort order —
has regression coverage in `Tests/`, run directly against the real logic
files (no XCTest, no Xcode project or SwiftPM package, matching the rest of
this project's `swiftc`-only build):

```bash
Tests/run_tests.sh
```

## Layout

```
Sources/
  App.swift, Models.swift, DuplicateGrouping.swift, FileCategory.swift, Support.swift, DupeModel.swift
  Services/  HashService, DuplicateScanner, TrashService
  Views/     MainView, StartView, ResultsView, GroupRowView, ThumbnailView,
             ConfirmDeletionSheet
```

## License

MIT
