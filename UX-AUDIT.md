# DupeFinder v1.1 — UI/UX & Functional Audit

**Remediation status (2026-09-10):** Findings #1–#5 from the Executive Summary (all Critical/High, plus the two Medium/Medium-High items in that list) are fixed, along with several cheap Medium items from the full findings list. See the per-finding status lines below and the Summary Table's Status column. Not fixed: #9 (stale-file re-check, explicitly low-priority per the audit's own cost/benefit note), #11 (batch-failure alert UI), #12 (Cancel keyboard shortcut — actually fixed as a side effect of #3's sheet rewrite), #13 (creation date on card), #14 (content-hash basis reinforcement). Reasoning for each skip is next to its row in the Summary Table.

**Method:** Static, code-driven audit of every file in `Sources/` and `Sources/Views/`, tracing the full pick-folders → scan → review → confirm-deletion flow against Apple's HIG and Nielsen's 10 usability heuristics, with destructive-action safety weighted highest since the app's entire value proposition is "trust me to safely delete your files." No live GUI automation was performed, per instruction.

**Overall polish: 6/10** against a paid Mac-utility bar. The bones are good — Trash-only deletion, content hashing (not name/size heuristics), thoughtful Pro-gating with soft upsells instead of hard walls, a real accessibility text-scale system consistently applied almost everywhere. But the single riskiest surface in the app — the deletion confirmation — doesn't itemize what it's about to delete, and there is at least one latent path (overlapping custom folders) where the UI can present the user's *only copy* of a file as a safe-looking "duplicate" to trash. For an app whose entire pitch is safety, those gaps keep it out of "ship with confidence" territory.

---

## Executive Summary — Top 5 Issues

1. **[Critical — Safety] Overlapping/nested custom folders can create phantom duplicate groups of a single, unique file.** Nothing validates that user-picked roots don't overlap (e.g. `~/Desktop` and `~/Desktop/Work` both checked). The scanner then enumerates the same physical file twice under two `Candidate` entries with the *same URL*, which get grouped as a "duplicate pair." The UI shows two visually identical cards (same name, same path — because it's the same file) and defaults to selecting the "non-keeper" copy for Trash. If the user doesn't notice the two cards are identical and confirms, DupeFinder deletes the user's only copy of that file while presenting it as routine, safe cleanup. See `Sources/Views/StartView.swift:137-145` (no containment check on `chooseFolder()`) and `Sources/Services/DuplicateScanner.swift:59-75` (`enumerate` walks each root independently with no cross-root dedup by URL).
2. **[High — Safety] A user can select every copy in a duplicate group for Trash, including the suggested keeper, with no warning.** Selection is a flat `Set<URL>` with no per-group "at least one must remain" invariant. `GroupRowView`'s per-item toggle (`Sources/Views/GroupRowView.swift:48-57`) applies identically to the keeper card and the others — nothing disables or warns when toggling the keeper on. `ConfirmDeletionSheet` (`Sources/Views/ConfirmDeletionSheet.swift`) never checks "does any group have zero surviving copies after this?" before letting the destructive action proceed.
3. **[High — Safety/HIG] The deletion confirmation sheet never itemizes what's being deleted.** `ConfirmDeletionSheet.swift:14-23` shows only an aggregate count and byte total ("Move 47 files to Trash? 1.2 GB will be reclaimed"). For the app's stated real-world use case — "thousands of files, deep folder trees" — a user commits to a specific, large, irreversible-feeling batch without ever seeing which files are in it. This fails both Nielsen's error-prevention and recognition-over-recall heuristics on the app's single most consequential screen.
4. **[Medium-High — Functional/Data-loss-of-intent] A Pro scheduled background scan can silently interrupt a user mid-review.** `DupeModel.configureScheduledScans` (`Sources/DupeModel.swift:206-225`) only guards against firing while `isScanning` is true — it does not check whether the user is currently on `ResultsView` reviewing results or has made manual trash-selection edits. When it fires, `startScan` immediately clears `groups`/`selectedForTrash` (`Sources/DupeModel.swift:53-58`) and `MainView` (`Sources/Views/MainView.swift:7-15`) switches straight to `ScanningView`, discarding the user's in-progress review with no confirmation.
5. **[Medium — Monetization UX / pre-launch blocker] Placeholder Polar org ID makes a real purchaser's valid license key report as "invalid."** `PolarConfig.organizationId` (`Sources/DupeFinderLicenseCheck.swift:42-45`) is a literal `"TODO-REPLACE-..."` string. Polar 404s any request against it, and `mapErrorResponse` (`Sources/DupeFinderLicenseCheck.swift:399-403`) maps HTTP 404 → `.invalidLicenseKey` → "The license key is invalid or not recognized." A customer who actually bought Pro and pastes a correct key today gets told their key is wrong, not that the product isn't available yet — actively misleading rather than honestly degraded.

