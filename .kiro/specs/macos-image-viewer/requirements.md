# macOS Image Viewer — Product Requirements

Status: Reconciled; production implementation authorized by product-owner risk acceptance  
Scope: MVP  
Platform: macOS 14 Sonoma and later  
Baseline: Apple Silicon Mac with 16 GB RAM  
Last updated: 2026-07-31

## 1. Product objective

Create a lightweight, native macOS image viewer that opens a Finder-selected image promptly and lets the user browse other supported images in the same folder.

The experience shall be as direct as Windows Photos while following macOS conventions. It shall prioritize fast navigation, predictable memory use, keyboard operation, photographer-friendly detail inspection, and graceful behavior in very large folders. It is a viewer, not an editor, library, or photo-management application.

## 2. Target users

- Everyday macOS users who want to open an image and browse neighboring files without importing a library.
- Photographers reviewing exported or processed folders with keyboard navigation and actual-size inspection.
- Keyboard-first users who expect complete menu and shortcut coverage.
- Users of VoiceOver, Reduced Motion, Increase Contrast, and keyboard accessibility.

## 3. MVP

The MVP includes:

- Open one image from Finder and reuse one primary viewer window.
- Discover supported images in the same authorized folder.
- Natural filename sorting.
- Previous and next navigation without wrapping.
- JPEG, PNG, HEIC/HEIF, GIF, and TIFF.
- Animated GIF playback.
- Fit, actual size, zoom, pan, and temporary rotation.
- Native full screen.
- Keyboard and trackpad interaction.
- Optional thumbnail strip, hidden by default with visibility remembered.
- Reveal in Finder.
- Confirmed Move to Trash.
- Dark Mode, accessibility, loading, empty, unsupported, and failure states.

## 4. User journeys

### UJ-001 — Open and browse

1. The user opens a supported image using Finder.
2. The application reuses its primary window and promptly displays the selected image or a truthful loading state.
3. The application attempts to obtain access to the containing folder.
4. When access is available, supported sibling images are discovered and naturally sorted.
5. Left Arrow and Right Arrow navigate without wrapping.
6. If folder access is unavailable, the selected image remains viewable and the user may authorize the folder.

### UJ-002 — Inspect detail

1. The image initially fits the viewport without upscaling.
2. The user pinches or invokes a command to zoom.
3. The user pans zoomed content with scrolling or dragging.
4. The user switches between fit and actual size.
5. Navigating to another image resets the viewport to fit.

### UJ-003 — Use thumbnails

1. The user shows the thumbnail strip.
2. Visible and nearby thumbnails load asynchronously.
3. The user selects a thumbnail to navigate.
4. The chosen visibility is remembered for later launches.

### UJ-004 — Rotate and view animation

1. The user temporarily rotates the current image in 90-degree increments.
2. Rotation is retained while that image remains part of the active session.
3. The source file is never modified.
4. An animated GIF plays while current and pauses when it is no longer current.

### UJ-005 — Use Finder actions

1. The user reveals the current image in Finder or invokes Move to Trash.
2. Move to Trash names the file and requires confirmation.
3. After success, the next sensible neighbor is shown.
4. Cancellation or failure leaves the current item unchanged.

## 5. Functional requirements

Each functional requirement has product-level acceptance criteria. Detailed fixture coverage appears in Section 15.

### Opening and lifecycle

#### FR-001 — Open a Finder-selected image

The application shall accept a supported image opened through Finder and make it the current image.

Acceptance criteria:

- **Given** a supported local image, **when** the user chooses Open With in Finder, **then** the application presents that image or a truthful loading state.
- **Given** an unsupported file, **when** it is sent to the application, **then** an unsupported-format state is shown without crashing.

Traceability: original FR-001, FR-002.

#### FR-002 — Reuse the primary viewer window

The application shall reuse one primary viewer window when another image is opened.

Acceptance criteria:

- **Given** the viewer is already open, **when** Finder opens another supported image, **then** the existing primary window becomes active and switches to that image.
- **Given** work from the previous session is still running, **then** it cannot later replace the newly opened image.

Traceability: original FR-003.

#### FR-003 — Prioritize the selected image

Loading the Finder-selected image shall not wait for complete folder authorization, enumeration, sorting, or thumbnail generation.

