# macOS Image Viewer — Production Architecture

Status: Production implementation authorized; sandbox uncertainty accepted by product owner  
Platform: macOS 14 Sonoma and later  
Baseline: Apple Silicon Mac with 16 GB RAM  
Language/UI: Swift, SwiftUI, narrowly scoped AppKit  
Distribution: Mac App Store  
Last updated: 2026-07-31

## 1. Purpose

This document defines the production architecture for the MVP specified in `requirements.md`.

The primary flow is:

1. Finder opens one image.
2. One primary viewer window presents that image promptly.
3. The application establishes the actual sandbox authority available.
4. Supported sibling images are discovered when the parent folder is authorized.
5. The user navigates with minimal latency.

The standalone sandbox spike was waived by product-owner decision. Folder access is validated incrementally through the integration acceptance gate in Section 24.

## 2. Architecture principles

- The selected image is never gated by complete folder discovery.
- Filesystem work and image decoding never block the main actor.
- Cancellation improves efficiency; identity and request generations guarantee correctness.
- Memory and concurrency are explicitly bounded.
- The application holds only the access granted by macOS and the user.
- The navigation index is in memory and session-scoped.
- SwiftUI is the default; AppKit is a measured, narrow fallback.
- Apple platform decoders are used for MVP.
- Failure of one file does not invalidate the session.
- No deferred feature receives production infrastructure.

## 3. Scope boundaries

### Included

- One reusable primary viewer window.
- Single Finder-selected image open flow.
- Explicit folder-authorization fallback.
- Non-recursive, non-hidden sibling discovery.
- Natural filename order.
- Static images and animated GIF.
- Previous/next, zoom, pan, rotation, thumbnails, full screen.
- Reveal in Finder and confirmed Move to Trash.
- Accessibility, sandboxing, resilience, and performance instrumentation.

### Excluded

- Multiple-file selection sessions and multiple viewer windows.
- Database or persistent image/folder index.
- Folder monitoring.
- Recursive browsing.
- Editing or saved transformations.
- RAW, video, Live Photos, advanced EXIF, slideshow, albums, ratings.
- Plug-in system, cloud layer, network service, or generic media framework.

## 4. System context

```text
Finder / NSOpenPanel
        |
        | authorized URL
        v
+------------------------------------------------+
| macOS Image Viewer                             |
|                                                |
| Application lifecycle and viewing session      |
| Folder authorization and navigation index      |
| Image and thumbnail pipelines                  |
| Viewport, commands, accessibility              |
| Finder actions and local instrumentation       |
+------------------------------------------------+
        |
        | sandbox-authorized operations only
        v
Filesystem / File Provider / Finder / Trash
```

The application is a single process with no backend, account, daemon, private media library, or network dependency.

## 5. Logical layers

```text
Presentation
    |
    v
Application Session
    |
    +-----------------------+
    v                       v
Media and Navigation        Platform Access
```

### Presentation

SwiftUI views and native commands, with a focused AppKit viewport adapter only if measurement proves necessary.

### Application session

Current item, folder authorization state, navigation state, view state, command capability, and session lifecycle.

### Media and navigation

Folder enumeration, natural sorting, image loading, GIF playback, thumbnail loading, bounded caching, and prefetch.

### Platform access

Security-scoped URLs, `NSOpenPanel`, filesystem metadata, Finder Reveal, Trash, File Provider behavior, and Apple decoders.

These are logical boundaries for responsibility and testing, not separate packages or a generic framework.

## 6. Component model

### 6.1 Application lifecycle coordinator

Responsibilities:

- Receive cold-start and warm-start open events.
- Accept one Finder-selected image.
- Reuse and activate the primary window.
- Cancel and replace the previous viewing session.
- Start selected-file access.
- Route application commands.

It does not enumerate folders or decode images.

Requirements: FR-001–003.

### 6.2 Viewing session

The single source of truth for the active viewer.

State:

- Session identity.
- Current item identity and URL.
- Current request generation.
- Folder authorization state.
- Latest navigation snapshot.
- Primary-image state.
- Viewport mode and temporary per-item rotation.
- Thumbnail visibility preference value.
- User-visible error.

Responsibilities:

- Accept user intent.
- Coordinate asynchronous services.
- Publish main-actor presentation state.
- Reject results from an inactive session or stale request.

Requirements: FR-002–004, FR-010, FR-013–024, FR-031–035.

### 6.3 Folder access controller

Owns the authorization state and security-scope lifetime.

Responsibilities:

- Start and stop access for the selected file.
- Test parent enumeration without assuming authority.
- Present or invoke the folder-selection fallback.
- Start and stop explicitly authorized folder access.
- Expose read and mutation capabilities.
- Handle denial, cancellation, scope loss, and same-session authorization state.

It never grants access by merely constructing a parent URL.

Requirements: FR-005, FR-006, FR-033, FR-035; PRIV-001–003.

### 6.4 Folder enumeration service

Responsibilities:

- Enumerate immediate entries of an authorized folder.
- Request only inexpensive keys for filtering and ordering.
- Exclude hidden files, directories, packages, and unsupported candidates.
- Emit cancelable, bounded batches.
- Never decode images or read full EXIF metadata.

Requirements: FR-007, FR-008; NFR-003, NFR-006.

### 6.5 Navigation index

An in-memory, session-scoped collection of lightweight entries.

Each entry contains only:

