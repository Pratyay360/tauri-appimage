#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:?Set APP_NAME to the installed binary name under usr/bin}"
IMAGE_REF="${IMAGE_REF:-rpm-appimage:build}"
APPDIR="${APPDIR:-AppDir}"
OUT="${OUT:-${APP_NAME}-x86_64.AppImage}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib/icon.sh
source "$SCRIPT_DIR/lib/icon.sh"

rm -rf "$APPDIR"
mkdir "$APPDIR"

CID=$(podman create --pull=never "$IMAGE_REF")
podman export "$CID" | tar -xC "$APPDIR"
podman rm "$CID"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"
export PATH="$HERE/usr/bin:$PATH"
exec "$HERE/usr/bin/__APP_NAME__" "$@"
APPRUN
sed -i "s#__APP_NAME__#${APP_NAME}#g" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

desktop_file="$(discover_primary_desktop_file "$APPDIR" "$APP_NAME")"
if [[ -z "$desktop_file" || ! -f "$desktop_file" ]]; then
  echo "ERROR: Unable to locate a desktop file inside '$APPDIR'." >&2
  exit 1
fi
icon_name="$(extract_icon_name_from_desktop "$desktop_file")"

if [[ -z "$icon_name" ]]; then
  echo "ERROR: Could not read Icon= from desktop file '$desktop_file'." >&2
  echo "Please ensure the desktop file contains an Icon entry or provide a valid package." >&2
  exit 1
fi

if ! final_icon_path="$(materialize_appdir_icon "$APPDIR" "$icon_name" "$APP_NAME" "${APP_ICON_URL:-}")"; then
  echo "ERROR: Failed to materialize icon for Icon='$icon_name'." >&2
  exit 1
fi

# appimagetool requires the .desktop file at the AppDir root; copy it there if needed
desktop_root_path="$APPDIR/$(basename "$desktop_file")"
if [[ "$desktop_file" != "$desktop_root_path" ]]; then
  cp "$desktop_file" "$desktop_root_path"
  desktop_file="$desktop_root_path"
fi

echo "Desktop file: $desktop_file"
echo "Desktop icon name: $icon_name"
echo "Final AppDir icon: $final_icon_path"

wget -qO appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool

export ARCH="${ARCH:-x86_64}"
export VERSION="${VERSION:-1.0.0}"

./appimagetool --appimage-extract-and-run "$APPDIR" "$OUT"
