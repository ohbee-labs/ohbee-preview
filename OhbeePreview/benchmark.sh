#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
SDK_ROOT="${OHBEE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
BUILD_ROOT="$PROJECT_DIR/.build-benchmark"
MODULE_CACHE="$BUILD_ROOT/ModuleCache"
CORE_MODULE="$BUILD_ROOT/CoreModule"
mkdir -p "$MODULE_CACHE" "$CORE_MODULE"

COMMON_FLAGS=(
  -target "$(uname -m)-apple-macos14.0"
  -sdk "$SDK_ROOT"
  -module-cache-path "$MODULE_CACHE"
  -swift-version 6
  -O
)

xcrun swiftc \
  "${COMMON_FLAGS[@]}" \
  -parse-as-library \
  -whole-module-optimization \
  -emit-module \
  -emit-object \
  -module-name OhbeeStage2Core \
  "$PROJECT_DIR/Sources/OhbeeStage2Core/FolderNavigation.swift" \
  "$PROJECT_DIR/Sources/OhbeeStage2Core/Stage2State.swift" \
  "$PROJECT_DIR/Sources/OhbeeStage2Core/ViewportGeometry.swift" \
  -emit-module-path "$CORE_MODULE/OhbeeStage2Core.swiftmodule" \
  -o "$CORE_MODULE/OhbeeStage2Core.o"

xcrun swiftc \
  "${COMMON_FLAGS[@]}" \
  -parse-as-library \
  -I "$CORE_MODULE" \
  "$CORE_MODULE/OhbeeStage2Core.o" \
  "$PROJECT_DIR/Benchmarks/LargeFolderBenchmark/main.swift" \
  -o "$BUILD_ROOT/LargeFolderBenchmark"

"$BUILD_ROOT/LargeFolderBenchmark" "$@"
