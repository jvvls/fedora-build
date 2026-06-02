#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

create_fedora_box dev
setup_common_box dev
setup_dev_box dev

log "jal-dev finalizado. Use: distrobox enter dev"
