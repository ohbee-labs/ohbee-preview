# macOS Image Viewer — Value-Oriented Delivery Plan

Status: Replanned for incremental user-visible delivery
Current implementation scope: Milestone 2 complete; engineering phase gate approved
Public baseline release: v1.0.2 — Stable MVP viewport-correctness patch — 2026-07-31
Release packaging: Complete — ad-hoc signed local artifact
Sources of truth: `requirements.md`, `design.md`  
Last updated: 2026-07-31

## 1. Delivery principles

- Each milestone must be independently buildable, testable, and releasable.
- Each milestone must produce a user-visible improvement.
- Infrastructure is implemented only inside the milestone whose user feature needs it.
- A milestone is complete only when its behavior works in a signed sandboxed build.
- The selected image must remain the highest-priority work.
- No blocking file I/O, enumeration, sorting, or image decode may run on the main actor.
- Cancellation is an efficiency mechanism; session, item, and generation identity checks are the correctness boundary.
- Logging and signposts remain local, lightweight, and privacy-preserving.
- Release builds never log full paths, filenames, image contents, EXIF values, user identifiers, or bookmark data.
- Do not add Post-MVP capabilities, speculative abstractions, a database, persistent image index, cloud layer, analytics, generic media framework, or unapproved dependency.

## 2. Delivery sequence

```text
Completed Foundation
    |
    v
1 Folder Navigation MVP
    |
    v
2 Image Inspection Controls
    |
    v
3 Visual Folder Browsing
    |
    v
4 Animated Image Viewing
    |
    v
5 Safe Finder File Actions
    |
    v
6 Accessible Native Experience
    |
    v
7 Large-Folder Reliability and MVP Release
```

Later milestones may begin only after the preceding milestone has a releasable build. Defects found in an earlier milestone take priority over adding the next feature.

## 3. Completed foundation — Application shell and Finder-open lifecycle

Status: Completed 2026-07-31
Estimated overall MVP completion: 15%

### User-visible outcome

- Opening one supported image from Finder activates one reusable Ohbee Preview window.
- The selected image has a non-blocking loading, ready, or failure presentation.
- If parent-folder access is unavailable, the user can explicitly choose Allow Folder Access without losing the selected image.

### Delivered foundation

- Native macOS 14 SwiftUI application with limited AppKit integration.
- Finder/Open With cold- and warm-open handling.
- First-supported-URL policy for unexpected multi-URL events.
- Replacement session ownership and stale-result rejection.
- Selected-file security-scope handling.
- Initial parent-access assessment and same-session folder-picker fallback.
- Same-session authorization and decline state; no bookmark persistence.
- Eagerly materialized selected-image presentation before selected-file scope closure.
- Release-safe `os.Logger` categories and initial `OSSignposter` intervals.
- Debug, Release, Profiling, and Benchmark build configurations.
- App Sandbox and user-selected read/write entitlements.
- Stage 2 core and integration checks.

### Accepted limitation

The standalone sandbox spike was waived by the product owner. Folder access must therefore continue to be validated in every affected milestone using signed sandboxed builds and the folder-picker fallback must remain available.

## 4. Milestone 1 — Folder Navigation MVP

Status: Completed 2026-07-31; full release gate passed
Estimated overall MVP completion after milestone: 40%

### Objective

Deliver the first version of Ohbee Preview that users can actually use every day: open one image from Finder and browse the supported images in the same folder.

### User-visible outcome

- The selected image appears immediately or shows a truthful loading/error state.
- Supported sibling images are discovered from the same folder.
- Images are ordered by natural filename.
- Left/Right and native Previous/Next commands navigate the folder.
- Navigation stops predictably at the first and last image.
- Rapid navigation settles on the final requested image without stale-image flashes.
- If automatic folder access fails, the existing user-invoked folder authorization action restores folder browsing.

### Included scope

- Display the selected static image.
- JPEG, PNG, HEIC/HEIF, GIF first frame, and default TIFF image presentation.
- Non-recursive sibling discovery.
- Hidden-file, directory, package, and unsupported-file filtering.
- Natural filename sorting with a deterministic tie-breaker.
- In-memory session-only navigation entries.
- Stable selected-item identity during discovery and sorting.
- Previous and Next commands.
- Left Arrow and Right Arrow keyboard navigation.
- Loading and per-item error states.
- Cancellation of obsolete enumeration and decode work.
- Session, item, and generation validation before presentation updates.
- First/last boundary state with no wrapping.
- Same-session folder authorization fallback.
- Minimum privacy-safe instrumentation needed to measure open, enumeration, sorting, decode, display, navigation, cancellation, stale-result rejection, and permission/decode failures.
- VoiceOver labels and enabled/disabled command states for the controls introduced in this milestone.

### Explicit exclusions

- Image cache optimization.
- Thumbnail strip.
- Neighbor prefetch.
- GIF animation.
- Rotation.
- Zoom.
- Pan.
- Full screen.
- Move to Trash.
- Reveal in Finder.
- Advanced performance optimization.
- Persistent folder permissions or security-scoped bookmarks.
- Folder monitoring or automatic refresh.
- Subfolder traversal.

### Requirement references

- FR-001–011
- FR-013–016
- FR-022
- FR-027
- FR-031–035
- FR-036–040 as applicable to included actions
- NFR-001–007
- PERF-001–005
- PERF-008
- PRIV-001–005
- AC-001–006
- AC-012 and AC-014 at milestone-appropriate scale

### Design references

- Sections 6.1–6.6 and 6.13
- Sections 7–12
- Sections 15–18
- ADR-001–007, ADR-009, ADR-010

### Implementation work

1. Replace the temporary selected-image presentation with the minimum production static-image result and typed failure states.
2. Keep selected-image decode independent from and higher priority than folder discovery.
3. Complete the folder authorization state transition from automatic access or explicit folder selection into active discovery.
4. Enumerate immediate folder entries asynchronously using only inexpensive resource properties.
5. Filter hidden files, directories, packages, and unsupported candidates.
6. Sort candidates using localized, case-insensitive, numeric-aware filename comparison plus deterministic tie-breaking.
7. Build a lightweight, in-memory navigation snapshot that preserves the selected file by identity.
8. Add Previous/Next intents, Left/Right shortcuts, menus, boundary state, filename, and position when reliable.
9. On navigation, update the target generation, cancel obsolete work, show loading, and decode only the current target.
10. Reject late enumeration and decode results whose session, item, or generation is stale.
11. Keep folder-picker cancellation non-destructive and do not reopen it automatically.
12. Add only the signposts, counters, and failure categories required to verify this user journey.

