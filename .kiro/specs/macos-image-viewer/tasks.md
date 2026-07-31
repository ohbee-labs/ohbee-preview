# macOS Image Viewer — Delivery Plan

Status: Production implementation authorized by product-owner risk acceptance  
Current implementation scope: Stage 2 only  
Sources of truth: `requirements.md`, `design.md`  
Last updated: 2026-07-31

## 1. Plan rules

- Execute production tasks in order beginning with Task 2.
- Task 1 standalone sandbox spike is cancelled and waived by product-owner decision.
- Validate folder access incrementally through the integration acceptance gate.
- Do not add Post-MVP capabilities.
- Do not add a database, persistent image index, plug-in system, cloud layer, generic media framework, or unapproved third-party dependency.
- Use release-like signing and sandbox settings for access tests.
- Every task is complete only when its deliverables, acceptance criteria, tests, and completion gate are satisfied.

## 2. Task dependency flow

```text
1 Sandbox spike (cancelled/waived)
    |
    v
2 App shell and lifecycle (authorized)
    v
3 Static rendering
    v
4 Folder discovery/navigation
    v
5 Viewport/full screen
    v
6 Thumbnails
    v
7 GIF
    v
8 Finder actions/Trash
    v
9 Accessibility/keyboard
    v
10 Performance/memory/resilience
    v
11 Packaging/signing/release
```

Tasks may be subdivided during implementation planning, but their completion gates and scope may not be weakened without approval.

## 3. Task 1 — Sandbox and Finder access spike

Status: Cancelled and waived by product-owner decision  
Completion: Not required

The unresolved Finder single-file parent-access risk is accepted. No standalone spike or findings document blocks production work.

Folder access is validated incrementally through the integration acceptance gate:

- Display the readable selected image first.
- Attempt parent enumeration and sibling access without prompting.
- Use one non-blocking, user-invoked folder-picker fallback after failure.
- Retain authorization and decline state only for the current application session.
- Never create or restore security-scoped bookmarks.
- Cover cold/warm Finder Open With, cancellation, authorization reuse, later Previous/Next and Trash integration, and required storage locations.

## 4. Task 2 — Application shell and Finder-open lifecycle

Status: Completed 2026-07-31

### Requirement references

- FR-001–004
- FR-027
- FR-031
- FR-040
- NFR-001–004
- PERF-001

### Design references

- Sections 5–7
- Sections 16–17
- Sections 21–22
- ADR-001, ADR-003, ADR-005

### Deliverables

- Native macOS 14 application shell.
- One reusable primary viewer window.
- Cold/warm single-image open handling using the approved access model.
- Session replacement and cancellation ownership.
- Initial authorization state: assessing, automatic access available, folder action available, picker presented, authorized for session, declined for image session, and access failed.
- Non-blocking Allow Folder Access action and user-invoked `NSOpenPanel` shell; complete sibling enumeration remains Task 4.
- Same-session in-memory authorization/decline tracking with no bookmark persistence.
- Native menu command surface and Dark Mode shell.
- Immediate loading-state presentation.
- `os.Logger` lifecycle and Finder-open categories using Release-safe privacy rules.
- `OSSignposter` intervals for startup-to-window, startup-to-first-pixels, open-to-window, and open-to-first-pixels.
- Opaque session/request correlation identifiers.
- Debug-only diagnostics overlay shell, disabled by default and compiled out of Release.

### Acceptance criteria

- Finder Open With activates the single primary viewer window.
- A warm open replaces the session without opening another viewer window.
- The window/loading state responds within PERF-001.
- Old-session results cannot update the new session.
- A readable selected image remains visible when parent access assessment fails.
- Folder picker never opens automatically and cancellation does not repeat the action for the same image session.
- No security-scoped bookmark API, entitlement, storage, control, or diagnostic exists.
- No application-originated network request occurs.

### Required tests

