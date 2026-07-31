# macOS Image Viewer — Value-Oriented Delivery Plan

Status: Replanned for incremental user-visible delivery
Current implementation scope: Folder Navigation MVP complete; Milestone 2 not started
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

Status: Planned; not started
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

## 6. Milestone 3 — Visual Folder Browsing

Status: Blocked by Milestone 2
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

## 7. Milestone 4 — Animated Image Viewing

Status: Blocked by Milestone 3
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

## 8. Milestone 5 — Safe Finder File Actions

Status: Blocked by Milestone 4
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

## 9. Milestone 6 — Accessible Native Experience

Status: Blocked by Milestone 5
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

## 10. Milestone 7 — Large-Folder Reliability and MVP Release

Status: Blocked by Milestone 6
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
- Milestone 2: Planned; not started.
- Later milestones: Planned only.
- Post-MVP capabilities: Not authorized.
- No production code may be added as part of this replanning change.
