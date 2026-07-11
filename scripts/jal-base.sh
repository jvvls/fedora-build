#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

ensure_bazzite_dx

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

install_proton_ge() {
  local compat_dir="$HOME/.local/share/Steam/compatibilitytools.d"

  if ! has_command curl || ! has_command jq || ! has_command tar; then
    warn "curl/jq/tar nao encontrados; pulando instalacao do Proton GE"
    return 0
  fi

  log "Verificando ultima versao do Proton GE"
  local release_info tag download_url tarball
  release_info="$(curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>/dev/null)" || release_info=""
  tag="$(printf '%s' "$release_info" | jq -r '.tag_name // empty' 2>/dev/null)"
  if [ -z "$tag" ]; then
    warn "nao consegui consultar releases do Proton GE"
    return 0
  fi

  if [ -d "${compat_dir}/${tag}" ]; then
    log "Proton GE ${tag} ja instalado"
    return 0
  fi

  download_url="$(printf '%s' "$release_info" | jq -r '[.assets[] | select(.name | endswith(".tar.gz") and (contains("aarch64") | not))][0].browser_download_url // empty' 2>/dev/null)"
  if [ -z "$download_url" ]; then
    warn "nao encontrei pacote do Proton GE ${tag}"
    return 0
  fi

  mkdir -p "$compat_dir"
  tarball="$(mktemp --suffix=.tar.gz)"
  log "Baixando Proton GE ${tag}"
  if curl -fsSL "$download_url" -o "$tarball"; then
    tar -xf "$tarball" -C "$compat_dir" || warn "falha ao extrair Proton GE ${tag}"
  else
    warn "falha ao baixar Proton GE ${tag}"
  fi
  rm -f "$tarball"
}

install_proton_ge

log "jal-base finalizado"
