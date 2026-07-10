jal-dev name="dev":
    @bash "${JAL_BAZZITE_HOME:-$HOME/.local/share/jal-bazzite}/scripts/jal-dev.sh" "{{name}}"

jal-dev-ephemeral:
    @bash "${JAL_BAZZITE_HOME:-$HOME/.local/share/jal-bazzite}/scripts/jal-dev.sh" "dev-$(date +%Y%m%d%H%M%S)"
