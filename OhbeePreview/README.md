# Ohbee Preview

Native macOS image viewer. Current implementation is limited to Stage 2:

- one reusable viewer window;
- Finder/Open With lifecycle handling;
- temporary selected-image presentation;
- initial same-session folder authorization state and explicit fallback shell;
- local `os.Logger` and signpost instrumentation.

Sibling navigation, thumbnails, zoom, rotation, GIF playback, and Trash are not
implemented in this stage.

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