---

## Findings by Category

### 1. Scan Flow

**1.1 — Enumeration phase isn't truly cancellable; UI can appear frozen on deep trees.**
`DuplicateScanner.scan` (`Sources/Services/DuplicateScanner.swift:15-55`) calls `enumerate(roots:extensions:)` synchronously (line 19) *before* the first `onProgress` callback and before any `isCancelled()` check. `enumerate` itself (lines 59-75) never checks `isCancelled` inside its loop. On a large/deep tree (the exact scenario named in the brief — "thousands of files, deep folder trees," possibly a slow network volume), pressing Cancel in `ScanningView` (`Sources/Views/ResultsView.swift:155-156`) has no effect until the entire enumeration finishes; the spinner + static "Scanning folders…" text (no live count) gives no feedback during this window either.
*Fix:* check `isCancelled()` inside the enumeration loop and break early; emit periodic `onProgress` during enumeration (e.g. every N files) instead of only once after it completes.

**1.2 — Free-tier folder cap is well-communicated upfront (positive finding).**
`StartView.swift:52-66`: when not Pro, "Choose Folder…" is replaced entirely by an `UnlockProButton` plus explanatory caption ("Free version scans the 5 folders above only") — the user never attempts a 6th folder and hits a surprise wall. This is exactly right per the brief's ask and worth preserving as-is.

**1.3 — Scan button disables silently with no reason shown.**
`StartView.swift:98`: `.disabled(checked.isEmpty || (resolvedExtensions?.isEmpty ?? false))`. If a user unchecks "All File Types" and picks no category and no custom extension, the button just goes gray — no inline text explains why. Minor, but a one-line hint ("Select at least one folder and file type") would close the gap per Nielsen's visibility-of-system-status heuristic.

**1.4 — Empty (0-byte) files are silently excluded from scanning.**
`DuplicateScanner.swift:69`: `size > 0` filter, undocumented in the UI. Reasonable product decision, but nowhere disclosed — a user with many duplicate empty placeholder files (e.g. `.gitkeep`-style) would see fewer "duplicates" than expected with no explanation.

---

### 2. Destructive Actions & Safety (most important section)

**2.1 — See Executive Summary #1: overlapping custom-folder roots can present a single unique file as a "duplicate" of itself.**
Root cause: no path-containment validation in `StartView.chooseFolder()` (`Sources/Views/StartView.swift:137-145`) or anywhere before `DuplicateScanner.enumerate` walks the checked roots independently. This is Pro-only (custom folders require Pro), which somewhat narrows exposure, but Pro is exactly the paying-customer segment that most deserves airtight safety guarantees.
*Fix:* before scanning, de-duplicate/collapse the root list so no checked root is a descendant of another checked root (or de-duplicate candidates by resolved URL after enumeration, before grouping — cheaper and also closes any symlink-driven variant of the same problem).

**2.2 — See Executive Summary #2: no group-level "keep at least one copy" invariant.**
`DupeModel.toggleSelection` (`Sources/DupeModel.swift:85-91`) and `applyAutoSelect` (`Sources/DupeModel.swift:140-149`) both operate on a flat `Set<URL>` with no group awareness once the user starts manually adjusting selections. Nothing in `ConfirmDeletionSheet` validates the final selection before the destructive action is enabled.
*Fix:* before enabling "Move to Trash," check whether any group would end up with zero remaining items in `selectedForTrash`, and either block the action or show an explicit, named warning ("This would delete every copy of `photo.jpg`").

