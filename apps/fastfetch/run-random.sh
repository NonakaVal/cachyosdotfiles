#!/usr/bin/env bash
# =============================================================================
# Fastfetch — run-random.sh
# =============================================================================
# Exibe fastfetch com uma imagem aleatória da pasta img/random.
# Detecta o backend do terminal (kitty/sixel/chafa) e calcula o tamanho ideal.
# Mantém uma fila embaralhada para não repetir imagens.
# =============================================================================
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

IMG_DIR="$HOME/.config/fastfetch/img/random"
TMP_CONFIG="$HOME/.config/fastfetch/.random-config.jsonc"
STATE_DIR="$HOME/.config/fastfetch/.state"
QUEUE_FILE="$STATE_DIR/image_queue.txt"

mkdir -p "$STATE_DIR"

# ================================
# Dependências
# ================================
if ! command -v identify >/dev/null 2>&1; then
    echo "identify não encontrado. Instale imagemagick."
    exit 1
fi

if ! command -v fastfetch >/dev/null 2>&1; then
    echo "fastfetch não encontrado."
    exit 1
fi

# ================================
# Detecta backend do logo
# ================================
LOGO_TYPE="chafa"
if [ -n "$KITTY_WINDOW_ID" ] || [ "$TERM" = "xterm-kitty" ]; then
    LOGO_TYPE="kitty"
elif [ -n "$KONSOLE_VERSION" ]; then
    LOGO_TYPE="sixel"
fi

# ================================
# Monta/renova fila embaralhada
# ================================
rebuild_queue() {
    find "$IMG_DIR" -maxdepth 1 -type file \( \
        -iname "*.png" -o \
        -iname "*.jpg" -o \
        -iname "*.jpeg" -o \
        -iname "*.webp" \
    \) | shuf > "$QUEUE_FILE"
}

if [ ! -d "$IMG_DIR" ]; then
    echo "Pasta não encontrada: $IMG_DIR"
    exit 1
fi

if [ ! -s "$QUEUE_FILE" ]; then
    rebuild_queue
fi

IMG=$(head -n 1 "$QUEUE_FILE")

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    rebuild_queue
    IMG=$(head -n 1 "$QUEUE_FILE")
fi

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "Nenhuma imagem encontrada em: $IMG_DIR"
    exit 1
fi

# remove a imagem usada da fila
tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"

# se acabou a fila, recria embaralhada para a próxima execução
if [ ! -s "$QUEUE_FILE" ]; then
    rebuild_queue
fi

# ================================
# Lê resolução da imagem
# ================================
read -r IMG_W IMG_H < <(identify -format "%w %h" "$IMG" 2>/dev/null)

if [ -z "$IMG_W" ] || [ -z "$IMG_H" ]; then
    echo "Não foi possível ler a resolução da imagem: $IMG"
    exit 1
fi

# ================================
# Tamanho do terminal
# ================================
TERM_COLS=$(tput cols 2>/dev/null)
TERM_LINES=$(tput lines 2>/dev/null)

TERM_COLS=${TERM_COLS:-120}
TERM_LINES=${TERM_LINES:-40}

# ================================
# Tamanho base do card
# ================================
if [ "$TERM_COLS" -ge 220 ]; then
    MAX_W=$(( TERM_COLS * 22 / 100 ))
    MAX_H=$(( TERM_LINES * 46 / 100 ))
    PADDING_RIGHT=5
    PADDING_TOP=1
elif [ "$TERM_COLS" -ge 170 ]; then
    MAX_W=$(( TERM_COLS * 24 / 100 ))
    MAX_H=$(( TERM_LINES * 48 / 100 ))
    PADDING_RIGHT=5
    PADDING_TOP=1
else
    MAX_W=$(( TERM_COLS * 26 / 100 ))
    MAX_H=$(( TERM_LINES * 50 / 100 ))
    PADDING_RIGHT=4
    PADDING_TOP=1
fi

[ "$MAX_W" -lt 20 ] && MAX_W=20
[ "$MAX_H" -lt 10 ] && MAX_H=10

# ================================
# Cálculo de dimensões por backend
# ================================
if [ "$LOGO_TYPE" = "sixel" ] || [ "$LOGO_TYPE" = "kitty" ]; then
    # sixel/kitty: imagem em pixels reais, fastfetch preserva aspecto
    CALC_W=$MAX_W
    CALC_H=$MAX_H
else
    # chafa: compensa aspect ratio das células (~2:1)
    if [ "$IMG_H" -gt "$IMG_W" ]; then
        CELL_ASPECT="2.20"
    elif [ "$IMG_W" -gt $(( IMG_H * 13 / 10 )) ]; then
        CELL_ASPECT="1.88"
    else
        CELL_ASPECT="2.00"
    fi

    IMG_RATIO=$(awk -v w="$IMG_W" -v h="$IMG_H" 'BEGIN { printf "%.8f", w / h }')

    CALC_W=$MAX_W
    CALC_H=$(awk -v w="$CALC_W" -v ratio="$IMG_RATIO" -v cell="$CELL_ASPECT" \
        'BEGIN { printf "%d", ((w / ratio) / cell) + 0.5 }')

    if [ "$CALC_H" -gt "$MAX_H" ]; then
        CALC_H=$MAX_H
        CALC_W=$(awk -v h="$CALC_H" -v ratio="$IMG_RATIO" -v cell="$CELL_ASPECT" \
            'BEGIN { printf "%d", ((h * ratio) * cell) + 0.5 }')
    fi
fi

[ "$CALC_W" -lt 16 ] && CALC_W=16
[ "$CALC_H" -lt 8 ] && CALC_H=8

cat > "$TMP_CONFIG" <<EOF
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",

  "logo": {
    "type": "$LOGO_TYPE",
    "source": "$IMG",
    "width": $CALC_W,
    "height": $CALC_H,
    "padding": {
      "right": $PADDING_RIGHT,
      "top": $PADDING_TOP
    }
  },

  "display": {
    "separator": " -> "
  },

  "modules": [
    {
      "type": "custom",
      "format": "\\n\\n"
    },
    "title",
    "separator",
    {
      "type": "os",
      "key": "├{icon}",
      "keyColor": "yellow"
    },
    "break",
    {
      "type": "host",
      "key": "󰌢 PC",
      "keyColor": "green"
    },
    {
      "type": "cpu",
      "key": "├󰻠",
      "keyColor": "green"
    },
    {
      "type": "gpu",
      "key": "├󰍛",
      "keyColor": "green"
    },
    {
      "type": "disk",
      "key": "├ ",
      "keyColor": "green"
    },
    {
      "type": "memory",
      "key": "├󰑭",
      "keyColor": "green"
    },
    {
      "type": "swap",
      "key": "├󰓡",
      "keyColor": "green"
    },
    {
      "type": "display",
      "key": "├󰍹",
      "keyColor": "green"
    },
    {
      "type": "uptime",
      "key": "└󰅐",
      "keyColor": "green"
    },

    "break",
    "colors"
  ]
}
EOF

fastfetch --config "$TMP_CONFIG"
