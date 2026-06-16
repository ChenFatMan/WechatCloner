#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/WechatCloner.xcodeproj"
SCHEME="WechatCloner"
CONFIGURATION="Release"
DERIVED_DATA="$PROJECT_ROOT/.build/DerivedData"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="WechatCloner.app"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
DIST_APP_PATH="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/WechatCloner.zip"

KEEP_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --keep-build)
      KEEP_BUILD=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: scripts/package.sh [--keep-build]" >&2
      exit 2
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install full Xcode first." >&2
  exit 1
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVELOPER_DIR" != */Xcode.app/Contents/Developer ]]; then
  echo "Active developer directory is not full Xcode: ${DEVELOPER_DIR:-unknown}" >&2
  echo "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

set +e
XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>&1)"
XCODE_VERSION_STATUS=$?
set -e

if [[ "$XCODE_VERSION_STATUS" -ne 0 ]]; then
  echo "$XCODE_VERSION_OUTPUT" >&2
  if [[ "$XCODE_VERSION_OUTPUT" == *"license"* ]]; then
    echo "Run this first, then rerun scripts/package.sh:" >&2
    echo "  sudo xcodebuild -license" >&2
    echo "  sudo xcodebuild -runFirstLaunch" >&2
  fi
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

set +e
BUILD_OUTPUT="$(xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build 2>&1)"
BUILD_STATUS=$?
set -e

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "$BUILD_OUTPUT" >&2
  if [[ "$BUILD_OUTPUT" == *"license"* ]]; then
    echo "Run this first, then rerun scripts/package.sh:" >&2
    echo "  sudo xcodebuild -license" >&2
    echo "  sudo xcodebuild -runFirstLaunch" >&2
  fi
  exit "$BUILD_STATUS"
fi

echo "$BUILD_OUTPUT"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app was not found: $APP_PATH" >&2
  exit 1
fi

ditto "$APP_PATH" "$DIST_APP_PATH"

(
  cd "$DIST_DIR"
  ditto -c -k --keepParent "$APP_NAME" "$ZIP_PATH"
)

if [[ "$KEEP_BUILD" -eq 0 ]]; then
  rm -rf "$PROJECT_ROOT/.build"
fi

echo "Packaged app: $DIST_APP_PATH"
echo "Packaged zip: $ZIP_PATH"
