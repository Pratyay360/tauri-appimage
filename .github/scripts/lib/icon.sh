#!/usr/bin/env bash

SCALABLE_ICON_SCORE=100000

create_default_desktop_file() {
  local appdir="$1"
  local app_name="$2"
  local desktop_path="$appdir/${app_name}.desktop"

  cat > "$desktop_path" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${app_name}
Exec=${app_name}
Icon=${app_name}
Categories=Utility;
Terminal=false
DESKTOP

  echo "$desktop_path"
}

discover_primary_desktop_file() {
  local appdir="$1"
  local app_name="$2"
  local desktop_path

  desktop_path="$(find "$appdir/usr/share/applications" -type f -name '*.desktop' 2>/dev/null | LC_ALL=C sort | head -n1 || true)"

  if [[ -z "$desktop_path" ]]; then
    desktop_path="$(find "$appdir" -type f -name '*.desktop' 2>/dev/null | LC_ALL=C sort | head -n1 || true)"
  fi

  if [[ -z "$desktop_path" ]]; then
    desktop_path="$(create_default_desktop_file "$appdir" "$app_name")"
  fi

  echo "$desktop_path"
}

extract_icon_name_from_desktop() {
  local desktop_path="$1"

  awk '
    /^[[:space:]]*Icon[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*Icon[[:space:]]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$desktop_path"
}

find_hicolor_icon_candidate() {
  local appdir="$1"
  local icon_name="$2"
  local best_candidate=""
  local best_score=-1

  while IFS= read -r -d '' candidate; do
    local size_dir
    local score=0

    size_dir="$(basename "$(dirname "$(dirname "$candidate")")")"

    if [[ "$size_dir" =~ ^([0-9]+)x([0-9]+)$ ]]; then
      score="${BASH_REMATCH[1]}"
    elif [[ "$size_dir" == "scalable" ]]; then
      score=$SCALABLE_ICON_SCORE
    fi

    if (( score > best_score )); then
      best_score=$score
      best_candidate="$candidate"
    fi
  done < <(
    find "$appdir/usr/share/icons/hicolor" -type f \
      \( -name "${icon_name}.png" -o -name "${icon_name}.svg" -o -name "${icon_name}.xpm" \) \
      -path '*/apps/*' -print0 2>/dev/null
  )

  echo "$best_candidate"
}

find_pixmaps_icon_candidate() {
  local appdir="$1"
  local icon_name="$2"
  local ext

  for ext in png svg xpm; do
    local candidate
    candidate="$(find "$appdir/usr/share/pixmaps" -type f -name "${icon_name}.${ext}" 2>/dev/null | LC_ALL=C sort | head -n1 || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  echo ""
}

find_icon_candidate_in_rootfs() {
  local appdir="$1"
  local icon_name="$2"
  local candidate

  candidate="$(find_hicolor_icon_candidate "$appdir" "$icon_name")"
  if [[ -z "$candidate" ]]; then
    candidate="$(find_pixmaps_icon_candidate "$appdir" "$icon_name")"
  fi

  echo "$candidate"
}

resolve_icon_extension_from_url() {
  local app_icon_url="$1"
  local url_path
  local ext

  url_path="${app_icon_url%%\?*}"
  url_path="${url_path%%\#*}"
  ext="${url_path##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    png|svg|xpm)
      echo "$ext"
      ;;
    *)
      echo "png"
      ;;
  esac
}

materialize_appdir_icon() {
  local appdir="$1"
  local icon_name="$2"
  local app_name="$3"
  local app_icon_url="${4:-}"
  local final_icon_path=""
  local candidate=""
  local ext

  for ext in png svg xpm; do
    if [[ -f "$appdir/${icon_name}.${ext}" ]]; then
      final_icon_path="$appdir/${icon_name}.${ext}"
      echo "$final_icon_path"
      return 0
    fi
  done

  candidate="$(find_icon_candidate_in_rootfs "$appdir" "$icon_name")"

  if [[ -z "$candidate" && "$icon_name" != "$app_name" ]]; then
    candidate="$(find_icon_candidate_in_rootfs "$appdir" "$app_name")"
  fi

  if [[ -n "$candidate" ]]; then
    ext="${candidate##*.}"
    final_icon_path="$appdir/${icon_name}.${ext}"
    cp "$candidate" "$final_icon_path"
    echo "$final_icon_path"
    return 0
  fi

  if [[ -n "$app_icon_url" ]]; then
    local mime_type=""
    ext="$(resolve_icon_extension_from_url "$app_icon_url")"
    final_icon_path="$appdir/${icon_name}.${ext}"
    if ! wget --timeout=30 --tries=2 --max-redirect=3 -qO "$final_icon_path" "$app_icon_url"; then
      rm -f "$final_icon_path"
      echo "ERROR: Failed to download icon from APP_ICON_URL='$app_icon_url' (network/URL error)." >&2
      return 1
    fi
    if [[ ! -s "$final_icon_path" ]]; then
      rm -f "$final_icon_path"
      echo "ERROR: Downloaded icon from APP_ICON_URL='$app_icon_url' is empty." >&2
      return 1
    fi
    if command -v file >/dev/null 2>&1; then
      mime_type="$(file -b --mime-type "$final_icon_path" || true)"
      case "$mime_type" in
        image/png|image/svg+xml|image/x-xpixmap|text/plain|text/xml)
          ;;
        *)
          rm -f "$final_icon_path"
          echo "ERROR: Downloaded icon from APP_ICON_URL='$app_icon_url' is not a supported image type (detected '$mime_type')." >&2
          return 1
          ;;
      esac
    fi
    if [[ "$ext" == "png" && "$mime_type" == "image/svg+xml" ]]; then
      mv "$final_icon_path" "$appdir/${icon_name}.svg"
      final_icon_path="$appdir/${icon_name}.svg"
    elif [[ "$ext" == "png" && "$mime_type" == "image/x-xpixmap" ]]; then
      mv "$final_icon_path" "$appdir/${icon_name}.xpm"
      final_icon_path="$appdir/${icon_name}.xpm"
    elif [[ "$ext" == "svg" && "$mime_type" == "image/png" ]]; then
      mv "$final_icon_path" "$appdir/${icon_name}.png"
      final_icon_path="$appdir/${icon_name}.png"
    elif [[ "$ext" == "xpm" && "$mime_type" == "image/png" ]]; then
      mv "$final_icon_path" "$appdir/${icon_name}.png"
      final_icon_path="$appdir/${icon_name}.png"
    fi

    if [[ ! -s "$final_icon_path" ]]; then
      rm -f "$final_icon_path"
      echo "ERROR: Downloaded icon materialization failed for APP_ICON_URL='$app_icon_url'." >&2
      return 1
    fi
    echo "$final_icon_path"
    return 0
  fi

  echo "ERROR: Icon '${icon_name}' from desktop file is missing." >&2
  echo "Expected one of '$appdir/${icon_name}.png', '$appdir/${icon_name}.svg', or '$appdir/${icon_name}.xpm'." >&2
  echo "Could not find matching icons in '$appdir/usr/share/icons/hicolor' or '$appdir/usr/share/pixmaps' (also tried APP_NAME='${app_name}')." >&2
  echo "Set APP_ICON_URL to a direct icon URL (.png/.svg/.xpm)." >&2
  return 1
}