- Session-local identity.
- Authorized location representation.
- Display filename.
- Supported-format classification.
- Minimal status or change token when cheap and useful.

Responsibilities:

- Natural filename sorting.
- Stable current selection as batches arrive.
- Previous/next lookup.
- Boundary capability state.
- Removal of confirmed missing or trashed entries.
- Deterministic post-Trash selection.

It contains no decoded images, full metadata, persistent records, or observation tokens.

Requirements: FR-009, FR-010, FR-013–016, FR-030, FR-033.

### 6.6 Full-image pipeline

Responsibilities:

- Load current-image properties and pixels off the main actor.
- Decode JPEG, PNG, HEIC/HEIF, TIFF, and GIF with Apple frameworks.
- Honor platform orientation, alpha, and color behavior.
- Produce a viewport-appropriate preview promptly.
- Produce actual-size detail only when requested and safe.
- Enforce pixel, frame, concurrency, and memory limits.
- Return typed failures.

Requirements: FR-003, FR-004, FR-011, FR-012, FR-031, FR-032, FR-034, FR-035.

### 6.7 Navigation prefetcher

Responsibilities:

- Prefetch at most a small bounded neighbor window.
- Prefer the last navigation direction.
- Cancel obsolete work.
- Yield resources to the current image.

Initial policy:

- Current image: user-initiated priority.
- One likely next neighbor: high prefetch priority.
- One opposite neighbor: lower prefetch priority.

The policy reduces or disables prefetch for very large sources or memory pressure.

Requirements: FR-015; NFR-005; PERF-003, PERF-007.

### 6.8 Thumbnail pipeline

Responsibilities:

- Load visible and nearby thumbnails asynchronously.
- Deduplicate matching requests.
- Cancel work outside the virtualized request window.
- Cache with an explicit byte/cost limit.
- Return a stable placeholder for failure.

There is no persistent thumbnail store.

Requirements: FR-025, FR-026.

### 6.9 Image viewport

Responsibilities:

- Render static image or animated-GIF output.
- Fit without upscaling.
- Show actual size.
- Apply bounded continuous and stepped zoom.
- Apply constrained pan.
- Apply session-only 90-degree rotation.
- Resolve trackpad and pointer gestures.
- Adapt to backing-scale, window-size, appearance, and accessibility changes.

Requirements: FR-004, FR-017–024, FR-027, FR-038.

### 6.10 GIF playback controller

Responsibilities:

- Interpret safe frame timing.
- Keep a bounded frame working set.
- Pause when the GIF is not current or visible.
- Stop immediately when the session or current item changes.
- Release discardable frames under pressure.

It is format-specific and not a generic media player.

Production boundary:

- `AnimatedImageController` owns selected-GIF and application-activity lifecycle.
- `ImageIOAnimatedImageLoader` performs selected-item classification and frame decode off the main actor.
- `AnimatedFrameScheduler` deduplicates by playback session, URL, and frame index and permits one GIF frame decode at a time.
- `AnimatedFrameStore` is independent from thumbnail storage and uses playback-session keys, an eight-frame limit, and a 64 MiB decoded-byte limit.
- `AppModel` does not own GIF frames, timing, scheduling, or cache state.

Requirements: FR-012; NFR-005.

### 6.11 Finder action service

Responsibilities:

- Reveal the current item in Finder.
- Move the authorized current file to Trash after presentation confirms.
- Report cancellation and typed failures.
- Never update navigation state before confirmed success.
- Capture an immutable `FinderActionTarget` at invocation with folder-session ID, committed URL, selected-image generation, file identity, size, and modification date.
- Keep native Reveal/Trash APIs and confirmation presentation in `FinderActionController` and its two concrete services; `AppModel` coordinates intent and the successful selection transition only.
- Revalidate the captured target after confirmation and immediately before Trash. Navigation may change the visible image, but it cannot retarget the pending action.

Requirements: FR-028–030, FR-039.

### 6.12 Memory and workload policy

Responsibilities:

- Set decoded-image, GIF-frame, thumbnail, and task concurrency limits.
- Account for approximate resource cost.
- Respond to system memory pressure.
- Stop speculative work before degrading current-image presentation.

Requirements: FR-034; NFR-005–008; PERF-006–008.

### 6.13 Local instrumentation

Responsibilities:

- Record privacy-safe signposts and counters for testing.
- Measure open, decode, navigation, discovery, sorting, thumbnails, stalls, and eviction.
- Never upload data or log filenames/full paths by default.

Requirements: FR-040; PERF-001–008.

## 7. Application lifecycle and Finder open handling

### 7.1 Cold start

```text
Open event received
    -> create session identity
    -> start selected-file access
    -> activate primary window
    -> show loading/current state
    -> load selected image
    -> assess parent-folder access concurrently
```

### 7.2 Warm start

```text
New open event received
    -> create replacement session identity
    -> cancel previous task tree
    -> stop previous security scopes after dependent work ends
    -> reuse and activate primary window
    -> start new selected image and access flows
```

Late work from the old session cannot update the new session because every result carries its session identity.

### 7.3 Multiple URLs

Multiple-file selection behavior is deferred. If macOS supplies multiple URLs unexpectedly, MVP selects the first supported URL for the single-image flow and does not create a selection-based navigation session or additional windows.

## 8. Folder authorization state machine

