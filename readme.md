# jal-bazzite

Recipes pessoais de `ujust` para montar minha configuracao no Bazzite.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/jvvls/jal-bazzite/main/install.sh | bash
```

Depois:

```bash
ujust jal-all
```

## Recipes

- `ujust jal-base`: instala apps Flatpak, ferramentas CLI via Homebrew quando disponivel, JetBrains Toolbox via recipe do Bazzite quando existir, Oh My Zsh e bloco JAL no `~/.zshrc`.
- `ujust jal-gaming`: instala Heroic, ProtonUp-Qt, MangoHud, Gamescope e nvtop.
- `ujust jal-dev`: cria/atualiza a distrobox `dev` com Java 17, Node, Python, Go, Maven, Gradle, Zsh e Oh My Zsh.
- `ujust jal-dataviva`: cria/atualiza a distrobox `dataviva` com Java 11, Spark, Maven, Python, Zsh e Oh My Zsh.
- `ujust jal-gnome`: aplica ajustes basicos de GNOME, restaura atalhos de teclado capturados da maquina atual e instala Extension Manager.
- `ujust jal-all`: executa tudo.

## Estrutura

```text
jal-bazzite/
+-- install.sh
+-- recipes/
|   +-- jal.just
|   +-- jal-base.just
|   +-- jal-dev.just
|   +-- jal-dataviva.just
|   +-- jal-gaming.just
|   +-- jal-gnome.just
|   +-- jal-all.just
+-- scripts/
    +-- lib.sh
    +-- jal-base.sh
    +-- jal-dev.sh
    +-- jal-dataviva.sh
    +-- jal-gaming.sh
    +-- jal-gnome.sh
```

O `install.sh` copia tudo para `~/.local/share/jal-bazzite` e adiciona um import em:

```text
/usr/share/ublue-os/just/60-custom.just
```

Esse arquivo e importado pelo `ujust` nas imagens Universal Blue/Bazzite.
