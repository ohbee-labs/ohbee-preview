# Ohbee Preview 1.1.0

Ohbee Preview 1.1.0 is the stable MVP of the lightweight, native macOS image
viewer for fast folder browsing.

## What’s new since 1.0.2

- Browse a folder visually with a collapsible, resizable thumbnail sidebar.
- View animated GIFs with bounded, cancellable frame decoding.
- Reveal the current image in Finder.
- Move an immutable confirmed target to Trash, then continue at the next or
  previous image without risking deletion of a later selection.
- Operate primary workflows from native menus and the keyboard.
- Use VoiceOver-ready labels, selection state, concise announcements, stable
  accessibility identifiers, semantic Light/Dark appearance, and Reduce Motion.
- Browse large mixed folders with measured, bounded enumeration, sorting,
  thumbnail work, and memory policies.
- Reject obviously unsafe static-image dimensions or decoded allocation estimates
  before full decode.

## Supported formats

JPEG, PNG, HEIC/HEIF, GIF, and TIFF. GIF animation is supported; APNG, animated
WebP, RAW, video, and Live Photos are not.

## Installation

1. Download `Ohbee-Preview-1.1.0-macOS.zip`.
2. Extract it and move **Ohbee Preview.app** to Applications.
3. Open an image through Finder → Open With → Ohbee Preview.

This repository-provided artifact is ad-hoc signed for local distribution. It is
not Developer ID signed, notarized, submitted to the Mac App Store, or presented
as such.

## Verified release posture

- Native macOS 14+ application, bundle ID `com.ohbee.preview`.
- App Sandbox enabled with user-selected read/write access only.
- Six declared image UTIs and the existing small-size icon artwork.
- No analytics, telemetry, network service, persistent security-scoped bookmark,
  database, disk thumbnail cache, or third-party dependency.

## Known environment limitations

- Slow iCloud materialization, third-party File Providers, and slow external
  volumes were unavailable for this release validation.
- HEIC/HEIF decoding is supported, but automated encoding of new HEIC fixtures
  was unavailable in the installed ImageIO environment.
- Real VoiceOver, Increase Contrast, Differentiate Without Color, and complete
  interactive fullscreen/system-panel matrices remain manual validations; this
  release does not claim accessibility certification.
- Developer ID signing and notarization were not configured.
