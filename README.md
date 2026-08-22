# CachyOS Dotfiles

Configurações pessoais para **CachyOS Linux** com **KDE Plasma 6** e **Fish shell**.
Organiza dotfiles, scripts e listas de pacotes para permitir reinstalação completa
do sistema após um reboot/reinstall via `install.sh` + `scripts/provision.sh`.

## Perfil do Sistema

| Componente   | Valor                                                    |
|--------------|----------------------------------------------------------|
| OS           | CachyOS Linux (Arch-based, rolling)                      |
| Kernel       | linux-cachyos 7.1.x + linux-cachyos-lts 6.18.x           |
| Bootloader   | Limine (com snapper-sync para rollback btrfs)            |
| Filesystem   | Btrfs + subvolumes (@, @home, @root, @srv, @cache, @tmp, @log) + zstd |
| CPU          | Intel Core i5-13400F (10 cores / 16 threads, 4.6GHz)     |
| GPU          | NVIDIA GTX 1660 SUPER (driver 610.43.03, nvidia-open)    |
| RAM          | 16GB + 15GB zram swap                                    |
| Bluetooth    | TP-Link UB5A (RTL8761BU) + headset KD-771               |
| Desktop      | KDE Plasma 6.7.2 (primário) + COSMIC 1.2 (alternativo)   |
| Shell        | Fish (cachyos-fish-config como base)                     |
| Tema KDE     | Reactionary95Dark + ChromeOS-dark (window decoration)    |

## Estrutura do Repositório

```
cachyosdotfiles/
├── install.sh                     # Symlink installer (rodar como usuário)
├── backup.sh                      # Salvar configs atuais → repo
├── .gitignore
│
├── scripts/
│   ├── provision.sh               # Menu interativo pós-reboot (rodar como root)
│   ├── otimizar_armazenamento.sh   # Limpeza/otimização de espaço (Btrfs/Snapper)
│   ├── packages-pacman.list       # Pacotes oficiais (279, categorizados)
│   ├── packages-aur.list          # Pacotes AUR (8)
│   └── packages-flatpak.list      # Flatpaks (3)
│
├── shell/fish/
│   ├── config.fish                # Fish config (greeting, aliases, funções)
│   ├── fish_plugins               # Fisher plugins (fish-nvm, bass)
│   └── conf.d/
│       └── 00-cachyos-dotfiles.fish  # Variáveis de ambiente
│
├── desktop/
│   ├── plasma/                    # KDE Plasma 6 (kwinrc, plasmarc, dolphinrc, etc)
│   └── gtk/                       # GTK 3.0/4.0 settings
│
├── apps/
│   ├── alacritty/alacritty.toml   # Terminal (tema Nord)
│   ├── fastfetch/                 # System info + run-random.sh (imagens aleatórias)
│   ├── git/.gitconfig             # Git (SSH rewrite, user NonakaVal)
│   └── aichat/config.yaml         # AI CLI (Gemini, API key como ENV)
│
├── services/
│   ├── bt-postlogin-fix.service   # Estabiliza Bluetooth no login
│   ├── rclone-drive001.service    # Monta Google Drive
│   └── README.md
│
└── bin/                           # Scripts em ~/.local/bin
    ├── bt-postlogin-fix           # Power-cycle BT após WirePlumber
    ├── install-bt-fix             # Fix root one-shot (TP-Link UB5A)
    ├── xbox-drift-fix             # Filtro de drift Xbox Controller (evsieve)
    ├── pybox                      # Launcher PyBox
    ├── clipa                      # Clipboard Assistant (fzf)
    ├── gca                        # Git Commit Assistant (Python)
    ├── qwen-edit                  # Edição de imagem via HF Space (LoRA)
    └── hydra                      # Launcher Hydra AppImage
```

## Fluxo Pós-Reboot (Reinstalação Completa)

Após uma instalação limpa do CachyOS:

