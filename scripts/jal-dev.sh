#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

BOX_NAME="${1:-dev}"

create_fedora_box "$BOX_NAME"
setup_common_box "$BOX_NAME"
setup_dev_box "$BOX_NAME"

log "jal-dev finalizado. Use: distrobox enter ${BOX_NAME}"
