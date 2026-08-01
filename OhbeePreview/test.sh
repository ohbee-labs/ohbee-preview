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
    "$PROJECT_DIR/Sources/OhbeeStage2Core/FolderNavigation.swift" \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/ViewportGeometry.swift" \
    "$PROJECT_DIR/Tests/Stage2CoreCLITests/main.swift" \
    -o "$BUILD_ROOT/Stage2CoreCLITests"
  "$BUILD_ROOT/Stage2CoreCLITests"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    -whole-module-optimization \
    -emit-module \
    -emit-object \
    -module-name OhbeeStage2Core \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/FolderNavigation.swift" \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" \
    "$PROJECT_DIR/Sources/OhbeeStage2Core/ViewportGeometry.swift" \
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
    -framework UniformTypeIdentifiers \
    -I "$BUILD_ROOT/CoreModule" \
    "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o" \
    "$PROJECT_DIR/Sources/OhbeePreview/SelectedImageLoader.swift" \
    "$PROJECT_DIR/Tests/Stage2IntegrationCLITests/main.swift" \
    -o "$BUILD_ROOT/Stage2IntegrationCLITests"
  "$BUILD_ROOT/Stage2IntegrationCLITests"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    -framework AppKit \
    -framework ImageIO \
    -framework OSLog \
    -I "$BUILD_ROOT/CoreModule" \
    "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o" \
    "$PROJECT_DIR/Sources/OhbeePreview/AppDelegate.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AppModel.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedFrameStore.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedImageLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/Diagnostics.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/FolderAccessController.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/SelectedImageLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailCache.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailController.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailScheduler.swift" \
    "$PROJECT_DIR/Tests/Milestone2IntegrationCLITests/main.swift" \
    -o "$BUILD_ROOT/Milestone2IntegrationCLITests"
  "$BUILD_ROOT/Milestone2IntegrationCLITests"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    -framework AppKit \
    -framework ImageIO \
    -framework OSLog \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    -I "$BUILD_ROOT/CoreModule" \
    "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedFrameStore.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedImageLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/Diagnostics.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/SelectedImageLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailCache.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailController.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailScheduler.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailSidebar.swift" \
    "$PROJECT_DIR/Tests/ThumbnailPipelineCLITests/main.swift" \
    -o "$BUILD_ROOT/ThumbnailPipelineCLITests"
  "$BUILD_ROOT/ThumbnailPipelineCLITests"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -O \
    -parse-as-library \
    -framework AppKit \
    -framework ImageIO \
    -framework OSLog \
    -framework UniformTypeIdentifiers \
    -I "$BUILD_ROOT/CoreModule" \
    "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedFrameScheduler.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedFrameStore.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedImageController.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/AnimatedImageLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/Diagnostics.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/FolderAccessController.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/SelectedImageLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailCache.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailLoader.swift" \
    "$PROJECT_DIR/Sources/OhbeePreview/ThumbnailScheduler.swift" \
    "$PROJECT_DIR/Tests/AnimatedImageCLITests/main.swift" \
    -o "$BUILD_ROOT/AnimatedImageCLITests"
  "$BUILD_ROOT/AnimatedImageCLITests"

  xcrun swiftc \
    -target "$(uname -m)-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/ModuleCache" \
    -swift-version 6 \
    -parse-as-library \
    -framework AppKit \
    -framework SwiftUI \
    -I "$BUILD_ROOT/CoreModule" \
    "$BUILD_ROOT/CoreModule/OhbeeStage2Core.o" \
    "$PROJECT_DIR/Sources/OhbeePreview/ImageInspectionView.swift" \
    "$PROJECT_DIR/Tests/NativeViewportCLITests/main.swift" \
    -o "$BUILD_ROOT/NativeViewportCLITests"
  "$BUILD_ROOT/NativeViewportCLITests"
fi

INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
[[ "$(plutil -extract CFBundleDocumentTypes.0.CFBundleTypeRole raw "$INFO_PLIST")" == "Viewer" ]]
[[ "$(plutil -extract CFBundleDocumentTypes.0.LSHandlerRank raw "$INFO_PLIST")" == "Alternate" ]]
EXPECTED_CONTENT_TYPES=(
  public.jpeg
  public.png
  public.heic
  public.heif
  com.compuserve.gif
  public.tiff
)
for index in {1..6}; do
  plist_index=$((index - 1))
  [[ "$(plutil -extract "CFBundleDocumentTypes.0.LSItemContentTypes.$plist_index" raw "$INFO_PLIST")" == "${EXPECTED_CONTENT_TYPES[$index]}" ]]
done
echo "PASS: Launch Services Viewer declarations for 6 approved content types"