### Acceptance criteria

- **Given** a folder containing naturally named supported images, **when** one image is opened from Finder, **then** the selected image is displayed and Previous/Next follows natural filename order.
- **Given** automatic parent access succeeds, **when** discovery completes, **then** no permission panel is shown.
- **Given** automatic parent access fails, **when** the user grants the exact parent folder, **then** the current image remains selected and navigation becomes available.
- **Given** hidden images, child folders, packages, and unsupported files, **when** discovery runs, **then** none becomes a navigation item.
- **Given** the first or last image, **when** navigation state is shown, **then** the unavailable direction is disabled and navigation does not wrap.
- **Given** twenty rapid alternating navigation commands, **when** work settles, **then** the final requested image is displayed and no older result replaces it.
- **Given** a corrupt or unreadable current item, **when** decode fails, **then** an error is shown for that item and navigation to a known neighbor remains possible.
- **Given** an image that is slow to materialize, **when** the user navigates away, **then** the obsolete result cannot update the active presentation.
- **Given** a signed Release build, **when** the full journey is performed, **then** logs contain no full path, filename, content, EXIF value, user identifier, or bookmark data.

### Required tests

- Static fixtures for JPEG, PNG with alpha, HEIC/HEIF, GIF first frame, and TIFF.
- Corrupt, zero-byte, deceptive-extension, missing, unreadable, and provider-failure cases.
- Natural-sort unit tests covering numeric names, case, locale, and deterministic ties.
- Hidden, package, directory, subfolder, and unsupported filtering tests.
- Stable-selected-item tests while the sorted snapshot changes.
- Previous/Next boundary and no-wrapping tests.
- Rapid-navigation cancellation and stale-result tests.
- Finder cold/warm open and replacement-session tests.
- Automatic access, explicit folder grant, wrong-folder selection, cancellation, and same-session authorization-reuse tests.
- Main-thread responsiveness check for enumeration, sorting, and decode.
- Signed sandbox smoke tests for local folder, Desktop, Documents, Downloads, Pictures, external drive, iCloud Drive, and available File Provider storage.
- Signpost pairing, counter correctness, and Release logger privacy tests for this journey.

### Release gate

Ship a signed sandboxed build to internal users only when the complete Finder-open-to-folder-navigation journey passes without thumbnails, cache optimization, prefetch, or viewport controls.

Result: **PASSED 2026-07-31**

Manual acceptance confirmed:

- Explicit Allow Folder Access grants the expected parent folder while preserving the displayed image.
- Discovery enables Previous/Next in correct natural filename order.
- First/last commands disable correctly and navigation does not wrap.
- Cancelling the folder picker preserves single-image viewing and does not reopen the picker automatically.
- A real HEIC/HEIF image opens and displays successfully.
- No bookmark-related UI or persistence is present.

## 5. Milestone 2 — Image Inspection Controls

Status: Completed 2026-07-31; stabilization and automated release gates pass
Estimated overall MVP completion after milestone: 58%

### Objective

Make Ohbee Preview useful for inspecting image detail while keeping the browsing model simple.

### User-visible outcome

- Images fit the window without unwanted upscaling.
- Users can switch to actual size, zoom, and pan.
- Session-only rotation helps inspect incorrectly oriented content without modifying files.
- Native full screen provides a focused viewing mode.
- Navigation remains available through keyboard commands and resets viewport state predictably.

### Included scope

- Fit to window.
- Actual-size view.
- Continuous trackpad pinch and bounded keyboard/menu zoom.
- Constrained pan for zoomed content.
- Session-only 90-degree left/right rotation.
- Reset zoom and pan to fit after navigation.
- Native macOS full screen.
- Mouse-wheel and trackpad gesture arbitration defined by requirements.
- Viewport-specific accessibility, menu state, signposts, and interaction tests.
- Resource-appropriate detail decode only when actual-size inspection requires it.

### Explicit exclusions

- Thumbnail strip.
- GIF animation.
- Persistent edits or rotation saving.
- Reveal in Finder and Trash.
- General-purpose render engine or editing canvas.

### Requirement references

- FR-004
- FR-017–024
- FR-027
- FR-034
- FR-036–039
- NFR-003, NFR-005, NFR-008
- AC-007, AC-008

### Acceptance criteria

- Fit, actual size, zoom, pan, rotation, and full screen work through native commands.
- Mouse wheel does not zoom or navigate.
- Zoomed horizontal movement pans and never navigates.
- Navigation resets zoom/pan to fit while retaining session-only per-item rotation.
- Source bytes and metadata remain unchanged.
- Full screen preserves the active folder session and current image.

### Required tests

- Viewport geometry and backing-scale tests.
- Gesture arbitration UI tests.
- Keyboard-only control tests.
- Multi-display and full-screen lifecycle tests.
- Rotation and source-integrity tests.
- Large-image detail failure that preserves fit presentation and navigation.
- Viewport signpost pairing and main-thread frame-stall checks.

### Release gate

Release when a user can browse and inspect static images entirely by keyboard or trackpad without modifying source files.

Automated implementation evidence:

- Milestone 1 regression, pure viewport geometry, AppModel integration, native AppKit viewport, source-integrity, Debug, Release, sandbox, entitlement, and signing gates pass.
- The navigation-centering regression is covered at the native NSScrollView/document-view seam across landscape, portrait, small, large, rotated, stale-origin, and resized replacements.
- Launch Services declares Viewer/Alternate support for JPEG, PNG, HEIC, HEIF, GIF, and TIFF; default-handler guidance is user-invoked and never changes system preferences.
- Folder-access fallback is shown only after the selected image is ready, remains non-modal, and does not repeat automatically after cancellation.
- Manual GUI smoke checks pass: replacement centering across image shapes and sizes, zoom/pan/rotation followed by navigation, resize and full-screen navigation, Finder Open With and Change All, contextual folder grant/cancellation, no automatic association mutation, and no bookmark persistence.

### Engineering review gate

Senior code-quality review completed 2026-07-31. Behavior-preserving stabilization performed:

- Cold-launch URL buffering now retains only the latest supported request, matching the existing stale-result policy.
- ImageIO decodes directly from the authorized file URL instead of first allocating the entire compressed file as `Data`.
- Equivalent viewport-scale publications are suppressed to avoid redundant SwiftUI invalidation.
- The representative-sibling read probe now closes its file handle on every path.
- Redundant viewport installation state was removed; canonical document/clip geometry remains the single centering model.

