# =============================================================================
# Fish Shell — config.fish
# =============================================================================
# Base: /usr/share/cachyos-fish-config/cachyos-config.fish
# Personalizações: greeting com fastfetch, aliases eza, funções, paths
# =============================================================================

source /usr/share/cachyos-fish-config/cachyos-config.fish

# ---------------------------------------------------------------------------
# Greeting — fastfetch com imagem aleatória
# ---------------------------------------------------------------------------
function fish_greeting
    ~/.config/fastfetch/run-random.sh
end

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------
fish_add_path /home/val/.opencode/bin
fish_add_path $HOME/.grok/bin
fish_add_path $HOME/.local/bin

# ---------------------------------------------------------------------------
# Aliases — eza clean e minimalista (sobrescreve o default do CachyOS)
# ---------------------------------------------------------------------------
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first'
alias la='eza -a --icons --group-directories-first'
alias editbash "code ~/.bashrc"
alias reloadfish "source ~/.config/fish/config.fish"

# ---------------------------------------------------------------------------
# Funções
# ---------------------------------------------------------------------------

# Reinicia o serviço bluetooth e reconecta o fone KD-771.
# Precisa de sudo (ver install-bt-fix para sudoers sem senha).
function restartbt --description 'Restart bluetooth and reconnect KD-771'
    sudo systemctl restart bluetooth
    and sleep 2
    and bluetoothctl connect 41:42:FF:6A:85:40
end

# >>> grok installer >>>
fish_add_path $HOME/.grok/bin
# <<< grok installer <<<
