# jal-bazzite

Recipes pessoais de `ujust` para montar minha configuracao no Bazzite.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/jvvls/fedora-build/main/install.sh | bash
```

Depois:

```bash
ujust jal-all
```

## Recipes

- `ujust jal-base`: instala apps Flatpak, ferramentas CLI via Homebrew quando disponivel, JetBrains Toolbox via recipe do Bazzite quando existir, Oh My Zsh e bloco JAL no `~/.zshrc`.
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
|   +-- jal-gnome.just
|   +-- jal-all.just
+-- scripts/
    +-- lib.sh
    +-- jal-base.sh
    +-- jal-dev.sh
    +-- jal-dataviva.sh
    +-- jal-gnome.sh
```

O `install.sh` copia tudo para `~/.local/share/jal-bazzite` e tenta adicionar um import em:

```text
/usr/share/ublue-os/just/60-custom.just
```

Esse arquivo e importado pelo `ujust` nas imagens Universal Blue/Bazzite. Em instalacoes com `/usr` somente leitura, o instalador cria um wrapper em `/usr/local/bin/ujust` que delega para `/usr/bin/ujust` e intercepta apenas as recipes `jal-*`.

## Testes

Rode a suite local segura com:

```bash
bash tests/run.sh
```

Ela valida sintaxe dos scripts, integridade dos recipes, instalacao local em diretorio temporario, fluxo de download do archive, idempotencia do import do `ujust` e um dry-run dos perfis com comandos perigosos mockados.

Para rodar a mesma suite dentro de uma VM cloud temporaria, informe uma imagem qcow2 ja baixada:

```bash
VM_BASE_IMAGE=/caminho/Fedora-Cloud.qcow2 bash tests/run-vm.sh
```

Ou deixe o runner baixar uma imagem cloud:

```bash
VM_IMAGE_URL=https://exemplo/imagem-cloud.qcow2 bash tests/run-vm.sh
```

O runner de VM precisa de `qemu-system-x86_64`, `qemu-img`, `ssh`, `scp`, `ssh-keygen` e uma ferramenta para seed de cloud-init (`cloud-localds`, `genisoimage` ou `mkisofs`). Por padrao ele cria um overlay temporario, sobe SSH em `127.0.0.1:22220`, copia o repo, roda `tests/run.sh` e remove a VM no final.
