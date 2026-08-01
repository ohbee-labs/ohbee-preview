# Changelog

All notable changes to Ohbee Preview are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added native Reveal in Finder and confirmed Move to Trash commands with
  immutable target identity, deterministic next/previous/empty reconciliation,
  accessible errors, and privacy-safe local diagnostics.
- Added targeted thumbnail eviction and GIF playback suspension around Trash.
- Added bounded, cancellable animated GIF playback using ImageIO with safe delay
  normalization, finite/infinite loop handling, lifecycle pause/restart, and
  generation-safe frame publication.
- Added an independent eight-frame / 64 MiB decoded frame store, concurrency-one
  frame scheduler, selected-GIF resource guards, and local GIF diagnostics.
- Added a collapsible, resizable thumbnail sidebar with persisted visibility.
- Added progressive ImageIO thumbnails, keyboard selection, selected-item
  highlighting, and automatic scroll synchronization.
- Added a dedicated bounded thumbnail scheduler, byte-cost cache, cancellation,
  stale-result rejection, memory-pressure handling, and local diagnostics.

### Fixed

- Prevented a confirmation opened for image A from ever deleting image B after
  rapid navigation, warm open, or overlapping action cleanup.
- Preserved zoom, pan, rotation, centering, and document geometry while animated
  frames replace one another in the existing AppKit viewport.
- Isolated frame task/cache identity by playback session and URL so obsolete GIF
  work cannot publish into or cancel a newer selection.
- Ensured thumbnail cancellation remains attached to the bounded scheduler task
  instead of allowing detached ImageIO work to outlive its request.
- Released row-owned thumbnail images when rows leave the visible working set so
  the bounded cache remains the sole retained thumbnail store.

## [1.0.2] - 2026-07-31

### Fixed

- Fixed replacement images sometimes aligning to the leading edge after
  Previous or Next navigation.
- Ensured Fit-to-Window centering remains valid after SwiftUI and AppKit layout
  updates.

## [1.0.1] - 2026-07-31

### Changed

- Improved application icon readability in Finder and Open With menus.
- Added purpose-designed bee artwork for small macOS display sizes.

### Fixed

- Fixed the application icon appearing as an indistinct multicolor shape at
  16×16 and 32×32 sizes.

## [1.0.0] - 2026-07-31

**Release name:** Version 1.0.0

**Status:** Stable MVP

The first stable Ohbee Preview baseline: a native, sandboxed macOS image viewer
for opening an image from Finder, browsing its folder, and inspecting images
with keyboard, trackpad, and native window controls.

### Added

- Finder cold- and warm-open URL handling, including Open With.
- Static display for JPEG, PNG, HEIC, HEIF, GIF, and TIFF images.
- Direct-child sibling discovery with natural filename sorting.
- Non-wrapping Previous and Next navigation with boundary-aware controls.
- Contextual, same-session folder authorization fallback.
- Fit to Window, Actual Size, bounded zoom, pinch, scrolling, and pointer panning.
- Non-destructive, per-image session rotation.
- Native macOS fullscreen and keyboard-accessible image commands.
- Loading, unsupported-file, missing-file, permission, unreadable, and decode-failure states.
- Finder Open With registration and user-invoked default-viewer guidance.
- Privacy-preserving local logging and signpost instrumentation.

### Changed

- Folder-access guidance appears only after the selected image is displayed and
  automatic sibling discovery cannot proceed.
- Image navigation resets zoom and pan to Fit while retaining bounded,
  session-only rotation state for previously viewed images.
- ImageIO now decodes directly from the authorized file URL.

### Fixed

- Replacement images no longer inherit stale document or clip-view origins and
  remain centered after navigation, rotation, resize, and fullscreen changes.
- Late decode and viewport commits cannot replace a newer navigation target.
- Cold-launch URL buffering now honors the latest supported open request.
- Cancelling folder authorization no longer causes automatic repeat prompts.
- Representative sibling access probes close file handles on every path.

### Performance

- Folder enumeration, natural sorting, file access, and image decoding run away
  from the main actor.
- Removed the unnecessary full compressed-file `Data` allocation before decode.
- Suppressed equivalent viewport-scale publications to reduce SwiftUI invalidation.
- Kept geometry calculations deterministic and lightweight.

### Security

- App Sandbox remains enabled with user-selected read/write access only.
- Folder authorization is held in memory for the current application session.
- No security-scoped bookmarks or persistent filesystem authority are stored.
- No analytics, telemetry, cloud service, or third-party dependency is included.
- Release diagnostics do not log full paths, filenames, image contents, EXIF,
  user identifiers, or personally identifiable information.

### Testing

- Added deterministic navigation, sorting, cancellation, and stale-result tests.
- Added image-loading and source-file integrity integration coverage.
- Added pure viewport geometry coverage for fit, actual size, zoom, rotation,
  pan bounds, and resize.
- Added native AppKit viewport regression coverage for image replacement and
  centering across different sizes and aspect ratios.
- Added Launch Services document-declaration checks and Debug/Release signing gates.
- Completed manual Finder, sandbox authorization, fullscreen, viewport, and
  default-handler smoke checks.

### Documentation

- Added public build, testing, architecture, privacy, sandbox, shortcut, and
  default-viewer documentation.
- Reconciled the Milestone 1 and Milestone 2 completion and engineering gates.