```bash
# 1. Clonar o repositório
git clone git@github.com:NonakaVal/cachyosdotfiles.git ~/Github/cachyosdotfiles

# 2. Provisionar o sistema (como root) — menu interativo
sudo bash ~/Github/cachyosdotfiles/scripts/provision.sh

#    Ou modo não-interativo (essentials sem dotfiles):
sudo bash ~/Github/cachyosdotfiles/scripts/provision.sh essential

# 3. Aplicar dotfiles (como usuário)
cd ~/Github/cachyosdotfiles && ./install.sh all

# 4. Reboot se o NVIDIA/bluetooth fix foi aplicado
sudo reboot

# 5. Após reboot — habilitar serviços de usuário
systemctl --user enable --now bt-postlogin-fix.service
systemctl --user enable --now rclone-drive001.service   # se rclone config feito

# 6. Configurar Fish plugins (se necessário)
fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher update"
```

## Menu de Provisioning

`scripts/provision.sh` oferece seleção interativa:

| Opção         | Descrição                                          |
|---------------|----------------------------------------------------|
| `1` update    | Atualização completa (pacman -Syu)                 |
| `2` repos     | Verificar repos CachyOS + instalar yay             |
| `3` pacman    | Pacotes oficiais (packages-pacman.list)            |
| `4` aur       | Pacotes AUR via yay (packages-aur.list)            |
| `5` flatpak   | Flathub + instalar Flatpaks                        |
| `6` tweaks    | mkinitcpio hooks, pacman.conf (Color, ILoveCandy)  |
| `7` bluetooth | Fix TP-Link UB5A (modprobe + udev + sudoers)       |
| `8` services  | Habilitar bluetooth, NetworkManager, ufw, etc      |
| `9` fish      | Fish como shell padrão (chsh)                      |
| `A` dotfiles  | Aplicar symlinks (install.sh)                      |
| `B` optimize  | Otimizar armazenamento (Btrfs/Snapper/Flatpak)     |

Atalhos: `essential` = 1+2+3+4+5+6+8+9 · `all` = tudo

Suporta `--dry-run` para preview sem alterações:
```bash
sudo bash scripts/provision.sh --dry-run
```

## Comandos do install.sh

```bash
# Instalar tudo (default)
./install.sh all

# Componentes individuais
./install.sh shell          # Fish config
./install.sh desktop        # KDE Plasma + GTK
./install.sh apps           # Alacritty, fastfetch, git, aichat
./install.sh services       # Systemd user services + bin scripts

# Opções
./install.sh all --dry-run     # Preview sem mudanças
./install.sh all --no-backup   # Sem backup dos existentes
```

## Comandos do backup.sh

```bash
# Backup completo das configs atuais → .backups/
./backup.sh all

# Componentes individuais
./backup.sh shell          # Fish
./backup.sh desktop        # KDE Plasma + GTK
./backup.sh apps           # Apps
./backup.sh services       # Serviços + bin

# Restaurar backup mais recente para a estrutura do repo
./backup.sh restore

# Listar backups
./backup.sh list
```

## O Que Está Incluído

### Shell (Fish)
- Greeting com **fastfetch** e imagens aleatórias (run-random.sh)
- Aliases **eza** (ls/ll/la com ícones)
- Função `restartbt` (restart bluetooth + reconecta headset)
- Paths: opencode, grok, ~/.local/bin
- Plugins: fisher, fish-nvm, bass

### KDE Plasma 6
- 3 desktops virtuais
- krohnkite (tiling KWin script)
- Window decoration: ChromeOS-dark (Aurorae)
- Baloofile indexing desativado
- Dolphin, KRunner configs
- Xwayland scale=1 (Steam no prompt list)
- LookAndFeel: Reactionary95Dark

### Apps
- **Alacritty** — tema Nord, opacidade 0.8
- **Fastfetch** — config estático + run-random.sh (detecta kitty/sixel/chafa)
- **Git** — SSH rewrite (github.com → git@), user NonakaVal
- **aichat** — Gemini 2.5 Flash (API key via ENV_GEMINI_API_KEY)

