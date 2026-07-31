# Ohbee Preview

Native macOS image viewer. Current implementation includes the Folder Navigation
MVP:

- one reusable viewer window;
- Finder/Open With lifecycle handling;
- production static-image presentation for approved formats;
- direct-child sibling discovery and natural filename sorting;
- Previous/Next navigation through buttons, menus, and Left/Right Arrow;
- same-session folder authorization and explicit fallback;
- loading, typed failure, cancellation, and stale-result protection;
- local `os.Logger` and signpost instrumentation.

Thumbnails, cache optimization, prefetch, zoom, rotation, animated GIF playback,
Finder actions, and Trash are not implemented in this milestone.

Build:

```sh
./build.sh
BUILD_CONFIGURATION=Release ./build.sh
```

Test:

```sh
./test.sh
```

The test script uses the standard SwiftPM/XCTest suite when Xcode provides
`xctest`. On Command Line Tools-only installations it runs equivalent core and
image-loading integration checks with `swiftc`.

Build and test scripts discover the active macOS SDK and machine architecture.
`OHBEE_SDK_PATH` and `OHBEE_BUILD_ARCH` can override those values for CI.