Acceptance criteria:

- **Given** a folder containing 100,000 entries, **when** one image is opened, **then** selected-image loading begins independently of folder discovery.
- **Given** parent-folder access is unavailable, **then** the selected image remains independently viewable when its own access permits.

Traceability: original FR-002, FR-006, FR-007.

#### FR-004 — Initial viewing mode

The selected image shall initially fit within the viewport without upscaling and with its aspect ratio preserved.

Acceptance criteria:

- **Given** an image larger than the viewport, **when** it first appears, **then** the whole image is visible.
- **Given** an image smaller than the viewport, **then** it is not enlarged above actual size.

Traceability: original FR-005, FR-022.

### Folder authorization, discovery, and ordering

#### FR-005 — Use only authorized file access

The application shall browse only files authorized through macOS user intent and sandbox mechanisms.

Acceptance criteria:

- **Given** only the selected file is accessible, **when** parent enumeration fails, **then** the viewer does not claim sibling access.
- **Given** an authorized folder, **then** discovery remains limited to that folder.

Traceability: original FR-006, FR-059; PRIV-002, PRIV-003.

#### FR-006 — Request folder access when necessary

If the selected-file grant does not permit sibling discovery, the application shall keep the image viewable and offer a system folder-selection fallback.

Acceptance criteria:

- **Given** parent enumeration is denied, **when** the image opens, **then** previous/next and thumbnails are unavailable and an Allow Folder Access action is offered.
- Automatic parent and sibling access is attempted before the action is shown; no permission dialog opens automatically.
- **When** the user authorizes the containing folder, **then** sibling discovery begins.
- The current image remains visible while authorization is unavailable or pending.
- **When** the user cancels, **then** the selected image remains viewable in single-image mode and the prompt is not shown again for that image session.
- The system folder picker opens only after an explicit user action and indicates the expected parent folder where platform APIs permit.
- A folder authorized during the current application session is not requested again during that session.

Traceability: original FR-048, FR-059, FR-064.

#### FR-007 — Discover supported sibling images

The application shall asynchronously discover supported regular image files in the authorized containing folder.

Acceptance criteria:

- **Given** an authorized folder, **when** discovery runs, **then** supported regular files are added to the navigation set without blocking the interface.
- Directories, packages, and unsupported formats are excluded.

Traceability: original FR-006, FR-007, FR-008.

#### FR-008 — Limit discovery to the current folder

Discovery shall be non-recursive and shall exclude hidden files.

Acceptance criteria:

- **Given** supported images in child folders, **when** the parent is discovered, **then** child-folder images are absent.
- **Given** a hidden supported image, **then** it is absent from the navigation set.

Traceability: original FR-061.

#### FR-009 — Sort by natural filename

Images shall be ordered by localized, case-insensitive, numeric-aware ascending filename order with deterministic handling of equal comparisons.

Acceptance criteria:

- **Given** `image1.jpg`, `Image2.png`, and `image10.heic`, **then** their order is `image1.jpg`, `Image2.png`, `image10.heic`.
- Exact Finder view ordering is not required.

Traceability: original FR-009.

#### FR-010 — Keep selection stable during discovery

Incremental discovery shall not unexpectedly change the current image.

Acceptance criteria:

- **Given** new entries are inserted before the current item in sorted order, **then** the same file remains current.
- The application shall not display duplicate navigation entries for the same discovered file.

Traceability: original FR-010, FR-013.

### Display and navigation

#### FR-011 — Display supported static formats

The application shall display JPEG, PNG, HEIC/HEIF still images, and the default image of TIFF files using platform-supported decoding.

Acceptance criteria:

- Valid representative fixtures for each format display successfully on macOS 14.
- PNG alpha and platform-supported orientation and color profiles are honored.
- Multi-page TIFF browsing is not required.

Traceability: original FR-015.

#### FR-012 — Play animated GIFs

The application shall display GIF files and play valid animated GIFs while they are current.

Acceptance criteria:

- **Given** a valid animated GIF, **when** it is current and visible, **then** it animates using safe frame timing.
- **When** another image becomes current, **then** playback pauses and releases discardable resources.
- A malformed or resource-excessive GIF fails or degrades safely without blocking navigation.

