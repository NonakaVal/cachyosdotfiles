#!/usr/bin/env bash
# =============================================================================
# CachyOS Dotfiles — Provisioning (pós-reboot)
# =============================================================================
# Menu interativo para configurar o sistema após uma instalação limpa.
# Deve ser executado como root:  sudo bash scripts/provision.sh
#
# Atalhos:
#   sudo bash scripts/provision.sh essential   # update + repos + pacman + aur + flatpak + tweaks + services
#   sudo bash scripts/provision.sh all         # tudo
#   sudo bash scripts/provision.sh --dry-run   # preview sem alterações
# =============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${DOTFILES_DIR}/scripts"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log()     { echo -e "${GREEN}==>${NC} $*"; }
warn()    { echo -e "${YELLOW}!! ${NC} $*"; }
info()    { echo -e "${CYAN}--${NC} $*"; }
fail()    { echo -e "${RED}ERRO:${NC} $*"; }

# ---------------------------------------------------------------------------
# Dry-run
# ---------------------------------------------------------------------------
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
    warn "DRY RUN — nenhuma alteração será feita"
    # Sobrescreve comandos destrutivos com versões dry-run
    pacman()  { echo "[dry] pacman $*"; }
    yay()     { echo "[dry] yay $*"; }
    flatpak() { echo "[dry] flatpak $*"; }
    chsh()    { echo "[dry] chsh $*"; }
    systemctl() { echo "[dry] systemctl $*"; }
    sed()     { echo "[dry] sed $*"; }
fi

# ---------------------------------------------------------------------------
# Verificar root
# ---------------------------------------------------------------------------
check_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        fail "Rode como root:  sudo bash $0"
        exit 1
    fi
}

# Detectar o usuário real (não root)
REAL_USER="${SUDO_USER:-${USER:-val}}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
info "Usuário: $REAL_USER  |  Home: $REAL_HOME"

# ---------------------------------------------------------------------------
# 1. System Update
# ---------------------------------------------------------------------------
do_system_update() {
    log "1. Atualização completa do sistema..."
    pacman -Syu --noconfirm
    log "Sistema atualizado."
}

# ---------------------------------------------------------------------------
# 2. Repositórios CachyOS
# ---------------------------------------------------------------------------
do_repos() {
    log "2. Verificando repositórios CachyOS..."

    if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
        warn "Repositório cachyos não encontrado. Reinstale a keyring:"
        warn "  pacman -Sy cachyos-keyring cachyos-mirrorlist"
    else
        info "Repositórios CachyOS já configurados."
    fi

    # yay para o usuário real
    if ! command -v yay &>/dev/null; then
        log "Instalando yay (AUR helper)..."
        pacman -S --needed --noconfirm base-devel git
        local build_dir="/tmp/yay-build"
        rm -rf "$build_dir"
        git clone https://aur.archlinux.org/yay.git "$build_dir"
        chown -R "$REAL_USER" "$build_dir"
        sudo -u "$REAL_USER" bash -c "cd '$build_dir' && makepkg -si --noconfirm"
        rm -rf "$build_dir"
    else
        info "yay já instalado."
    fi
}

# ---------------------------------------------------------------------------
# 3. Pacotes oficiais (pacman)
# ---------------------------------------------------------------------------
do_pacman() {
    log "3. Instalando pacotes oficiais (pacman)..."
    if [[ -f "${SCRIPTS_DIR}/packages-pacman.list" ]]; then
        # Filtra comentários e linhas vazias
        local pkgs
        pkgs=$(grep -vE '^\s*#|^\s*$' "${SCRIPTS_DIR}/packages-pacman.list" | tr '\n' ' ')
        if [[ -n "$pkgs" ]]; then
            pacman -S --needed --noconfirm $pkgs
        fi
        log "Pacotes oficiais instalados."
    else
        fail "Arquivo não encontrado: scripts/packages-pacman.list"
    fi
}

# ---------------------------------------------------------------------------
# 4. Pacotes AUR (yay)
# ---------------------------------------------------------------------------
do_aur() {
    log "4. Instalando pacotes AUR (yay)..."
    if ! command -v yay &>/dev/null; then
        fail "yay não encontrado. Execute a opção 'repos' primeiro."
        return 1
    fi
    if [[ -f "${SCRIPTS_DIR}/packages-aur.list" ]]; then
        local pkgs
        pkgs=$(grep -vE '^\s*#|^\s*$' "${SCRIPTS_DIR}/packages-aur.list" | tr '\n' ' ')
        if [[ -n "$pkgs" ]]; then
            sudo -u "$REAL_USER" yay -S --needed --noconfirm $pkgs
        fi
        log "Pacotes AUR instalados."
    else
        fail "Arquivo não encontrado: scripts/packages-aur.list"
    fi
}