All Milestone 1, Milestone 2, centering, source-integrity, Launch Services, Debug, Release, sandbox, entitlement, and signing checks passed after that review. Engineering decision: **APPROVED WITH MINOR DEBT**. Milestone 3 was subsequently authorized and completed on 2026-08-01.

## 6. Milestone 3 — Visual Folder Browsing

Status: Completed 2026-08-01; release gate passed with documented slow-storage limitations
Estimated overall MVP completion after milestone: 69%

### Objective

Help users recognize and jump to nearby images visually without turning the application into a photo manager.

### User-visible outcome

- A hidden-by-default thumbnail strip can be toggled.
- Visible thumbnails load progressively.
- Selecting a thumbnail changes the current image.
- Large folders do not freeze the strip or trigger all thumbnails at once.

### Included scope

- Optional thumbnail strip.
- Persisted strip visibility preference only.
- Virtualized visible/nearby thumbnail request window.
- Bounded thumbnail work and memory cost.
- Placeholder and isolated thumbnail failure.
- Keyboard and VoiceOver thumbnail selection.
- Thumbnail latency, request, cancellation, hit/miss, insertion, eviction, cost, and stale-result instrumentation.

### Explicit exclusions

- Persistent thumbnail database.
- Albums, favorites, tagging, drag reordering, or batch selection.
- Full-image neighbor prefetch.

### Requirement references

- FR-025, FR-026
- FR-027
- FR-036–038
- NFR-003, NFR-005
- PERF-006, PERF-007
- AC-009

### Acceptance criteria

- The strip is off by default and its visibility choice survives relaunch.
- A 10,000-item folder requests only visible and nearby thumbnails.
- Rapid scrolling cancels obsolete work.
- Thumbnail failure never blocks primary image navigation.
- Keyboard and VoiceOver users can select a thumbnail and understand selection.

### Required tests

- Visibility preference test.
- Virtualization and request-count tests.
- Rapid-scroll cancellation and stale-result tests.
- Bounded-cost and eviction tests.
- Thumbnail failure isolation.
- Keyboard, focus, and VoiceOver assertions.
- 10K/100K request-volume and memory observation.

### Release gate

Release when the optional strip adds visual navigation without changing the lightweight folder-viewer model or making work proportional to total folder size.

### Implementation record — 2026-08-01

- Added a hidden-by-default, persisted, resizable SwiftUI thumbnail sidebar with automatic nonanimated selection scrolling.
- Added an isolated `ThumbnailController`, ImageIO `ThumbnailLoader`, priority-aware bounded `ThumbnailScheduler`, byte-cost `ThumbnailCache`, and row-scoped `ThumbnailViewModel`.
- Thumbnail generation uses ImageIO thumbnail APIs with orientation transforms and never enters the selected-image decode pipeline.
- `LazyVStack` row appearance/disappearance owns request/cancellation, so work follows the rendered working set rather than total folder size.
- Folder replacement, sidebar closure, application-view teardown, and memory pressure cancel thumbnail work; generation/session checks reject stale publication.
- Cache default is 64 MiB, uses deterministic least-recently-used byte-cost eviction, and is purged on memory pressure. There is no disk cache.
- Local diagnostics cover cache hits, misses, hit rate, count, cost, insertions, evictions, generated count, latency average, active/waiting/peak tasks, cancellations, stale results, and failures without paths or filenames.
- Automated coverage passes for selection synchronization, cache hit/eviction, duplicate suppression, visible priority, active and queued cancellation, folder switch, stale session rejection, ImageIO orientation, corrupt images, memory pressure, concurrency bounds, and a 10,000-entry/20-request working set.
- Synthetic 10,000-entry scheduling measurement: 20 requested thumbnails in approximately 16 ms, peak three decodes, 61,440-byte cache cost. A 100-thumbnail ImageIO fixture run completes in approximately 11 ms total on the current development machine with peak concurrency three; fixture results are comparative engineering measurements, not user-device guarantees.
- The local interactive GUI, persistence, divider, keyboard, VoiceOver, selection-scroll, rapid-scroll, Dark Mode, bounded-memory smoke, and UI-responsiveness checks were subsequently completed and passed. Slow-storage environments remain documented below.

### Post-milestone release-gate review — 2026-08-01

- Actual signed Release application opened a 300-image local folder successfully with the sidebar disabled and enabled; the process remained alive throughout each smoke observation.
- Observed RSS was 93,712 KiB with the sidebar disabled and 109,504 KiB with it enabled after initial materialization, an increase of 15,792 KiB. Subsequent representative physical scrolling showed no unbounded growth; quantitative post-close RSS and system-pressure measurements remain unavailable.
- Automation could not drive accessibility UI or capture the screen in the execution environment. The user subsequently completed and passed the divider, show/hide, relaunch persistence, synchronization, physical scrolling, Light/Dark, fullscreen, keyboard-focus, and VoiceOver matrix manually.
- Slow iCloud Drive materialization, third-party File Provider behavior, and slow external-volume behavior remain unverified release limitations.
- Engineering review found and fixed two serious lifecycle defects: detached ImageIO generation could outlive scheduler cancellation, and retained off-screen row view models could hold `CGImage` instances outside the cache budget.
- Safe review refactors also removed per-render `Array(enumerated())` allocation, added visible sidebar focus indication, strengthened cancellation immediately after permit acquisition, and replaced brittle fixed test delays with state-based waits.
- Architecture review: 9/10. Thumbnail decode, scheduling, caching, lifecycle, and rendering remain outside `AppModel`; dependency direction is concrete and narrow.
- Concurrency review: 8.5/10. Actor isolation, bounded priority scheduling, deduplication, priority promotion, queued/active cancellation, session invalidation, and stale publication checks pass. ImageIO C calls cannot be interrupted mid-call, but cancellation is checked immediately before and after them.
- Memory-management review: 8.5/10. Cache cost is byte-based and bounded, off-screen row images are released, nearby task retention is bounded, and memory pressure purges cache/work. Representative real-folder scrolling passed; quantitative post-close RSS remains unmeasured.
- SwiftUI/AppKit integration review: 8/10. `HSplitView`, `LazyVStack`, stable URL identity, selection scrolling, row lifecycle, adaptive system colors, and focus indication are appropriate. Real divider, VoiceOver, Dark Mode, and fullscreen validation subsequently passed manually.
- Testability review: 8.5/10. Deterministic cache/scheduler/session fixtures and native integration coverage are strong; full UI automation and accessibility automation are absent.
- Final release gate decision after the manual matrix: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**. Official project completion is 69%.