Traceability: original FR-016, FR-068.

#### FR-013 — Navigate with Previous and Next

Left Arrow and Right Arrow and equivalent menu commands shall navigate to the previous and next image in sorted order.

Acceptance criteria:

- **Given** a middle item, **when** Right Arrow is pressed, **then** the next item becomes current; Left Arrow returns to the prior item.
- Commands work while the viewing window is key unless a modal or focused control legitimately consumes them.

Traceability: original FR-017, FR-051.

#### FR-014 — Stop at folder boundaries

Navigation shall not wrap.

Acceptance criteria:

- **Given** the first item, **then** Previous is disabled and invoking it does not change the image.
- **Given** the last item, **then** Next is disabled and invoking it does not change the image.

Traceability: original FR-011, FR-012.

#### FR-015 — Make rapid navigation deterministic

When navigation outpaces loading, the most recently selected image shall remain authoritative and stale results shall not replace it.

Acceptance criteria:

- **Given** 20 rapid navigation commands with delayed loads, **then** the viewer settles on the final accepted target.
- Transition or loading work never prevents another navigation command from being accepted.

Traceability: original FR-018, FR-069.

#### FR-016 — Communicate current context

The viewer shall identify the current filename and expose reliable navigation availability.

Acceptance criteria:

- The window or accessible viewing context exposes the current filename.
- Position and total count are shown only when sufficiently reliable and do not delay image display.

Traceability: original FR-011, FR-021.

### Zoom, pan, rotation, and full screen

#### FR-017 — Fit image to window

The user shall be able to return to fit mode at any time.

Acceptance criteria:

- Fit preserves aspect ratio, accounts for temporary rotation, and does not upscale beyond actual size.
- Fit recenters the image and restores a valid pan position.

Traceability: original FR-022.

#### FR-018 — Show actual size

The user shall be able to view one source pixel per backing pixel on the active display when resource limits permit.

Acceptance criteria:

- **When** Actual Size is invoked, **then** the zoom reflects the current display backing scale.
- Moving the window to a display with a different scale preserves actual-size semantics.

Traceability: original FR-023, FR-072.

#### FR-019 — Zoom predictably

The application shall provide bounded stepped keyboard zoom and continuous pinch zoom.

Acceptance criteria:

- Command-Plus/Equals and Command-Minus change zoom in bounded steps.
- Pinch changes zoom continuously around the gesture centroid where practical.
- Keyboard zoom preserves the viewport center.
- Reaching a zoom limit does not produce an error.

Traceability: original FR-024, FR-025, FR-026.

#### FR-020 — Pan zoomed content

The user shall be able to pan content that exceeds the viewport using pointer drag, mouse wheel, or two-finger scrolling.

Acceptance criteria:

- Scrolling pans only when the image has overflow.
- Mouse-wheel and vertical scrolling do not zoom or navigate by default.
- Pan constraints prevent the image from becoming permanently lost outside the viewport.

Traceability: original FR-027, FR-054.

#### FR-021 — Navigate with a horizontal trackpad gesture

A deliberate horizontal swipe shall navigate one image only while the current image is at fit scale.

Acceptance criteria:

- **Given** fit mode and an available neighbor, **when** the swipe crosses the navigation threshold, **then** one navigation occurs.
- **Given** a zoomed image, **then** horizontal scrolling pans and never navigates.
- Reduce Motion replaces large spatial movement with a restrained transition.

Traceability: original FR-054, FR-055.

#### FR-022 — Reset view on navigation

Navigating to another image shall reset the viewport to fit.

Acceptance criteria:

- **Given** custom zoom and pan, **when** another image becomes current, **then** that image starts in fit mode.
- Returning to the previous image does not restore its prior zoom or pan.

Traceability: original FR-028.

#### FR-023 — Rotate for the active session

The application shall rotate the displayed image left or right in 90-degree increments, retain that rotation per image for the active session, and never save it.

Acceptance criteria:

- Rotation updates display and fit geometry.
- Navigating away and back during the same session restores that image’s temporary rotation.
- File bytes, metadata, and modification date remain unchanged.
- Reopening in a new application session does not require restoration.