- Cold/warm integration tests.
- Repeated replacement-open concurrency test.
- Main-thread responsiveness test.
- Dark Mode smoke test.
- Offline/network inspection test.
- Logger privacy test proving Release records contain no full path or filename.
- Startup/Finder signpost pairing and endpoint tests.
- Configuration tests proving the diagnostics overlay is absent from Release.
- Authorization-state transition and no-repeat unit tests.
- Folder-picker explicit-invocation and cancellation integration tests where automation permits.

### Dependencies

- Product-owner risk acceptance recorded in `requirements.md` and `design.md`.
- Approved production access strategy in Design Sections 8–9.

### Completion gate

The lifecycle vertical slice passes FR-001–003, initial FR-005–006 behavior, old-session isolation, no-automatic-prompt, and no-bookmark tests in a signed sandboxed build.

Completion evidence:

- Debug and Release builds compile and pass ad-hoc code-sign verification with App Sandbox and user-selected read/write entitlements.
- Four Stage 2 state/coordinator unit tests pass.
- Cold and warm Open With integration requests reuse one process and primary viewer session.
- The selected image uses a non-blocking loading state and temporary minimal presentation.
- Authorization assessment and the folder-picker fallback are non-blocking and session-only.
- No bookmark entitlement, API, persistence, UI, or diagnostic control is present.
- Stage 3 remains unimplemented and unauthorized.

## 5. Task 3 — Static image rendering

Status: Blocked by Tasks 1–2

### Requirement references

- FR-004
- FR-011
- FR-031–035
- FR-039
- NFR-002, NFR-003, NFR-005, NFR-007
- PERF-002, PERF-004

### Design references

- Sections 6.6, 11–12
- Sections 15–16
- Section 18 error taxonomy
- ADR-004–007

### Deliverables

- Full-image pipeline for JPEG, PNG, HEIC/HEIF, and default TIFF image.
- Viewport-appropriate preview loading.
- Platform orientation, alpha, and color handling.
- Typed loading, unsupported, permission, missing, unreadable, decode, provider, and resource-limit results.
- Very-large-image safety checks and fit-preview degradation.
- Cancellation and identity/generation validation.
- Image property-read, preview-decode, detail-decode, display-latency, cancellation, stale-result, and typed-failure instrumentation.

### Acceptance criteria

- Representative static fixtures display correctly.
- Selected-image loading occurs off the main actor.
- Corrupt, zero-byte, deceptive-extension, missing, and oversized fixtures fail individually.
- Late static-image results cannot replace the current target.
- Viewing does not modify source bytes or metadata.
- PERF-002 and PERF-004 pass on baseline fixtures.

### Required tests

- Unit tests for error mapping and result validation.
- Supported-format fixture tests.
- Corrupt and hostile fixture tests.
- Late-completion concurrency test.
- File Provider pending/failure integration tests where available.
- Hash/metadata integrity tests.
- Instruments main-thread and allocation checks.
- Signpost pairing tests for success, cancellation, and failure.
- Decode/permission failure category counter tests.

### Dependencies

- Task 2 lifecycle/session.
- Task 1 approved access model.

### Completion gate

All static format, failure-isolation, cancellation, integrity, and initial latency tests pass.

## 6. Task 4 — Folder enumeration and navigation

Status: Blocked by Tasks 1–3

### Requirement references

- FR-005–010
- FR-013–016
- FR-022
- FR-033
- NFR-002, NFR-003, NFR-006
- PERF-003–005, PERF-008
- AC-002–004, AC-012

### Design references

- Sections 6.3–6.5
- Sections 8–11
- Sections 15–16
- ADR-002, ADR-004, ADR-005, ADR-009, ADR-010

### Deliverables

- Folder authorization state machine using the approved access strategy and integration observations.
- File-only fallback and approved folder authorization action.
- Non-recursive asynchronous enumeration.
- Hidden/package/unsupported filtering.
- Natural filename sorting.
- In-memory navigation index.
- Stable current selection across incremental snapshots.
- Left/Right and command navigation with no wrapping.
- Bounded neighbor prefetch.
- Enumeration, first-batch, natural-sort, navigation, cancellation, and stale-result signposts/counters.

