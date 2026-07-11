# JAL Bazzite recipes.
import "jal-base.just"
import "jal-dev.just"
import "jal-dataviva.just"
import "jal-gnome.just"
import "jal-all.just"

jal-help:
    @echo "JAL Bazzite recipes:"
    @echo "  ujust jal-base              (rebase bazzite-dx + apps base)"
    @echo "  ujust jal-dev               (container dev padrao)"
    @echo "  ujust jal-dev name=foo      (container dev com nome customizado)"
    @echo "  ujust jal-dev-ephemeral     (container dev descartavel com timestamp)"
    @echo "  ujust jal-dataviva          (stack DataViva no host, sem container)"
    @echo "  ujust jal-gnome             (rice: Ptyxis, Oh My Zsh, pywal)"
    @echo "  ujust jal-all"
