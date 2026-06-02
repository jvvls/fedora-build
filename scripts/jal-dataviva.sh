#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_not_root

create_fedora_box dataviva
setup_common_box dataviva
setup_dataviva_box dataviva

log "jal-dataviva finalizado. Use: distrobox enter dataviva"
