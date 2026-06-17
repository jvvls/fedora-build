#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

VM_NAME="${VM_NAME:-jal-bazzite-test-$$}"
VM_MEMORY="${VM_MEMORY:-2048}"
VM_CPUS="${VM_CPUS:-2}"
SSH_PORT="${SSH_PORT:-22220}"
VM_USER="${VM_USER:-tester}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
VM_IMAGE_URL="${VM_IMAGE_URL:-}"
KEEP_VM="${KEEP_VM:-0}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"

WORK_DIR=""
QEMU_PID=""

die() {
  printf 'erro: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

cleanup() {
  if [ -n "${QEMU_PID:-}" ] && kill -0 "$QEMU_PID" >/dev/null 2>&1; then
    if [ "$KEEP_VM" = "1" ]; then
      info "KEEP_VM=1 ativo; VM continua rodando com PID ${QEMU_PID}"
    else
      kill "$QEMU_PID" >/dev/null 2>&1 || true
      wait "$QEMU_PID" >/dev/null 2>&1 || true
    fi
  fi

  if [ "$KEEP_VM" != "1" ] && [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "comando obrigatorio nao encontrado: $1"
}

make_seed_iso() {
  local seed_dir="$1"
  local output="$2"

  if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "$output" "${seed_dir}/user-data" "${seed_dir}/meta-data"
    return 0
  fi

  if command -v genisoimage >/dev/null 2>&1; then
    genisoimage -quiet -output "$output" -volid cidata -joliet -rock "${seed_dir}/user-data" "${seed_dir}/meta-data"
    return 0
  fi

  if command -v mkisofs >/dev/null 2>&1; then
    mkisofs -quiet -output "$output" -volid cidata -joliet -rock "${seed_dir}/user-data" "${seed_dir}/meta-data"
    return 0
  fi

  die "instale cloud-localds, genisoimage ou mkisofs para criar o seed ISO de cloud-init"
}

wait_for_ssh() {
  local key="$1"
  local deadline
  deadline=$((SECONDS + TIMEOUT_SECONDS))

  info "Aguardando SSH na porta local ${SSH_PORT}"
  until ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key" -p "$SSH_PORT" "${VM_USER}@127.0.0.1" true >/dev/null 2>&1; do
    if [ "$SECONDS" -gt "$deadline" ]; then
      die "timeout esperando a VM iniciar SSH"
    fi
    sleep 3
  done
}

require_command qemu-img
require_command qemu-system-x86_64
require_command ssh
require_command scp
require_command tar

WORK_DIR="$(mktemp -d)"
BASE_IMAGE="${WORK_DIR}/base.qcow2"
OVERLAY_IMAGE="${WORK_DIR}/${VM_NAME}.qcow2"
SSH_KEY="${WORK_DIR}/id_ed25519"
SEED_DIR="${WORK_DIR}/seed"
SEED_ISO="${WORK_DIR}/seed.iso"
REPO_TAR="${WORK_DIR}/repo.tar"

mkdir -p "$SEED_DIR"

if [ -n "$VM_BASE_IMAGE" ]; then
  [ -f "$VM_BASE_IMAGE" ] || die "VM_BASE_IMAGE nao existe: ${VM_BASE_IMAGE}"
  BASE_IMAGE="$VM_BASE_IMAGE"
elif [ -n "$VM_IMAGE_URL" ]; then
  require_command curl
  info "Baixando imagem cloud de ${VM_IMAGE_URL}"
  curl -fL "$VM_IMAGE_URL" -o "$BASE_IMAGE"
else
  die "defina VM_BASE_IMAGE=/caminho/imagem.qcow2 ou VM_IMAGE_URL=https://... para a imagem cloud"
fi

require_command ssh-keygen
ssh-keygen -q -t ed25519 -N "" -f "$SSH_KEY"

cat >"${SEED_DIR}/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

cat >"${SEED_DIR}/user-data" <<EOF
#cloud-config
users:
  - name: ${VM_USER}
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")
ssh_pwauth: false
package_update: false
EOF

make_seed_iso "$SEED_DIR" "$SEED_ISO"
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$OVERLAY_IMAGE" 20G >/dev/null

info "Iniciando VM temporaria ${VM_NAME}"
qemu-system-x86_64 \
  -name "$VM_NAME" \
  -m "$VM_MEMORY" \
  -smp "$VM_CPUS" \
  -drive "file=${OVERLAY_IMAGE},if=virtio,format=qcow2" \
  -drive "file=${SEED_ISO},if=virtio,format=raw,readonly=on" \
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
  -nographic \
  -serial mon:stdio \
  >"${WORK_DIR}/qemu.log" 2>&1 &
QEMU_PID="$!"

wait_for_ssh "$SSH_KEY"

info "Copiando repo para a VM"
tar --exclude='.git' -C "$ROOT_DIR" -cf "$REPO_TAR" .
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" -p "$SSH_PORT" "${VM_USER}@127.0.0.1" "mkdir -p ~/jal-bazzite"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" -P "$SSH_PORT" "$REPO_TAR" "${VM_USER}@127.0.0.1:/tmp/jal-bazzite.tar" >/dev/null
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" -p "$SSH_PORT" "${VM_USER}@127.0.0.1" "tar -C ~/jal-bazzite -xf /tmp/jal-bazzite.tar"

info "Rodando testes dentro da VM"
ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" -p "$SSH_PORT" "${VM_USER}@127.0.0.1" "cd ~/jal-bazzite && bash tests/run.sh"

info "VM temporaria validou a suite com sucesso"
