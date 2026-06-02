#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

flatpak_install \
  com.heroicgameslauncher.hgl \
  net.davidotek.pupgui2

install_host_rpms \
  mangohud \
  gamescope \
  nvtop

log "jal-gaming finalizado"
