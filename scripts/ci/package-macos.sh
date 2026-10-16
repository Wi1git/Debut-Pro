#!/bin/bash
# Turn the Shotcut.app bundle produced by build-shotcut.sh into a signed
# "Debut Pro.app" inside a disk image.
#
# Usage: package-macos.sh <Shotcut.app> <version> <output-dir> [<COPYING>]
#
# Writes <output-dir>/DebutPro-macos-arm64.dmg (or DebutPro-macos-arm64.zip,
# made with ditto, if hdiutil keeps failing) and, when running in GitHub
# Actions, sets the step outputs "artifact" (that file) and "app" (the signed
# "Debut Pro.app" in the staging folder).
#
# The app is signed ad hoc ("codesign --sign -"): install_name_tool rewrote
# nearly every binary, which invalidates their signatures, and Apple Silicon
# refuses to run code without a valid signature. Every Mach-O file is signed
# on its own first, because "codesign --deep" does not reach the QML plugins
# in Contents/Resources; then the whole bundle is signed with --deep. No Apple
# developer identity is used and nothing is notarized.

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "usage: $0 <Shotcut.app> <version> <output-dir> [<COPYING>]" >&2
  exit 2
fi

APP_SRC=${1%/}
VERSION=$2
OUT_DIR=$3
COPYING=${4:-}
APP_NAME="Debut Pro"
BASENAME="DebutPro-macos-arm64"

if [ ! -x "$APP_SRC/Contents/MacOS/Shotcut" ]; then
  echo "error: $APP_SRC/Contents/MacOS/Shotcut not found; did the build and deploy succeed?" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAGE="$OUT_DIR/dmg"
APP="$STAGE/$APP_NAME.app"
rm -rf "$STAGE" "${OUT_DIR:?}/$BASENAME.dmg" "${OUT_DIR:?}/$BASENAME.zip"
mkdir -p "$STAGE"

echo "Staging $APP_SRC as $APP"
ditto "$APP_SRC" "$APP"

# Build leftovers that do not belong in the bundle
find "$APP" -name '*.bundled' -delete
find "$APP" \( -name '*.a' -o -name '*.la' -o -name '*.prl' \) -type f -delete
find "$APP" \( -name '*.dSYM' -o -name '__pycache__' \) -type d -prune -exec rm -rf {} +

# The binaries are built for MACOSX_DEPLOYMENT_TARGET (and Homebrew's
# libraries for the build machine's macOS), so say so in Info.plist.
PLIST="$APP/Contents/Info.plist"
if [ -n "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MACOSX_DEPLOYMENT_TARGET" "$PLIST" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MACOSX_DEPLOYMENT_TARGET" "$PLIST"
fi

is_macho() {
  [[ "$(file -b "$1")" == Mach-O* ]]
}

# All Mach-O files in the bundle, deepest paths first.
MACHO_LIST="$OUT_DIR/macho-files.txt"
: > "$MACHO_LIST"
while IFS= read -r -d '' f; do
  if is_macho "$f"; then
    printf '%s\n' "$f" >> "$MACHO_LIST"
  fi
done < <(find "$APP/Contents" -type f -print0)
echo "Found $(wc -l < "$MACHO_LIST" | tr -d ' ') Mach-O files"

# Qt's binaries are universal; keep only the Apple Silicon code.
echo "Thinning universal binaries to arm64"
while IFS= read -r f; do
  archs=$(lipo -archs "$f" 2>/dev/null || true)
  if [ "$archs" != "arm64" ] && [[ " $archs " == *" arm64 "* ]]; then
    lipo "$f" -thin arm64 -output "$f.thin" && mv -f "$f.thin" "$f"
  fi
done < "$MACHO_LIST"

# Drop run paths that point at the build machine (our prefix, Qt, Homebrew)
# so a user's own Homebrew libraries can never be picked up instead of the
# bundled ones; everything is found via @executable_path/../Frameworks.
echo "Removing absolute run paths"
while IFS= read -r f; do
  otool -l "$f" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }' |
    while IFS= read -r rpath; do
      case "$rpath" in
        /*) install_name_tool -delete_rpath "$rpath" "$f" 2>/dev/null || true ;;
      esac
    done
done < "$MACHO_LIST"

xattr -cr "$APP"

echo "Signing (ad hoc)"
# Nested code first (deepest paths first), then the bundle, which also signs
# the main executable and seals the resources.
while IFS= read -r f; do
  [ "$f" = "$APP/Contents/MacOS/Shotcut" ] && continue
  codesign --force --sign - --timestamp=none "$f"
done < <(awk '{ print length($0) "\t" $0 }' "$MACHO_LIST" | sort -rn | cut -f2-)
codesign --force --deep --sign - --timestamp=none "$APP"
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
  echo "::warning::codesign --verify reported problems with $APP_NAME.app"
fi

cat > "$STAGE/READ ME FIRST.txt" <<EOF
Debut Pro $VERSION for macOS (Apple Silicon)

Install: drag "$APP_NAME" onto the Applications folder.

This build is not notarized by Apple, so macOS blocks the first launch.
Either:
  - open System Settings > Privacy & Security, scroll down and click
    "Open Anyway" next to the message about "$APP_NAME", or
  - run this once in Terminal:
      xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app"

Debut Pro is based on Shotcut (https://www.shotcut.org) and is free software
under the GNU General Public License v3; see COPYING.txt.
EOF
if [ -n "$COPYING" ] && [ -f "$COPYING" ]; then
  cp "$COPYING" "$STAGE/COPYING.txt"
fi
ln -s /Applications "$STAGE/Applications"

ARTIFACT=
DMG="$OUT_DIR/$BASENAME.dmg"
SIZE_MB=$(du -sm "$STAGE" | cut -f1)
SIZE_MB=$((SIZE_MB * 13 / 10 + 64))
for attempt in 1 2 3 4 5; do
  echo "Creating $DMG (attempt $attempt)"
  if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ \
       -format UDZO -size "${SIZE_MB}m" -ov "$DMG"; then
    ARTIFACT=$DMG
    break
  fi
  # hdiutil sometimes fails with "Resource busy" on CI machines
  sleep $((attempt * 15))
done

if [ -z "$ARTIFACT" ]; then
  echo "::warning::hdiutil failed; packaging the app as a zip instead"
  ARTIFACT="$OUT_DIR/$BASENAME.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACT"
fi

ls -l "$ARTIFACT"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "artifact=$ARTIFACT" >> "$GITHUB_OUTPUT"
  echo "app=$APP" >> "$GITHUB_OUTPUT"
fi