### Acceptance criteria

- AC-002, AC-003, and AC-004 pass.
- Hidden and child-folder images are excluded.
- Exact Finder view ordering is not attempted.
- Selected-image display does not wait for enumeration.
- Current file remains stable when earlier-sorting entries arrive.
- First/last command states are correct.
- 20-command navigation settles on the final target.

### Required tests

- Natural-sort unit tests with case, numeric, locale, and tie fixtures.
- Filtering tests.
- Stable-selection tests.
- Navigation boundary tests.
- 1K/10K/100K enumeration benchmarks.
- Access loss during enumeration.
- Rapid navigation and stale-result tests.
- Counter assertions for enumeration/navigation cancellations and stale-result rejection.

### Dependencies

- Tasks 1–3.

### Completion gate

The core Finder-to-sibling-navigation vertical slice passes on authorized local folders and approved fallback flow, with no main-thread enumeration or decode.

## 7. Task 5 — Zoom, pan, rotation, and full screen

Status: Blocked by Tasks 3–4

### Requirement references

- FR-004
- FR-017–024
- FR-038, FR-039
- NFR-008
- AC-007, AC-008

### Design references

- Sections 6.9
- Section 14
- Sections 16–17
- ADR-008, ADR-011, ADR-012

### Deliverables

- Fit without upscaling.
- Actual-size mode.
- Continuous pinch and bounded stepped keyboard zoom.
- Constrained pointer and scroll panning.
- Fit-only horizontal navigation gesture.
- Session-only per-image 90-degree rotation.
- Reset-to-fit on navigation.
- Native macOS full screen.
- SwiftUI viewport or a documented, measured AppKit adapter.

### Acceptance criteria

- FR-017–024 acceptance criteria pass.
- Mouse wheel does not zoom or navigate.
- Zoomed horizontal scrolling never navigates.
- Navigation resets zoom/pan but preserves session rotation per item.
- Source files remain unchanged.
- Full screen preserves the active session.
- Reduce Motion behavior remains possible without separate interaction logic.

### Required tests

- Viewport geometry unit tests.
- Backing-scale actual-size tests.
- Gesture arbitration UI tests.
- Multi-display integration test.
- Rotation/file-integrity test.
- Full-screen lifecycle test.
- Frame-rate and main-thread instrumentation.

### Dependencies

- Static presentation from Task 3.
- Navigation from Task 4.

### Completion gate

The viewport passes interaction correctness, integrity, accessibility hooks, and baseline smoothness measurements. Any AppKit use is documented as a measured necessity.

## 8. Task 6 — Thumbnail strip

Status: Blocked by Tasks 4–5

### Requirement references

- FR-025, FR-026
- FR-037
- NFR-003, NFR-005
- PERF-006, PERF-007
- AC-009

### Design references

- Sections 6.8
- Section 13
- Sections 15–16
- ADR-007, ADR-008

### Deliverables

- Hidden-by-default, toggleable thumbnail strip.
- Persisted visibility preference only.
- Virtualized visible/nearby request window.
- Bounded thumbnail cache.
- Selection/current-state behavior.
- Placeholders and isolated thumbnail failure.
- Request/cancellation/cache instrumentation.
- Thumbnail latency signposts and cache hit, miss, insertion, eviction, cost, cancellation, and stale-result counters.

### Acceptance criteria

- Relaunch restores visibility.
- Thumbnail selection navigates.
- A 10,000-item strip does not request all thumbnails.
- Rapid scrolling cancels obsolete requests.
- Thumbnail failure does not affect full-image navigation.

### Required tests

- Preference test.
- Virtualization request-count test.
- Rapid-scroll cancellation test.
- Cache cost/eviction test.
- Thumbnail failure test.
- Keyboard and accessibility selection hooks.
- 10K/100K memory observation.
- Cache counter correctness and Release privacy tests.

