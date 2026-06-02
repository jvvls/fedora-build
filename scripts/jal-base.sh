#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

flatpak_install \
  com.brave.Browser \
  com.discordapp.Discord \
  com.spotify.Client \
  com.stremio.Stremio \
  io.dbeaver.DBeaverCommunity \
  com.mongodb.Compass \
  com.mattjakeman.ExtensionManager

run_ujust_if_available install-jetbrains-toolbox || true

brew_install_if_available \
  git \
  gh \
  zsh \
  fzf \
  ripgrep \
  fd \
  bat \
  eza \
  jq \
  btop \
  fastfetch \
  direnv \
  starship

ensure_oh_my_zsh
configure_host_zsh

log "jal-base finalizado"
