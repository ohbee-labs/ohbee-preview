# Ohbee Preview

Ohbee Preview is a lightweight, native macOS image viewer focused on fast
folder browsing, keyboard-first navigation, and predictable image inspection.

Release **v1.0.2** is the current stable MVP baseline. It preserves the v1.0.1
icon improvement and fixes Fit-to-Window centering after image navigation.
The current development branch additionally contains Milestone 3 visual folder
browsing; its local-folder GUI, keyboard, VoiceOver, Dark Mode, memory-smoke,
and engineering gates pass, but it has not been published as a numbered release.
It also contains Milestone 4 animated GIF viewing with bounded frame memory and
cancellable playback; this work has not been published as a numbered release.
Milestone 5 adds confirmed, immutable-target Finder Reveal and Move to Trash
actions; it is likewise not yet a numbered release.
Milestone 6 completes the keyboard command surface, predictable viewer/sidebar
focus, concise VoiceOver semantics, stable UI-test identifiers, and native
appearance accessibility; it is not yet a numbered release.

## Highlights

- Native macOS application built with Swift, SwiftUI, and focused AppKit integration
- Open supported images from Finder using Open or Open With
- Discover sibling images in the selected file's folder
- Natural filename sorting with non-wrapping Previous and Next navigation
- Optional, resizable thumbnail sidebar with progressive on-demand loading
- Animated GIF playback while the GIF is current and the app is active
- Reveal the committed image in Finder and move it to Trash after confirmation
- Fit to Window and Actual Size viewing modes
- Bounded zoom, trackpad pinch, scrolling, and pointer panning
- Non-destructive, session-only left and right rotation
- Native macOS fullscreen
- Keyboard-accessible navigation and inspection commands
- Keyboard-only Open, folder authorization, thumbnail browsing, Finder actions,
  confirmation, and error recovery
- VoiceOver labels, position/selection state, concise state announcements, and
  stable privacy-safe accessibility identifiers
- Semantic Light/Dark appearance with Reduce Motion-aware sidebar scrolling
- App Sandbox support with contextual folder authorization
- Local-only diagnostics using Apple system logging and signposts
- No analytics, telemetry, cloud services, or third-party dependencies

## Screenshots

Screenshots are being prepared for a future documentation update.

## Project Goals

Ohbee Preview aims to provide the speed and simplicity expected from a focused
image viewer while behaving like a native Mac application. The project favors:

- fast startup and immediate access to the selected image;
- minimal, discoverable UI;
- native keyboard, trackpad, window, and fullscreen behavior;
- predictable CPU and memory use;
- concrete implementations instead of unnecessary abstractions;
- measurement-driven performance work; and
- private, entirely local image processing.

## Architecture Overview

The application has a small set of focused components:

- **Application lifecycle** receives Finder open requests and routes the latest
  supported image to the active viewer.
- **Viewer state** owns the current image session, navigation, authorization,
  loading state, and inspection commands.
- **Core model** provides folder discovery, natural ordering, request identity,
  and deterministic viewport geometry.
- **Image pipeline** performs file access and ImageIO decoding away from the
  main actor.
- **Native viewport** integrates `NSScrollView` with SwiftUI for magnification,
  panning, centering, rotation, and keyboard navigation.
- **Thumbnail subsystem** independently owns ImageIO thumbnail generation,
  visible/nearby-row cancellation, bounded scheduling, and a byte-cost memory
  cache. Off-screen rows release their image so they cannot bypass that bound.
- **Animated GIF subsystem** classifies only the selected GIF, schedules one
  frame decode at a time, and keeps at most eight frames / 64 MiB of decoded
  frame data independently from thumbnails. Navigation and app inactivity stop
  playback; returning restarts from frame zero.
- **Finder-action subsystem** captures an immutable committed-image identity,
  presents native confirmation, and uses macOS Reveal/Trash APIs. Successful
  Trash selects next, then previous, or shows an empty-folder state; navigation
  while confirmation is open cannot retarget the action.
- **Diagnostics** uses privacy-preserving `os.Logger` and signposts locally.
- **Accessibility metadata** keeps stable identifiers and the reviewed shortcut
  map near the UI, while a small local announcement coordinator suppresses
  duplicate announcements without owning feature logic.

Additional design and product specifications are available in
[`.kiro/specs/macos-image-viewer`](.kiro/specs/macos-image-viewer/).

Milestone 3 slow iCloud materialization, third-party File Provider behavior,
and slow external-volume behavior remain unverified environment-specific
limitations. They do not affect the verified local-folder workflow.

Milestone 4 visual checks with real transparent/disposal-heavy, large, and
high-frame-count GIFs, plus multi-minute CPU/RSS observation, remain manual
release limitations. APNG, animated WebP, video, and Live Photos are unsupported.

## Supported Image Formats

| Format | Extensions |
|---|---|
| JPEG | `.jpg`, `.jpeg`, `.jpe` |
| PNG | `.png` |
| HEIC / HEIF | `.heic`, `.heif` |
| GIF | `.gif` (animated on the current development branch; first-frame-only in v1.0.2) |
| TIFF | `.tif`, `.tiff` |

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Open image | Command-O |
| Previous image | Left Arrow |
| Next image | Right Arrow |
| Toggle thumbnails | Option-Command-T |
| Reveal in Finder | Shift-Command-R |
| Move to Trash | Command-Delete |
| Fit to Window | Command-9 |
| Actual Size | Command-0 |
| Zoom In | Command-Equals / Command-Plus |
| Zoom Out | Command-Minus |
| Rotate Left | Command-L |
| Rotate Right | Command-R |
| Toggle Fullscreen | Control-Command-F |