**2.3 — See Executive Summary #3: confirmation sheet doesn't itemize.**
`ConfirmDeletionSheet.swift:14-23` — only "Move 47 files to Trash? 1.2 GB will be reclaimed." No expandable list, no per-group breakdown, no way to review or deselect an individual file from the sheet itself (the user has to Cancel, scroll back through potentially dozens of `GroupRowView` cards, and re-open the sheet).
*Fix:* add a disclosure/expandable list (even a simple scrollable text list of filenames+paths grouped by set) inside the sheet, and let the user uncheck an item directly from there rather than forcing a round-trip to `ResultsView`.

**2.4 — Auto-selected default (all-but-oldest) is under-communicated at the point of commitment.**
The default selection — "everything except the oldest copy in each group" — is set in `DupeModel.startScan` (`Sources/DupeModel.swift:71-73`) and surfaced on-canvas only as a green border + small "Suggested keep" caption per card (`Sources/Views/GroupRowView.swift:44-64`). There is no summary-level statement anywhere in `ResultsView` (e.g. in `summaryBar`, `Sources/Views/ResultsView.swift:62-72`) or in `ConfirmDeletionSheet` explicitly stating the rule ("We've pre-selected every copy except the oldest in each set for deletion — review before confirming"). A user who scans a large batch and scrolls straight to the bottom "Move N to Trash" button without reading every card's green border may not consciously register what the default rule was.
*Fix:* add one line to `summaryBar` or the confirm sheet stating the default rule explicitly, once, in plain language.

**2.5 — Smart Select (Pro) overwrites the user's manual edits with no warning.**
`ResultsView.autoSelectMenu` (`Sources/Views/ResultsView.swift:74-87`) calls `model.applyAutoSelect(strategy)` directly on tap; `applyAutoSelect` (`Sources/DupeModel.swift:140-149`) fully replaces `selectedForTrash` for every group. If a user has already hand-adjusted selections in some groups, one Smart Select tap silently discards that work with no confirmation or undo affordance.
*Fix:* at minimum, a brief undo toast ("Selection replaced by Smart Select — Undo"), or a confirmation if any manual edits exist.

**2.6 — No re-verification that a selected file still matches what was scanned (stale-reference / TOCTOU gap).**
Between scan and confirm, a file could be modified (content changed, still same path) by another process/app. `TrashService.moveToTrash` (`Sources/Services/TrashService.swift:15-27`) will still happily trash it — it only fails if the file is now *missing*, not if it's changed. Since the "keeper" is chosen by content hash at scan time, a scenario exists where the "duplicate" selected for deletion has since diverged from the keeper and is no longer actually redundant, and the app has no way to know or warn. This is a low-probability but real edge case for long review sessions on active file trees (e.g. a Downloads folder still receiving files).
*Fix:* low priority given cost/benefit, but consider a cheap mtime-vs-scan-time check on the selected files right before trashing, surfaced as a soft warning rather than a hard block.

**2.7 — Positive: Trash-only deletion, no permanent-delete path.**
`TrashService.swift:1-5` deliberately never calls `removeItem` — everything is recoverable until the user empties Trash. `ConfirmDeletionSheet.swift:20` states this plainly ("Files go to Trash, recoverable until you empty it."). This is the right default and the right disclosure, and it's the safety net that keeps 2.1/2.2 above from being unrecoverable data loss on first contact — though note it doesn't help once Trash is emptied, which for most users happens routinely.

