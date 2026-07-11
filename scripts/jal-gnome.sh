#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

flatpak_install \
  com.mattjakeman.ExtensionManager \
  app.devsuite.Ptyxis

log "Configurando Oh My Zsh no host"
ensure_oh_my_zsh
configure_host_zsh

log "Instalando pywal"
if has_command python3; then
  python3 -m pip install --user pywal || warn "falha ao instalar pywal via pip"
else
  warn "python3 nao encontrado; pywal nao instalado"
fi

# Adicionar restauracao de cores do pywal ao .zshrc e ao .bashrc.
# Grava nos dois porque o shell padrao pode ainda nao ser zsh (chsh pode
# falhar/nao persistir), e sem isso o pywal "para de funcionar" em
# qualquer terminal novo que suba em bash.
for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
  touch "$rcfile"
  sed -i "/^# >>> jal-pywal$/,/^# <<< jal-pywal$/d" "$rcfile"
  cat >> "$rcfile" <<'EOF'
# >>> jal-pywal
export PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.cache/wal/sequences" ] && (command cat "$HOME/.cache/wal/sequences" &)
[ -f "$HOME/.cache/wal/colors.sh" ] && source "$HOME/.cache/wal/colors.sh"
# <<< jal-pywal
EOF
done

# Garantir que pywal esta no PATH para uso imediato
export PATH="$HOME/.local/bin:$PATH"

# Rodar pywal com o wallpaper atual, se disponivel
if has_command wal && has_command gsettings; then
  _wp_raw=$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)
  _wp="${_wp_raw//\'/}"
  _wp="${_wp#file://}"
  if [ -f "$_wp" ]; then
    log "Aplicando pywal com wallpaper atual: ${_wp}"
    wal -i "$_wp" --backend haishoku 2>/dev/null || wal -i "$_wp" 2>/dev/null || warn "falha ao rodar wal"
  else
    warn "Wallpaper nao encontrado em '${_wp}'; rode 'wal -i <imagem>' manualmente"
  fi
else
  warn "wal ou gsettings nao encontrado; rode 'wal -i <imagem>' apos reiniciar o shell"
fi

# Mudar shell padrao para zsh
# chsh (pacote util-linux-user) nao vem nesta imagem; usa usermod como
# alternativa, que e o caminho recomendado em imagens atomicas.
if has_command zsh && [ "$SHELL" != "$(command -v zsh)" ]; then
  log "Mudando shell padrao para zsh"
  if has_command chsh; then
    chsh -s "$(command -v zsh)" || warn "falha ao mudar shell; rode manualmente: chsh -s $(command -v zsh)"
  else
    sudo usermod -s "$(command -v zsh)" "$(id -un)" \
      || warn "falha ao mudar shell; rode manualmente: sudo usermod -s $(command -v zsh) $(id -un)"
  fi
fi

log "Configurando preferencias GNOME"

set_gsetting() {
  local schema="$1"
  local key="$2"
  local value="$3"

  if [ "$(gsettings writable "$schema" "$key" 2>/dev/null || true)" = "true" ]; then
    gsettings set "$schema" "$key" "$value" || warn "falha ao configurar ${schema} ${key}"
  else
    warn "gsetting indisponivel: ${schema} ${key}"
  fi
}

set_custom_keybinding() {
  local slot="$1"
  local name="$2"
  local command="$3"
  local binding="$4"
  local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${slot}/"
  local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${path}"

  gsettings set "$schema" name "$name" || warn "falha ao configurar nome do atalho ${slot}"
  gsettings set "$schema" command "$command" || warn "falha ao configurar comando do atalho ${slot}"
  gsettings set "$schema" binding "$binding" || warn "falha ao configurar binding do atalho ${slot}"
}

configure_keyboard_shortcuts() {
  local custom_paths="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/']"

  log "Configurando atalhos de teclado GNOME"

  set_gsetting org.gnome.desktop.wm.keybindings begin-resize "['<Super>BackSpace']"
  set_gsetting org.gnome.desktop.wm.keybindings close "['<Super>w']"
  set_gsetting org.gnome.desktop.wm.keybindings maximize "['<Super>Up']"
  set_gsetting org.gnome.desktop.wm.keybindings minimize "['<Super>h']"
  set_gsetting org.gnome.desktop.wm.keybindings show-desktop "['<Primary><Super>d', '<Primary><Alt>d', '<Super>d']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-applications-backward "['<Shift><Super>Tab']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"
  set_gsetting org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Shift>F11']"

  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>2']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>3']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>4']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Super>5']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-6 "['<Super>6']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-7 "@as []"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-8 "@as []"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-9 "@as []"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-10 "@as []"

  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Super><Shift>1']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Super><Shift>2']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Super><Shift>3']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Super><Shift>4']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Super><Shift>5']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-6 "['<Super><Shift>6']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-7 "['<Super><Shift>7']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-8 "['<Super><Shift>8']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-9 "['<Super><Shift>9']"
  set_gsetting org.gnome.desktop.wm.keybindings move-to-workspace-10 "['<Super><Shift>0']"

  set_gsetting org.gnome.mutter.keybindings toggle-tiled-left "['<Super>Left']"
  set_gsetting org.gnome.mutter.keybindings toggle-tiled-right "['<Super>Right']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-1 "['<Alt>1']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-2 "['<Alt>2']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-3 "['<Alt>3']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-4 "['<Alt>4']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-5 "['<Alt>5']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-6 "['<Alt>6']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-7 "['<Alt>7']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-8 "['<Alt>8']"
  set_gsetting org.gnome.shell.keybindings switch-to-application-9 "['<Alt>9']"

  set_gsetting org.gnome.settings-daemon.plugins.media-keys terminal "['<Primary><Alt>t']"
  set_gsetting org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$custom_paths"

  set_custom_keybinding custom0 "Ulauncher" 'sh -c "pgrep -x ulauncher && { ulauncher-toggle || true; } || setsid -f ulauncher"' '<Super>space'
  set_custom_keybinding custom1 "Flameshot" 'sh -c -- "flameshot gui"' '<Control>Print'
  set_custom_keybinding custom2 "New Ptyxis Window" 'flatpak run app.devsuite.Ptyxis' '<Shift><Alt>2'
  set_custom_keybinding custom3 "New Chrome Window" 'google-chrome --new-window' '<Shift><Alt>1'
  set_custom_keybinding custom4 "Apple Brightness Down (ASDControl)" "sh -c 'asdcontrol \$(asdcontrol --detect /dev/usb/hiddev* 2>/dev/null | grep ^/dev/usb/hiddev | cut -d: -f1) -- -5000'" '<Control>F1'
  set_custom_keybinding custom5 "Apple Brightness Up (ASDControl)" "sh -c 'asdcontrol \$(asdcontrol --detect /dev/usb/hiddev* 2>/dev/null | grep ^/dev/usb/hiddev | cut -d: -f1) -- +5000'" '<Control>F2'
  set_custom_keybinding custom6 "Apple Brightness Max (ASDControl)" "sh -c 'asdcontrol \$(asdcontrol --detect /dev/usb/hiddev* 2>/dev/null | grep ^/dev/usb/hiddev | cut -d: -f1) -- +60000'" '<Control><Shift>F2'
}

if has_command gsettings; then
  gsettings set org.gnome.mutter dynamic-workspaces true || true
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  gsettings set org.gnome.desktop.interface clock-show-weekday true || true
  gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' || true
  configure_keyboard_shortcuts
else
  warn "gsettings nao encontrado; pulando ajustes GNOME"
fi

log "Astra Monitor ainda fica como etapa manual pelo Extension Manager."
log "jal-gnome finalizado"
