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
ZIP_NAME="WechatCloner.zip"
ARCH=""

KEEP_BUILD=0

while [[ "$#" -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --keep-build)
      KEEP_BUILD=1
      shift
      ;;
    --arch)
      ARCH="${2:-}"
      if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
        echo "--arch must be arm64 or x86_64" >&2
        exit 2
      fi
      shift 2
      ;;
    --zip-name)
      ZIP_NAME="${2:-}"
      if [[ -z "$ZIP_NAME" || "$ZIP_NAME" == */* ]]; then
        echo "--zip-name must be a file name, not a path" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: scripts/package.sh [--keep-build] [--arch arm64|x86_64] [--zip-name NAME.zip]" >&2
      exit 2
      ;;
  esac
done

ZIP_PATH="$DIST_DIR/$ZIP_NAME"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install full Xcode first." >&2
  exit 1
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVELOPER_DIR" != */*.app/Contents/Developer ]]; then
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
BUILD_ARGS=(
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA"
)

if [[ -n "$ARCH" ]]; then
  BUILD_ARGS+=(ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO)
fi

BUILD_OUTPUT="$(xcodebuild "${BUILD_ARGS[@]}" clean build 2>&1)"
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
