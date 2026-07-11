#!/usr/bin/env bash
# =============================================================================
# CachyOS Dotfiles — Backup
# =============================================================================
# Copia as configs atuais do sistema para a estrutura do repo.
# Útil para capturar mudanças feitas manualmente e versioná-las.
#
# Uso:
#   ./backup.sh all              # backup completo (default)
#   ./backup.sh shell            # só Fish
#   ./backup.sh desktop          # só KDE Plasma + GTK
#   ./backup.sh apps             # só apps
#   ./backup.sh services         # só serviços + bin
#   ./backup.sh list             # listar backups existentes
#   ./backup.sh help
# =============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${DOTFILES_DIR}/.backups/home_backup_${TIMESTAMP}"

log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

backup_file() {
    local src=$1
    local dest=$2

    if [ -e "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        if [ -L "$src" ]; then
            cp -P "$src" "$dest"
            log "Symlink copiado: $src"
        else
            cp -r "$src" "$dest"
            log "Copiado: $src"
        fi
    else
        log "Não encontrado (pulando): $src"
    fi
}

backup_shell() {
    log "Backup Fish..."
    for item in config.fish fish_plugins; do
        backup_file "$HOME/.config/fish/$item" "${BACKUP_DIR}/shell/fish/$item"
    done
    if [ -d "$HOME/.config/fish/functions" ]; then
        for item in "$HOME/.config/fish/functions"/*; do
            [[ -e "$item" ]] || continue
            backup_file "$item" "${BACKUP_DIR}/shell/fish/functions/$(basename "$item")"
        done
    fi
}

backup_desktop() {
    log "Backup KDE Plasma + GTK..."

    local plasma_files=(
        kdeglobals
        kwinrc
        plasmarc
        ksmserverrc
        baloofilerc
        dolphinrc
        krunnerrc
        kactivitymanagerdrc
    )
    for f in "${plasma_files[@]}"; do
        backup_file "$HOME/.config/$f" "${BACKUP_DIR}/desktop/plasma/$f"
    done

    local gtk_files=(
        gtkrc
        gtkrc-2.0
    )
    for f in "${gtk_files[@]}"; do
        backup_file "$HOME/.config/$f" "${BACKUP_DIR}/desktop/gtk/$f"
    done
    for d in gtk-3.0 gtk-4.0; do
        backup_file "$HOME/.config/$d/settings.ini" "${BACKUP_DIR}/desktop/gtk/${d}/settings.ini"
    done
}

backup_apps() {
    log "Backup apps..."

    backup_file "$HOME/.gitconfig" "${BACKUP_DIR}/apps/git/.gitconfig"

    local app_dirs=(alacritty aichat fastfetch)
    for dir in "${app_dirs[@]}"; do
        if [ -d "$HOME/.config/$dir" ]; then
            for item in "$HOME/.config/$dir"/*; do
                [[ -e "$item" ]] || continue
                backup_file "$item" "${BACKUP_DIR}/apps/$dir/$(basename "$item")"
            done
        fi
    done
}

backup_services() {
    log "Backup serviços + bin..."

    if [ -d "$HOME/.config/systemd/user" ]; then
        for item in "$HOME/.config/systemd/user"/*.service; do
            [[ -e "$item" ]] || continue
            backup_file "$item" "${BACKUP_DIR}/services/$(basename "$item")"
        done
    fi

    local bin_scripts=(bt-postlogin-fix install-bt-fix pybox clipa gca)
    for script in "${bin_scripts[@]}"; do
        backup_file "$HOME/.local/bin/$script" "${BACKUP_DIR}/bin/$script"
    done
}

backup_all() {
    log "Backup completo -> ${BACKUP_DIR#${DOTFILES_DIR}/}"
    backup_shell
    backup_desktop
    backup_apps
    backup_services
    log "Concluído! Arquivos em: ${BACKUP_DIR#${DOTFILES_DIR}/}"
    log "Para aplicar ao repo: cp -r ${BACKUP_DIR#${DOTFILES_DIR}/}/* <destino>"
}

copy_to_repo() {
    local backup_source=$1
    local repo_target=$2

    if [ -d "$backup_source" ]; then
        mkdir -p "$repo_target"
        cp -r "$backup_source"/* "$repo_target"/ 2>/dev/null || true
        log "Copiado para o repo: ${repo_target#${DOTFILES_DIR}/}"
    fi
}

restore_to_repo() {
    log "Restaurando backup para a estrutura do repo..."
    copy_to_repo "${BACKUP_DIR}/shell"   "${DOTFILES_DIR}/shell"
    copy_to_repo "${BACKUP_DIR}/desktop" "${DOTFILES_DIR}/desktop"
    copy_to_repo "${BACKUP_DIR}/apps"    "${DOTFILES_DIR}/apps"
    copy_to_repo "${BACKUP_DIR}/services" "${DOTFILES_DIR}/services"
    copy_to_repo "${BACKUP_DIR}/bin"     "${DOTFILES_DIR}/bin"
    log "Pronto! Revise com 'git diff' antes de commitar."
}

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    all         Backup completo (default)
    shell       Fish config
    desktop     KDE Plasma + GTK
    apps        Apps (alacritty, aichat, fastfetch, git)
    services    Serviços systemd + bin scripts
    restore     Copia o backup mais recente para a estrutura do repo
    list        Listar backups disponíveis
    help        Esta ajuda

Examples:
    $0 all
    $0 desktop
    $0 restore
EOF
}

COMPONENT=all

if [[ $# -eq 0 ]]; then
    COMPONENT=all
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            all|shell|desktop|apps|services|restore|list|help)
                COMPONENT=$1
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

if [[ $COMPONENT == "list" ]]; then
    if [ -d "${DOTFILES_DIR}/.backups" ]; then
        log "Backups disponíveis:"
        ls -1t "${DOTFILES_DIR}/.backups/" | head -10
    else
        log "Nenhum backup em ${DOTFILES_DIR}/.backups/"
    fi
    exit 0
fi

if [[ $COMPONENT == "restore" ]]; then
    LATEST_BACKUP=$(ls -1t "${DOTFILES_DIR}/.backups/" 2>/dev/null | head -1)
    if [ -z "$LATEST_BACKUP" ]; then
        log "Nenhum backup encontrado!"
        exit 1
    fi
    BACKUP_DIR="${DOTFILES_DIR}/.backups/${LATEST_BACKUP}"
    restore_to_repo
    exit 0
fi

case $COMPONENT in
    all)         backup_all ;;
    shell)       backup_shell ;;
    desktop)     backup_desktop ;;
    apps)        backup_apps ;;
    services)    backup_services ;;
esac
