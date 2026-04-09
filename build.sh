#!/bin/bash
# 从 .env 读取配置并构建 Flutter
# 用法: ./build.sh [platform] (web/macos/ios/android)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 未找到 .env 文件，请复制 .env.example 并填入配置"
  exit 1
fi

# 读取 .env
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Flutter SDK 路径（可通过环境变量 FLUTTER_BIN 覆盖）
FLUTTER="${FLUTTER_BIN:-flutter}"

PLATFORM="${1:-macos}"
DART_DEFINES="--dart-define=WEBDAV_URL=$WEBDAV_URL --dart-define=WEBDAV_USER=$WEBDAV_USER --dart-define=WEBDAV_PASS=$WEBDAV_PASS --dart-define=CRYPTO_SALT=$CRYPTO_SALT"

echo "🔨 Building for $PLATFORM (using: $FLUTTER)..."

case "$PLATFORM" in
  web)
    $FLUTTER build web $DART_DEFINES
    # 修补 CanvasKit 本地化
    cd build/web
    sed -i '' 's/"engineRevision":"[^"]*"/"engineRevision":"425cfb54d01a9472b3e81d9e76fd63a4a44cfbcb","useLocalCanvasKit":true/' flutter_bootstrap.js 2>/dev/null || true
    cp "$SCRIPT_DIR/web/sqlite3.wasm" . 2>/dev/null || true
    cp "$SCRIPT_DIR/web/drift_worker.js" . 2>/dev/null || true
    echo "✅ Web build complete: build/web/"
    ;;
  macos)
    $FLUTTER build macos $DART_DEFINES
    echo "✅ macOS build complete"
    ;;
  ios)
    $FLUTTER build ios $DART_DEFINES --no-codesign
    echo "✅ iOS build complete"
    ;;
  android)
    $FLUTTER build apk $DART_DEFINES
    echo "✅ Android build complete"
    ;;
  run-web)
    $FLUTTER build web $DART_DEFINES
    cd build/web
    sed -i '' 's/"engineRevision":"[^"]*"/"engineRevision":"425cfb54d01a9472b3e81d9e76fd63a4a44cfbcb","useLocalCanvasKit":true/' flutter_bootstrap.js 2>/dev/null || true
    cp "$SCRIPT_DIR/web/sqlite3.wasm" . 2>/dev/null || true
    cp "$SCRIPT_DIR/web/drift_worker.js" . 2>/dev/null || true
    cd "$SCRIPT_DIR"
    echo "✅ Web build complete, starting server..."
    python3 web_server.py
    ;;
  run-macos)
    $FLUTTER run -d macos $DART_DEFINES
    ;;
  *)
    echo "用法: ./build.sh [web|macos|ios|android|run-web|run-macos]"
    exit 1
    ;;
esac
