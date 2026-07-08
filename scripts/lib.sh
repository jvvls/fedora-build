#!/usr/bin/env bash

set -euo pipefail

SPARK_VERSION="${SPARK_VERSION:-3.5.1}"
SPARK_PACKAGE="spark-${SPARK_VERSION}-bin-hadoop3"
SPARK_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_PACKAGE}.tgz"

log() {
  echo "==> $*"
}

warn() {
  echo "aviso: $*" >&2
}

die() {
  echo "erro: $*" >&2
  exit 1
}

ensure_not_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    die "nao rode como root. Rode como seu usuario normal."
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

ensure_flathub() {
  has_command flatpak || die "flatpak nao encontrado"
  log "Garantindo Flathub"
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

flatpak_install() {
  ensure_flathub
  log "Instalando Flatpaks"
  flatpak install --user -y flathub "$@"
}

brew_install_if_available() {
  if ! has_command brew; then
    warn "brew nao encontrado; pulando pacotes Homebrew: $*"
    return 0
  fi

  log "Instalando pacotes via Homebrew"
  brew install "$@"
}

rpm_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

install_host_rpms() {
  local missing=()
  local pkg

  has_command rpm || return 0

  for pkg in "$@"; do
    if ! rpm_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "Pacotes RPM do host ja estao presentes: $*"
    return 0
  fi

  if has_command rpm-ostree; then
    log "Instalando RPMs no host via rpm-ostree: ${missing[*]}"
    sudo rpm-ostree install "${missing[@]}"
    warn "rpm-ostree pode exigir reboot para ativar os pacotes."
  elif has_command dnf; then
    log "Instalando RPMs no host via dnf: ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
  else
    warn "sem rpm-ostree/dnf; instale manualmente: ${missing[*]}"
  fi
}

ujust_has_recipe() {
  has_command ujust || return 1
  ujust --summary 2>/dev/null | tr ' ' '\n' | grep -Fxq "$1"
}

run_ujust_if_available() {
  local recipe="$1"

  if ujust_has_recipe "$recipe"; then
    log "Executando ujust ${recipe}"
    ujust "$recipe"
  else
    warn "recipe ujust nao encontrado: ${recipe}"
  fi
}

ensure_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh ja esta instalado"
    return 0
  fi

  has_command curl || die "curl nao encontrado"
  log "Instalando Oh My Zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

write_marker_block() {
  local file="$1"
  local start="# >>> jal-bazzite"
  local end="# <<< jal-bazzite"

  touch "$file"
  sed -i "/^${start}$/,/^${end}$/d" "$file"
  {
    echo "$start"
    sed '/^$/N;/^\n$/D'
    echo "$end"
  } >>"$file"
}

configure_host_zsh() {
  log "Configurando bloco JAL no ~/.zshrc"
  write_marker_block "$HOME/.zshrc" <<'EOF'
export PATH="$HOME/.linuxbrew/bin:$HOME/.local/bin:$PATH"

ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(
  git
  docker
  npm
  python
  pip
  fzf
)

[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

eval "$(starship init zsh)" 2>/dev/null || true
eval "$(direnv hook zsh)" 2>/dev/null || true

alias ll="eza -la --icons"
alias cat="bat"
alias top="btop"
alias update="ujust update"
alias dev="distrobox enter dev"
alias dataviva="distrobox enter dataviva"
EOF
}

ensure_distrobox() {
  has_command distrobox || die "distrobox nao encontrado. No Bazzite DX ele deveria estar disponivel."
}

distrobox_exists() {
  local name="$1"
  distrobox list 2>/dev/null | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}' | grep -Fxq "$name"
}

create_fedora_box() {
  local name="$1"

  ensure_distrobox

  if distrobox_exists "$name"; then
    log "Distrobox ${name} ja existe"
    return 0
  fi

  log "Criando distrobox ${name}"
  distrobox create --name "$name" --image fedora:latest --yes
}

setup_common_box() {
  local name="$1"

  log "Configurando base comum em ${name}"
  distrobox enter "$name" -- bash -lc '
    set -euo pipefail

    sudo dnf upgrade -y
    sudo dnf install -y \
      zsh \
      git \
      gh \
      curl \
      wget \
      unzip \
      zip \
      tar \
      gcc \
      gcc-c++ \
      make \
      cmake \
      python3 \
      python3-pip \
      python3-virtualenv \
      maven \
      fzf \
      ripgrep \
      fd-find \
      bat \
      eza \
      jq \
      btop \
      fastfetch \
      direnv \
      util-linux

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi

    touch "$HOME/.zshrc"
    sed -i "/^# >>> jal-bazzite$/,/^# <<< jal-bazzite$/d" "$HOME/.zshrc"
    cat >> "$HOME/.zshrc" <<'"'"'EOF'"'"'
# >>> jal-bazzite
ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(
  git
  docker
  npm
  python
  pip
  fzf
)

[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

eval "$(direnv hook zsh)" 2>/dev/null || true

alias ll="eza -la --icons"
alias cat="bat"
alias top="btop"
alias python="python3"
# <<< jal-bazzite
EOF

    sudo chsh -s /usr/bin/zsh "$USER" || true
  '
}

setup_dev_box() {
  local name="$1"

  log "Instalando stack dev em ${name}"
  distrobox enter "$name" -- bash -lc '
    set -euo pipefail

    sudo dnf install -y \
      java-17-openjdk \
      java-17-openjdk-devel \
      nodejs \
      npm \
      golang \
      gradle

    touch "$HOME/.zshrc"
    sed -i "/^# >>> jal-dev$/,/^# <<< jal-dev$/d" "$HOME/.zshrc"
    cat >> "$HOME/.zshrc" <<'"'"'EOF'"'"'
# >>> jal-dev
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="$JAVA_HOME/bin:$PATH"
# <<< jal-dev
EOF
  '
}

setup_dataviva_box() {
  local name="$1"

  log "Instalando stack DataViva em ${name}"
  distrobox enter "$name" -- bash -lc "
    set -euo pipefail

    sudo dnf install -y \
      java-11-openjdk \
      java-11-openjdk-devel \
      python3 \
      python3-pip \
      maven

    mkdir -p \"\$HOME/apps\"

    if [ ! -d \"\$HOME/apps/${SPARK_PACKAGE}\" ]; then
      wget -c \"${SPARK_URL}\" -O \"/tmp/${SPARK_PACKAGE}.tgz\"
      tar -xzf \"/tmp/${SPARK_PACKAGE}.tgz\" -C \"\$HOME/apps\"
    fi

    ln -sfn \"\$HOME/apps/${SPARK_PACKAGE}\" \"\$HOME/apps/spark\"

    touch \"\$HOME/.zshrc\"
    sed -i \"/^# >>> jal-dataviva$/,/^# <<< jal-dataviva$/d\" \"\$HOME/.zshrc\"
    cat >> \"\$HOME/.zshrc\" <<'EOF'
# >>> jal-dataviva
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export SPARK_HOME=\$HOME/apps/spark
export PATH=\$JAVA_HOME/bin:\$SPARK_HOME/bin:\$SPARK_HOME/sbin:\$PATH
# <<< jal-dataviva
EOF
  "
}