### Scripts Bin (~/.local/bin)
- `bt-postlogin-fix` — power-cycle BT após WirePlumber (serviço de usuário)
- `install-bt-fix` — fix root one-shot para TP-Link UB5A (modprobe + udev + sudoers)
- `xbox-drift-fix` — filtro de drift do Xbox Wireless Controller via evsieve (start/stop/status)
- `pybox` — launcher PyBox (venv dedicado)
- `clipa` — Clipboard Assistant (fzf, Wayland/X11)
- `gca` — Git Commit Assistant (Python)
- `qwen-edit` — edição/transformação de imagens via HuggingFace Space (LoRA adapters)
- `hydra` — launcher Hydra AppImage

### Scripts de Sistema (scripts/)
- `provision.sh` — menu interativo de provisioning pós-reboot (root, com --dry-run)
- `otimizar_armazenamento.sh` — limpeza de espaço (Snapper, pacman cache, Flatpak, Steam, journal, Btrfs balance)

### Serviços
- `bt-postlogin-fix.service` — estabiliza Bluetooth no login
- `rclone-drive001.service` — monta Google Drive via rclone

## Customização

### Adicionar Pacote

1. Instalar: `sudo pacman -S pacote` ou `yay -S pacote-aur`
2. Editar `scripts/packages-pacman.list` ou `packages-aur.list`
3. Commitar

### Atualizar Lista de Pacotes do Sistema

```bash
# Gerar lista fresh do sistema atual
pacman -Qeq > /tmp/pkgs.txt
# Comparar com o arquivo no repo
diff scripts/packages-pacman.list /tmp/pkgs.txt
```

### Salvar Mudanças do KDE

Após ajustar configurações no System Settings:

```bash
./backup.sh desktop
./backup.sh restore
git diff desktop/
git add desktop/ && git commit -m "Update KDE settings"
```

### Imagens do Fastfetch

Coloque imagens em `apps/fastfetch/img/random/`. Elas não são versionadas
(ver `.gitignore`). O `run-random.sh` sorteia uma diferente a cada terminal.

### Secrets

- **aichat**: o config.yaml usa `ENV_GEMINI_API_KEY`. Defina no `~/.config/fish/conf.d/`:
  ```fish
  set -gx GEMINI_API_KEY "sua-key-aqui"
  ```
- **SSH**: adicione sua chave `~/.ssh/id_ed25519` manualmente após restore.
- **rclone**: rode `rclone config` para autenticar o Google Drive.

## Hardware Específico

### NVIDIA GTX 1660 SUPER

O CachyOS já inclui os pacotes `linux-cachyos-nvidia-open` e `nvidia-utils`.
Não é necessário instalar driver separadamente. Os módulos open funcionam para
a série GTX 16xx (Turing).

### TP-Link UB5A Bluetooth Dongle

O dongle USB TP-Link UB5A (chipset Realtek RTL8761BU) tem dois problemas:

1. **USB autosuspend** derruba a conexão → corrigido via modprobe + udev
2. **Timing no boot** — bluez sobe antes do PipeWire → corrigido via serviço
   de usuário `bt-postlogin-fix`

Rode uma vez após provision:
```bash
sudo ~/.local/bin/install-bt-fix
```

### Headset KD-771

O MAC do headset está hardcoded no `bin/bt-postlogin-fix` e em `shell/fish/config.fish`:
```
41:42:FF:6A:85:40
```
Altere se usar um headset diferente.

### Xbox Wireless Controller (Drift Fix)

O controle Xbox via Bluetooth pode apresentar drift no analógico esquerdo.
O script `bin/xbox-drift-fix` usa `evsieve` para aplicar um deadzone:

```bash
xbox-drift-fix start          # ativa deadzone (±3000, padrão)
xbox-drift-fix start zero     # desativa analógico esquerdo completamente
xbox-drift-fix stop           # desativa
xbox-drift-fix status         # verifica estado
```

Requer: `evsieve` (AUR) e NOPASSWD para evsieve em `/etc/sudoers.d/evsieve`.

## Licença

MIT