**2.8 — Failure reporting on partial-batch trash failures is easy to miss.**
`ResultsView.footer` (`Sources/Views/ResultsView.swift:114-134`) surfaces `model.lastError` as a `.caption`-sized, `.lineLimit(2)` orange label at the bottom of the window, easy to overlook, especially if several files failed (permission denied, in use) — the message is a newline-joined blob (`Sources/DupeModel.swift:111`) that gets visually truncated at 2 lines with no way to see the rest.
*Fix:* surface batch failures in a dismissable alert or expandable list, not a clipped caption.

---

### 3. Pro/Monetization UX

**3.1 — See Executive Summary #4: scheduled scans can interrupt an active review session.**
`DupeModel.configureScheduledScans` (`Sources/DupeModel.swift:206-225`) checks only `!self.isScanning`, never whether the user is actively reviewing (e.g. `hasScanned && !model.groups.isEmpty` with unsaved selection edits). Combine with `MainView`'s unconditional `if isScanning { ScanningView }` switch (`Sources/Views/MainView.swift:7-15`) and a background scan silently rips the user out of `ResultsView`.
*Fix:* skip/defer a scheduled run if the user currently has unreviewed results on screen (`hasScanned && !groups.isEmpty`), or at minimum prompt before replacing.

**3.2 — See Executive Summary #5: placeholder Polar org ID produces a misleading error for real customers.**
`DupeFinderLicenseCheck.swift:37-45` — the doc comment is candid about this being unfinished, which is good internal hygiene, but as shipped today the failure mode a paying user sees is "invalid license key," not "Pro isn't available yet" or a maintenance-style message. This is flagged as a functional bug in §6 as well since it's as much a bug as a UX issue.
*Fix (when wiring the real org):* trivial once the TODO is resolved. Until then, if there's any chance v1.1 ships before that's done, consider special-casing the placeholder org ID to short-circuit with a distinct, honest "Pro licensing isn't live yet" message rather than routing through the generic 404 path.

**3.3 — Free-tier degrades honestly; upsell moments are soft, not hard walls (positive finding).**
Every Pro-gated affordance in the codebase — `UnlockProButton`/`ProBadge` (`Sources/Views/ProGate.swift`), Smart Select (`ResultsView.swift:76-86`), Export Report (`ResultsView.swift:90-100`), Custom folders (`StartView.swift:52-66`), Scheduled scans (`SettingsView.swift:162-176`) — replaces the feature with a clearly labeled, appropriately styled (orange, lock icon) unlock button rather than disabling a control silently or showing an error. None of these attempt a live network call as a free user, so the placeholder-org failure mode in 3.2 only affects users who actually *have* a key, not free users generally — free-tier degradation is honest and confusion-free, matching the brief's ask.

**3.4 — License entry UI has no forward path once "invalid" is shown (compounds 3.2).**
`LicenseManagementView.swift` shows the error inline (`verificationMessage`, lines 45-55) but offers no "Contact support" / "report an issue" link from that specific failure state — the general bug-report link lives only in the About tab (`SettingsView.swift:219-222`), several tabs away. A confused paying customer seeing "invalid key" has no obvious next step from where the error appears.

---

### 4. Accessibility

**4.1 — Icon-only Trash-selection toggle has no accessibility label or tooltip.**
`GroupRowView.swift:48-57` — the per-item circle/checkmark toggle button (the single most important interactive control on the results screen) has neither `.help(...)` nor `.accessibilityLabel(...)`. Every other custom control in the app that isn't a `Label` (e.g. `LicenseManagementView.swift:65-71`'s xmark-circle clear button) at least has `.help(...)`; this one has neither, so VoiceOver users get no spoken description of what the control does or its current state (selected/not).
*Fix:* add `.accessibilityLabel(isSelected ? "Selected for Trash" : "Not selected")` and a `.help(...)` tooltip, consistent with the rest of the app's pattern.

**4.2 — `.appFont`/text-scale is applied consistently everywhere it should be.**
Grep confirms every `.font(...)` call outside `Support.swift` itself is on a decorative/large icon (`StartView.swift:31`, `ResultsView.swift:17`, `ConfirmDeletionSheet.swift:16`, `ThumbnailView.swift:21`, `GroupRowView.swift:52`) or the monospaced license-key `TextEditor` (`LicenseManagementView.swift:155`, a reasonable exception for a code-entry field) — never on body/label text that should be scaling with the user's Text Size setting. No bypass of the accessibility text-scale system was found. This is a clean pass and worth calling out as a strength.

