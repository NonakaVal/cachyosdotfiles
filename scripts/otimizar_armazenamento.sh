#!/usr/bin/env bash
# =============================================================================
# otimizar_armazenamento
# =============================================================================
# Limpeza/otimização de espaço para CachyOS (Btrfs + Snapper + Flatpak + Steam).
#
# Uso:
#   sudo bash scripts/otimizar_armazenamento.sh            # modo interativo
#   sudo bash scripts/otimizar_armazenamento.sh --dry-run  # só mostra, não apaga
#
# O script NUNCA apaga nada sem confirmação explícita, exceto operações
# comprovadamente seguras (cache de pacotes do pacman, unused do flatpak).
# =============================================================================
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "### MODO DRY-RUN: nada será apagado, só relatado ###"
fi

confirm() {
    local prompt="$1"
    if $DRY_RUN; then
        echo "[dry-run] pularia confirmação: $prompt"
        return 1
    fi
    read -rp "$prompt [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]]
}

section() {
    echo
    echo "==================================================================="
    echo "  $1"
    echo "==================================================================="
}

require_root_actions() {
    if [[ $EUID -ne 0 ]]; then
        echo "Aviso: este script usa 'sudo' internamente para as ações que precisam de root."
    fi
}

require_root_actions

# ---------------------------------------------------------------------------
section "1. Uso atual do disco (antes)"
# ---------------------------------------------------------------------------
df -h / 2>/dev/null
echo
sudo btrfs filesystem usage / 2>/dev/null

# ---------------------------------------------------------------------------
section "2. Snapshots (Snapper)"
# ---------------------------------------------------------------------------
if command -v snapper &>/dev/null; then
    echo "Snapshots atuais:"
    sudo snapper list

    echo
    echo "Opções:"
    echo "  [1] Apagar TODOS os snapshots exceto o atual (0)"
    echo "  [2] Rodar limpeza automática baseada nos limites configurados (number/timeline)"
    echo "  [3] Pular"
    if ! $DRY_RUN; then
        read -rp "Escolha [1/2/3]: " snap_opt
    else
        snap_opt="dry"
    fi

    case "$snap_opt" in
        1)
            # pega todos os IDs exceto o 0 (current)
            ids=$(sudo snapper list --columns number 2>/dev/null | tail -n +4 | tr -d ' ' | grep -v '^0$' | grep -v '^$')
            if [[ -n "$ids" ]]; then
                echo "Apagando: $ids"
                sudo snapper delete $ids
            else
                echo "Nenhum snapshot extra encontrado."
            fi
            ;;
        2)
            sudo snapper cleanup number
            sudo snapper cleanup timeline
            ;;
        dry)
            echo "[dry-run] listaria e perguntaria se apaga snapshots"
            ;;
        *)
            echo "Pulado."
            ;;
    esac

    echo
    echo "Configurando limites para evitar acúmulo futuro (recomendado)..."
    if confirm "Aplicar limites de retenção (NUMBER_LIMIT=10, NUMBER_LIMIT_IMPORTANT=5)?"; then
        sudo snapper -c root set-config "NUMBER_LIMIT=10" "NUMBER_LIMIT_IMPORTANT=5"
    fi
else
    echo "snapper não encontrado, pulando."
fi

# ---------------------------------------------------------------------------
section "3. Cache do Pacman (pacotes antigos baixados)"
# ---------------------------------------------------------------------------
if command -v pacman &>/dev/null; then
    echo "Tamanho atual do cache do pacman:"
    du -sh /var/cache/pacman/pkg 2>/dev/null

    echo "Isto é seguro: remove versões antigas de pacotes já atualizados, mantendo as instaladas + 1 versão anterior."
    if confirm "Limpar cache do pacman (paccache -rk1)?"; then
        if command -v paccache &>/dev/null; then
            sudo paccache -rk1
            sudo paccache -ruk0   # remove pacotes desinstalados do cache
        else
            echo "paccache não encontrado (pacote pacman-contrib). Instale com: sudo pacman -S pacman-contrib"
        fi
    fi
else
    echo "pacman não encontrado, pulando."
fi

# ---------------------------------------------------------------------------
section "4. Flatpak"
# ---------------------------------------------------------------------------
if command -v flatpak &>/dev/null; then
    echo "Runtimes/apps instalados:"
    flatpak list --app --columns=application,size 2>/dev/null
    echo
    echo "Removendo runtimes/dependências não usadas (seguro)..."
    if $DRY_RUN; then
        flatpak uninstall --unused --noninteractive --dry-run 2>/dev/null || echo "[dry-run] flatpak uninstall --unused"
    else
        flatpak uninstall --unused
        flatpak repair
    fi
else
    echo "flatpak não encontrado, pulando."
fi

