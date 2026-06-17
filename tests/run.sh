#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TMP_DIRS=()

cleanup() {
  local dir
  for dir in "${TMP_DIRS[@]:-}"; do
    [ -d "$dir" ] && rm -rf "$dir"
  done
  return 0
}
trap cleanup EXIT

note() {
  printf '==> %s\n' "$*"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok - %s\n' "$*"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$*" >&2
}

skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf 'skip - %s\n' "$*"
}

run_test() {
  local name="$1"
  shift

  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

tmpdir() {
  local dir
  dir="$(mktemp -d)"
  TMP_DIRS+=("$dir")
  printf '%s\n' "$dir"
}

assert_file_exists() {
  [ -e "$1" ] || {
    printf 'expected file to exist: %s\n' "$1" >&2
    return 1
  }
}

assert_executable() {
  [ -x "$1" ] || {
    printf 'expected file to be executable: %s\n' "$1" >&2
    return 1
  }
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq "$expected" "$file" || {
    printf 'expected %s to contain: %s\n' "$file" "$expected" >&2
    return 1
  }
}

assert_equals() {
  local expected="$1"
  local actual="$2"

  [ "$expected" = "$actual" ] || {
    printf 'expected [%s], got [%s]\n' "$expected" "$actual" >&2
    return 1
  }
}

write_mock() {
  local dir="$1"
  local name="$2"
  local body="$3"
  local path="${dir}/${name}"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf '%s\n' "$body"
  } >"$path"
  chmod +x "$path"
}

make_common_mocks() {
  local dir="$1"

  mkdir -p "$dir"

  write_mock "$dir" sudo '
printf "sudo" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
if [ "${JAL_TEST_SUDO_FAIL_TEE:-0}" = "1" ] && [ "${1:-}" = "tee" ]; then
  printf "sudo mock refusing tee\n" >&2
  exit 1
fi
exec "$@"
'

  write_mock "$dir" ujust '
if [ "${1:-}" = "--summary" ]; then
  printf "install-jetbrains-toolbox jal-base jal-gaming jal-dev jal-dataviva jal-gnome jal-all\n"
  exit 0
fi
printf "ujust" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" flatpak '
printf "flatpak" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" brew '
printf "brew" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" rpm '
printf "rpm" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
if [ "${1:-}" = "-q" ]; then
  exit 1
fi
'

  write_mock "$dir" rpm-ostree '
printf "rpm-ostree" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" dnf '
printf "dnf" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" curl '
printf "curl" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" gsettings '
if [ "${1:-}" = "writable" ]; then
  printf "true\n"
  exit 0
fi
printf "gsettings" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
'

  write_mock "$dir" distrobox '
printf "distrobox" >> "${JAL_TEST_LOG:?}"
printf " %q" "$@" >> "${JAL_TEST_LOG:?}"
printf "\n" >> "${JAL_TEST_LOG:?}"
if [ "${1:-}" = "list" ]; then
  printf "ID | NAME | STATUS | IMAGE\n"
fi
'
}

