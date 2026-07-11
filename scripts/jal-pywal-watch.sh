#!/usr/bin/env bash
set -uo pipefail

# systemd --user nao inclui ~/.local/bin no PATH por padrao, e e la que o
# pip instala o binario do wal.
export PATH="$HOME/.local/bin:$PATH"

apply_wallpaper() {
  local uri="$1"
  local path="${uri//\'/}"
  path="${path#file://}"

  [ -f "$path" ] || return 0
  command -v wal >/dev/null 2>&1 || return 0

  wal -i "$path" --backend haishoku 2>/dev/null || wal -i "$path" 2>/dev/null || true
}

gsettings monitor org.gnome.desktop.background 2>/dev/null |
while IFS= read -r line; do
  case "$line" in
    picture-uri:*|picture-uri-dark:*)
      uri="${line#*: }"
      apply_wallpaper "$uri"
      ;;
  esac
done