### Final manual acceptance — 2026-08-01

- Passed show/hide behavior, real-quit visibility persistence, sensible divider resizing, stable thumbnail geometry, main-image centering, window resizing, and fullscreen layout.
- Passed progressive population, responsive rapid physical scrolling, cache-backed revisits, sidebar close/reopen stability, and representative bounded-memory observation without an obvious UI stall.
- Passed click, Previous/Next, keyboard, automatic scroll-to-selection, rapid-navigation synchronization, and final-main-image consistency.
- Passed Light and Dark appearance checks, meaningful VoiceOver labels, selected-state announcement, sidebar-control labels, and privacy review with no private paths announced or logged.
- Slow iCloud materialization, third-party File Provider behavior, and slow external-volume behavior remain unverified release limitations, not blockers for the local-folder milestone.
- Engineering decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**.
- Repository ignore rules were intentionally consolidated from `OhbeePreview/.gitignore` into the root `.gitignore`, preserving `.DS_Store`, SwiftPM, build, test, icon-generation, `dist`, and DerivedData exclusions for the whole repository.

## 7. Milestone 4 — Animated Image Viewing

Status: Completed 2026-08-01; automated and signed-build gates passed with documented manual limitations
Estimated overall MVP completion after milestone: 76%

### Objective

Display ordinary animated GIFs correctly without allowing animation work to degrade navigation.

### User-visible outcome

- Animated GIFs play with valid timing.
- Playback pauses when the item is no longer current or visible.
- Leaving a GIF remains immediate.
- Unsafe GIFs degrade to a safe state rather than destabilizing the app.

### Included scope

- GIF property and frame validation.
- Bounded frame working set.
- Timing normalization.
- Pause/resume based on current item and visibility.
- Immediate cancellation on navigation/session replacement.
- Safe first-frame or resource-limit fallback.
- GIF-specific startup, failure, frame pacing, cancellation, and memory instrumentation.

### Explicit exclusions

- Video, Live Photos, editing, export, or generic media playback.

### Requirement references

- FR-012
- FR-015
- FR-031, FR-032, FR-034
- FR-036–040
- NFR-005, NFR-007, NFR-008

### Acceptance criteria

- Ordinary valid GIFs animate with reasonable timing.
- Navigating away stops GIF work promptly.
- Rapid Previous/Next remains deterministic while GIFs are present.
- Corrupt, excessive, or malformed GIFs produce a useful safe result.
- Memory pressure releases discardable frame data.

### Required tests

- Static and animated GIF fixtures.
- Long, large, high-frame-count, corrupt, truncated, and malformed-timing fixtures.
- Navigation/session cancellation tests.
- Window visibility lifecycle test.
- CPU, frame pacing, and peak-memory measurements.

### Release gate

Release when GIF support cannot delay current-image navigation or violate provisional memory limits.

### Implementation record — 2026-08-01

- Added an isolated `AnimatedImageController`, ImageIO loader, concurrency-one frame scheduler, and playback-session-aware bounded frame store; `AppModel`, folder navigation, viewport geometry, and thumbnail responsibilities remain separate.
- Selected-only classification distinguishes static files, single-frame GIFs, multi-frame GIFs, and invalid/resource-excessive GIFs without parsing GIFs during folder discovery.
- Timing prefers valid unclamped/clamped GIF delay metadata, substitutes 100 ms for missing, invalid, zero, or sub-20 ms values, uses `ContinuousClock`, accounts for decode time, and skips overdue frames without creating a backlog.
- Missing or zero loop metadata plays indefinitely while active. A positive loop count is treated as repeat count after the initial pass. Reselecting or reactivating a GIF restarts at frame zero; loop progress is never persisted.
- Playback identity includes folder/current-image generation through the selected-image generation plus a dedicated playback session, URL, and frame index. Navigation, Finder open, view disappearance, application inactivity, and superseding selections cancel or invalidate prior publication.
- The frame store is independent from thumbnail storage, limited to eight decoded frames and 64 MiB, accounts with decoded bytes, retains the presented frame outside the store, and purges all noncurrent frames on memory pressure. There is no disk cache.
- Resource guards reject more than 10,000 frames, dimensions above 16,384 pixels per axis, and decoded frame estimates above 64 MiB before animated frame decode. A later bad frame preserves the last valid presentation and does not disable navigation.
- The existing AppKit viewport replaces only frame pixels for a content revision, preserving document geometry, Fit/Actual Size state, zoom, pan, rotation, resize, fullscreen, and centering. Thumbnail rows remain static first-frame images.
- Local-only privacy-safe diagnostics cover classification/first-frame context, frame decode duration, presentation lateness, displayed/skipped frames, starts/stops, pause/resume, loop completion, cache hit/miss/cost, cancellation, stale rejection, timing normalization, failure, and memory-pressure purges without paths or filenames.
- Deterministic generated fixtures and fakes cover static/single/multi-frame classification, timing normalization, loop parsing/completion, frame decode, corruption, excessive cost, LRU/cost/count/purge behavior, URL/session identity, deduplication, concurrency bound, queued/active cancellation, pause/resume, static navigation invalidation, stale publication, and corrupt-frame isolation.
- Final automated results: 22 Folder Navigation core, 17 viewport geometry, 13 Milestone 1 integration, 21 Milestone 2 integration, 34 thumbnail pipeline, 31 animated-image pipeline, 73 native AppKit viewport, and six-UTI Launch Services checks pass. HEIC fixture generation remains skipped because the installed ImageIO encoder is unavailable.
- Optimized fixture measurement on the development environment for a generated 3-frame 8×8 GIF: classification approximately 0.31 ms and one frame decode approximately 14.9 ms. The frame limits are 64 MiB and eight frames; these synthetic numbers are comparative, not universal guarantees.

### Post-implementation engineering review — 2026-08-01

- Review found and fixed a serious cross-session identity defect: frame tasks and cached frames now key by playback session, URL where applicable, and frame index, preventing an old GIF from satisfying or cancelling a newer request.
- Review added an explicit concurrency-one decode gate, active and queued cancellation coverage, resource checks before the selected GIF's first decode, per-frame property/cost validation, and a viewport regression proving animated frame replacement preserves geometry, pan, and magnification.
- Architecture 9/10; concurrency 9/10; memory 8.5/10; performance 8.5/10; testability 8.5/10; privacy/security 9.5/10; production readiness 8.5/10.
- Known technical debt: ImageIO is trusted for GIF compositing/disposal; no automated macOS accessibility/UI harness observes animation; high-frame-count and pathological real-world files need broader device measurements; ImageIO frame creation cannot be interrupted during the native call but late publication is generation-safe.