```text
No Access Session
    |
    | Finder/Open event
    v
Selected File Access
    |
    | assess parent
    +------------------------------+
    |                              |
    v                              v
Folder Authorized           Folder Access Unavailable
    |                              |
    | enumerate                    | user chooses Allow Folder Access
    v                              v
Discovering                 Folder Panel Presented
    |                              |
    v                     +--------+--------+
Folder Ready              |                 |
                          v                 v
                    Folder Authorized   File-Only Mode
```

Any active state may transition to `Access Lost`, which retains any already displayable current content, cancels inaccessible work, disables affected commands, and offers reauthorization only when useful.

### 8.1 Security-scope rules

- Treat the Finder-provided file scope and an explicitly selected folder scope as distinct.
- Balance every successful scope start with a stop.
- Cancel dependent tasks before stopping access.
- Never assume a parent scope from a child path.
- Retain explicit folder authorization only in memory for the current application session.
- Do not create, store, resolve, restore, or refresh security-scoped bookmarks.
- Discard all folder authorization state at termination.

## 9. Accepted sandbox risk and production access strategy

The product owner accepts that Finder-provided access to one image may or may not authorize parent enumeration and sibling reads. The standalone sandbox spike is cancelled and does not gate implementation.

Opening one user-selected image therefore does not guarantee authority for its
parent folder. If automatic enumeration fails after the image is displayed,
Ohbee offers a secondary, non-modal action to select that exact folder. The
choice is remembered only for the current process: persistent authorization and
security-scoped bookmarks remain intentionally out of scope. Consequently,
Ohbee cannot guarantee both persistent zero-prompt folder browsing and the
current sandbox/no-bookmark policy. A direct-distribution, non-sandboxed variant
is a possible future product decision, not part of the MVP architecture.

Required flow:

1. Start selected-file access and display the selected image whenever readable.
2. Attempt parent enumeration and a representative sibling read without showing a permission dialog.
3. If both succeed, create the folder session and do not ask for permission.
4. If either fails, remain in file-only mode and show one non-blocking Allow Folder Access action.
5. Open `NSOpenPanel` for folder selection only after the user invokes that action.
6. Preselect or indicate the expected parent folder where permitted.
7. After authorization, keep the same selected image and continue the session while discovery begins.
8. Track authorized and declined folders/images in memory so the same session does not prompt repeatedly.
9. After cancellation, remain in file-only mode until the user manually invokes folder browsing.
10. Stop active security scopes and discard authorization state at application termination.

Permission failure never replaces a successfully displayed image, opens a modal automatically, or triggers repeated retries. No Pictures, Downloads, Desktop, full-filesystem, bookmark, or broader-than-parent-folder authority is requested.

## 10. Folder enumeration and natural sorting

### 10.1 Enumeration

- Immediate directory only.
- No package descent.
- Hidden files excluded.
- Lightweight resource properties only.
- Case-insensitive approved extension/type prefilter.
- Decoder is the final validation authority.
- Batches are bounded and cancellation-aware.

### 10.2 Sorting

Localized, case-insensitive, numeric-aware ascending filename comparison, with a deterministic tie-breaker.

The application does not attempt to reproduce Finder view configuration.

### 10.3 Partial and complete snapshots

- A partial snapshot contains known candidates in correct relative order.
- A complete snapshot contains all discovered eligible entries.
- The selected file remains stable by identity while indices shift.
- Count/position may be omitted while incomplete.
- The UI does not claim globally final neighbors before discovery can support that claim.

Batch size and update coalescing are determined by the 1K/10K/100K benchmark, not hard-coded in this document.

## 11. Image navigation state machine

```text
No Current Image
    |
    | select/open
    v
Loading(target, generation)
    |
    +------ success ------> Ready(target, generation)
    |
    +------ failure ------> Failed(target, generation)

Ready / Failed
    |
    | previous, next, or thumbnail
    v
Loading(newTarget, newGeneration)
```

### 11.1 Navigation transaction

1. Resolve target identity from the latest snapshot.
2. Increment the request generation.
3. Update selection immediately.
4. Reset viewport to fit.
5. Pause old GIF playback.
6. Cancel obsolete image and prefetch tasks.
7. Start target loading.
8. Reprioritize bounded neighbor prefetch.

### 11.2 Stale-result prevention

A result updates presentation only if:

- Its session identity is active.
- Its item identity is current.
- Its request generation is current.

Cancellation is not the correctness boundary because an Apple decode may finish after cancellation.

### 11.3 Boundaries

Previous and Next capability derives from the latest reliable navigation snapshot. The first and last items disable the unavailable direction. No wrapping or boundary animation is required.

## 12. Full-image loading pipeline

```text
Authorized item request
    -> inexpensive source inspection
    -> format and resource-safety classification
    -> viewport-sized preview decode
    -> publish identity-checked presentation
    -> optional actual-size/detail decode on demand
```

### 12.1 Static image policy

- Use Apple image frameworks.
- Preserve alpha and platform-supported orientation/color handling.
- Use the default/representative TIFF image.
- Avoid full-resolution decode when a fit preview is sufficient.

### 12.2 Very large image policy

1. Inspect dimensions and format properties without committing full allocation.
2. Estimate decoded pixel cost.
3. Prefer a downsampled fit preview.
4. Allow detail only within the current memory budget.
5. Return a resource-limit failure if safe presentation is impossible.

The MVP static-image guard rejects a dimension above 32,768 pixels per axis,
an overflow while calculating `width × height × 4`, or an estimated decoded
cost above 512 MiB before requesting full ImageIO decode. This is a bounded
allocation guard, not a claim of complete decompression-bomb protection.