# ---------------------------------------------------------------------------
section "5. Steam (shader cache)"
# ---------------------------------------------------------------------------
STEAM_SHADERCACHE="$HOME/.steam/steam/steamapps/shadercache"
if [[ -d "$STEAM_SHADERCACHE" ]]; then
    echo "Tamanho do shader cache:"
    du -sh "$STEAM_SHADERCACHE" 2>/dev/null
    echo "Apagar é seguro — o Steam recompila os shaders sob demanda (pode causar stutter na próxima sessão de jogo)."
    if confirm "Limpar shader cache do Steam?"; then
        rm -rf "${STEAM_SHADERCACHE:?}"/*
    fi
else
    echo "Pasta de shader cache do Steam não encontrada em $STEAM_SHADERCACHE"
fi

echo
echo "Versões do Proton/compatibilitytools.d instaladas:"
COMPAT_DIR="$HOME/.steam/steam/steamapps/compatibilitytools.d"
if [[ -d "$COMPAT_DIR" ]]; then
    du -sh "$COMPAT_DIR"/*/ 2>/dev/null
    echo "(Revise manualmente e apague versões antigas do Proton-GE que não usa mais com: rm -rf \"$COMPAT_DIR/<versao>\")"
fi

# ---------------------------------------------------------------------------
section "6. Journal do systemd (logs)"
# ---------------------------------------------------------------------------
echo "Tamanho atual dos logs:"
sudo journalctl --disk-usage 2>/dev/null
if confirm "Limitar journal a 300MB e últimos 30 dias?"; then
    sudo journalctl --vacuum-size=300M
    sudo journalctl --vacuum-time=30d
fi

# ---------------------------------------------------------------------------
section "7. Cache de usuário (~/.cache)"
# ---------------------------------------------------------------------------
echo "Maiores subpastas em ~/.cache:"
du -sh "$HOME"/.cache/* 2>/dev/null | sort -rh | head -20

echo
echo "Verificando arquivo suspeito 'empty_...' (tamanho aparente pode estar errado por ser sparse/reflink no Btrfs):"
find "$HOME/.cache" -maxdepth 1 -iname "empty_*" -print 2>/dev/null | while read -r f; do
    echo "Arquivo: $f"
    echo -n "  Tamanho real (disco): "; du -h "$f" 2>/dev/null | cut -f1
    echo -n "  Tamanho aparente:      "; du -h --apparent-size "$f" 2>/dev/null | cut -f1
done
echo "(Se 'tamanho real' for pequeno, é só um artefato de exibição do Btrfs — não precisa apagar.)"

echo
echo "Cache do npm/yarn/pip/cargo (se existirem), geralmente seguro de limpar:"
[[ -d "$HOME/.npm" ]] && du -sh "$HOME/.npm" 2>/dev/null
[[ -d "$HOME/.cache/pip" ]] && du -sh "$HOME/.cache/pip" 2>/dev/null
[[ -d "$HOME/.cargo/registry" ]] && du -sh "$HOME/.cargo/registry" 2>/dev/null

if confirm "Limpar caches de pip/npm/cargo (não afeta pacotes já instalados)?"; then
    command -v pip &>/dev/null && pip cache purge 2>/dev/null
    command -v npm &>/dev/null && npm cache clean --force 2>/dev/null
    command -v cargo &>/dev/null && cargo cache -a 2>/dev/null
fi

# ---------------------------------------------------------------------------
section "8. Miniaturas (thumbnails) e lixeira"
# ---------------------------------------------------------------------------
[[ -d "$HOME/.cache/thumbnails" ]] && echo "Thumbnails: $(du -sh "$HOME/.cache/thumbnails" 2>/dev/null | cut -f1)"
[[ -d "$HOME/.local/share/Trash" ]] && echo "Lixeira: $(du -sh "$HOME/.local/share/Trash" 2>/dev/null | cut -f1)"

if confirm "Esvaziar cache de thumbnails e lixeira?"; then
    rm -rf "${HOME:?}/.cache/thumbnails"/*
    rm -rf "${HOME:?}/.local/share/Trash"/*
fi

# ---------------------------------------------------------------------------
section "9. Balance do Btrfs (recupera espaço de extents órfãos)"
# ---------------------------------------------------------------------------
echo "Isso reorganiza os dados no disco e pode liberar espaço 'preso' após deleções grandes."
echo "Pode demorar bastante dependendo do tamanho usado. Rode em um momento tranquilo."
if confirm "Rodar 'btrfs balance start -dusage=50 /' agora?"; then
    sudo btrfs balance start -dusage=50 /
fi

# ---------------------------------------------------------------------------
section "10. Resultado final"
# ---------------------------------------------------------------------------
df -h / 2>/dev/null
echo
sudo btrfs filesystem usage / 2>/dev/null

echo
echo "Concluído."
