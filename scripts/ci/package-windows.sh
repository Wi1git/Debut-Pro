#!/bin/bash
# Turn the folder deployed by build-shotcut-msys2.sh into the portable
# "Debut Pro" zip. Runs in the MSYS2 shell.
#
# Usage: package-windows.sh <deployed-dir> <version> <output-dir>
#   deployed-dir  the "Shotcut" folder produced by the build ($INSTALL_DIR/Shotcut)
#   version       version string shown in the README
#   output-dir    where "stage/Debut Pro/" is staged and the zip is written
#
# Writes <output-dir>/DebutPro-windows-x64.zip whose top folder is
# "Debut Pro/". The deployed folder is moved, not copied.
#
# Internal names (share/shotcut, lib/mlt, ...) are left unchanged; only the
# main executable is renamed to "Debut Pro.exe". That is safe because the app
# never relies on its own file name: it finds its helpers (melt, ffmpeg,
# ffprobe) and data via QCoreApplication::applicationDirPath(), restarts
# itself via applicationFilePath(), Qt reads qt.conf from the executable's
# folder, and the Dr. Mingw crash handler is only linked into debug builds.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <deployed-dir> <version> <output-dir>" >&2
  exit 2
fi

DEPLOYED=$1
VERSION=$2
OUT_DIR=$3
APP_NAME="Debut Pro"
ZIP_NAME="DebutPro-windows-x64.zip"

if [ ! -f "$DEPLOYED/shotcut.exe" ]; then
  echo "error: $DEPLOYED/shotcut.exe not found; did the build and deploy succeed?" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAGE="$OUT_DIR/stage"
rm -rf "$STAGE" "${OUT_DIR:?}/$ZIP_NAME"
mkdir -p "$STAGE"

echo "Staging $DEPLOYED as $STAGE/$APP_NAME"
mv "$DEPLOYED" "$STAGE/$APP_NAME"
mv "$STAGE/$APP_NAME/shotcut.exe" "$STAGE/$APP_NAME/$APP_NAME.exe"
# Leftovers from the dependency bundling step
rm -f "$STAGE/$APP_NAME"/*.bundled

cat > "$STAGE/$APP_NAME/README.txt" <<EOF
Debut Pro $VERSION for Windows (x64), portable edition

No installation or administrator rights are needed: extract this folder
anywhere you can write to (for example your Documents folder) and run
"$APP_NAME.exe". To uninstall, delete the folder.

This build is not signed, so Windows SmartScreen may say "Windows protected
your PC" the first time: click "More info", then "Run anyway".

Debut Pro is based on Shotcut (https://www.shotcut.org) and is free software
under the GNU General Public License v3; see COPYING.txt.
EOF
# Windows line endings for Notepad
sed -i 's/$/\r/' "$STAGE/$APP_NAME/README.txt"

echo "Creating $OUT_DIR/$ZIP_NAME"
(cd "$STAGE" && zip -q -r -X "../$ZIP_NAME" "$APP_NAME")
ls -l "$OUT_DIR/$ZIP_NAME"
