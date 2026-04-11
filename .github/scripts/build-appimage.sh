#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:?Set APP_NAME to the installed binary name under usr/bin}"
IMAGE_REF="${IMAGE_REF:-rpm-appimage:build}"
APPDIR="${APPDIR:-AppDir}"
OUT="${OUT:-${APP_NAME}-x86_64.AppImage}"

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

# Minimal 1x1 PNG for Icon= in .desktop (appimagetool




cat > "$APPDIR/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=${APP_NAME}
Icon=/usr/share/icons/hicolor/256x256@2/apps/*
Categories=Utility;
Terminal=false
EOF

wget -qO appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool

export ARCH="${ARCH:-x86_64}"
export VERSION="${VERSION:-1.0.0}"

./appimagetool --appimage-extract-and-run "$APPDIR" "$OUT"
