#!/usr/bin/env bash

set -euo pipefail

SPARK_VERSION="${SPARK_VERSION:-3.5.1}"
SPARK_PACKAGE="spark-${SPARK_VERSION}-bin-hadoop3"
SPARK_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_PACKAGE}.tgz"

HADOOP_VERSION="${HADOOP_VERSION:-3.3.6}"
HADOOP_PACKAGE="hadoop-${HADOOP_VERSION}"
HADOOP_URL="https://archive.apache.org/dist/hadoop/common/${HADOOP_PACKAGE}/${HADOOP_PACKAGE}.tar.gz"

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
  rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
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

eval "$(direnv hook zsh)" 2>/dev/null || true

alias ll="eza -la --icons"
alias cat="bat"
alias top="btop"
alias update="ujust update"
alias dev="distrobox enter dev"
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
      curl \
      nodejs \
      npm \
      golang

    # JDK 17 via SDKMan: o Fedora 44 nao empacota mais java-17-openjdk no
    # dnf, e o JDK 17 e exclusivo deste container (o host usa JDK 11).
    if [ ! -d "$HOME/.sdkman" ]; then
      curl -s "https://get.sdkman.io" | bash
    fi

    set +u
    # shellcheck disable=SC1091
    source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
    if command -v sdk >/dev/null 2>&1; then
      java_id="$(sdk list java 2>/dev/null | grep -oE "17\.[0-9]+\.[0-9]+-tem" | head -n1)"
      if [ -n "$java_id" ]; then
        sdk install java "$java_id" || true
      fi
    fi
    set -u

    # Instalar VSCode via repositorio Microsoft
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" \
      | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    sudo dnf install -y code

    touch "$HOME/.zshrc"
    sed -i "/^# >>> jal-dev$/,/^# <<< jal-dev$/d" "$HOME/.zshrc"
    cat >> "$HOME/.zshrc" <<'"'"'EOF'"'"'
# >>> jal-dev
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && source "$HOME/.sdkman/bin/sdkman-init.sh"
export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
export PATH="$JAVA_HOME/bin:$PATH"
# <<< jal-dev
EOF

    # Exportar VSCode para o sistema host
    command -v distrobox-export >/dev/null 2>&1 && distrobox-export --app code || true
  '
}

setup_dataviva_host() {
  log "Instalando stack DataViva no host"

  # Java via SDKMan (nao requer root nem rpm-ostree)
  if [ ! -d "$HOME/.sdkman" ]; then
    has_command curl || die "curl nao encontrado"
    log "Instalando SDKMan"
    curl -s "https://get.sdkman.io" | bash
  fi

  # sdkman-init.sh e os comandos `sdk` referenciam variaveis nao definidas
  # (ZSH_VERSION, PAGER etc.) e quebram com set -u; desativa nounset so
  # neste trecho.
  set +u
  # shellcheck disable=SC1091
  source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true

  if has_command sdk; then
    local java_id
    java_id="$(sdk list java 2>/dev/null | grep -oE '11\.[0-9]+\.[0-9]+-tem' | head -n1)"
    if [ -n "$java_id" ]; then
      sdk install java "$java_id" || true
    else
      warn "nao encontrei build Temurin 11 no SDKMan; rode 'sdk list java' e instale manualmente"
    fi
  else
    warn "sdk nao disponivel apos instalacao; reinicie o shell e rode sdk install java 11"
  fi
  set -u

  # Spark
  mkdir -p "$HOME/apps"
  if [ ! -d "$HOME/apps/${SPARK_PACKAGE}" ]; then
    log "Baixando Apache Spark ${SPARK_VERSION}"
    wget -c "${SPARK_URL}" -O "/tmp/${SPARK_PACKAGE}.tgz"
    tar -xzf "/tmp/${SPARK_PACKAGE}.tgz" -C "$HOME/apps"
  fi
  ln -sfn "$HOME/apps/${SPARK_PACKAGE}" "$HOME/apps/spark"

  # Hadoop
  mkdir -p "$HOME/apps"
  if [ ! -d "$HOME/apps/${HADOOP_PACKAGE}" ]; then
    log "Baixando Apache Hadoop ${HADOOP_VERSION}"
    wget -c "${HADOOP_URL}" -O "/tmp/${HADOOP_PACKAGE}.tar.gz"
    tar -xzf "/tmp/${HADOOP_PACKAGE}.tar.gz" -C "$HOME/apps"
  fi
  ln -sfn "$HOME/apps/${HADOOP_PACKAGE}" "$HOME/apps/hadoop"

  # Python deps (sem container)
  has_command python3 || warn "python3 nao encontrado no host"
  if has_command python3; then
    python3 -m pip install --user pyspark || warn "falha ao instalar pyspark via pip"
  fi

  # Bloco .zshrc
  touch "$HOME/.zshrc"
  sed -i "/^# >>> jal-dataviva$/,/^# <<< jal-dataviva$/d" "$HOME/.zshrc"
  cat >> "$HOME/.zshrc" <<'EOF'
# >>> jal-dataviva
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && source "$HOME/.sdkman/bin/sdkman-init.sh"
export SPARK_HOME="$HOME/apps/spark"
export HADOOP_HOME="$HOME/apps/hadoop"
export PATH="$SPARK_HOME/bin:$SPARK_HOME/sbin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"
# <<< jal-dataviva
EOF
}

ensure_bazzite_dx() {
  log "Verificando imagem bazzite-dx"

  local target="bazzite-dx-nvidia-gnome:stable"

  # Ja esta na imagem dx?
  if rpm-ostree status 2>/dev/null | grep -q "bazzite-dx"; then
    log "Ja rodando bazzite-dx. Nenhuma acao necessaria."
    return 0
  fi

  if has_command brh; then
    log "Fazendo rebase para ${target} via brh"
    brh rebase "${target}"
  elif has_command rpm-ostree; then
    log "Fazendo rebase para ${target} via rpm-ostree"
    sudo rpm-ostree rebase "ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-dx-nvidia-gnome:stable"
  else
    warn "brh e rpm-ostree nao encontrados; rebase nao realizado"
    return 1
  fi

  warn "Rebase agendado. E necessario reiniciar o sistema para aplicar a nova imagem."
}