### 12.3 GIF policy

- Validate dimensions, frame count, and timing.
- Animate ordinary valid files.
- Normalize malformed or unsafe timing.
- Bound decoded frames and concurrent work.
- Pause and release discardable frames when no longer current.
- Permit safe first-frame degradation plus a resource explanation for excessive files.
- Classify only the selected `.gif`; folder discovery and thumbnail generation do not count animation frames.
- Treat a one-frame GIF as a static image and restart a multi-frame GIF from frame zero whenever it becomes current again.
- Use unclamped delay metadata when valid, fall back to clamped delay metadata, and replace missing, non-finite, zero, or sub-20 ms values with 100 ms.
- Interpret a positive ImageIO loop count as repeat count after the initial pass; zero or missing loop metadata plays indefinitely while current.
- Pause when the application resigns active and restart from frame zero when it becomes active again. No explicit playback control is included in this milestone.
- Reject more than 10,000 frames, dimensions above 16,384 pixels per axis, or a decoded frame estimate above 64 MiB. These are safety limits, not a claim of complete decompression-bomb protection.
- Use ImageIO-composited frames; unusual disposal/partial-frame files that ImageIO cannot render correctly remain a platform limitation rather than grounds for a custom GIF decoder.

## 13. Thumbnail loading pipeline

```text
Virtualized strip calculates visible range
    -> add bounded leading/trailing margin
    -> diff against active requests
    -> cancel obsolete work
    -> load/generate missing thumbnails
    -> identity-check and display
```

Cache key includes item identity, requested logical size, and display scale. Source-change data may be included only when cheap.

Thumbnail failure does not remove an item or imply primary decode failure.

## 14. Zoom, pan, rotation, and full screen

### Fit

- Preserve aspect ratio.
- Account for 90-degree rotation.
- Center the image.
- Do not upscale above actual size.

### Actual size

Map one source pixel to one backing pixel on the active display. Recalculate after a display-scale change.

### Zoom

- Continuous pinch around gesture centroid where practical.
- Stepped keyboard zoom around viewport center.
- Finite safe limits established by viewport testing.

### Pan

- Available only when content overflows.
- Pointer drag, mouse wheel, and two-finger scrolling pan.
- Scrolling does not zoom or navigate by default.
- Offsets remain constrained.

### Horizontal navigation gesture

- Active only at fit scale.
- Requires a deliberate threshold.
- Produces at most one navigation.
- Zoomed content pans and never navigates.
- Reduced Motion uses a restrained transition.

### Rotation

- Multiples of 90 degrees.
- Stored in memory per item for the active session.
- Never written to the source.

### Full screen

Use the native macOS full-screen mechanism and the same window, session, commands, and pipelines.

## 15. Memory and cache policy

### 15.1 Working-set model

- UI/application baseline.
- Lightweight navigation entries.
- Current image.
- At most a small neighbor prefetch window.
- Bounded current-GIF frames.
- Visible/nearby thumbnails.
- Temporary decode workspace.

### 15.2 Cache policy

Use byte/cost limits, not count-only limits. Initial policy:

- One current presentation.
- Up to two neighbor previews when cost permits.
- Thumbnail cache bounded independently.
- GIF buffer dynamically reduced by frame cost.

Final limits come from baseline measurements. Typical still-image browsing has a 300 MB soft resident-memory target.

### 15.3 Memory pressure

Evict in this order:

1. Distant thumbnails.
2. Nonvisible nearby thumbnails.
3. Opposite-direction prefetch.
4. Likely-direction prefetch.
5. Noncurrent or future GIF frames.
6. Current detail representation, retaining or regenerating a fit preview when possible.

Stop speculative work and avoid immediate cache repopulation during pressure.

## 16. Concurrency and cancellation

### 16.1 Main actor

Owns:

- Observable UI state.
- Window and command state.
- Focus and accessibility coordination.

Never owns:

- Directory enumeration.
- File reads or provider waits.
- Type/property inspection that may block.
- Image or thumbnail decoding.

### 16.2 Task ownership

- Application coordinator owns the viewing-session lifetime.
- Folder access controller owns scope lifetime.
- Folder session owns enumeration and sorting.
- Viewing session owns current-image loading.
- Prefetcher owns bounded neighbor work.
- Thumbnail strip owns visible-window work.
- GIF controller owns frame scheduling.

Replacing the viewing session cancels its task tree before releasing access.

### 16.3 Priority

1. Current image and direct interaction.
2. Likely next neighbor.
3. Visible thumbnails.
4. Folder enumeration/sorting.
5. Opposite neighbor and thumbnail margin.

Bounded parallelism is mandatory even when priorities differ.

### 16.4 Backpressure

- Coalesce discovery snapshot updates.
- Drop obsolete thumbnail requests.
- Replace pending current-image intent with the latest target.
- Limit concurrent decodes and thumbnail generation.
- Prefer visible work over completeness.

## 17. SwiftUI and AppKit boundaries

### SwiftUI owns

- Window content composition.
- Loading, error, and empty states.
- Thumbnail strip composition.
- Native commands and menu state.
- Toolbar or overlay controls.
- Preference-driven thumbnail visibility.
- Accessibility modifiers where sufficient.
- Appearance and full-screen command integration where reliable.

### AppKit may own

