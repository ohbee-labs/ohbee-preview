#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
CONFIGURATION="${BUILD_CONFIGURATION:-Debug}"
SDK_PATH="${OHBEE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
BUILD_ARCH="${OHBEE_BUILD_ARCH:-$(uname -m)}"
CLT_COMPATIBLE_SDK="$(xcode-select -p)/SDKs/MacOSX15.sdk"
if [[ -z "${OHBEE_SDK_PATH:-}" && -d "$CLT_COMPATIBLE_SDK" ]]; then
  # Some Command Line Tools installations expose a newer default SDK whose
  # Swift module version does not match their bundled compiler.
  if ! xcrun swiftc -sdk "$SDK_PATH" -typecheck \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" >/dev/null 2>&1; then
    SDK_PATH="$CLT_COMPATIBLE_SDK"
  fi
fi
BUILD_ROOT="$PROJECT_DIR/.build-stage2"
MODULE_CACHE="$BUILD_ROOT/ModuleCache"
APP_DIR="$BUILD_ROOT/$CONFIGURATION/Ohbee Preview.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CORE_MODULE_DIR="$BUILD_ROOT/$CONFIGURATION/CoreModule"

case "$CONFIGURATION" in
  Debug)
    SWIFT_FLAGS=(-Onone -g -D DEBUG)
    ;;
  Release)
    SWIFT_FLAGS=(-O)
    ;;
  Profiling)
    SWIFT_FLAGS=(-O -g -D PROFILING)
    ;;
  Benchmark)
    SWIFT_FLAGS=(-O -D BENCHMARK)
    ;;
  *)
    echo "Unknown BUILD_CONFIGURATION: $CONFIGURATION" >&2
    exit 2
    ;;
esac

mkdir -p "$MODULE_CACHE" "$MACOS_DIR" "$RESOURCES_DIR" "$CORE_MODULE_DIR"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

COMMON_FLAGS=(
  -target "$BUILD_ARCH-apple-macos14.0"
  -sdk "$SDK_PATH"
  -module-cache-path "$MODULE_CACHE"
  -swift-version 6
)

xcrun swiftc \
  "${COMMON_FLAGS[@]}" \
  "${SWIFT_FLAGS[@]}" \
  -parse-as-library \
  -emit-module \
  -emit-object \
  -module-name OhbeeStage2Core \
  "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" \
  -emit-module-path "$CORE_MODULE_DIR/OhbeeStage2Core.swiftmodule" \
  -o "$CORE_MODULE_DIR/OhbeeStage2Core.o"

xcrun swiftc \
  "${COMMON_FLAGS[@]}" \
  "${SWIFT_FLAGS[@]}" \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -framework OSLog \
  -I "$CORE_MODULE_DIR" \
  "$CORE_MODULE_DIR/OhbeeStage2Core.o" \
  "$PROJECT_DIR/Sources/OhbeePreview/AppDelegate.swift" \
  "$PROJECT_DIR/Sources/OhbeePreview/AppModel.swift" \
  "$PROJECT_DIR/Sources/OhbeePreview/ContentView.swift" \
  "$PROJECT_DIR/Sources/OhbeePreview/Diagnostics.swift" \
  "$PROJECT_DIR/Sources/OhbeePreview/FolderAccessController.swift" \
  "$PROJECT_DIR/Sources/OhbeePreview/OhbeePreviewApp.swift" \
  "$PROJECT_DIR/Sources/OhbeePreview/SelectedImageLoader.swift" \
  -o "$MACOS_DIR/OhbeePreview"

codesign --force --deep --sign - \
  --entitlements "$PROJECT_DIR/Resources/OhbeePreview.entitlements" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign -d --entitlements :- "$APP_DIR"
echo "$APP_DIR"
