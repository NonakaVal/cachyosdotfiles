# =============================================================================
# Fish — conf.d/00-cachyos-dotfiles.fish
# =============================================================================
# Configurações carregadas automaticamente pelo Fish em toda sessão.
# Mantém o config.fish limpo — aqui ficam variáveis de ambiente e paths.
# =============================================================================

# XDG
set -gx XDG_CONFIG_HOME $HOME/.config
set -gx XDG_DATA_HOME $HOME/.local/share
set -gx XDG_CACHE_HOME $HOME/.cache

# Editor padrão
set -gx EDITOR micro
set -gx VISUAL code

# Menos histórico duplicado
set -gx HISTCONTROL ignoreboth

# Python venv marker
set -gx PYBOX_CALL_DIR (pwd)
