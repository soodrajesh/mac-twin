# DupeFinder Audit — 2026-09-10

## Build
- Compiled all of `Sources/**/*.swift` directly with `swiftc -O -parse-as-library` (matching what `build.sh` does per-arch): **clean build, zero errors, zero warnings.**
- Did not run the full `build.sh` (it installs into `/Applications` and code-signs), since this pass is build+audit only — the raw compile above is equivalent for catching build issues.

## Tests
- `Tests/run_tests.sh` (a standalone `swiftc` harness against `Models.swift`, `DuplicateGrouping.swift`, `FileCategory.swift` — no XCTest): **all tests passed**, before and after the fix below.

## Fix made
- **`Sources/DupeModel.swift` — `moveSelectedToTrash` removed files from the results list even when trashing them failed.**
  `TrashService.moveToTrash` reports per-item success/failure (permission denied, file in use, etc.), but `moveSelectedToTrash` called `removeTrashed(urls)` with the full original selection regardless of outcome. A file that failed to trash would vanish from the UI and its bytes would be counted as "reclaimed" in the confirmation sheet, even though it was still sitting on disk untouched. Fixed by collecting only the URLs that actually succeeded and passing those to `removeTrashed`. Failed items now stay visible/selected in the results list, and `lastError` still surfaces the per-file failure reasons as before.
  - This introduced a Swift 6 strict-concurrency warning (`var` captured across an actor-isolated closure) on first pass; resolved by snapshotting the successful list into a `let` before crossing into the `MainActor.run` block. Build is warning-free.

## Audit findings

**Crashes / force-unwraps / TODOs** — none found. No `!` force-unwraps, `as!`, `try!`, or `fatalError` anywhere in `Sources/`. No `TODO`/`FIXME`/`XXX` comments. Error handling is consistently done via `try?`/`guard let` with graceful fallbacks (e.g. `HashService.sha256` returns `nil` on unreadable files rather than crashing the scan).

**App icon** — no placeholder/missing states. There's no static `Assets.xcassets`; `build.sh` renders `AppIcon.icns` at build time from the `doc.on.doc.fill` SF Symbol over a gradient background, at all required sizes (16–512, @1x/@2x) via `sips`/`iconutil`. This is a deliberate, working approach for a bundle-less `swiftc` project — not a gap.

**SF Symbols vs custom assets** — fully consistent: `doc.on.doc` (start screen + app icon), `doc` (thumbnail fallback), `checkmark.circle` (empty state), `trash` (delete confirmation). No custom image assets anywhere, so there's no mixed-style inconsistency to flag.

**Entitlements** — `DupeFinder.entitlements` exists and matches the app's actual needs: no App Sandbox (deliberate — DupeFinder is DMG-distributed and needs unrestricted filesystem access for scanning/trashing arbitrary user-picked folders, which would be broken under sandboxing), Hardened Runtime applied at sign time, and all three hardened-runtime exemption keys explicitly set to `false` with a comment explaining why they're intentionally not granted. Sane and well-documented.

**Dead code / unused files** — none found. All 15 Swift files are referenced and used (`ScanningView` is defined in `ResultsView.swift` but that's just co-location, not dead code — it's driven from `MainView`). `docs/` is an empty directory; harmless, nothing to clean there.

**Version currency** — consistent. `build.sh` bakes `CFBundleShortVersionString = 1.0` / `CFBundleVersion = 1` into `Info.plist`; `make-dmg.sh` reads that value back out of the built bundle to name the DMG, so `DupeFinder-1.0.dmg` in the repo root and the Info.plist version can't drift apart. Current version: **1.0**.

## Open issues
- None found that need follow-up beyond the fix above. The codebase is small (~1,000 lines), has no SwiftPM/Xcode project (deliberate `swiftc`-only build, documented in `Tests/run_tests.sh`'s comment), and is generally well-commented about *why*, not just *what*.
- Not addressed here (out of scope per instructions): UI/theme consistency — deferred to the later UI/theme refactor stage.
