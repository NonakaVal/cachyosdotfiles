#!/usr/bin/env bash
# =============================================================================
# CachyOS Dotfiles — Symlink Installer
# =============================================================================
# Cria symlinks dos arquivos de config do repo para $HOME.
# Baseado no padrão do repositório dotfile (Debian) anterior.
#
# Uso:
#   ./install.sh all              # instalar tudo (default)
#   ./install.sh shell            # só Fish
#   ./install.sh desktop          # só KDE Plasma + GTK
#   ./install.sh apps             # só apps (alacritty, fastfetch, git, etc)
#   ./install.sh services         # só serviços systemd + bin scripts
#   ./install.sh all --dry-run    # preview sem alterações
#   ./install.sh all --no-backup  # sem backup dos arquivos existentes
#   ./install.sh help
# =============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${DOTFILES_DIR}/.backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${DOTFILES_DIR}/install.log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Cria backup de arquivo existente (não-symlink) antes de sobrescrever
create_backup() {
    local file=$1
    if [ -e "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path="${BACKUP_DIR}/${file}.${TIMESTAMP}"
        mkdir -p "$(dirname "$backup_path")"
        cp -r "$HOME/$file" "$backup_path"
        log "Backup: ~/$file -> ${backup_path#${DOTFILES_DIR}/}"
    fi
}

# Cria symlink sobrescrevendo existente
create_symlink() {
    local src=$1
    local dest=$2
    local dest_dir
    dest_dir=$(dirname "$dest")

    mkdir -p "$dest_dir"

    if [ -L "$dest" ]; then
        local current_target src_resolved
        current_target=$(readlink -f "$dest")
        src_resolved=$(readlink -f "$src" 2>/dev/null || echo "$src")
        if [[ "$current_target" == "$src_resolved" ]]; then
            return
        fi
        rm "$dest"
    fi

    ln -sf "$src" "$dest"
    log "Symlink: ${dest#$HOME/} -> ${src#$DOTFILES_DIR/}"
}

# Symlink de todos os arquivos dentro de um diretório do repo para ~/.config/<name>
link_config_dir() {
    local repo_subdir=$1   # ex: apps/alacritty
    local config_name=$2   # ex: alacritty
    local src_dir="${DOTFILES_DIR}/${repo_subdir}"
    local dest_dir="$HOME/.config/${config_name}"

    [[ ! -d "$src_dir" ]] && { log "Pulando (não existe): $repo_subdir"; return; }

    for item in "$src_dir"/*; do
        [[ ! -e "$item" ]] && continue
        local item_name
        item_name=$(basename "$item")
        create_backup ".config/${config_name}/${item_name}"
        create_symlink "$item" "${dest_dir}/${item_name}"
    done
}

# ---------------------------------------------------------------------------
# Componentes
# ---------------------------------------------------------------------------

install_shell() {
    log "Fish shell configurations..."

    # garante ~/.config/fish/functions, completions
    mkdir -p "$HOME/.config/fish"/{functions,completions}

    # link_config_dir já cobre config.fish, fish_plugins, conf.d/
    link_config_dir "shell/fish" "fish"
}

install_desktop() {
    log "KDE Plasma + GTK configurations..."

    # Plasma config files
    local plasma_dir="${DOTFILES_DIR}/desktop/plasma"
    if [[ -d "$plasma_dir" ]]; then
    for item in "$plasma_dir"/*; do
        [[ ! -e "$item" ]] && continue
        local item_name
        item_name=$(basename "$item")
        # Pular arquivos de referência (.reference)
        [[ "$item_name" == *.reference ]] && continue
        create_backup ".config/${item_name}"
        create_symlink "$item" "$HOME/.config/${item_name}"
    done
    fi

    # GTK configs
    local gtk_dir="${DOTFILES_DIR}/desktop/gtk"
    if [[ -d "$gtk_dir" ]]; then
        for item in "$gtk_dir"/*; do
            [[ ! -e "$item" ]] && continue
            local item_name
            item_name=$(basename "$item")
            create_backup ".config/${item_name}"
            create_symlink "$item" "$HOME/.config/${item_name}"
        done
    fi
}

install_apps() {
    log "Application configurations..."

    # Git
    if [[ -f "${DOTFILES_DIR}/apps/git/.gitconfig" ]]; then
        create_backup ".gitconfig"
        create_symlink "${DOTFILES_DIR}/apps/git/.gitconfig" "$HOME/.gitconfig"
    fi

    # App configs via .config
    link_config_dir "apps/alacritty" "alacritty"
    link_config_dir "apps/aichat"    "aichat"
    link_config_dir "apps/fastfetch" "fastfetch"
}

install_services() {
    log "Systemd user services + bin scripts..."

    # User services -> ~/.config/systemd/user/
    local svc_dir="${DOTFILES_DIR}/services"
    if [[ -d "$svc_dir" ]]; then
        mkdir -p "$HOME/.config/systemd/user"
        for item in "$svc_dir"/*.service; do
            [[ ! -e "$item" ]] && continue
            local item_name
            item_name=$(basename "$item")
            create_backup ".config/systemd/user/${item_name}"
            create_symlink "$item" "$HOME/.config/systemd/user/${item_name}"
        done
    fi

    # Bin scripts -> ~/.local/bin/
    mkdir -p "$HOME/.local/bin"
    for script in "${DOTFILES_DIR}/bin"/*; do
        [[ ! -e "$script" ]] && continue
        local script_name
        script_name=$(basename "$script")
        create_backup ".local/bin/${script_name}"
        create_symlink "$script" "$HOME/.local/bin/${script_name}"
        chmod +x "$script" 2>/dev/null || true
    done

    # Reload systemd se houver serviços novos
    if [[ -d "$svc_dir" ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
        log "systemctl --user daemon-reload executado"
    fi
}

install_all() {
    log "Instalação completa..."
    install_shell
    install_desktop
    install_apps
    install_services
    log "Concluído! Reinicie o Fish: 'exec fish' ou abra um novo terminal."
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    all         Instalar tudo (default)
    shell       Fish config (~/.config/fish)
    desktop     KDE Plasma + GTK configs (~/.config)
    apps        Apps (alacritty, aichat, fastfetch, git)
    services    Systemd user services + bin scripts (~/.local/bin)
    help        Mostrar esta ajuda

Options:
    --no-backup     Não fazer backup dos arquivos existentes
    --dry-run       Preview sem fazer mudanças

Examples:
    $0 all
    $0 shell --no-backup
    $0 desktop --dry-run
EOF
}

DRY_RUN=false
NO_BACKUP=false
COMPONENT=all

if [[ $# -eq 0 ]]; then
    COMPONENT=all
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            all|shell|desktop|apps|services|help)
                COMPONENT=$1
                shift
                ;;
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                echo "Opção desconhecida: $1"
                show_usage
                exit 1
                ;;
        esac
    done
fi

if [[ $COMPONENT == "help" ]]; then
    show_usage
    exit 0
fi

if [[ $DRY_RUN == true ]]; then
    log "DRY RUN — nenhuma mudança será feita"
    create_symlink() { log "[dry] symlink: $2 -> $1"; }
    create_backup() { log "[dry] backup: $1"; }
fi

if [[ $NO_BACKUP == true ]]; then
    log "Skipping backups (--no-backup)"
    create_backup() { :; }
fi

case $COMPONENT in
    all)         install_all ;;
    shell)       install_shell ;;
    desktop)     install_desktop ;;
    apps)        install_apps ;;
    services)    install_services ;;
esac