Traceability: original FR-029, FR-030, FR-031.

#### FR-024 — Use native macOS full screen

The viewer shall enter and exit native macOS full screen while preserving the current session.

Acceptance criteria:

- Control-Command-F toggles native full screen.
- Current image, navigation position, temporary rotation, and thumbnail visibility remain intact.

Traceability: original FR-039.

### Thumbnail strip and native controls

#### FR-025 — Provide an optional thumbnail strip

The application shall provide a thumbnail strip that is hidden by default, toggleable, and remembers its visibility as an application preference.

Acceptance criteria:

- A menu command shows and hides the strip.
- Relaunching restores the last chosen visibility.
- Selecting a thumbnail makes that image current and visibly selected.

Traceability: original FR-032, FR-033, FR-034.

#### FR-026 — Load thumbnails on demand

Thumbnail generation shall be asynchronous, failure-isolated, and limited to visible and nearby items.

Acceptance criteria:

- Opening a folder does not generate every thumbnail upfront.
- Scrolling a 10,000-item strip requests only the visible range and a bounded prefetch margin.
- A failed thumbnail shows a placeholder and does not block primary navigation.

Traceability: original FR-035, FR-036.

#### FR-027 — Provide native commands and appearance

Core actions shall be available through native macOS menus and controls, with Dark Mode support and no appearance-based alteration of image pixels.

Acceptance criteria:

- Menu items show their shortcuts and disabled states.
- Chrome updates when system appearance changes.
- Image pixel values are not tinted for Dark Mode.

Traceability: original FR-037, FR-038, FR-040, FR-041.

### Finder actions

#### FR-028 — Reveal the current image in Finder

The application shall reveal and select the current file in Finder when it still exists.

Acceptance criteria:

- **Given** an accessible current file, **when** Reveal in Finder is invoked, **then** Finder selects that exact file.
- A missing file produces a non-destructive error.

Traceability: original FR-042.

#### FR-029 — Confirm Move to Trash

The application shall require confirmation before moving the current file to the system Trash.

Acceptance criteria:

- The confirmation names the file and explains that it will move to Trash.
- Cancelling retains the file and current selection.
- The application never permanently deletes the file.

Traceability: original FR-043, FR-044, FR-046.

#### FR-030 — Continue after Trash

After a successful move to Trash, the viewer shall remove the item from navigation and select the next item at the same index, otherwise the previous item, otherwise show an empty state.

Acceptance criteria:

- Navigation state changes only after confirmed Trash success.
- Failure retains the item and reports that the move did not complete.
- Trashing the final image produces a stable empty state.

Traceability: original FR-045, FR-046, FR-071.

### Loading, errors, and resilience

#### FR-031 — Show truthful loading states

The application shall immediately show non-blocking, indeterminate progress when the current item cannot be displayed promptly and duration is unknown.

Acceptance criteria:

- Loading never prevents closing or navigating to a known neighbor.
- Fabricated progress percentages are not shown.

Traceability: original FR-019, FR-049.

#### FR-032 — Isolate unsupported and decode failures

Unsupported, corrupt, deceptive-extension, zero-byte, and undecodable files shall fail as individual items without invalidating the session.

Acceptance criteria:

- The error names the file when appropriate and distinguishes unsupported from unreadable when known.
- Previous/next remains available when known neighbors exist.
- No failure produces an indefinite spinner or process crash.

Traceability: original FR-020, FR-047, FR-050, FR-065, FR-066.

#### FR-033 — Handle missing files and permission loss

If a known item becomes unavailable or permission is lost, the application shall remain usable and offer recovery when appropriate.

Acceptance criteria:

- A confirmed missing item is removed or skipped without breaking later navigation.
- Permission failure does not claim the file is corrupt.
- Folder reauthorization is offered only when it can restore the intended workflow.

Traceability: original FR-063, FR-064.

#### FR-034 — Handle large images safely

The application shall attempt a resource-appropriate presentation of very large images and show a resource-limit state when safe display is not possible.

Acceptance criteria:

- Fit presentation does not require an unbounded full-resolution decode.
- Failure to provide actual size does not terminate the app or prevent navigation.

Traceability: original FR-067.

#### FR-035 — Handle File Provider delays

