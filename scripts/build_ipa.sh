#!/usr/bin/env bash
set -euo pipefail

# Build unsigned TrainBotIOS.ipa ready for Sideloadly, AltStore, SideStore, or Signulous.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/TrainBotIOS/TrainBotIOS.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
PRODUCTS_DIR="$BUILD_DIR/Products"

echo "🔨 Building TrainBotIOS (Release, iphoneos)..."
rm -rf "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -target "TrainBotIOS" \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$BUILD_DIR/sym" \
  OBJROOT="$BUILD_DIR/obj" \
  CONFIGURATION_BUILD_DIR="$PRODUCTS_DIR" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build

mkdir -p "$BUILD_DIR/Payload"
APP_PATH="$PRODUCTS_DIR/TrainBotIOS.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH=$(find "$BUILD_DIR" -name "TrainBotIOS.app" -type d | head -n 1)
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "❌ TrainBotIOS.app not found after build"
  exit 1
fi

cp -R "$APP_PATH" "$BUILD_DIR/Payload/TrainBotIOS.app"
cd "$BUILD_DIR"
zip -qry "TrainBotIOS.ipa" Payload

echo "✅ Successfully packaged: $BUILD_DIR/TrainBotIOS.ipa"
ls -lh "$BUILD_DIR/TrainBotIOS.ipa"