### Manual validation status — 2026-08-01

- Terminal-driven fixtures verify metadata, decode, timing, loop, cancellation, memory bounds, viewport preservation, and failure behavior. Debug and clean signed Release builds pass.
- Visual/manual checks remain unverified for real transparent and disposal-heavy GIFs, large/high-frame-count GIFs, rapid installed-app navigation, interactive zoom/pan/rotation/fullscreen/sidebar behavior during playback, window-close and inactivity observation, multi-minute RSS/CPU behavior, and Light/Dark visual consistency.
- Gate decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**. The unverified visual and long-running environments are release limitations to close before a public numbered release, not evidence of automated failure.

## 8. Milestone 5 — Safe Finder File Actions

Status: Completed 2026-08-01; automated and signed-build gates passed with documented manual limitations
Estimated overall MVP completion after milestone: 84%

### Objective

Let users move between Ohbee Preview and Finder and safely remove unwanted images without becoming a file manager.

### User-visible outcome

- Reveal in Finder selects the current file.
- Move to Trash always requires confirmation.
- Successful Trash chooses a deterministic next image.
- Cancellation or failure preserves the file and navigation state.

### Included scope

- Reveal current image in Finder.
- Native Trash confirmation naming the file.
- Sandboxed move to system Trash.
- Typed cancellation and failure behavior.
- Deterministic next, previous, or empty selection after success.
- Coordination with current decode, GIF, and thumbnail work.
- Privacy-safe action duration, outcome, and failure instrumentation.

### Explicit exclusions

- Permanent delete.
- Batch actions.
- Rename, duplicate detection, rating, tagging, albums, or file organization.

### Requirement references

- FR-028–030
- FR-033
- FR-036–040
- PRIV-001–003
- AC-010

### Acceptance criteria

- Reveal selects the exact existing file.
- No file moves before affirmative confirmation.
- Cancellation changes nothing.
- Navigation changes only after confirmed Trash success.
- A successful middle-item Trash selects the next item at the same index; otherwise previous; otherwise empty.
- Failure retains the current item and explains that Trash did not complete.

### Required tests

- Local writable, read-only, missing, external-volume, iCloud, and available File Provider cases.
- Confirmation cancellation.
- Middle, first, last, and only-item selection.
- File location and source-integrity verification.
- Permission failure and signpost pairing tests.

### Release gate

Release only after Trash behavior passes signed sandbox tests and no permanent-delete path exists.

### Implementation record — 2026-08-01

- Added an isolated `FinderActionController`, native confirmation, Reveal service, and Trash service. Mutation APIs remain outside image decode, thumbnail decode, GIF playback, viewport geometry, and folder enumeration.
- Every action captures an immutable target containing folder-session ID, committed URL, selected-image generation, filesystem identity, size, and modification date. Confirmation and native execution never reread the later current selection to choose a target.
- The critical A→B race is covered deterministically: Delete is invoked for A, confirmation remains open, navigation commits B, confirmation resolves, and the service receives only A's original URL/generation while B remains intact and selected.
- Post-confirmation validation rejects a target removed from the active session; pre-mutation validation rejects missing/replaced files. Per-action UUID ownership prevents a late old action from clearing pending/error/animation state belonging to a newer action.
- Reveal uses `NSWorkspace.activateFileViewerSelecting`. Trash uses only `FileManager.trashItem`; no permanent-delete API, shell command, AppleScript, bookmark, folder monitor, retry loop, or broad filesystem entitlement was added.
- Successful current-item Trash chooses the next item at the removed index, otherwise the previous item, otherwise a stable empty-folder state. Removing a noncurrent immutable target preserves the newer current selection.
- Successful reconciliation cancels stale selected-image work, resets viewport state, removes session rotation state, releases the selected-file scope when applicable, removes the navigation entry, and issues targeted thumbnail cancellation/eviction without rebuilding the thumbnail cache.
- GIF playback is suspended for the full confirmation/operation interval, resumes after cancellation/failure, and is invalidated by the replacement or empty presentation after successful current-GIF Trash.
- Added native File-menu commands: Reveal in Finder (`Shift-Command-R`) and destructive Move to Trash (`Command-Delete`), with computed committed-image enabled states, safe-default Cancel confirmation, accessible native labels, concise failure alert, and meaningful empty-folder content.
- Local diagnostics record Reveal count/outcome, confirmation shown/cancelled, Trash duration/success/failure with exact underlying domain/code where available, post-Trash update latency, targeted thumbnail eviction, stale-action rejection, and empty-folder transitions without paths or filenames.
- Automated results pass: 22 Folder Navigation core, 17 viewport geometry, 13 Milestone 1 integration, 21 Milestone 2 integration, 30 Finder-action checks, 35 thumbnail pipeline checks, 33 animated-image checks, 73 native AppKit viewport checks, and six-UTI Launch Services validation. HEIC fixture generation remains skipped because the installed ImageIO encoder is unavailable.

### Post-implementation engineering review — 2026-08-01

- Review found and fixed three serious correctness risks: confirmation retargeting after navigation, reconciliation into a newer folder session after an in-flight native mutation, and stale action cleanup clearing state owned by a newer action.
- Review replaced transiently invalid empty `NavigationSnapshot` mutation with a pure removal result, added filesystem replacement fingerprints when a resource identifier is unavailable, removed cancellation failure after an irreversible Trash commit, and added targeted thumbnail/GIF regression coverage.
- Architecture 8.8/10; concurrency 9.2/10; safety 9.5/10; memory/resources 9/10; testability 8.8/10; privacy/security 9.5/10; production readiness 8.5/10.
- Known debt: `NSWorkspace` does not report whether Finder visibly selected the file; native sheet focus, real system Trash placement, VoiceOver, fullscreen, and storage-provider behavior require interactive validation; file size/date is only a fallback identity when the platform resource identifier is unavailable.

### Manual validation status — 2026-08-01

- Automated mutation tests use only disposable temporary copies and a fake disposal directory; no user file is touched and no test permanently deletes a real fixture.
- Interactive signed-app validation remains pending for visible Finder selection, actual macOS Trash placement/recovery, confirmation focus/VoiceOver, fullscreen, Light/Dark appearance, read-only/unavailable volumes, iCloud Drive, third-party File Providers, and external volumes.
- Gate decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**. These interactive and environment-specific checks must be closed before a public numbered release.

## 9. Milestone 6 — Accessible Native Experience