### Dependencies

- Navigation index from Task 4.
- Viewport selection from Task 5.

### Completion gate

AC-009 passes and thumbnail work remains proportional to the visible window rather than folder size.

## 9. Task 7 — GIF playback

Status: Blocked by Tasks 3–6

### Requirement references

- FR-012
- FR-015
- FR-031, FR-032, FR-034
- NFR-005, NFR-007, NFR-008

### Design references

- Sections 6.10
- Section 12.3
- Sections 15–16
- ADR-004–007

### Deliverables

- Safe animated-GIF property and frame handling.
- Bounded frame working set.
- Valid timing playback and unsafe-timing normalization.
- Pause when no longer current or visible.
- Cancellation on navigation/session replacement.
- Resource-limit degradation.
- GIF-specific memory and frame instrumentation.
- GIF startup/decode, failure, pause, cancellation, and peak working-set measurements.

### Acceptance criteria

- Ordinary animated GIFs play.
- Leaving the item pauses playback.
- Rapid navigation is never delayed by GIF frame work.
- Pathological GIFs remain within approved safety policy or degrade with a useful state.
- Memory pressure releases discardable frames.

### Required tests

- Static and animated GIF fixtures.
- Long, large, high-frame-count, malformed-timing, corrupt, and truncated fixtures.
- Navigation cancellation test.
- Window occlusion/current-item lifecycle test.
- Memory pressure test.
- CPU, frame pacing, and resident-memory measurements.

### Dependencies

- Full-image pipeline from Task 3.
- Navigation from Task 4.
- Viewport from Task 5.
- Final GIF memory limits may depend on Task 10 calibration.

### Completion gate

GIF acceptance and safety tests pass without violating navigation correctness or provisional memory limits.

## 10. Task 8 — Finder actions and Trash

Status: Blocked by Tasks 1, 4, and 7

### Requirement references

- FR-028–030
- FR-033
- FR-039
- PRIV-001–003
- AC-010

### Design references

- Sections 6.11
- Sections 8–9
- Section 18
- Section 19

### Deliverables

- Reveal in Finder.
- Native confirmation naming the file.
- Sandboxed move to system Trash.
- Cancellation and typed failure behavior.
- Deterministic next/previous/empty selection.
- Coordination with decode, prefetch, GIF, and thumbnails.
- Privacy-safe confirmation-result, Trash-duration, success, and failure instrumentation.

### Acceptance criteria

- Reveal selects the exact existing file.
- Trash never occurs before confirmation.
- Cancellation changes nothing.
- Navigation changes only after confirmed success.
- Last-item Trash produces the empty state.
- No permanent-delete operation exists.

### Required tests

- Local writable file.
- Read-only file.
- Missing file.
- External-volume file.
- iCloud/File Provider item where available.
- Confirmation cancellation.
- Last-item and middle-item selection.
- File hash/location verification.
- Trash signpost closure and failure-category logging tests.

### Dependencies

- Integration observations for mutation under granted scopes.
- Task 4 navigation index.
- Task 7 playback cancellation coordination.

### Completion gate

AC-010 passes in signed sandboxed local scenarios, and provider/volume limitations are documented accurately.

## 11. Task 9 — Accessibility and keyboard operation

Status: Blocked by Tasks 2–8

### Requirement references

- FR-013, FR-014
- FR-021, FR-024, FR-025, FR-027
- FR-036–038
- AC-011

### Design references

- Sections 14, 17, 20
- Section 23 accessibility tests

### Deliverables

- Complete native menu and shortcut coverage.
- VoiceOver labels, roles, states, selection, and image status.
- Logical focus order and restoration.
- Keyboard thumbnail operation and Trash confirmation.
- Reduced Motion transitions.
- Increase Contrast and non-color state treatment.
- Coalesced rapid-navigation announcements.

### Acceptance criteria