The viewer shall remain responsive while macOS materializes an authorized iCloud Drive or File Provider item.

Acceptance criteria:

- Delayed items show a truthful loading state.
- Closing or navigating cancels or detaches obsolete presentation work.
- Provider failure is reported without being described as an unsupported format.

Traceability: original FR-062.

### Accessibility and safety

#### FR-036 — Support complete keyboard operation

Every MVP action shall be available through the keyboard and native menus.

Acceptance criteria:

- Opening, navigation, zoom, fit, actual size, rotation, thumbnail selection, full screen, Reveal, Trash confirmation, and dialog dismissal can be completed without a pointer.
- Gestures always have a keyboard or command alternative.

Traceability: original FR-038, FR-051, FR-053, FR-056; A11Y-003.

#### FR-037 — Support VoiceOver and focus

Interactive controls and important image states shall expose meaningful accessibility labels, roles, values, selection, enabled state, and logical focus behavior.

Acceptance criteria:

- The current image exposes filename, dimensions when known, and loading/error status.
- Thumbnail selection and command availability are announced.
- Dialog dismissal restores focus sensibly.

Traceability: A11Y-001, A11Y-002, A11Y-004, A11Y-008.

#### FR-038 — Honor accessibility appearance settings

The interface shall honor Reduce Motion, Increase Contrast, and Differentiate Without Color.

Acceptance criteria:

- Reduce Motion removes or replaces large spatial transitions.
- Selection, focus, disabled state, and errors remain understandable without color alone.

Traceability: A11Y-005, A11Y-006, A11Y-007.

#### FR-039 — Preserve viewed files

Except for a confirmed Move to Trash command, viewing actions shall not modify, rename, relocate, or write metadata to source images.

Acceptance criteria:

- Browsing, zooming, panning, rotation, GIF playback, thumbnails, and full screen leave file bytes and metadata unchanged.
- No private image library copy is created.

Traceability: original FR-030; NFR-012; PRIV-005.

#### FR-040 — Operate offline and privately

All MVP viewing behavior shall work without a network connection and shall perform no analytics, tracking, upload, AI analysis, or remote-content request.

Acceptance criteria:

- Core acceptance tests pass offline.
- A release build makes no application-originated network request during normal viewing.
- The application does not collect or transmit image content or metadata.

Traceability: PRIV-004, PRIV-005, STORE-006.

## 6. Supported formats

| Format | Extensions | MVP behavior |
|---|---|---|
| JPEG | `.jpg`, `.jpeg`, `.jpe` | Static display |
| PNG | `.png` | Static display with alpha |
| HEIC/HEIF still image | `.heic`, `.heif` | Static display supported by macOS 14 |
| GIF | `.gif` | Static or animated display |
| TIFF | `.tif`, `.tiff` | Default/representative image |

Extension matching is case-insensitive. Platform type identification and successful decoding are authoritative.

## 7. Unsupported formats

- Camera RAW, including DNG and manufacturer formats.
- Video and Live Photos.
- PDF, SVG, EPS, PSD, XCF, and general documents.
- AVIF, WebP, JPEG XL, and formats not listed in Section 6.
- Multi-page TIFF browsing.
- Items macOS cannot make readable under granted access.

## 8. Keyboard and pointer interactions

| Action | Input |
|---|---|
| Previous image | Left Arrow |
| Next image | Right Arrow |
| Zoom in | Command-Plus / Command-Equals |
| Zoom out | Command-Minus |
| Actual size | Command-0 |
| Fit to window | Command-9 |
| Rotate left | Command-L, pending shortcut validation |
| Rotate right | Command-R, pending shortcut validation |
| Toggle thumbnails | Option-Command-T |
| Reveal in Finder | Option-Command-R |
| Move to Trash | Command-Delete |
| Toggle full screen | Control-Command-F |
| Close window | Command-W |

| Pointer/trackpad input | Behavior |
|---|---|
| Pinch | Continuous zoom |
| Mouse wheel / two-finger scroll while zoomed | Pan |
| Mouse wheel / vertical scroll at fit | No image navigation or zoom |
| Horizontal swipe at fit | Previous/next after threshold |
| Horizontal scroll while zoomed | Pan only |
| Pointer drag while zoomed | Pan |