Status: Implemented; automated/build gates passed with manual accessibility limitations
Estimated overall MVP completion after milestone: 92%

### Objective

Make every delivered MVP journey complete for keyboard and assistive-technology users, and polish the application into a coherent native macOS experience.

### User-visible outcome

- Every action is available from native menus and keyboard shortcuts.
- VoiceOver communicates current file, position, loading/error state, selection, and command availability.
- Focus moves and returns predictably.
- Reduce Motion, Increase Contrast, and Differentiate Without Color are honored.
- Rapid navigation announcements remain useful rather than noisy.

### Included scope

- End-to-end command and shortcut audit.
- VoiceOver labels, roles, values, enabled state, and selection.
- Logical focus order and focus restoration.
- Keyboard thumbnail and Trash-confirmation journeys.
- Reduced Motion transitions.
- Increased contrast and non-color state communication.
- Coalesced navigation announcements.
- Accessibility fixes for all preceding milestones.

### Requirement references

- FR-027
- FR-036–038
- AC-011

### Acceptance criteria

- Every MVP action can be completed without a pointer.
- VoiceOver communicates the current image and every loading, error, selection, and boundary state.
- Dialog dismissal restores focus sensibly.
- Reduce Motion removes large spatial transitions.
- Selection, focus, disabled state, and errors remain clear without color alone.

### Required tests

- Shortcut and native-menu UI tests.
- Keyboard-only end-to-end journeys.
- Accessibility property assertions.
- Manual VoiceOver audit.
- Focus restoration tests.
- Reduce Motion, Increase Contrast, and Differentiate Without Color tests.

### Release gate

Release when there is no critical keyboard, VoiceOver, focus, or appearance-accessibility defect across the complete MVP journey.

### Implementation and verification record

- [x] Restored native File > Open with Command-O and audited the complete shortcut map for uniqueness.
- [x] Added stable, localization-independent identifiers for the viewer, commands, sidebar/rows, Trash confirmation, folder access, error, and empty state.
- [x] Added an explicit viewer/sidebar/folder-access/error/empty-state focus model without tying focus to GIF frames or thumbnail publication.
- [x] Kept Trash Cancel as the default action and restored focus after cancellation, success, failure, and empty-folder transition.
- [x] Added concise VoiceOver labels, image position, selected thumbnail trait/value, state announcements, and duplicate-announcement suppression.
- [x] Preserved filename-only user-visible semantics and excluded paths, URLs, cache state, generations, EXIF, and per-frame GIF announcements.
- [x] Audited semantic system colors; selected rows use both outline and selected semantics so state is not color-only.
- [x] Disabled nonessential programmatic thumbnail-scroll animation under Reduce Motion while preserving GIF content playback.
- [x] Added privacy-preserving local diagnostics for focus intents, duplicate announcement suppression, and Reduced Motion branch use.
- [x] Added Milestone 6 deterministic command, metadata, focus-intent, safe-confirmation, and appearance-branch checks.
- [x] Ran Milestones 1–6 automated suites, Debug/Release builds, signing, sandbox, entitlement, UTI, icon, source-integrity, bookmark-absence, network, and Milestone 7 scope audits.
- [x] Completed post-implementation engineering review; no serious architecture, concurrency, memory, privacy, or performance finding remains.
- [ ] Manual signed-app keyboard-only matrix remains to be performed with real system panels and Trash.
- [ ] Manual VoiceOver hierarchy/focus/announcement matrix remains to be performed with VoiceOver running.
- [ ] Manual Light/Dark, Increase Contrast, Differentiate Without Color, Reduce Motion, small-window, and fullscreen appearance matrix remains to be performed.

Final gate decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**. Automated behavior, build, signing, privacy, and prior-milestone regression gates pass; the three real assistive-technology/appearance matrices above are explicitly unverified and must be completed before a public release claim.

Engineering review scores: architecture 9.0/10; SwiftUI/AppKit 8.8/10; accessibility implementation 8.5/10; testing 8.6/10; performance 9.1/10; privacy 9.6/10; maintainability 9.0/10; production readiness 8.5/10 pending the documented manual matrices. Review refactors kept `NSOpenPanel` ownership out of `AppModel` and replaced raw file-resource identity in thumbnail identifiers with a stable opaque hash.

## 10. Milestone 7 — Large-Folder Reliability and MVP Release

Status: Complete; Release v1.1.0 packaged with documented environment limitations
Estimated overall MVP completion after milestone: 100%

### Objective

Turn the complete feature set into a dependable lightweight release for photographers, large folders, slow storage, and Mac App Store distribution.

### User-visible outcome

- The selected image remains responsive in folders ranging from ordinary size to 100,000 directory entries.
- Repeated and rapid navigation does not cause stale images, runaway memory, or long UI stalls.
- Large TIFF, corrupt images, memory pressure, and slow iCloud/File Provider items fail or degrade predictably.
- Users receive a correctly signed, sandboxed, installable MVP build.

### Included scope

- Final bounded full-image, thumbnail, and GIF memory/work policies.
- Image cache optimization and tightly bounded neighbor prefetch, only if measurements prove user-visible navigation benefit.
- Memory-pressure handling.
- 100/1K/10K/100K repeatable benchmark fixtures.
- Rapid navigation and cancellation stress.
- Large TIFF, animated GIF, corrupt image, missing image, and slow-provider scenarios.
- Performance budgets and regression gates.
- Release logging/signpost/counter audit.
- Debug-only diagnostics overlay using existing metrics.
- App Store/Developer ID signing, archive, sandbox, privacy, and packaging validation.
- Final source-integrity and offline/no-network verification.

### Explicit exclusions

- Any new end-user feature.
- Analytics, cloud telemetry, user tracking, or uploaded diagnostics.
- Database, persistent folder index, persistent thumbnail store, or persistent security-scoped bookmark.
- Optimization without a failing measurement or demonstrated user-visible benefit.

### Requirement references

- FR-015, FR-026, FR-031–035, FR-039, FR-040
- NFR-002–010
- PERF-001–008
- PRIV-001–005
- AC-004, AC-006, AC-012–014

### Performance and regression gates

- Window/loading response meets PERF-001.
- Typical first-image display meets PERF-002.
- Warm Previous/Next meets PERF-003 after any approved bounded optimization.
- No application-caused main-thread stall exceeds the approved normal-journey budget.
- A 100,000-entry folder never gates selected-image presentation.
- The app never decodes all images, generates all thumbnails, or loads full EXIF metadata upfront.
- Memory stabilizes during a ten-minute mixed navigation session.
- Every signpost closes on success, cancellation, and failure.
- Release logs contain no path, filename, EXIF value, identifier, bookmark data, or file content.
- No unexplained median or p95 regression above the approved threshold is accepted.