Tab and Shift-Tab use the native macOS focus order. Opening the thumbnail
sidebar places keyboard focus in its list; Up/Down changes the selected image,
and hiding the sidebar restores focus to the main viewport. Native alerts and
panels retain their standard Return, Escape, and Tab behavior. The Trash alert
defaults Return to the safe Cancel action.

## Accessibility

Ohbee Preview supports keyboard-only primary workflows and exposes the current
filename, folder position, loading/error/empty state, thumbnail selection, and
control purpose to VoiceOver. Animated GIF frames and progressive thumbnail
arrivals are intentionally not announced. Full paths, internal generations,
cache details, and decode details are never exposed through accessibility
metadata.

The interface uses semantic macOS colors in Light and Dark Mode. Selected
thumbnails use both a selected trait and a visible outline, rather than color
alone. With Reduce Motion enabled, programmatic thumbnail scrolling avoids
custom animation; user-selected animated GIF content continues to play.

Automated metadata, command, focus-intent, and regression checks are included.
A real signed-app keyboard, VoiceOver, Increase Contrast, Differentiate Without
Color, Reduce Motion, small-window, and fullscreen matrix remains a manual
release validation and is not represented as accessibility certification.

## Installation

### Requirements

- macOS 14 or later
- Xcode 16 or a compatible Swift 6 toolchain
- Apple Silicon or Intel Mac supported by the selected macOS SDK

### Build from source

```sh
git clone git@github.com:ohbee-labs/ohbee-preview.git
cd ohbee-preview/OhbeePreview
./build.sh
```

The Debug application is produced at:

```text
OhbeePreview/.build-stage2/Debug/Ohbee Preview.app
```

For an optimized build:

```sh
BUILD_CONFIGURATION=Release ./build.sh
```

Copy the resulting application to `/Applications` if desired. The build script
uses ad-hoc signing for local development; distribution requires an appropriate
Apple signing identity and release workflow.

To make Ohbee Preview the default for a format, select an image in Finder,
choose **File > Get Info**, select **Ohbee Preview** under **Open with**, and
choose **Change All**. macOS may store this choice separately for each format.

## Development

```text
OhbeePreview/
├── Resources/                  App metadata, sandbox entitlements, and icons
├── Sources/OhbeePreview/       SwiftUI application and AppKit integration
├── Sources/OhbeeStage2Core/    Navigation and viewport domain logic
├── Tests/                      Unit, integration, and native viewport tests
├── build.sh                    Local application-bundle build
└── test.sh                     Test entry point

.kiro/specs/macos-image-viewer/ Product requirements, design, and delivery plan
```

Production changes should preserve the narrow dependency direction from the UI
and application layer toward the core model. New infrastructure should be added
only when an authorized user-facing capability requires it.

## Testing

Run the complete test entry point from the application directory:

```sh
cd OhbeePreview
./test.sh
```

The suite covers:

- unit tests for navigation state, natural sorting, and viewport geometry;
- integration tests for image loading, folder discovery, cancellation,
  stale-result rejection, and source-file integrity;
- native AppKit viewport tests for magnification, rotation, centering, resize,
  and image replacement;
- thumbnail tests for ImageIO orientation, deduplication, priority, cancellation,
  stale-session rejection, cache eviction, memory pressure, and 10K request
  bounds; and
- deterministic Launch Services document-type checks.

When Xcode provides `xctest`, the project uses SwiftPM/XCTest. The test script
also supports a Command Line Tools environment through equivalent CLI suites.

## Performance Philosophy

Ohbee Preview prioritizes the selected image and keeps file access, folder
enumeration, sorting, image decoding, and thumbnail generation off the main
actor. Rendering uses native Apple frameworks. Full-image loading remains
independent from the thumbnail subsystem. Thumbnails use a concurrency-limited
ImageIO pipeline and a 64 MiB byte-cost memory cache; there is no disk cache or
background folder indexing. Further optimization is driven by measured
user-visible bottlenecks.

## Privacy

Images are processed locally. Ohbee Preview includes no analytics SDK, user
tracking, cloud synchronization, or network telemetry. Engineering diagnostics
remain on the device and avoid paths, filenames, image contents, EXIF values,
and personal identifiers in Release builds.

## Sandbox Behavior

Ohbee Preview runs with App Sandbox enabled. Opening a file through Finder does
not always grant access to other files in its parent folder. If automatic sibling
discovery is unavailable, the app presents a secondary **Allow Access** action
after the selected image is displayed.

Folder authorization is retained only for the current application session.
Persistent authorization and security-scoped bookmarks are intentionally out of
scope for v1.0.2. Cancelling the folder picker leaves single-image viewing
available and does not trigger an automatic repeat prompt.

## Roadmap

Potential future directions include:

- measurement-driven optimization for extremely large folders.

These items are future work, have no promised release date, and are not included
in v1.0.2.

## License

A project license has not yet been selected. Until a license is added, no usage
rights are granted beyond those provided by applicable law.