test_shell_syntax() {
  local script

  bash -n "${ROOT_DIR}/install.sh"
  for script in "${ROOT_DIR}"/scripts/*.sh; do
    bash -n "$script"
  done
  for script in "${ROOT_DIR}"/tests/*.sh; do
    bash -n "$script"
  done
}

test_recipe_graph() {
  local import
  local recipe
  local profile

  while IFS= read -r import; do
    assert_file_exists "${ROOT_DIR}/recipes/${import}"
  done < <(awk '/^import / { gsub(/"/, "", $2); print $2 }' "${ROOT_DIR}/recipes/jal.just")

  for profile in base gaming dev dataviva gnome; do
    recipe="${ROOT_DIR}/recipes/jal-${profile}.just"
    assert_file_exists "$recipe"
    assert_contains "$recipe" "scripts/jal-${profile}.sh"
    assert_file_exists "${ROOT_DIR}/scripts/jal-${profile}.sh"
  done

  assert_contains "${ROOT_DIR}/recipes/jal-all.just" "jal-all: jal-base jal-gaming jal-dev jal-dataviva jal-gnome"

  if command -v just >/dev/null 2>&1; then
    (cd "${ROOT_DIR}/recipes" && just --justfile jal.just --summary >/dev/null)
  else
    skip "just nao instalado; pulando validacao nativa dos recipes"
  fi
}

test_install_local_source_is_idempotent() {
  local tmp
  local mock_bin
  local home
  local install_dir
  local ublue_dir
  local import_line
  local count

  tmp="$(tmpdir)"
  mock_bin="${tmp}/bin"
  home="${tmp}/home"
  install_dir="${tmp}/install"
  ublue_dir="${tmp}/ublue-just"
  import_line="import? '${install_dir}/recipes/jal.just'"

  mkdir -p "$home"
  make_common_mocks "$mock_bin"
  : >"${tmp}/commands.log"

  env \
    HOME="$home" \
    JAL_BAZZITE_HOME="$install_dir" \
    JAL_BAZZITE_UBLUE_JUST_DIR="$ublue_dir" \
    JAL_TEST_LOG="${tmp}/commands.log" \
    PATH="${mock_bin}:${PATH}" \
    bash "${ROOT_DIR}/install.sh" >/dev/null

  assert_file_exists "${install_dir}/recipes/jal.just"
  assert_file_exists "${install_dir}/scripts/lib.sh"
  assert_executable "${install_dir}/scripts/jal-base.sh"
  assert_contains "${ublue_dir}/60-custom.just" "$import_line"

  env \
    HOME="$home" \
    JAL_BAZZITE_HOME="$install_dir" \
    JAL_BAZZITE_UBLUE_JUST_DIR="$ublue_dir" \
    JAL_TEST_LOG="${tmp}/commands.log" \
    PATH="${mock_bin}:${PATH}" \
    bash "${ROOT_DIR}/install.sh" >/dev/null

  count="$(grep -Fx "$import_line" "${ublue_dir}/60-custom.just" | wc -l | tr -d ' ')"
  assert_equals "1" "$count"
}

test_install_download_source_with_mocked_curl() {
  local tmp
  local mock_bin
  local home
  local install_dir
  local ublue_dir
  local archive_root
  local archive
  local isolated_installer

  tmp="$(tmpdir)"
  mock_bin="${tmp}/bin"
  home="${tmp}/home"
  install_dir="${tmp}/install"
  ublue_dir="${tmp}/ublue-just"
  archive_root="${tmp}/archive/jal-bazzite-main"
  archive="${tmp}/jal-bazzite-main.tar.gz"
  isolated_installer="${tmp}/installer/install.sh"

  mkdir -p "$home" "$archive_root" "$(dirname "$isolated_installer")"
  cp -R "${ROOT_DIR}/recipes" "$archive_root/"
  cp -R "${ROOT_DIR}/scripts" "$archive_root/"
  tar -czf "$archive" -C "${tmp}/archive" jal-bazzite-main
  cp "${ROOT_DIR}/install.sh" "$isolated_installer"

  make_common_mocks "$mock_bin"
  write_mock "$mock_bin" curl '
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      shift
      out="$1"
      ;;
  esac
  shift || true
done
[ -n "$out" ] || {
  printf "curl mock expected -o output\n" >&2
  exit 1
}
cp "${JAL_TEST_ARCHIVE:?}" "$out"
'
  : >"${tmp}/commands.log"

  env \
    HOME="$home" \
    JAL_BAZZITE_HOME="$install_dir" \
    JAL_BAZZITE_UBLUE_JUST_DIR="$ublue_dir" \
    JAL_BAZZITE_ARCHIVE_URL="https://example.invalid/jal-bazzite.tar.gz" \
    JAL_TEST_ARCHIVE="$archive" \
    JAL_TEST_LOG="${tmp}/commands.log" \
    PATH="${mock_bin}:${PATH}" \
    bash "$isolated_installer" >/dev/null

  assert_file_exists "${install_dir}/recipes/jal.just"
  assert_file_exists "${install_dir}/scripts/jal-dev.sh"
  assert_executable "${install_dir}/scripts/jal-dev.sh"
  assert_contains "${ublue_dir}/60-custom.just" "import? '${install_dir}/recipes/jal.just'"
}

test_install_falls_back_to_ujust_wrapper() {
  local tmp
  local mock_bin
  local home
  local install_dir
  local ublue_dir
  local wrapper

  tmp="$(tmpdir)"
  mock_bin="${tmp}/bin"
  home="${tmp}/home"
  install_dir="${tmp}/install"
  ublue_dir="${tmp}/readonly-ublue-just"
  wrapper="${tmp}/usr-local-bin/ujust"

  mkdir -p "$home"
  make_common_mocks "$mock_bin"
  : >"${tmp}/commands.log"

  env \
    HOME="$home" \
    JAL_BAZZITE_HOME="$install_dir" \
    JAL_BAZZITE_UBLUE_JUST_DIR="$ublue_dir" \
    JAL_BAZZITE_UJUST_WRAPPER="$wrapper" \
    JAL_TEST_SUDO_FAIL_TEE=1 \
    JAL_TEST_LOG="${tmp}/commands.log" \
    PATH="${mock_bin}:${PATH}" \
    bash "${ROOT_DIR}/install.sh" >/dev/null

  assert_file_exists "${install_dir}/recipes/jal.just"
  assert_executable "$wrapper"
  assert_contains "$wrapper" "system_ujust=\"/usr/bin/ujust\""
  assert_contains "$wrapper" "jal-*|jal-help)"
  assert_contains "${tmp}/commands.log" "sudo tee -a ${ublue_dir}/60-custom.just"
  assert_contains "${tmp}/commands.log" "sudo install -m 0755"
}

test_profile_scripts_dry_run_with_mocks() {
  local tmp
  local mock_bin
  local home
  local script

  tmp="$(tmpdir)"
  mock_bin="${tmp}/bin"
  home="${tmp}/home"

  mkdir -p "$home/.oh-my-zsh"
  make_common_mocks "$mock_bin"
  : >"${tmp}/commands.log"

  for script in \
    "${ROOT_DIR}/scripts/jal-base.sh" \
    "${ROOT_DIR}/scripts/jal-gaming.sh" \
    "${ROOT_DIR}/scripts/jal-dev.sh" \
    "${ROOT_DIR}/scripts/jal-dataviva.sh" \
    "${ROOT_DIR}/scripts/jal-gnome.sh"; do
    env \
      HOME="$home" \
      JAL_TEST_LOG="${tmp}/commands.log" \
      PATH="${mock_bin}:${PATH}" \
      bash "$script" >/dev/null
  done

  assert_contains "${tmp}/commands.log" "flatpak install -y flathub com.brave.Browser"
  assert_contains "${tmp}/commands.log" "rpm-ostree install mangohud gamescope nvtop"
  assert_contains "${tmp}/commands.log" "distrobox create --name dev --image fedora:latest --yes"
  assert_contains "${tmp}/commands.log" "distrobox create --name dataviva --image fedora:latest --yes"
  assert_contains "${tmp}/commands.log" "gsettings set org.gnome.desktop.interface color-scheme prefer-dark"
  assert_contains "${home}/.zshrc" "# >>> jal-bazzite"
}

test_marker_block_is_idempotent() {
  local tmp
  local target
  local count

  tmp="$(tmpdir)"
  target="${tmp}/zshrc"

  (
    # shellcheck source=scripts/lib.sh
    source "${ROOT_DIR}/scripts/lib.sh"

    printf 'before\n# >>> jal-bazzite\nold\n# <<< jal-bazzite\nafter\n' >"$target"
    write_marker_block "$target" <<'EOF'
new line 1

new line 2
EOF
    write_marker_block "$target" <<'EOF'
new line 1

new line 2
EOF
  )

  assert_contains "$target" "before"
  assert_contains "$target" "after"
  assert_contains "$target" "new line 1"
  assert_contains "$target" "new line 2"

  count="$(grep -Fx "# >>> jal-bazzite" "$target" | wc -l | tr -d ' ')"
  assert_equals "1" "$count"
}

note "Rodando testes em ${ROOT_DIR}"
run_test "shell scripts tem sintaxe valida" test_shell_syntax
run_test "recipes apontam para scripts existentes" test_recipe_graph
run_test "install.sh instala localmente e nao duplica import" test_install_local_source_is_idempotent
run_test "install.sh baixa archive quando nao ha fonte local" test_install_download_source_with_mocked_curl
run_test "install.sh cria wrapper quando ujust custom fica somente leitura" test_install_falls_back_to_ujust_wrapper
run_test "scripts de perfil rodam em dry-run com comandos mockados" test_profile_scripts_dry_run_with_mocks
run_test "bloco gerenciado do zshrc e idempotente" test_marker_block_is_idempotent

printf '\nResumo: %s ok, %s falha(s), %s skip(s)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