- Finder/open-event bridging not adequately exposed by the selected SwiftUI lifecycle.
- `NSOpenPanel` folder authorization.
- Finder selection/reveal integration.
- Precise event arbitration or backing-scale behavior in the image viewport.
- An `NSScrollView`/custom view-backed viewport if SwiftUI fails measured zoom, pan, memory, or frame targets.

### Boundary rule

AppKit adapters expose narrow application-level actions and values. AppKit types do not spread through the folder index or media services.

A viewport spike decides whether a SwiftUI implementation passes; AppKit is not adopted preemptively.

## 18. Error taxonomy

| Category | Meaning | User recovery |
|---|---|---|
| Unsupported | Format is outside MVP | Reveal or close/navigate |
| Permission unavailable | Sandbox/filesystem denies access | Authorize folder when useful |
| Missing | File no longer exists | Remove/skip and continue |
| Unreadable | File exists but cannot be read | Navigate or Reveal |
| Decode failed | Bytes cannot produce a valid image | Navigate or Reveal |
| Resource limit | Safe memory/work limit would be exceeded | Use fit preview if available or navigate |
| Provider pending | macOS is materializing the item | Wait, navigate, or close |
| Provider failed | Provider cannot deliver the item | Retry through provider or navigate |
| Trash cancelled | User declined confirmation | No state change |
| Trash failed | Mutation was not completed | Retain selection and report |
| Folder unavailable | Siblings cannot be enumerated | Continue file-only or authorize folder |

Raw framework errors and private full paths are not shown. Underlying codes may be captured in explicit local Debug diagnostics with controlled fixtures.

## 19. Finder actions

### Reveal

Resolve the current authorized item and ask Finder to select it. Missing-file failure does not mutate the session.

### Confirmed Trash transaction

1. Capture immutable folder-session, committed URL, image-generation, and filesystem identity. Never reread the current selection to choose the target later.
2. Present native confirmation naming the file.
3. On cancel, end with no change.
4. On confirm, stop item-specific playback and speculative work.
5. Request permitted move to system Trash.
6. On success, remove from index.
7. Select next at the removed index, otherwise previous, otherwise empty state.
8. On failure, retain item and report.
9. If the folder session changes before execution, reject the stale action. If it changes while native Trash is committing, never reconcile the old result into the new session.

There is no permanent delete action.

## 20. Accessibility

- Every control exposes label, role, value, enabled state, and selection where applicable.
- Current image exposes filename, dimensions when known, and loading/error state.
- All actions have menu and keyboard access.
- Thumbnail focus order follows visual order.
- Dialog dismissal restores focus to the initiator or viewport.
- Rapid navigation announcements coalesce toward the settled image.
- Reduce Motion removes large spatial transitions.
- Increase Contrast and Differentiate Without Color preserve state meaning.
- Native controls and system typography are preferred.

## 21. Privacy, sandbox, and App Store compliance

Expected entitlements:

- App Sandbox.
- User-selected file read/write.

Not expected:

- Network client/server.
- Broad Pictures, Downloads, or all-files access as a workaround.
- Photos library, camera, microphone, contacts, location, or calendars.
- App-scoped or document-scoped security-scoped bookmark entitlements.

Policies:

- Access only selected file/folder scopes.
- Balance scope lifetime.
- No persistent image library or thumbnail database.
- No telemetry, tracking, analytics, uploads, or AI requests.
- No filenames, paths, bookmark data, or image metadata in production logs by default.
- Use public Apple APIs and declare only supported viewer document types.
- Recheck current Mac App Store rules before submission.

## 22. Local observability and diagnostics

Observability exists only for engineering, testing, and local troubleshooting. It is not analytics, cloud telemetry, user tracking, or a product data-collection feature.

Use Apple system facilities directly:

- `os.Logger` for structured local events.
- `OSSignposter` for interval and point signposts.
- XCTest/XCMetric and Instruments for repeatable measurements where available.
- Atomic or actor-isolated in-memory counters for cache, cancellation, stale-result, and failure totals.

Do not introduce an analytics SDK, logging framework, telemetry backend, upload service, generic observability abstraction, or third-party dependency.

### 22.1 Instrumentation ownership

Instrumentation is placed at the component that owns the measured operation. A small compile-time diagnostics namespace may define logger categories, signpost names, privacy helpers, and counter storage; it must not become a general event bus.

| Boundary | Logger category | Signposts and counters |
|---|---|---|
| Application lifecycle | `lifecycle` | process start, scene/window ready, cold/warm classification, termination |
| Finder-open handling | `open` | URL receipt point, open-to-window interval, open-to-first-pixels interval, replacement-session count |
| Authorization and sandbox | `authorization` | scope-start result, scope-stop point, parent-enumeration permission outcome, folder-panel presentation/outcome, same-session authorization reuse |
| Folder enumeration | `enumeration` | enumeration interval, first-batch latency, entry count, cancellation count, failure count |
| Natural sorting | `sorting` | sort interval, input count, completed/cancelled count |
| Navigation | `navigation` | input point, target-selected point, first-pixels interval, rapid-navigation count, cancellation count, stale-result rejection count |
| Image loading and decoding | `image` | property-read interval, preview decode interval, detail decode interval, pixel-cost class, decode success/failure count |
| Thumbnail generation | `thumbnail` | request-to-result interval, generation interval, cancellation count, placeholder/failure count |
| Image/thumbnail caches | `cache` | hit, miss, insert, eviction, current cost, cost limit, memory-pressure purge |
| Rendering | `rendering` | presentation-commit point, first rendered frame when measurable, viewport transition interval, dropped-frame investigation signposts |
| Trash operations | `trash` | confirmation result, Trash interval, success/failure category |