- Every MVP action is keyboard-operable.
- Left/Right navigation respects boundaries.
- VoiceOver conveys filename, loading/error status, selection, and command availability.
- Dialog focus restores correctly.
- Reduced Motion and Increase Contrast journeys remain complete.

### Required tests

- Shortcut/menu UI tests.
- Keyboard-only end-to-end journeys.
- Manual VoiceOver audit plus accessibility assertions.
- Focus restoration tests.
- Reduced Motion, Increase Contrast, and Differentiate Without Color tests.

### Dependencies

- Completed user-facing features from Tasks 2–8.

### Completion gate

AC-011 passes with no pointer requirement and no critical VoiceOver or focus defect.

## 12. Task 10 — Performance, memory, and resilience

Status: Blocked by Tasks 2–9

### Requirement references

- FR-015, FR-026, FR-031–035, FR-039–040
- NFR-002–010
- PERF-001–008
- AC-004, AC-006, AC-012–014

### Design references

- Sections 10–16
- Section 18
- Sections 22–24, especially Sections 22.5–22.9
- ADR-004–007
- ADR-013

### Deliverables

- Final bounded decode, thumbnail, prefetch, GIF, and cache limits.
- Memory-pressure behavior.
- Versioned synthetic benchmark-fixture manifest.
- 100/1K/10K/100K benchmark suite.
- Rapid Previous/Next and cancellation-stress benchmarks.
- Large-TIFF, animated-GIF, corrupt-image, memory-pressure, and slow-File-Provider benchmarks.
- Open and navigation latency suite.
- Main-thread stall instrumentation.
- Ten-minute navigation stress suite.
- Hostile/corrupt/large/provider fixture suite.
- Final hard memory budgets and documented baseline.
- Privacy/network and source-integrity verification.
- Release-safe `os.Logger` category audit.
- Complete `OSSignposter` interval audit.
- Cache hit/miss, cancellation, stale-result, memory-pressure, decode-failure, and permission-failure counter audit.
- Benchmark configuration and local result artifacts containing environment metadata, median, p95, minimum, maximum, failures, memory, and counter deltas.
- Profiling configuration suitable for Instruments.
- Completed Debug-only diagnostics overlay showing existing metrics without changing functional state.

### Acceptance criteria

- PERF-001–008 pass or approved adjustments are reconciled into requirements.
- No eager all-image decode, all-thumbnail generation, or full EXIF scan occurs.
- No application-caused main-thread stall exceeds 100 ms in tested normal journeys.
- 100,000 entries do not gate selected-image presentation.
- Memory stabilizes across repeated navigation.
- One bad item cannot crash or invalidate the session.
- Offline and no-unintended-write criteria pass.
- Every required signpost interval closes on success, cancellation, and failure.
- Release logs contain no path, filename, EXIF value, user identifier, bookmark data, or file content.
- Debug paths appear only after explicit opt-in.
- No hard budget or unexplained greater-than-15% median/p95 regression remains.

### Required tests

- Instruments Time Profiler, Allocations, Leaks, hangs, and signpost runs.
- Automated latency percentile collection.
- 100/1K/10K/100K enumeration/sort tests.
- Rapid navigation stress.
- Cancellation stress with counter assertions.
- Ten-minute memory test.
- Memory-pressure injection.
- Large TIFF, animated GIF, corrupt, oversized, and malformed image suite.
- Slow iCloud/File Provider scenario where available.
- Logger privacy redaction tests in Release, Profiling, and Benchmark.
- Build-configuration behavior tests.
- Diagnostics-overlay Debug-only compilation and data-source tests.
- Network inspection.
- Before/after file hash and metadata comparison.

### Dependencies

- Tasks 2–9.
- Baseline Apple Silicon Mac with 16 GB RAM.

### Completion gate

All performance requirements have measured results, instrumentation coverage is complete, privacy tests pass, final budgets are approved, and no Critical/High resilience defect or unexplained greater-than-15% performance regression remains.

## 13. Task 11 — Packaging, signing, and release validation