# ---------------------------------------------------------------------------
# 5. Flatpaks
# ---------------------------------------------------------------------------
do_flatpak() {
    log "5. Configurando Flatpak + Flathub..."
    pacman -S --needed --noconfirm flatpak

    if ! flatpak remotes | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub \
            https://flathub.org/repo/flathub.flatpakrepo
        info "Remote flathub adicionado."
    else
        info "Flathub já configurado."
    fi

    if [[ -f "${SCRIPTS_DIR}/packages-flatpak.list" ]]; then
        while read -r app; do
            [[ -z "$app" || "$app" == \#* ]] && continue
            flatpak install -y flathub "$app" 2>/dev/null || warn "Falha: $app"
        done < "${SCRIPTS_DIR}/packages-flatpak.list"
        log "Flatpaks instalados."
    fi
}

# ---------------------------------------------------------------------------
# 6. System Tweaks (mkinitcpio, pacman.conf, sysctl, etc)
# ---------------------------------------------------------------------------
do_system_tweaks() {
    log "6. Aplicando system tweaks..."

    # mkinitcpio: garantir hooks corretos
    if [[ -f /etc/mkinitcpio.conf ]]; then
        cp -a /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$(date +%s)"
        # Hooks: base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems
        if ! grep -q 'sd-vconsole' /etc/mkinitcpio.conf; then
            sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)/' /etc/mkinitcpio.conf
            info "mkinitcpio HOOKS atualizados."
        fi
    fi

    # pacman.conf: Color, ParallelDownloads, ILoveCandy
    if [[ -f /etc/pacman.conf ]]; then
        grep -q '^Color' /etc/pacman.conf || sed -i 's/^#Color/Color/' /etc/pacman.conf
        grep -q '^ILoveCandy' /etc/pacman.conf || sed -i '/^#TotalDownload/a ILoveCandy' /etc/pacman.conf 2>/dev/null || true
        sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
        info "pacman.conf otimizado."
    fi

    log "System tweaks aplicados."
}

# ---------------------------------------------------------------------------
# 7. Bluetooth Fix (TP-Link UB5A)
# ---------------------------------------------------------------------------
do_bluetooth_fix() {
    log "7. Aplicando fix de Bluetooth (TP-Link UB5A)..."

    if [[ -f "${DOTFILES_DIR}/bin/install-bt-fix" ]]; then
        bash "${DOTFILES_DIR}/bin/install-bt-fix"
    else
        warn "install-bt-fix não encontrado. Pulando."
    fi
}

# ---------------------------------------------------------------------------
# 8. Serviços
# ---------------------------------------------------------------------------
do_services() {
    log "8. Habilitando serviços do sistema..."

    local system_services=(
        bluetooth
        NetworkManager
        systemd-resolved
        systemd-timesyncd
        ufw
        avahi-daemon
        ananicy-cpp
    )
    for svc in "${system_services[@]}"; do
        if systemctl cat "$svc" &>/dev/null; then
            systemctl enable --now "$svc" 2>/dev/null && info "  $svc habilitado" || warn "  $svc falhou"
        fi
    done

    log "Serviços de sistema habilitados."
    info "Serviços de usuário (bt-postlogin-fix, rclone) devem ser habilitados depois do login:"
    info "  systemctl --user enable --now bt-postlogin-fix.service"
    info "  systemctl --user enable --now rclone-drive001.service"
}

# ---------------------------------------------------------------------------
# 9. Fish como shell padrão
# ---------------------------------------------------------------------------
do_fish_shell() {
    log "9. Configurando Fish como shell padrão..."
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || echo "/usr/bin/fish")
    if [[ -x "$fish_path" ]]; then
        if ! grep -q "$fish_path" /etc/shells; then
            echo "$fish_path" >> /etc/shells
        fi
        chsh -s "$fish_path" "$REAL_USER" 2>/dev/null || warn "Não foi possível mudar shell (use: chsh -s $fish_path)"
        info "Fish configurado para $REAL_USER"
    else
        warn "Fish não encontrado. Instale com: pacman -S fish cachyos-fish-config"
    fi
}

