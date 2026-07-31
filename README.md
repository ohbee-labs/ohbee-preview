# Ohbee Preview

Ohbee Preview is a lightweight, native macOS image viewer focused on fast
folder browsing, keyboard-first navigation, and predictable image inspection.

Release **v1.0.2** is the current stable MVP baseline. It preserves the v1.0.1
icon improvement and fixes Fit-to-Window centering after image navigation.

## Highlights

- Native macOS application built with Swift, SwiftUI, and focused AppKit integration
- Open supported images from Finder using Open or Open With
- Discover sibling images in the selected file's folder
- Natural filename sorting with non-wrapping Previous and Next navigation
- Fit to Window and Actual Size viewing modes
- Bounded zoom, trackpad pinch, scrolling, and pointer panning
- Non-destructive, session-only left and right rotation
- Native macOS fullscreen
- Keyboard-accessible navigation and inspection commands
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
- **Diagnostics** uses privacy-preserving `os.Logger` and signposts locally.

Additional design and product specifications are available in
[`.kiro/specs/macos-image-viewer`](.kiro/specs/macos-image-viewer/).

## Supported Image Formats

| Format | Extensions |
|---|---|
| JPEG | `.jpg`, `.jpeg`, `.jpe` |
| PNG | `.png` |
| HEIC / HEIF | `.heic`, `.heif` |
| GIF | `.gif` (static first-frame display in v1.0.2) |
| TIFF | `.tif`, `.tiff` |

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Previous image | Left Arrow |
| Next image | Right Arrow |
| Fit to Window | Command-9 |
| Actual Size | Command-0 |
| Zoom In | Command-Equals / Command-Plus |
| Zoom Out | Command-Minus |
| Rotate Left | Command-L |
| Rotate Right | Command-R |
| Toggle Fullscreen | Control-Command-F |

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
  and image replacement; and
- deterministic Launch Services document-type checks.

When Xcode provides `xctest`, the project uses SwiftPM/XCTest. The test script
also supports a Command Line Tools environment through equivalent CLI suites.

## Performance Philosophy

Ohbee Preview prioritizes the selected image and keeps file access, folder
enumeration, sorting, and decoding off the main actor. Rendering uses native
Apple frameworks. The current release does not add speculative image caching or
prefetch, and ImageIO decodes directly from the authorized file URL to avoid an
unnecessary compressed-file copy. Further optimization is driven by measured
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

- an optional, on-demand thumbnail browser;
- animated GIF playback;
- additional Finder integration and safe file actions;
- accessibility hardening; and
- measurement-driven optimization for extremely large folders.

These items are future work, have no promised release date, and are not included
in v1.0.2.

## License

A project license has not yet been selected. Until a license is added, no usage
rights are granted beyond those provided by applicable law.