Double-click behavior is deferred until interaction testing demonstrates a clear need.

## 9. Non-functional requirements

#### NFR-001 — Native platform

The product shall target macOS 14 Sonoma and later using Swift and SwiftUI, with narrowly scoped AppKit integration only where SwiftUI is insufficient.

#### NFR-002 — Structured concurrency

Asynchronous work shall use Swift Concurrency, bounded parallelism, cancellation, and stale-result validation.

#### NFR-003 — Main-thread responsiveness

Filesystem enumeration, file access, type inspection, image decoding, thumbnail generation, and File Provider waits shall not block the main actor.

#### NFR-004 — Minimal dependencies

Apple frameworks shall be preferred. Any third-party dependency requires explicit approval, license review, privacy review, and maintenance justification.

#### NFR-005 — Predictable memory

Decoded images, GIF frames, thumbnails, and prefetch work shall have explicit cost limits and shall respond to memory pressure.

#### NFR-006 — Large-folder readiness

The selected image shall remain promptly usable while discovery proceeds in folders containing up to 100,000 entries. MVP does not promise complete instant indexing.

#### NFR-007 — Reliability

One failed or malicious file shall not terminate the application, corrupt another file, or invalidate the browsing session.

#### NFR-008 — Smooth, interruptible interaction

Direct manipulation and transitions shall target the display refresh rate, remain interruptible, and never gate command completion.

#### NFR-009 — Localization readiness

User-facing text shall be externalizable and layouts shall tolerate longer localized strings.

#### NFR-010 — No speculative infrastructure

The MVP shall not contain a database, persistent image index, plug-in system, cloud layer, generic media framework, or abstraction built solely for deferred features.

## 10. Performance requirements

Measure release builds on an Apple Silicon Mac with 16 GB RAM, local internal SSD fixtures, and macOS 14 or a later supported release.

#### PERF-001 — Open responsiveness

The primary window or a truthful loading state shall respond within 150 ms of an open request at the 95th percentile.

#### PERF-002 — Typical first image

A valid local 24-megapixel JPEG shall display within 750 ms at the 95th percentile when uncached.

#### PERF-003 — Navigation

Prefetched-neighbor navigation shall update visual content within 100 ms at the 95th percentile. Uncached navigation shall acknowledge input within 100 ms and display content within 750 ms at the 95th percentile.

#### PERF-004 — Main-thread stalls

Normal opening, discovery, navigation, and thumbnail use shall produce no application-caused main-thread stall longer than 100 ms. Repeated stalls longer than 50 ms are defects.

#### PERF-005 — Folder scale

- 1,000 entries: complete discovery and ordering should be effectively immediate on baseline local storage.
- 10,000 entries: complete navigability target is 2 seconds at the 95th percentile.
- 100,000 entries: selected-image presentation and UI interaction shall not wait for complete discovery; no universal completion deadline is imposed.

#### PERF-006 — Bounded work

The application shall not decode every image, generate every thumbnail, load full EXIF metadata, or retain unlimited decoded images.

#### PERF-007 — Memory stability

Typical 24-megapixel still-image browsing has an initial soft resident-memory target of 300 MB after settling. A 10-minute navigation stress test shall stabilize rather than grow with every visited image.

#### PERF-008 — Rapid-navigation correctness

After a burst of 20 accepted navigation commands, the final requested item shall remain current and no stale completion shall replace it.

## 11. Privacy, sandbox, and App Store requirements

#### PRIV-001 — App Sandbox

The application shall enable App Sandbox and use only entitlements justified by shipped behavior.

#### PRIV-002 — User-selected access

File and folder access shall originate from Finder/open events or a system selection panel. Broad Pictures, Downloads, or all-files access shall not be used as a sibling-browsing workaround.

#### PRIV-003 — Security scopes

Security-scoped access shall be held only while needed and balanced correctly. Folder authorization is in-memory and same-session only. MVP shall not create, store, resolve, restore, or refresh security-scoped bookmarks.

#### PRIV-004 — App Store compatibility

The app shall use public Apple APIs, accurate viewer document declarations, supported entitlements, compatible assets and dependencies, and current App Store privacy disclosures.

#### PRIV-005 — Untrusted input