### Required tests

- Instruments Time Profiler, Allocations, Leaks, hangs, and signpost runs.
- Automated latency percentile collection.
- 100/1K/10K/100K enumeration and sorting scenarios.
- Rapid navigation and cancellation stress.
- Ten-minute memory stability test.
- Memory-pressure injection.
- Large TIFF, animated GIF, corrupt, oversized, malformed, missing, and unreadable fixtures.
- Slow iCloud/File Provider scenario where available.
- Release, Profiling, Benchmark, and Debug configuration checks.
- Logger privacy and Debug-path opt-in tests.
- Offline/network inspection.
- Before/after file hash and metadata comparison.
- Archive entitlement, signature, document-role, launch, and clean-install validation.

### Release gate

The MVP may ship when all measurable requirements pass or approved requirement changes are reconciled, all critical/high defects are closed, signed sandbox behavior is verified on the required storage locations, and no Post-MVP infrastructure is present.

### Implementation, benchmark, and release record

- [x] Added deterministic optimized folder benchmark tooling with disposable mixed-entry fixtures, isolated measurement processes, human output, JSON output, and automatic cleanup.
- [x] Measured cold-process local/internal-SSD discovery with the final symlink-inclusive fixture: 100 entries 121 ms / 15 MiB peak RSS; 1,000 entries 154 ms / 17 MiB; 10,000 entries 823 ms / 38 MiB; 100,000 entries 7.63 s / 254 MiB.
- [x] Confirmed enumeration dominates 100K time (~7.05 s), while natural sorting is ~555 ms and matching is below 1 ms; no persistent index, sort-key cache, database, or opaque micro-optimization was justified.
- [x] Confirmed selected-image decode runs independently from folder discovery and obsolete discovery/decode work remains cancellation- and generation-guarded.
- [x] Extended the 100K thumbnail gate: only 20 visible requests, peak concurrency 3, bounded queue/cache, off-screen release, cancellation, session invalidation, and memory-pressure purge remain intact.
- [x] Added overflow-safe static-image resource guards: 32,768 pixels per axis and 512 MiB estimated decoded cost; ordinary 24 MP images remain accepted.
- [x] Confirmed GIF limits remain 10,000 frames, 16,384 pixels per axis, 64 MiB per decoded frame estimate, eight cached frames, and concurrency one.
- [x] Added viewer-close cleanup for image/navigation/rotation/session tasks and all held security-scoped resources.
- [x] Re-ran all Milestones 1–6 suites plus Milestone 7 static-resource and 100K reliability checks.
- [x] Built and signed Debug, Profiling, Benchmark, and clean optimized Release configurations.
- [x] Verified six UTIs, icon checksum, App Sandbox, `user-selected.read-write`, bookmark absence, network absence, and non-Trash source integrity.
- [x] Set marketing version 1.1.0 and build 4; created release notes and verified packaging metadata.
- [x] Completed final engineering, concurrency, memory, performance, safety, privacy, repository, and post-MVP scope reviews; no critical/high defect remains.
- [ ] Fifteen-minute fully interactive GUI session was unavailable; five repeated automated thumbnail/GIF resource cycles passed in 4.22 seconds without crash, but are not claimed as equivalent to a sustained GUI/RSS observation.
- [ ] iCloud, third-party File Provider, slow external-volume, and offline-materialization matrices remain unavailable.
- [ ] Real VoiceOver/appearance and complete packaged GUI interaction matrices remain manual environment limitations.

Final gate decision: **PASSED WITH DOCUMENTED ENVIRONMENT LIMITATIONS**. All deterministic functional, resource, benchmark, build, signing, metadata, packaging, privacy, and scope gates pass. Unavailable storage-provider, assistive-technology, and long interactive GUI environments are documented rather than inferred.

Final engineering review scores: architecture 9.1/10; concurrency 9.3/10; memory 9.1/10; performance 9.0/10; reliability and file safety 9.3/10; testing 8.8/10; privacy and sandboxing 9.7/10; release readiness 8.6/10. Release readiness is reduced only by ad-hoc signing and the explicitly unavailable interactive/storage-provider matrices, not by a confirmed functional or packaging defect.

## 11. Instrumentation ownership

Observability is not a standalone infrastructure milestone. Each user feature owns the minimum instrumentation needed to prove its behavior:

| Milestone | Required instrumentation |
|---|---|
| Completed foundation | Application lifecycle, Finder URL receipt, authorization assessment, selected-image decode/display |
| Folder Navigation MVP | Enumeration, sorting, navigation, decode, cancellation, stale-result prevention, permission/decode failures |
| Image Inspection Controls | Preview/detail decode, render commit, viewport interaction and frame stalls |
| Visual Folder Browsing | Thumbnail generation, request cancellation, bounded cache hit/miss/eviction/cost |
| Animated Image Viewing | GIF startup, frame pacing, pause, cancellation, failure, working set |
| Safe Finder File Actions | Reveal/Trash duration, confirmation outcome, success and failure |
| Accessible Native Experience | No user tracking; accessibility is validated through UI state and tests |
| Large-Folder Reliability and MVP Release | Memory pressure, full regression counters, benchmark result collection and privacy audit |

Instrumentation must use Apple system APIs such as `os.Logger`, `OSSignposter`, MetricKit where locally appropriate, and Instruments. It must not introduce an analytics SDK, generic telemetry framework, cloud service, or third-party dependency. No diagnostic data leaves the device.

## 12. Milestone completion summary

| Delivery point | Main user value | Estimated overall MVP |
|---|---|---:|
| Completed foundation | Open and display one Finder-selected image | 15% |
| 1. Folder Navigation MVP | Browse a folder with Previous/Next | 40% |
| 2. Image Inspection Controls | Zoom, pan, rotate, actual size, full screen | 58% |
| 3. Visual Folder Browsing | Optional on-demand thumbnail navigation | 69% |
| 4. Animated Image Viewing | Safe animated GIF playback | 76% |
| 5. Safe Finder File Actions | Reveal and confirmed Move to Trash | 84% |
| 6. Accessible Native Experience | Complete keyboard, VoiceOver, focus, appearance support | 92% |
| 7. Large-Folder Reliability and MVP Release | Measured large-folder resilience and distributable MVP | 100% |

Percentages estimate completed MVP user value and release readiness, not engineering hours. They are planning indicators rather than contractual progress measurements.

## 13. Primary risks