Status: Blocked by Tasks 1–10

### Requirement references

- FR-001, FR-005, FR-027, FR-036–040
- NFR-001, NFR-004, NFR-009, NFR-010
- PRIV-001–005
- AC-001–014

### Design references

- Sections 21–24
- Gate 4 in Section 24
- ADR-001–012

### Deliverables

- Production signing and sandbox configuration.
- Accurate document type declarations with viewer role.
- Final entitlement audit.
- App Store privacy and review checklist.
- Supported macOS 14+ validation matrix.
- Release acceptance report mapping FR-001–040 and AC-001–014.
- Confirmation that Post-MVP infrastructure is absent.
- Final Debug/Release/Profiling/Benchmark configuration audit.
- Observability privacy audit confirming Apple-local facilities only.

### Acceptance criteria

- Signed release build opens declared formats through Finder.
- Entitlements match actual behavior and integration acceptance results.
- No network entitlement or unexpected connection exists.
- No unapproved dependency exists.
- Every FR and end-to-end AC is Passed or has an explicit approved exception.
- App Store submission metadata accurately describes data and file behavior.
- Release contains minimal privacy-preserving logging and critical low-overhead signposts only.
- Debug diagnostics overlay and detailed path logging are absent from Release.
- No diagnostics data can leave the device automatically.

### Required tests

- Signed clean-install smoke test.
- Finder default/Open With tests.
- Sandbox regression matrix.
- Supported macOS version matrix.
- Accessibility and performance release regression.
- Offline run and connection inspection.
- Source integrity and Trash verification.
- Archive/signature/entitlement inspection.
- Binary/configuration inspection for Debug-only overlay exclusion.
- Release Console/signpost privacy inspection.

### Dependencies

- Tasks 1–10 complete.
- Current App Store policy review.

### Completion gate

The product owner approves the release acceptance report and all architecture production-readiness gates pass.

## 14. Cross-cutting observability implementation tasks

These are production implementation tasks scheduled within Tasks 2–10. In the current authorization, only the Task 2 subset may be implemented.

### OBS-001 — Structured local logging

Deliverables:

- Direct `os.Logger` categories for lifecycle, open, authorization, enumeration, sorting, navigation, image, thumbnail, cache, rendering, and Trash boundaries.
- Release-safe message schemas and typed failure categories.
- Explicit Debug path-logging opt-in.

Tests:

- Release, Profiling, and Benchmark logs contain no full path, filename, file content, EXIF value, bookmark data, user identifier, or PII.
- Debug path logging is absent until explicitly enabled.
- No logging path performs network or persistent user-history writes.

Dependencies:

- Task 2 application shell.
- Integration-test observations for authorization error categories as they become available.

Completion gate:

- Privacy tests pass and logger categories match Design Section 22.1.

### OBS-002 — Signpost instrumentation

Deliverables:

- `OSSignposter` point and interval coverage for startup, Finder URL receipt, authorization, enumeration, first batch, sorting, decode, display, navigation, thumbnails, rendering, and Trash.
- Opaque session/request correlation values.

Tests:

- Every interval closes on success, cancellation, and failure.
- Metric endpoints match Design Section 22.2.
- Profiling traces contain no user path or filename.

Dependencies:

- Implemented operation boundaries from Tasks 2–8.

Completion gate:

- A Profiling trace demonstrates every required interval and point with balanced begin/end events.

### OBS-003 — Local counters and memory events

Deliverables:

- Process-local cache hit/miss/insert/eviction/cost counters.
- Cancellation and stale-result rejection counters.
- Active/peak decode and thumbnail gauges.
- Memory-pressure, purge, decode-failure, and permission-failure counters.

Tests:

- Deterministic fake-cache and cancellation tests assert exact deltas.
- Memory-pressure tests assert purge counters and eviction order.
- Counters reset between benchmark runs.

Dependencies:

- Tasks 3, 4, 6, 7, and 10.

Completion gate:

- Counters are bounded, actor-safe, nonpersistent, and agree with controlled test outcomes.

### OBS-004 — Benchmark fixtures and scenarios

Deliverables:

- Synthetic/nonpersonal fixture generator or checked fixture set.
- Versioned fixture manifest.
- Scenarios for 100, 1,000, 10,000, and 100,000 entries; rapid navigation; cancellation; large TIFF; animated GIF; corrupt image; memory pressure; and slow iCloud/File Provider.
- Local benchmark result schema with hardware, OS, configuration, commit, storage, fixture version, sample count, latency statistics, memory, and counter deltas.

Tests:

- Fixture manifest is reproducible and contains no personal image.
- Scenario setup verifies expected entry/file counts and expected success/failure.
- Slow provider scenario records Not Available rather than Pass when no provider is available.

Dependencies:

- Tasks 3–7 for complete media scenarios.
- Integration acceptance observations for authorization scenario expectations.

Completion gate:

- Every required scenario is reproducible on the baseline Mac or explicitly marked Not Available with reason.

### OBS-005 — Performance and memory regression gates

Deliverables:

- Optimized Benchmark configuration.
- Profiling configuration for Instruments.
- Automated median/p95/minimum/maximum/failure evaluation.
- Main-thread stall, settled/peak memory, ten-minute stability, and 15% regression checks.
- Locally retained reviewed baseline artifacts.

Tests:

- Known synthetic regression causes the gate to fail.
- Hard product-budget breach always fails.
- Correctness, stale-result, unbounded-growth, and main-thread-blocking failures cannot be waived by a good average.

Dependencies:

- OBS-002 through OBS-004.
- Task 10.

Completion gate:

- All Design Section 22.8 gates pass or specification changes are explicitly approved.

### OBS-006 — Debug diagnostics overlay

Deliverables:

- Optional Engineering Diagnostics overlay compiled only into Debug.
- Read-only presentation of current state, durations, counts, cache cost, active work, failures, and memory-pressure events.
- Explicit separate opt-in for paths.

Tests:

- Overlay is absent from Release and Benchmark products.
- Overlay reads existing instrumentation rather than creating duplicate state.
- Enabling the overlay does not change authorization, scheduling, cache limits, or result correctness.

Dependencies:

- OBS-001 through OBS-003.
- Task 2 overlay shell.

Completion gate:

- Debug UI test verifies contents, default-off state, privacy behavior, and Release exclusion.

## 15. Requirement coverage

| Task | Primary functional requirements |
|---|---|
| 1 | FR-001–003, FR-005–006, FR-028–030, FR-033, FR-035 |
| 2 | FR-001–004, FR-027, FR-031, FR-040 |
| 3 | FR-004, FR-011, FR-031–035, FR-039 |
| 4 | FR-005–010, FR-013–016, FR-022, FR-033 |
| 5 | FR-004, FR-017–024, FR-038–039 |
| 6 | FR-025–027 |
| 7 | FR-012, FR-015, FR-031–034 |
| 8 | FR-028–030, FR-033, FR-039 |
| 9 | FR-013–014, FR-021, FR-024–025, FR-027, FR-036–038 |
| 10 | FR-015, FR-026, FR-031–035, FR-039–040 |
| 11 | FR-001–040 release coverage |

All FR-001 through FR-040 receive implementation and/or release coverage. Cross-cutting requirements intentionally appear in more than one task.

## 16. Current authorization

- Specification reconciliation: Complete.
- Sandbox spike: Cancelled and waived by product-owner decision.
- Unresolved Finder parent-access risk: Explicitly accepted.
- User-controlled folder-picker fallback: Approved MVP behavior.
- Production application implementation: Authorized.
- Stage 2 / Task 2: Complete.
- Current authorized scope: No further production stage; explicit authorization is required before Task 3.
- Tasks 3–11: Not authorized in the current stage.
- Observability tasks: Task 2 lifecycle/open/authorization subset implemented; later subsets remain planned.