Interval identifiers must carry an opaque session/request correlation value, not a path or filename.

### 22.2 Required timing definitions

Metrics use one monotonic clock and documented start/end points:

| Metric | Start | End |
|---|---|---|
| Startup to window ready | earliest application entry | primary window can display a loading state |
| Startup to first pixels | earliest application entry | selected image is committed for rendering |
| Finder URL receipt | earliest application entry | open handler receives the URL |
| Open to first pixels | Finder URL receipt | selected image is committed for rendering |
| Folder enumeration | enumerator request accepted | final batch or terminal failure |
| First folder batch | enumerator request accepted | first nonempty batch emitted |
| Natural sorting | sort begins for a snapshot | ordered snapshot published |
| Image decode | decoder begins source operation | decoded presentation or typed failure returned |
| Image display latency | current target selected | matching presentation committed |
| Navigation latency | Previous/Next intent accepted | matching target presentation committed |
| Thumbnail latency | visible-range request accepted | matching thumbnail or placeholder published |
| Trash latency | confirmed operation begins | success or typed failure returned |

“First pixels” is a presentation-commit proxy unless the selected rendering technology provides a reliable first-frame callback. The chosen endpoint must remain stable across benchmark runs.

### 22.3 Counters and gauges

Required local counters:

- Image-preview cache hits and misses.
- Thumbnail cache hits and misses.
- Cache insertions and evictions.
- Cache cost and configured limit.
- Current and peak concurrent image decodes.
- Current and peak concurrent thumbnail operations.
- Current-image cancellations.
- Prefetch cancellations.
- Thumbnail cancellations.
- Folder-enumeration cancellations.
- Stale image results rejected.
- Stale thumbnail results rejected.
- Decode failures by non-sensitive category.
- Permission failures by operation category.
- Memory-pressure events by system level.
- Memory-pressure cache purges.

Counters reset at process launch unless a benchmark harness explicitly aggregates results. They are not persisted as user history.

### 22.4 Structured logging policy

Release-safe logging may include:

- Stable operation name.
- Success, cancellation, or typed failure category.
- Duration bucket or numeric duration.
- Entry count, pixel-count class, frame-count class, cache cost, and concurrency count.
- Opaque session/request correlation identifier.
- Public framework error domain and numeric code when it does not reveal private data.

Release logging must not include:

- Full paths or folder paths.
- Filenames or extensions tied to a user file.
- File contents or image bytes.
- EXIF values or arbitrary metadata.
- Security-scoped URL data or authorization tokens.
- Apple IDs, account identifiers, user names, device names, or other identifiers.
- User-generated labels or personally identifiable information.

Detailed paths are allowed only in an explicit Debug diagnostics mode, disabled by default, with a visible warning that private local file locations may appear in Console. Profiling, Benchmark, and Release use privacy-preserving values only.

Use `Logger` privacy interpolation deliberately. Dynamic strings derived from user files remain private; do not rely on default interpolation as the sole policy.

No log, signpost, counter, benchmark result, or diagnostics snapshot may leave the device automatically.

### 22.5 Build configurations

| Configuration | Logging | Signposts | Counters | Diagnostics overlay | Optimization/use |
|---|---|---|---|---|---|
| Debug | Detailed local logs; paths only after explicit diagnostics opt-in | All defined signposts | All counters | Available, off by default | Development and fault injection |
| Release | Minimal privacy-preserving fault and lifecycle logs | Low-overhead critical intervals and points | Bounded process-local counters needed for behavior; no UI | Excluded | Shipping build |
| Profiling | Release privacy rules with full signpost coverage | All performance intervals | All counters | Excluded | Instruments on release-like optimized code |
| Benchmark | Release privacy rules; deterministic summary output to local test artifacts | All benchmark intervals | Resettable counters | Excluded to avoid perturbation | Automated, optimized repeatable performance tests |

Debug-only code must not change authorization, scheduling, cache limits, or functional behavior unless a clearly labeled fault-injection switch is active.

### 22.6 Debug diagnostics overlay

An optional Debug-only overlay may show:

- Current opaque session/request IDs.
- Current state: loading, ready, failed, or file-only mode.
- Folder entry count and discovery completion state.
- Last open, enumeration, sort, decode, display, navigation, and thumbnail durations.
- Image and thumbnail cache hits, misses, cost, and evictions.
- Active decode/thumbnail counts.
- Cancellation and stale-result rejection totals.
- Last non-sensitive failure category, domain, and code.
- Memory-pressure event count.

The overlay:

- Is compiled out of Release.
- Is disabled by default.
- Never shows image contents beyond the normal viewer.
- Shows paths only under the explicit Debug path-logging opt-in.
- Reads existing counters and must not create a second source of truth.
- Must be visually marked “Engineering Diagnostics.”

### 22.7 Repeatable benchmark scenarios

Benchmark fixtures must be generated or sourced without personal images and versioned by a manifest containing dimensions, format, byte size, frame count where relevant, and expected result.

Required scenarios:

| Scenario | Required measurement |
|---|---|
| 100 images | startup, complete enumeration/sort, first image, sequential navigation, thumbnail window |
| 1,000 images | complete enumeration/sort, first-batch latency, index memory, thumbnail request bound |
| 10,000 images | complete enumeration/sort, UI responsiveness, index memory, thumbnail request bound |
| 100,000 directory entries | selected-image independence, first batch, progressive enumeration/sort, peak index memory, main-thread stalls |
| Rapid Previous/Next | input-to-display percentiles, cancellations, stale rejections, final-target correctness |
| Cancellation stress | current/prefetch/thumbnail/enumeration cancellations and leaked/late work |
| Large TIFF | property read, fit preview, detail decode, peak memory, resource-limit behavior |
| Animated GIF | startup, frame pacing, CPU, memory, pause/release behavior |
| Corrupt image | failure latency, error category, navigation recovery, memory cleanup |
| Memory pressure | eviction order, purge duration, surviving current presentation, post-pressure stability |
| Slow iCloud/File Provider | URL receipt, provider wait, cancellation, permission/provider failures, UI responsiveness |

Each benchmark records:

- Hardware model, memory, macOS version, build commit, configuration, thermal state when available, storage type, fixture manifest version, and sample count.
- Median, p95, minimum, maximum, and failure count for latency metrics.
- Settled and peak resident memory for memory scenarios.
- Counter deltas for cache, cancellation, stale-result, and failures.

Use a warm-up policy and fixed iteration count documented with the results. Do not mix Debug results with release gates.

### 22.8 Performance budgets and regression gates

Product budgets remain defined by `requirements.md`. Observability enforces them using optimized Benchmark or Profiling builds.

Initial gates:

- Window/loading response: p95 no greater than 150 ms.
- Uncached local 24 MP JPEG display: p95 no greater than 750 ms.
- Prefetched navigation: p95 no greater than 100 ms.
- Uncached navigation: acknowledgement within 100 ms and display p95 no greater than 750 ms.
- No application-caused main-thread stall over 100 ms; repeated stalls over 50 ms fail review.
- 10,000-entry complete navigability: p95 no greater than 2 seconds on the approved baseline.
- 100,000-entry scenario must not gate selected-image display or initiate eager image/thumbnail/EXIF work.
- Ten-minute navigation memory must stabilize; typical still-image settled memory uses the approved budget, initially 300 MB soft.
- Final-target correctness and stale-result prevention must have zero failures.
- Cache and thumbnail work must remain bounded by configured limits.

A change fails the regression gate when:

- It exceeds a hard product budget.
- It introduces correctness failures, unbounded growth, or main-thread blocking.
- Its median or p95 regresses more than 15% against the accepted baseline across two controlled runs without an approved explanation.
- Cache misses, cancellations, or failures change materially and the change cannot be explained by the fixture or intended behavior.

Benchmark baselines are updated only through reviewed local artifacts that identify the reason for change.

### 22.9 Authorization integration observability

The production authorization flow uses the same semantic measurement names across automated and manual integration scenarios:

- URL receipt.
- Security-scope start result.
- Selected-file read.
- Parent enumeration.
- Sibling read.
- Folder-panel result.
- Trash result.

Exact paths and full `NSError` details may appear only in explicit Debug path-logging mode with controlled fixtures. Production Release logging follows Section 22.4.

## 23. Testing strategy

### Unit tests

- Natural sorting.
- Filtering of hidden, nested, package, and unsupported entries.
- Stable selection through discovery updates.
- Navigation boundaries.
- Request-generation rejection.
- Viewport geometry and rotation.
- Post-Trash selection.
- Error mapping.
- Cache cost and eviction.

### Deterministic concurrency tests

- 20-command rapid navigation.
- Replacement Finder open during decode.
- Late decode after cancellation.
- Access loss during enumeration.
- Fast thumbnail scrolling.
- Memory pressure during GIF playback.
- Trash while prefetch is active.

Tests use controllable fakes, clocks, and continuations rather than arbitrary sleeps.

### Integration tests

- Signed sandbox integration matrix.
- Cold/warm Finder Open With.
- Folder fallback and scope lifetime.
- Supported formats and corrupt fixtures.
- Reveal and confirmed Trash.
- iCloud/File Provider pending/failure.
- External volume removal.
- Full screen, Dark Mode, and display scale.

### Accessibility/UI tests

- All shortcuts and menu enabled states.
- Keyboard-only thumbnail use and confirmation.
- VoiceOver labels, selection, status, and focus.
- Reduced Motion and Increase Contrast.
- Loading/error recovery.

### Performance tests

- Open and navigation latency.
- 100/1K/10K/100K enumeration and ordering.
- Main-thread stalls.
- Thumbnail request bounds.
- Typical and pathological image/GIF memory.
- Ten-minute navigation stability.
- Large TIFF, corrupt image, cancellation stress, and memory-pressure scenarios.
- Slow iCloud/File Provider access.
- Cache hit/miss, cancellation, stale-result, and failure counter assertions.
- Performance-budget and 15% regression-gate evaluation from Section 22.8.

Performance tests run in Benchmark configuration for gates and Profiling configuration for Instruments investigation. Debug results are diagnostic only.

## 24. Production readiness gates

### Integration acceptance gate — Sandbox and Finder access

The standalone spike gate is waived. This gate runs incrementally against production integration and must pass before MVP release:

- Finder Open With on cold launch and warm launch.
- Prompt selected-image display whenever the file is readable.
- Automatic parent enumeration and sibling read where the delivered scope permits.
- File-only mode and one non-blocking Allow Folder Access action when automatic access fails.
- `NSOpenPanel` appears only after explicit user action.
- Cancellation retains the image and does not repeat the prompt in the same image session.
- Authorized folder scope is reused within the application session.
- Previous/Next works after folder authorization.
- Trash behavior is tested under the granted scope when Stage 8 exists.
- Desktop, Downloads, Pictures, arbitrary folders, external volumes, and iCloud Drive are covered where available.
- Exact non-sensitive error domains/codes and authorization outcomes are represented in local instrumentation tests.
- No bookmark entitlement, bookmark data, or persistent folder authority exists.

### Gate 1 — Core correctness

- Finder open, selected-image display, authorized discovery, sorting, and previous/next work.
- Stale results cannot replace current selection.
- No main-thread I/O or decode.

### Gate 2 — Viewing and resource safety

- Static formats, GIF, viewport, thumbnails, and Trash pass acceptance tests.
- Memory and concurrency are bounded.
- Large and malformed files fail safely.

### Gate 3 — Product quality

- Accessibility suite passes.
- 100/1K/10K/100K performance targets pass.
- Ten-minute memory test stabilizes.
- Signed sandbox and File Provider scenarios pass.
- Benchmark artifacts contain required environment metadata and counter deltas.
- No hard budget, correctness, unbounded-growth, or unexplained greater-than-15% regression remains.

### Gate 4 — Release

- Entitlements and document declarations match behavior.
- No unintended writes or network requests.
- Current App Store checks pass.
- All MVP acceptance criteria pass on supported macOS versions.

## 25. Architecture decisions

### ADR-001 — One primary session

Reuse one viewer window and replace its active session for new Finder opens.

### ADR-002 — No persistent catalog

Keep folder navigation in memory. Enumerate per authorized session.

### ADR-003 — Independent selected-image loading

Load the selected image concurrently with folder authorization and discovery.

### ADR-004 — Explicit, non-repeating folder fallback

Attempt available parent access first. When it is unavailable, remain in file-only mode and offer one non-blocking `NSOpenPanel` folder-authorization action. Retain authorization and decline state only for the current application session.

### ADR-005 — Latest request wins

Use task cancellation plus session, item, and generation validation.

### ADR-006 — Apple decoders

Use maintained platform decoding and no third-party format library for MVP.

### ADR-007 — Bounded in-memory caches

Use cost-limited current, neighbor, GIF, and visible-thumbnail working sets.

### ADR-008 — Virtualized optional thumbnails

Hide the strip by default, remember visibility, and request only visible/nearby thumbnails.

### ADR-009 — Native full screen

Use the standard macOS full-screen mechanism.

### ADR-010 — Non-recursive natural-order session

Exclude hidden/nested items and use natural filename order rather than Finder view order.

### ADR-011 — Session-only view transforms

Never save zoom, pan, or rotation to image files.

### ADR-012 — Measured AppKit fallback

Adopt AppKit only for specific platform integration or viewport requirements that fail SwiftUI testing.

### ADR-013 — Apple-local observability only

Use `os.Logger`, `OSSignposter`, Apple profiling/test facilities, and bounded in-memory counters. No analytics SDK, network transport, persistent user-history store, or generic observability framework is permitted.

## 26. Removed or simplified architecture

This revision removes or simplifies:

- A distinct multiple-file selection/session path; deferred behavior is reduced to choosing the first supported URL.
- Persistent folder restoration and all security-scoped bookmark behavior.
- Broad alias, symbolic-link, and external-change reconciliation designs.
- Separate architecture for position/count while discovery is incomplete.
- Any implication of live folder observation.
- Generic extension points for media types or Post-MVP features.
- Package/module decomposition not justified by MVP.
- Detailed transition-animation machinery; only interruptibility and accessibility behavior remain.

## 27. Traceability

| Architecture area | Revised requirements |
|---|---|
| Lifecycle coordinator and viewing session | FR-001–004 |
| Folder access state machine | FR-005–006, FR-033, FR-035 |
| Enumeration and navigation index | FR-007–010, FR-013–016, FR-030 |
| Full-image and GIF pipeline | FR-011–012, FR-031–035 |
| Navigation cancellation/prefetch | FR-013–016 |
| Viewport | FR-004, FR-017–024 |
| Thumbnail pipeline | FR-025–026 |
| Native commands and appearance | FR-027, FR-036–038 |
| Finder actions | FR-028–030, FR-039 |
| Memory/workload policy | FR-012, FR-015, FR-026, FR-034; NFR-005–008 |
| Privacy and sandbox | FR-005–006, FR-039–040; PRIV-001–005 |
| Instrumentation and testing | PERF-001–008 |

## 28. Unresolved decisions

1. Final Rotate Left/Right shortcuts after command-conflict testing.
2. Final hard memory budgets after image and GIF benchmarks.
3. Final wording and placement of the approved folder-access fallback.
4. Whether SwiftUI alone meets viewport interaction and performance targets.

## 29. Implementation authorization

The product owner explicitly accepts the unresolved Finder/sandbox risk, cancels the standalone spike, approves the user-controlled folder-picker fallback, and authorizes production implementation.

Folder-access behavior is validated incrementally through the integration acceptance gate. This authorization does not broaden MVP scope or permit security-scoped bookmarks, persistent folder authority, broad filesystem entitlements, or automatic permission prompts.