**4.3 — No accessibility labels anywhere else that need them.**
A full-repo grep for `accessibilit*` returns zero hits. Beyond 4.1, this doesn't currently surface other concrete gaps because most interactive elements use `Label(...)` (which VoiceOver reads correctly) rather than bare icons — but it's worth a deliberate pass before a Mac App Store submission or any accessibility-conscious review, since there's evidently no established pattern/convention for it yet in this codebase.

---

### 5. Consistency

**5.1 — Confirmation-sheet keyboard shortcuts are inconsistent with the rest of the app.**
`ConfirmDeletionSheet.swift:26-34` gives neither the Cancel nor the "Move to Trash" button a `.keyboardShortcut`, whereas `LicenseEntrySheet` (`LicenseManagementView.swift:143-146, 176-179, 183-187`) consistently wires `.cancelAction`/`.defaultAction`. For a destructive action, deliberately omitting `.defaultAction` from "Move to Trash" (so Return doesn't trigger it) is arguably the *safer* choice and may be intentional — but Cancel should still get `.keyboardShortcut(.cancelAction)` for Escape-to-dismiss, matching every other sheet in the app.

**5.2 — Recognition-over-recall: item cards show enough to make an informed decision (positive finding).**
`GroupRowView.ItemCard` (`Sources/Views/GroupRowView.swift:33-88`) shows a real Quick Look thumbnail, filename, folder path (abbreviated with `~`), a full-path tooltip on hover, and a green "Suggested keep" badge on the keeper — plus a context menu for Reveal in Finder / Copy Path and double-click-to-reveal. This is meaningfully more than "just filenames" and satisfies the brief's ask. Creation date, the actual basis for keeper selection (`Sources/DuplicateGrouping.swift:16-22`), is *not* shown on the card itself, though — a user can't see *why* one copy was suggested as keeper over another without hovering/reasoning it out. Minor: surfacing the creation date directly on the card (or in the tooltip) would close this gap.

**5.3 — Content-hash basis for grouping is disclosed once, upfront, but not reinforced at the point of decision.**
`StartView.swift:35` states "Finds files with identical content" before the first scan — good, honest framing that heads off the "is this matching by name?" confusion named in the brief. But `ResultsView`/`GroupRowView` never reinforce this at the point where the user is actually making keep/trash decisions (e.g. no "matched by content" microcopy per group) — someone who scans, reviews results days later, or shares a screenshot out of context has no on-screen reminder of the matching basis.

---

### 6. Functional Bugs

**6.1 — Duplicate URL entries from overlapping scan roots — see §2.1 / Executive Summary #1.** Highest-severity functional bug found.

**6.2 — Placeholder Polar org ID causes real license keys to report as invalid — see §3.2 / Executive Summary #5.**

**6.3 — Enumeration phase not cancellable — see §1.1.**

**6.4 — Scheduled scan can clobber unreviewed results mid-session — see §3.1 / Executive Summary #4.**

**6.5 — No group-invariant check allows deleting every copy of a file — see §2.2 / Executive Summary #2.**

---

## Summary Table

| # | Finding | Category | Severity | Status |
|---|---|---|---|---|
| 1 | Overlapping custom folders → phantom duplicate of a unique file | Destructive Actions | Critical | **Fixed** — `DuplicateScanner.enumerate` dedupes candidates by canonical (symlink-resolved, standardized) path across all roots combined (`Sources/Services/DuplicateScanner.swift`), the robust fix regardless of UI bypass. Added a secondary UI-level warning in `StartView.chooseFolder()` when a newly-picked folder overlaps an already-checked one. Regression-tested in `Tests/main.swift`. |
| 2 | No "keep ≥1 copy" invariant; user can select every copy incl. keeper | Destructive Actions | High | **Fixed** — `DupeModel.groupsWithNoSurvivors` computed property; `ConfirmDeletionSheet` shows a named, red warning listing the affected files and disables "Move to Trash" until the user explicitly checks an override toggle. |
| 3 | Confirm sheet never itemizes files being deleted | Destructive Actions | High | **Fixed** — `ConfirmDeletionSheet` now has an expandable/scrollable itemized list (path + size, grouped by duplicate set) of every file about to be trashed. |
| 4 | Scheduled scan can silently interrupt mid-review | Pro/Monetization | Medium-High | **Fixed** — `DupeModel.isReviewingResults` (`hasScanned && !groups.isEmpty`); `configureScheduledScans`'s scheduled activity now defers (skips that tick) rather than running when the user has unreviewed results on screen. |
| 5 | Placeholder Polar org ID → misleading "invalid key" for real buyers | Pro/Monetization | Medium | **Fixed** — `PolarConfig.isConfigured` detects the still-placeholder org id; `LicenseChecker.verify` short-circuits with a new `.notYetAvailable` error ("DupeFinder Pro isn't available for purchase yet…") before ever hitting the network, so a real purchaser's valid key is never told it's "invalid." |
| 6 | Default all-but-oldest selection rule under-communicated | Destructive Actions | Medium | **Fixed (cheap)** — one line added to `ResultsView.summaryBar` stating the default rule in plain language. |
| 7 | Smart Select silently overwrites manual selection edits | Pro/Monetization | Medium | Skipped — needs an undo/confirmation affordance design decision (toast vs. alert vs. diff-preview) that's more than a cheap fix; left for a follow-up pass. |
| 8 | Enumeration phase not cancellable; scan can look frozen | Scan Flow | Medium | **Fixed (cheap)** — `DuplicateScanner.enumerate` now checks `isCancelled()` inside the walk loop and breaks early, and emits `onProgress` every 200 files during enumeration instead of only once after it completes. |
| 9 | No stale-file/content re-check between scan and trash | Destructive Actions | Low-Medium | Skipped, per the audit's own note — explicitly low priority given cost/benefit for a low-probability edge case. |
| 10 | Icon-only Trash-toggle missing accessibility label | Accessibility | Medium | **Fixed (cheap)** — `.help(...)` and `.accessibilityLabel(...)` added to the per-item toggle in `GroupRowView`, matching the app's existing pattern elsewhere. |
| 11 | Batch-failure messages truncated/easy to miss | Destructive Actions | Low-Medium | Skipped — would need a dedicated alert/expandable-list UI; deferred as a non-trivial addition beyond this pass's cheap-fix bar. |
| 12 | Confirm sheet Cancel lacks Escape shortcut (inconsistent) | Consistency | Low | **Fixed** — picked up as a side effect of the #3 sheet rewrite: Cancel now has `.keyboardShortcut(.cancelAction)`; "Move to Trash" deliberately still has none (Return doesn't trigger a destructive action). |
| 13 | Keeper's creation date (the actual selection basis) not shown on card | Consistency | Low | Skipped — cosmetic, no safety impact; left for a follow-up polish pass. |
| 14 | Content-hash basis not reinforced at point of decision | Consistency | Low | Skipped — cosmetic microcopy addition; left for a follow-up polish pass. |
| 15 | Scan-button disabled state gives no reason | Scan Flow | Low | **Fixed (cheap)** — inline caption in `StartView` explains why the Scan button is disabled (no folder selected / no file type selected). |
| 16 | Empty (0-byte) files silently excluded, undisclosed | Scan Flow | Low | Skipped — cosmetic disclosure only, no safety impact; left for a follow-up polish pass. |

**Positive findings worth preserving:** Trash-only deletion with no permanent-delete path; honest, non-error free-tier degradation with soft upsells throughout; consistent `.appFont`/text-scale usage everywhere except decorative icons; rich per-item info (thumbnail, path, tooltip, context menu) on duplicate cards; clear upfront disclosure that matching is content-based, not name-based; free-tier folder cap communicated before the user can hit it.