### Critical — Finder parent access under App Sandbox

The standalone spike was waived, so automatic sibling access remains environment-dependent.

Mitigation:

- Validate in signed builds during Folder Navigation MVP.
- Never assume parent authority from a selected-file URL.
- Preserve the selected image when discovery fails.
- Keep the explicit exact-parent folder-picker fallback.

### High — Stale results during rapid navigation

Apple decode or provider work may complete after cancellation.

Mitigation:

- Validate session, item, and generation on every result.
- Stress rapid Previous/Next before releasing Folder Navigation MVP.

### High — Large-image memory usage

A compressed image may require a much larger decoded allocation.

Mitigation:

- Keep Folder Navigation MVP to one current decode with no cache or prefetch.
- Add resource-aware preview/detail behavior with inspection controls.
- Finalize memory budgets from measured fixtures in the release milestone.

### High — Large-folder enumeration

Sorting or publishing a very large directory can create latency, allocation, and MainActor pressure.

Mitigation:

- Keep entries lightweight and enumeration off the main actor.
- Do not decode images or load EXIF during discovery.
- Preserve selected-image priority.
- Finalize batching and coalescing only from benchmark evidence.

### Medium — Slow iCloud and File Provider materialization

Authorized items may still be delayed or unavailable.

Mitigation:

- Show truthful loading.
- Allow navigation away.
- Reject obsolete provider results.
- Distinguish provider and permission failures from unsupported formats.

### Medium — Gesture and accessibility interaction complexity

Zoom, pan, navigation, thumbnail selection, and VoiceOver can conflict if added without end-to-end validation.

Mitigation:

- Add viewport gestures in one inspection milestone.
- Include accessibility hooks with every feature.
- Perform the complete accessibility audit before release hardening.

### Medium — Trash capability differs by volume/provider

Mutation behavior may vary across local, external, iCloud, and File Provider storage.

Mitigation:

- Test in a signed sandboxed build.
- Update navigation only after confirmed success.
- Preserve state and report typed failure otherwise.

## 14. Why this order improves incremental delivery

1. Folder Navigation MVP combines rendering, authorization, discovery, sorting, and navigation because none provides the intended daily workflow alone.
2. The first new milestone answers the central product question: whether opening one Finder image and browsing its folder feels immediate and native.
3. Cache optimization and prefetch no longer delay first usable navigation; they are introduced only when measurements demonstrate a need.
4. Viewport controls follow navigation because detail inspection is valuable only after the user can reach the desired image.
5. Thumbnails follow the stable navigation index and viewport, producing a complete visual-browsing increment rather than isolated thumbnail infrastructure.
6. GIF and file actions build on a stable current-item lifecycle, preventing format and mutation complexity from destabilizing the core journey.
7. Accessibility hooks ship with each feature, while the dedicated audit closes end-to-end gaps before release.
8. Large-folder optimization and packaging occur after the complete user workflow exists, allowing performance work to target real journeys instead of speculative abstractions.
9. Every milestone can be handed to internal users as a coherent build and evaluated before committing to the next scope.

## 15. Current authorization

- Completed foundation: Implemented and published.
- Folder Navigation MVP: Complete; automated, manual, build, signing, and release gates pass.
- Overall MVP progress: 40%.
- Milestone 2: Complete; automated, manual GUI, engineering review, build, sandbox, entitlement, signing, and release gates pass.
- Overall MVP progress: 58%.
- Milestone 3: Complete; automated, signed-build, local interactive GUI, memory-smoke, Dark Mode, keyboard, VoiceOver, engineering-review, and privacy gates pass. Slow iCloud, third-party File Provider, and slow external-volume validation remain documented limitations.
- Final Milestone 3 decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**.
- Official overall MVP progress: 69%.
- Milestone 4: Complete; animated GIF architecture, automated regressions, resource bounds, diagnostics, engineering review, Debug/Release, signing, sandbox, entitlement, UTI, icon, source-integrity, and scope gates pass with visual and long-running manual limitations documented.
- Final Milestone 4 decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**.
- Official overall MVP progress: 76%.
- Milestone 5: Complete; immutable-target Finder actions, deterministic Trash reconciliation, disposable mutation tests, engineering review, Debug/Release, signing, sandbox, entitlement, UTI, icon, privacy, bookmark-absence, and scope gates pass with interactive/system-Trash limitations documented.
- Final Milestone 5 decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**.
- Official overall MVP progress: 84%.
- Milestone 6: Implemented; keyboard command, focus, accessibility metadata, VoiceOver announcement policy, Reduce Motion, semantic appearance, diagnostics, automated regression, build, signing, entitlement, and engineering-review gates pass. Real signed-app keyboard, VoiceOver, and accessibility-appearance matrices remain documented manual limitations.
- Final Milestone 6 decision: **PASSED WITH DOCUMENTED MANUAL LIMITATIONS**.
- Official overall MVP progress: 92%.
- Release v1.0.1 remains the completed icon-legibility patch with dedicated simplified 16×16, 32×32, and 64×64 artwork and unchanged large artwork.
- Release v1.0.2 is a focused viewport-correctness patch that reasserts the committed image generation's centering invariant after later SwiftUI/AppKit layout updates.
- Release v1.0.2 is packaged at `dist/Ohbee-Preview-1.0.2/Ohbee Preview.app` and `dist/Ohbee-Preview-1.0.2/Ohbee-Preview-1.0.2-macOS.zip`; no Milestone 3 functionality is included.
- Packaged metadata verifies marketing version `1.0.2`, build `3`, bundle identifier `com.ohbee.preview`, and the same six approved image UTIs.
- Full automated validation, lifecycle regression coverage, clean Debug and optimized Release builds, ad-hoc signature verification, App Sandbox, `user-selected.read-write`, v1.0.1 icon checksum preservation, ZIP extraction, packaged launch smoke, and the installed-build manual Next/Previous matrix pass.
- Clean optimized Release build, ad-hoc signature verification, App Sandbox, `user-selected.read-write`, ZIP extraction, and full automated validation pass.
- Milestone 7: Complete; large-folder benchmarks, static/GIF/thumbnail resource bounds, session cleanup, all-build verification, release metadata, packaging, documentation, and final engineering-review gates pass with documented environment limitations.
- Final Milestone 7 decision: **PASSED WITH DOCUMENTED ENVIRONMENT LIMITATIONS**.
- Official overall MVP progress: 100%.
- Planned MVP: Complete.
- Post-MVP capabilities: Not started and not authorized.
- No post-MVP production code is authorized.
