# Ohbee Preview 1.0.0

Ohbee Preview 1.0.0 is the first stable MVP baseline: a lightweight, native
macOS image viewer designed for fast folder browsing and keyboard-first image
inspection.

## Highlights

- Open JPEG, PNG, HEIC/HEIF, GIF, and TIFF images from Finder.
- Discover and naturally sort supported sibling images.
- Navigate with Previous, Next, and the Left and Right Arrow keys.
- Inspect images with Fit to Window, Actual Size, bounded zoom, pan, and
  non-destructive session rotation.
- Use native macOS fullscreen, menus, keyboard shortcuts, and trackpad gestures.
- Continue viewing a selected image when sandboxed folder access is unavailable.

## Performance and reliability

- Image decoding, folder enumeration, and sorting stay off the main actor.
- ImageIO decodes directly from the authorized file URL without an unnecessary
  compressed-file copy.
- Cancellation and generation checks prevent obsolete navigation results from
  replacing the current image.
- Replacement images reset stale viewport geometry and remain correctly fitted
  and centered.

## Supported formats

- JPEG (`.jpg`, `.jpeg`, `.jpe`)
- PNG (`.png`)
- HEIC / HEIF (`.heic`, `.heif`)
- GIF (`.gif`, static first frame)
- TIFF (`.tif`, `.tiff`)

## Privacy and sandbox

All image processing is local. The app includes no analytics, telemetry, cloud
service, or third-party dependency. App Sandbox remains enabled. If opening one
image does not authorize its parent folder, Ohbee offers an explicit same-session
folder access action. Version 1.0.0 stores no security-scoped bookmarks or
persistent folder authorization.

## Known limitations

- GIF animation is not available; GIF files display their first frame.
- Thumbnail browsing, editing, EXIF inspection, Finder file actions, and
  persistent folder authorization are not included.
- Very large folders use complete one-pass enumeration and sorting in this
  baseline release.
- The artifact is ad-hoc signed for local use. It is not Developer ID signed,
  notarized, distributed through the Mac App Store, or automatically trusted by
  Gatekeeper on other Macs.

## Installation

Extract `Ohbee-Preview-1.0.0-macOS.zip`, move **Ohbee Preview.app** to
`/Applications`, and open a supported image with Finder's **Open With** command.
Because this build uses ad-hoc signing, it is intended for local development and
evaluation on the machine where it was built.
