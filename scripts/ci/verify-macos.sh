#!/bin/bash
# Sanity checks for the packaged "Debut Pro.app".
#
# Usage: verify-macos.sh <Debut Pro.app>
#
# Fails if any bundled binary still refers to a library outside the bundle
# (other than macOS system libraries), if anything links SDL, or if the
# bundled FFmpeg lacks the expected codecs and VideoToolbox.

set -uo pipefail

# install-qt-action points these at the Qt SDK; the app must use its own copies.
unset QT_PLUGIN_PATH QML2_IMPORT_PATH

APP=${1%/}
CONTENTS="$APP/Contents"
FRAMEWORKS="$CONTENTS/Frameworks"
errors=0

error() {
  echo "::error::$*"
  errors=$((errors + 1))
}

echo "== Checking library references"
while IFS= read -r -d '' f; do
  [[ "$(file -b "$f")" == Mach-O* ]] || continue
  # The library's own install name (header lines end with a colon)
  ids=$(otool -D "$f" | awk '!/:$/')
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    grep -qxF -- "$ref" <<< "$ids" && continue
    case "$ref" in
      /usr/lib/* | /System/*) ;;
      @rpath/*)
        [ -e "$FRAMEWORKS/${ref#@rpath/}" ] || error "${f#"$APP"/} needs $ref, which is not in Contents/Frameworks"
        ;;
      @loader_path/*)
        [ -e "$(dirname "$f")/${ref#@loader_path/}" ] || error "${f#"$APP"/} needs $ref, which does not exist"
        ;;
      @executable_path/*)
        [ -e "$CONTENTS/MacOS/${ref#@executable_path/}" ] || error "${f#"$APP"/} needs $ref, which does not exist"
        ;;
      *) error "${f#"$APP"/} refers to $ref outside the bundle" ;;
    esac
    case "$ref" in
      *libSDL*) error "${f#"$APP"/} links $ref; sdl2-compat aborts without SDL3" ;;
    esac
  done < <(otool -L "$f" | awk '/^\t/ { print $1 }' | sort -u)
done < <(find "$CONTENTS" -type f -print0)

echo "== Checking bundle layout"
for path in MacOS/Shotcut MacOS/melt MacOS/ffmpeg MacOS/ffprobe Resources/qt.conf \
            PlugIns/qt/platforms/libqcocoa.dylib PlugIns/qt/sqldrivers/libqsqlite.dylib \
            Resources/qml/QtQuick/Controls Resources/mlt/profiles Resources/movit \
            Resources/shotcut/qml Resources/shotcut/translations PlugIns/mlt PlugIns/frei0r-1 PlugIns/ladspa; do
  [ -e "$CONTENTS/$path" ] || error "Contents/$path is missing"
done

echo "== Checking architecture"
lipo -archs "$CONTENTS/MacOS/Shotcut" | grep -qw arm64 || error "Shotcut is not built for arm64"

echo "== Checking FFmpeg"
FFMPEG="$CONTENTS/MacOS/ffmpeg"
if [ -x "$FFMPEG" ]; then
  encoders=$("$FFMPEG" -hide_banner -encoders 2>&1) || error "ffmpeg -encoders failed: $encoders"
  for e in h264_videotoolbox hevc_videotoolbox libx264 libx265 libsvtav1 libvpx-vp9 libopus libmp3lame libwebp; do
    grep -qw -- "$e" <<< "$encoders" || error "ffmpeg is missing encoder $e"
  done
  decoders=$("$FFMPEG" -hide_banner -decoders 2>&1) || error "ffmpeg -decoders failed: $decoders"
  grep -qw libdav1d <<< "$decoders" || error "ffmpeg is missing decoder libdav1d"
  hwaccels=$("$FFMPEG" -hide_banner -hwaccels 2>&1) || error "ffmpeg -hwaccels failed: $hwaccels"
  grep -qw videotoolbox <<< "$hwaccels" || error "ffmpeg is missing the videotoolbox hwaccel"
  "$FFMPEG" -hide_banner -version | head -n 1
else
  error "ffmpeg is missing from Contents/MacOS"
fi

echo "== Checking MLT"
MELT="$CONTENTS/MacOS/melt"
if [ -x "$MELT" ]; then
  # Loads every MLT module (and frei0r plugin), which catches unresolved libraries.
  services=$("$MELT" -query 2>&1) || error "melt -query failed: $services"
  for s in avformat xml qimage qtblend movit.blur rbpitch vidstab sox rnnoise ladspa \
           frei0r.cairoblend rtaudio; do
    grep -qE -- "^[[:space:]]*-[[:space:]]+${s//./\\.}[[:space:]]*\$" <<< "$services" || error "MLT service $s is missing"
  done
else
  error "melt is missing from Contents/MacOS"
fi

echo "== Checking that the app starts"
log=$(mktemp)
"$CONTENTS/MacOS/Shotcut" --version > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 60); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
if kill -0 "$pid" 2>/dev/null; then
  echo "Still running after 60 s; assuming it started"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
else
  wait "$pid"
  status=$?
  cat "$log"
  if [ "$status" -ne 0 ] || grep -q 'Library not loaded\|Symbol not found' "$log"; then
    error "Shotcut --version exited with status $status"
  fi
fi
rm -f "$log"

if [ "$errors" -gt 0 ]; then
  echo "$errors problem(s) found"
  exit 1
fi
echo "All checks passed"