# ---------------------------------------------------------------------------
# 10. Otimização de armazenamento
# ---------------------------------------------------------------------------
do_optimize() {
    log "10. Otimização de armazenamento..."
    if [[ -f "${SCRIPTS_DIR}/otimizar_armazenamento.sh" ]]; then
        bash "${SCRIPTS_DIR}/otimizar_armazenamento.sh"
    else
        warn "otimizar_armazenamento.sh não encontrado. Pulando."
    fi
}

# ---------------------------------------------------------------------------
# 11. Dotfiles (install.sh como usuário)
# ---------------------------------------------------------------------------
do_dotfiles() {
    log "11. Aplicando dotfiles (symlinks)..."
    if [[ -f "${DOTFILES_DIR}/install.sh" ]]; then
        sudo -u "$REAL_USER" bash "${DOTFILES_DIR}/install.sh" all
    else
        warn "install.sh não encontrado."
    fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

show_menu() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   CachyOS Dotfiles — Provisioning            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}  system-update   Atualização completa (pacman -Syu)"
    echo -e "  ${GREEN}2${NC}  repos           Repos CachyOS + yay (AUR helper)"
    echo -e "  ${GREEN}3${NC}  pacman          Pacotes oficiais (packages-pacman.list)"
    echo -e "  ${GREEN}4${NC}  aur             Pacotes AUR (packages-aur.list)"
    echo -e "  ${GREEN}5${NC}  flatpak         Flathub + Flatpaks"
    echo -e "  ${GREEN}6${NC}  tweaks          mkinitcpio, pacman.conf, sysctl"
    echo -e "  ${GREEN}7${NC}  bluetooth       Fix TP-Link UB5A + BlueZ"
    echo -e "  ${GREEN}8${NC}  services        Habilitar serviços systemd"
    echo -e "  ${GREEN}9${NC}  fish            Fish como shell padrão"
    echo -e "  ${GREEN}A${NC}  dotfiles        Aplicar symlinks (install.sh)"
    echo -e "  ${GREEN}B${NC}  optimize        Otimizar armazenamento (Btrfs/Snapper/Flatpak)"
    echo ""
    echo -e "  ${YELLOW}essentials${NC}     = 1+2+3+4+5+6+8+9 (sem bluetooth/dotfiles/optimize)"
    echo -e "  ${YELLOW}all${NC}            = tudo acima"
    echo -e "  ${YELLOW}q${NC}              sair"
    echo ""
    read -rp "Escolha [1-9,A-B,all,essentials,q]: " choice
    echo ""

    case "${choice,,}" in
        1|system-update)  do_system_update ;;
        2|repos)          do_repos ;;
        3|pacman)         do_pacman ;;
        4|aur)            do_aur ;;
        5|flatpak)        do_flatpak ;;
        6|tweaks)         do_system_tweaks ;;
        7|bluetooth)      do_bluetooth_fix ;;
        8|services)       do_services ;;
        9|fish)           do_fish_shell ;;
        a|dotfiles)       do_dotfiles ;;
        b|optimize)       do_optimize ;;
        essentials)
            do_system_update
            do_repos
            do_pacman
            do_aur
            do_flatpak
            do_system_tweaks
            do_services
            do_fish_shell
            ;;
        all)
            do_system_update
            do_repos
            do_pacman
            do_aur
            do_flatpak
            do_system_tweaks
            do_bluetooth_fix
            do_services
            do_fish_shell
            do_dotfiles
            do_optimize
            ;;
        q|quit|exit)      exit 0 ;;
        *)                warn "Opção inválida: $choice" ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_root

# Modo não-interativo
if [[ $# -ge 1 ]]; then
    case "$1" in
        essential|essentials)
            do_system_update
            do_repos
            do_pacman
            do_aur
            do_flatpak
            do_system_tweaks
            do_services
            do_fish_shell
            log "Essentials concluído! Reinicie e depois rode:"
            log "  cd ~/Github/cachyosdotfiles && ./install.sh all"
            exit 0
            ;;
        all)
            do_system_update
            do_repos
            do_pacman
            do_aur
            do_flatpak
            do_system_tweaks
            do_bluetooth_fix
            do_services
            do_fish_shell
            do_dotfiles
            do_optimize
            log "Provisioning completo! Reinicie o sistema."
            exit 0
            ;;
        help|--help|-h)
            echo "Uso: sudo bash $0 [essential|all|--dry-run]"
            echo "  sem argumentos = menu interativo"
            exit 0
            ;;
    esac
fi

# Menu interativo
while true; do
    show_menu
    echo ""
    read -rp "Continuar? [s/n]: " cont
    [[ "${cont,,}" == "n" ]] && break
done

log "Provisioning finalizado."