Image files and metadata shall be treated as untrusted input. Platform decoders, allocation limits, and failure isolation shall be used.

## 12. Explicit non-goals

The MVP does not include:

- Multiple-file Finder selection sessions.
- Multiple independent viewer windows.
- Editing or saving image modifications.
- RAW processing.
- Video or Live Photos.
- Duplicate detection.
- Batch rename or batch file actions.
- Cloud synchronization.
- AI image analysis.
- Advanced EXIF panels or upfront full EXIF loading.
- Folder monitoring or automatic live reconciliation.
- Slideshow.
- Favorites, albums, ratings, or cataloging.
- Recursive subfolder browsing.
- Hidden-file browsing.
- Exact Finder view ordering.
- Navigation wrapping.
- Persistent folder or image index.
- Persistent zoom, pan, or rotation across launches.
- Double-click-specific behavior.
- A plug-in system.

## 13. Assumptions requiring validation

- Finder Open With grants access to the selected file.
- Parent-folder enumeration and sibling reads may or may not be included in that grant; this is not treated as confirmed.
- Explicit folder selection through `NSOpenPanel` can provide the required folder scope.
- User-selected read/write access can support Move to Trash for authorized local items, subject to filesystem and provider behavior.
- Apple image frameworks can meet the supported-format and memory targets on the baseline Mac.

## 14. Technical risks

| Severity | Risk | Required validation |
|---|---|---|
| Accepted Critical | Finder single-file sandbox access may not permit parent enumeration | Product owner accepted the uncertainty; validate incrementally through the approved non-blocking folder-picker fallback and integration gate |
| High | Complete natural ordering can lag in 100,000-entry folders | Enumeration/sort benchmark |
| High | Very large images and GIFs can exceed memory | Decode and memory spike with hostile fixtures |
| High | Late decode results can replace newer navigation | Deterministic cancellation stress tests |
| High | Thumbnail virtualization can accidentally create unbounded work | Request-count and memory instrumentation |
| Medium | Trackpad pan/navigation arbitration may feel unreliable | Viewport interaction prototype |
| Medium | File Provider materialization and mutation differ from local storage | Provider scenario matrix |
| Medium | SwiftUI viewport behavior may need AppKit | Measured SwiftUI/AppKit spike |
| Low | Native full screen, appearance, menus, and Reveal in Finder | Integration tests |

## 15. End-to-end acceptance criteria

### AC-001 — Finder open

**Given** the application is not running and Finder contains a valid JPEG  
**When** the user chooses Open With  
**Then** the primary window or loading state responds within 150 ms  
**And** the selected image loads independently of folder discovery.

### AC-002 — Natural sibling navigation

**Given** an authorized folder contains `image1.jpg`, `Image2.png`, `image10.heic`, a hidden image, a text file, and a supported image in a child folder  
**When** discovery completes  
**Then** only the three visible immediate-folder images are navigable  
**And** their order is `image1.jpg`, `Image2.png`, `image10.heic`.

### AC-003 — Folder fallback

**Given** the selected file is readable but parent enumeration is denied  
**When** the image opens  
**Then** the image remains viewable  
**And** sibling navigation is unavailable  
**And** the user can authorize the containing folder through a system panel.

### AC-004 — Rapid navigation

**Given** delayed image loads  
**When** 20 navigation commands are accepted rapidly  
**Then** the final target remains current  
**And** no stale load later replaces it.

### AC-005 — Supported formats

**Given** valid representative JPEG, PNG, HEIC, GIF, and TIFF fixtures  
**When** each is opened  
**Then** each displays  
**And** PNG alpha is preserved  
**And** animated GIF playback runs only while the GIF is current.

### AC-006 — Failure isolation

**Given** a folder contains valid neighbors around a corrupt or unsupported item  
**When** the bad item becomes current  
**Then** an actionable state is shown  
**And** navigation remains functional  
**And** the application does not crash or spin indefinitely.

### AC-007 — Viewport behavior

**Given** an image is current  
**When** the user invokes fit, actual size, zoom, pan, and rotation  
**Then** each view operation behaves according to FR-017 through FR-023  
**And** the source file remains unchanged.

### AC-008 — Gesture arbitration

