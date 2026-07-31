#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
SDK_PATH="${OHBEE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
CLT_COMPATIBLE_SDK="$(xcode-select -p)/SDKs/MacOSX15.sdk"
if [[ -z "${OHBEE_SDK_PATH:-}" && -d "$CLT_COMPATIBLE_SDK" ]]; then
  if ! xcrun swiftc -sdk "$SDK_PATH" -typecheck \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" >/dev/null 2>&1; then
    SDK_PATH="$CLT_COMPATIBLE_SDK"
  fi
fi

BUILD_ROOT="$PROJECT_DIR/.build-stage2-tests"
mkdir -p "$BUILD_ROOT/ModuleCache"

cd "$PROJECT_DIR"
if xcrun --find xctest >/dev/null 2>&1; then
  SDKROOT="$SDK_PATH" \
  CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/ModuleCache" \
  xcrun swift test --disable-sandbox --scratch-path "$BUILD_ROOT"
else
  mkdir -p "$BUILD_ROOT/CoreModule"
  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" \
    "$PROJECT_DIR/Tests/Stage2CoreCLITests/main.swift" \
    -o "$BUILD_ROOT/Stage2CoreCLITests"
  "$BUILD_ROOT/Stage2CoreCLITests"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    -emit-module \
    -emit-object \
    -module-name OhbeeStage2Core \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" \
    -emit-module-path "$BUILD_ROOT/CoreModule/OhbeeStage2Core.swiftmodule" \
    -o "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    -framework AppKit \
    -framework ImageIO \
    -I "$BUILD_ROOT/CoreModule" \
    "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o" \
    "$PROJECT_DIR/Sources/OhbeePreview/SelectedImageLoader.swift" \
    "$PROJECT_DIR/Tests/Stage2IntegrationCLITests/main.swift" \
    -o "$BUILD_ROOT/Stage2IntegrationCLITests"
  "$BUILD_ROOT/Stage2IntegrationCLITests"
fi
