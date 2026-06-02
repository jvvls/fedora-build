#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${JAL_BAZZITE_REPO_OWNER:-jvvls}"
REPO_NAME="${JAL_BAZZITE_REPO_NAME:-jal-bazzite}"
REPO_BRANCH="${JAL_BAZZITE_REPO_BRANCH:-main}"
ARCHIVE_URL="${JAL_BAZZITE_ARCHIVE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_BRANCH}.tar.gz}"
INSTALL_DIR="${JAL_BAZZITE_HOME:-$HOME/.local/share/jal-bazzite}"
UBLUE_JUST_DIR="${JAL_BAZZITE_UBLUE_JUST_DIR:-/usr/share/ublue-os/just}"
UBLUE_CUSTOM_JUST="${UBLUE_JUST_DIR}/60-custom.just"

die() {
  echo "erro: $*" >&2
  exit 1
}

info() {
  echo "==> $*" >&2
}

warn() {
  echo "aviso: $*" >&2
}

cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  die "nao rode como root. Rode como seu usuario normal."
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "comando obrigatorio nao encontrado: $1"
}

script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd
}

find_local_source() {
  local dir
  dir="$(script_dir)"

  if [ -d "${dir}/recipes" ] && [ -d "${dir}/scripts" ]; then
    printf '%s\n' "$dir"
    return 0
  fi

  return 1
}

download_source() {
  require_command curl
  require_command tar

  TMP_DIR="$(mktemp -d)"
  info "Baixando ${ARCHIVE_URL}"
  curl -fsSL "$ARCHIVE_URL" -o "${TMP_DIR}/repo.tar.gz"
  tar -xzf "${TMP_DIR}/repo.tar.gz" -C "$TMP_DIR"

  local src
  src="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [ -n "$src" ] || die "nao consegui localizar o conteudo baixado"
  [ -d "${src}/recipes" ] || die "arquivo baixado nao contem recipes/"
  [ -d "${src}/scripts" ] || die "arquivo baixado nao contem scripts/"

  printf '%s\n' "$src"
}

install_files() {
  local src="$1"

  info "Instalando recipes em ${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}/recipes" "${INSTALL_DIR}/scripts"

  cp -R "${src}/recipes/." "${INSTALL_DIR}/recipes/"
  cp -R "${src}/scripts/." "${INSTALL_DIR}/scripts/"
  chmod +x "${INSTALL_DIR}"/scripts/*.sh
}

register_ujust_import() {
  local import_line="import? '${INSTALL_DIR}/recipes/jal.just'"

  if ! command -v ujust >/dev/null 2>&1; then
    warn "ujust nao encontrado. Os arquivos foram instalados, mas nao registrei no Bazzite."
    return 0
  fi

  info "Registrando recipes no ujust"

  if sudo mkdir -p "$UBLUE_JUST_DIR"; then
    if sudo test -f "$UBLUE_CUSTOM_JUST" && sudo grep -Fxq "$import_line" "$UBLUE_CUSTOM_JUST"; then
      info "Import ja existe em ${UBLUE_CUSTOM_JUST}"
      return 0
    fi

    if printf '\n%s\n' "$import_line" | sudo tee -a "$UBLUE_CUSTOM_JUST" >/dev/null; then
      info "Import adicionado em ${UBLUE_CUSTOM_JUST}"
      return 0
    fi
  fi

  warn "nao consegui escrever em ${UBLUE_CUSTOM_JUST}."
  warn "Se o sistema estiver bloqueando /usr, registre manualmente este import:"
  warn "  ${import_line}"
}

main() {
  local src

  if src="$(find_local_source)"; then
    info "Usando arquivos locais em ${src}"
  else
    src="$(download_source)"
  fi

  install_files "$src"
  register_ujust_import

  echo
  info "Pronto."
  echo "Use:"
  echo "  ujust jal-base"
  echo "  ujust jal-gaming"
  echo "  ujust jal-dev"
  echo "  ujust jal-dataviva"
  echo "  ujust jal-gnome"
  echo "  ujust jal-all"
}

main "$@"