**Given** an image is at fit scale  
**When** a deliberate horizontal swipe crosses the threshold  
**Then** one navigation occurs  
**But given** a zoomed image  
**When** horizontal scrolling occurs  
**Then** the image pans and navigation does not occur.

### AC-009 — Bounded thumbnails

**Given** a 10,000-image folder  
**When** the thumbnail strip is shown and scrolled  
**Then** only visible and nearby thumbnails are requested  
**And** primary navigation remains responsive.

### AC-010 — Confirmed Trash

**Given** a current writable file  
**When** the user invokes Move to Trash  
**Then** confirmation names the file  
**And** cancellation changes nothing  
**And** confirmed success selects the next item, otherwise previous, otherwise empty state.

### AC-011 — Accessibility

**Given** VoiceOver, keyboard-only input, Reduce Motion, or Increase Contrast  
**When** the user completes the MVP journeys  
**Then** actions, states, selection, focus, and feedback remain operable and understandable.

### AC-012 — Large-folder responsiveness

**Given** a folder containing 100,000 mixed entries  
**When** one supported image is opened  
**Then** selected-image loading does not wait for full discovery  
**And** no image, thumbnail, or full EXIF data is loaded for every entry  
**And** no application-caused main-thread stall exceeds 100 ms.

### AC-013 — Memory stability

**Given** representative 24-megapixel images  
**When** navigation runs continuously for 10 minutes  
**Then** resident memory converges toward the approved budget  
**And** does not grow in proportion to images visited.

### AC-014 — Offline privacy and integrity

**Given** the Mac is offline  
**When** the user browses, zooms, rotates, uses thumbnails, and enters full screen  
**Then** all core actions work  
**And** the application makes no network request  
**And** source files remain unchanged.

## 16. Decisions resolved in this revision

- Minimum deployment target: macOS 14 Sonoma.
- Baseline: Apple Silicon Mac with 16 GB RAM.
- One reusable primary viewer window.
- Natural filename sorting; exact Finder ordering is not required.
- Hidden files and subfolders excluded.
- Left/Right Arrow navigation with non-wrapping boundaries.
- Thumbnail strip hidden by default, toggleable, and visibility remembered.
- Fit without upscaling; navigation resets to fit.
- Continuous pinch zoom.
- Scrolling pans only while zoomed and never zooms or navigates by default.
- Horizontal swipe navigation only at fit scale.
- Session-only, non-destructive rotation.
- Animated GIF playback, paused when not current.
- Native macOS full screen.
- Move to Trash confirmation.
- Multiple-file Finder behavior deferred.

## 17. Remaining decisions

1. Confirm or replace the provisional Rotate Left and Rotate Right shortcuts after menu-conflict testing.
2. Set final hard memory budgets after the image/GIF benchmark; 300 MB remains a soft typical-still target.
3. Finalize exact wording and placement of the approved Allow Folder Access action during Stage 2 integration work.

## 18. Product-owner risk acceptance and integration gate

The standalone sandbox spike was waived and cancelled by product-owner decision.

The product owner accepts that a Finder-provided single-file grant may not permit parent enumeration or sibling reads. Production implementation is authorized with this required behavior:

1. Display the selected readable image immediately.
2. Attempt parent enumeration and sibling access without presenting a permission dialog.
3. If access succeeds, begin the folder session without asking.
4. If access fails, retain the image and show one non-blocking Allow Folder Access action.
5. Open the system folder picker only after explicit user action.
6. Continue the current session after authorization without unnecessarily reopening the image.
7. After cancellation, remain a single-image viewer and do not prompt again for that image session unless the user manually invokes folder browsing.
8. Keep authorized folder scope only in memory for the current application session.
9. Create no security-scoped bookmark or persistent folder authorization.

Folder access is validated incrementally during implementation through an integration acceptance gate covering:

- Finder Open With.
- Cold and warm launch.
- Selected-image display.
- Automatic sibling discovery where permitted.
- Explicit folder-access fallback where automatic access fails.
- User cancellation and absence of repeated requests.
- Previous/Next after authorization.
- Trash under the granted access scope.
- Desktop, Downloads, Pictures, arbitrary folders, external volumes, and iCloud Drive where available.
