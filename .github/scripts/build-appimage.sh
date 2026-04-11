#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:?Set APP_NAME to the installed binary name under usr/bin}"
IMAGE_REF="${IMAGE_REF:-rpm-appimage:build}"
APPDIR="${APPDIR:-AppDir}"
OUT="${OUT:-${APP_NAME}-x86_64.AppImage}"

rm -rf "$APPDIR"
mkdir "$APPDIR"

CID=$(sudo podman create --pull=never "$IMAGE_REF")
sudo podman export "$CID" | tar -xC "$APPDIR"
sudo podman rm "$CID"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"
export PATH="$HERE/usr/bin:$PATH"
exec "$HERE/usr/bin/__APP_NAME__" "$@"
APPRUN
sed -i "s#__APP_NAME__#${APP_NAME}#g" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

# Icon= uses the freedesktop icon name; files must live under AppDir/usr/share/icons/hicolor/
ICON_NAME="${APP_NAME}"
shopt -s nullglob
icon_candidates=( "$APPDIR"/usr/share/icons/hicolor/*/apps/"${ICON_NAME}".{png,svg,xpm} )
shopt -u nullglob

if [[ ${#icon_candidates[@]} -eq 0 && -n "${APP_ICON_URL:-}" ]]; then
  url_path="${APP_ICON_URL%%\?*}"
  ext="${url_path##*.}"
  ext="${ext,,}"
  case "$ext" in
    png|svg|xpm) ;;
    *) ext=png ;;
  esac
  if [[ "$ext" == "svg" ]]; then
    icon_dir="$APPDIR/usr/share/icons/hicolor/scalable/apps"
  else
    icon_dir="$APPDIR/usr/share/icons/hicolor/256x256/apps"
  fi
  mkdir -p "$icon_dir"
  wget -qO "$icon_dir/${ICON_NAME}.${ext}" "$APP_ICON_URL"
fi

cat > "$APPDIR/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=${APP_NAME}
Icon=${ICON_NAME}
Categories=Utility;
Terminal=false
EOF

wget -qO appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool

export ARCH="${ARCH:-x86_64}"
export VERSION="${VERSION:-1.0.0}"

./appimagetool --appimage-extract-and-run "$APPDIR" "$OUT"
