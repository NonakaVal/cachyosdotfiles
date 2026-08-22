#!/usr/bin/env bash
# joyfix — correção centralizada de drift de analógico para o Xbox Wireless
# Controller conectado via Bluetooth (driver xpadneo).
#
# Substitui e unifica:
#   - /usr/local/bin/xbox-drift-fix.sh   (evsieve, só ABS_X/ABS_Y, deadzone fixa)
#   - /usr/local/bin/xbox-disable-ls.py  (zera ABS_X/ABS_Y, sem deadzone real)
#   - xbox-disable-ls.service            (systemd, conflitante)
#
# Uso:
#   joyfix start [--deadzone N]   # calibra (se preciso) e ativa a correção nos 4 eixos
#   joyfix stop                   # desativa e libera o dispositivo
#   joyfix status                 # mostra se está rodando
#   joyfix calibrate              # mede o drift em repouso (analógicos soltos) e salva
#   joyfix show                   # mostra a última calibração salva
#   joyfix install                # instala em /usr/local/bin, desativa mecanismos antigos
#
# Requer: evsieve, python-evdev (ambos já instalados no sistema)

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/joyfix"
CALFILE="$CONFIG_DIR/calibration.conf"
PIDFILE="/tmp/joyfix.pid"
DEVICE_NAME="${JOYFIX_DEVICE_NAME:-Xbox Wireless Controller}"
DEADZONE_MARGIN="${JOYFIX_DEADZONE:-500}"   # margem em torno do offset medido (ajustável)
AXIS_MIN=-32768
AXIS_MAX=32767
AXES=(ABS_X ABS_Y ABS_RX ABS_RY)

mkdir -p "$CONFIG_DIR"

log() { echo "$(date '+%H:%M:%S') $*" >&2; }

# ---------------------------------------------------------------------------
# Localiza o event node mais recente do controle pelo nome (robusto a
# reconexões Bluetooth, que criam novos /dev/input/eventN).
# ---------------------------------------------------------------------------
find_device() {
    local candidate="" best=-1 num
    for _ in $(seq 1 20); do
        for p in /sys/class/input/event*; do
            [ -r "$p/device/name" ] || continue
            if [ "$(cat "$p/device/name")" = "$DEVICE_NAME" ]; then
                num="${p##*event}"
                if [ "$num" -gt "$best" ]; then
                    best="$num"
                    candidate="/dev/input/event${num}"
                fi
            fi
        done
        [ -n "$candidate" ] && { echo "$candidate"; return 0; }
        sleep 1
    done
    return 1
}

# ---------------------------------------------------------------------------
# Lê o valor atual de ABS_X/ABS_Y/ABS_RX/ABS_RY via python-evdev.
# ---------------------------------------------------------------------------
read_axes() {
    local dev="$1"
    python3 - "$dev" <<'PYEOF'
import sys, evdev
dev = evdev.InputDevice(sys.argv[1])
caps = dict(dev.capabilities().get(evdev.ecodes.EV_ABS, []))
wanted = ("ABS_X", "ABS_Y", "ABS_RX", "ABS_RY")
name_to_code = {v: k for k, v in evdev.ecodes.ABS.items() if isinstance(v, str)}
for name in wanted:
    code = name_to_code.get(name)
    info = caps.get(code)
    print(f"{name}={info.value if info else 0}")
PYEOF
}

# ---------------------------------------------------------------------------
# Calibração: mede o repouso real dos 4 eixos e salva em disco.
# ---------------------------------------------------------------------------
calibrate() {
    echo "Procurando o controle ($DEVICE_NAME)..."
    local dev
    dev=$(find_device) || { echo "Controle não encontrado (timeout 20s)." >&2; exit 1; }
    echo "Usando: $dev"
    echo "Solte os dois analógicos (repouso) — calibrando em 2s..."
    sleep 2

    local vals
    vals=$(read_axes "$dev")
    {
        echo "# Calibração gerada em $(date -Iseconds)"
        echo "# Dispositivo: $DEVICE_NAME"
        echo "$vals"
    } > "$CALFILE"

    echo "--- valores de repouso (drift real) ---"
    echo "$vals"
    echo "Calibração salva em $CALFILE"
}

show() {
    if [ -f "$CALFILE" ]; then
        cat "$CALFILE"
    else
        echo "Nenhuma calibração encontrada. Rode: joyfix calibrate"
    fi
}

# ---------------------------------------------------------------------------
# Gera os pares --map do evsieve para UM eixo: 3 segmentos lineares
#   [MIN .. offset-margem]   -> [MIN .. 0]
#   [offset-margem .. offset+margem] -> 0   (deadzone real, centrada no drift)
#   [offset+margem .. MAX]   -> [0 .. MAX]
# Isso remove o offset de drift e preserva o range de movimento real,
# ao contrário da deadzone fixa (±3000) do script antigo.
# ---------------------------------------------------------------------------
axis_map_args() {
    local axis_lc="$1" offset="$2" margin="$3"
    local lo=$((offset - margin))
    local hi=$((offset + margin))
    (( lo < AXIS_MIN )) && lo=$AXIS_MIN
    (( hi > AXIS_MAX )) && hi=$AXIS_MAX

    printf '%s\n' \
        --map "abs:${axis_lc}:${AXIS_MIN}~${lo}" "abs:${axis_lc}:${AXIS_MIN}~0" \
        --map "abs:${axis_lc}:${lo}~${hi}"        "abs:${axis_lc}:0" \
        --map "abs:${axis_lc}:${hi}~${AXIS_MAX}"  "abs:${axis_lc}:0~${AXIS_MAX}"
}

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Já está rodando (PID $(cat "$PIDFILE"))."
        exit 0
    fi

    [ -f "$CALFILE" ] || { echo "Sem calibração salva — calibrando agora."; calibrate; }

    declare -A OFFSET
    while IFS='=' read -r k v; do
        [[ "$k" =~ ^ABS_ ]] && OFFSET["$k"]="$v"
    done < <(grep -E '^ABS_' "$CALFILE")

    if ! sudo -n evsieve --version >/dev/null 2>&1; then
        echo "AVISO: 'sudo evsieve' pede senha. Configure NOPASSWD em /etc/sudoers.d/evsieve" >&2
        echo "       (linha: seu_usuario ALL=(root) NOPASSWD: /usr/bin/evsieve)" >&2
    fi

    echo "Iniciando correção — offsets: ${OFFSET[ABS_X]:-0}/${OFFSET[ABS_Y]:-0} (esq.)  ${OFFSET[ABS_RX]:-0}/${OFFSET[ABS_RY]:-0} (dir.)  margem=${DEADZONE_MARGIN}"

    (
        while true; do
            DEV=$(find_device) || { sleep 2; continue; }

            MAP_ARGS=()
            MAP_ARGS+=( $(axis_map_args x  "${OFFSET[ABS_X]:-0}"  "$DEADZONE_MARGIN") )
            MAP_ARGS+=( $(axis_map_args y  "${OFFSET[ABS_Y]:-0}"  "$DEADZONE_MARGIN") )
            MAP_ARGS+=( $(axis_map_args rx "${OFFSET[ABS_RX]:-0}" "$DEADZONE_MARGIN") )
            MAP_ARGS+=( $(axis_map_args ry "${OFFSET[ABS_RY]:-0}" "$DEADZONE_MARGIN") )

            sudo evsieve \
                --input "$DEV" grab=force persist=exit \
                "${MAP_ARGS[@]}" \
                --output name="Xbox Wireless Controller - joyfix" \
                || true

            log "evsieve caiu, tentando reconectar..."
            sleep 2
        done
    ) &

    echo $! > "$PIDFILE"
    echo "Ativo (PID $!). Use 'joyfix stop' para desligar."
}

stop() {
    if [ ! -f "$PIDFILE" ]; then
        echo "Não está rodando."
        exit 0
    fi
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    pkill -f "evsieve --input.*joyfix" 2>/dev/null || true
    sudo pkill -f "evsieve --input.*grab=force" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Desativado."
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Rodando (PID $(cat "$PIDFILE"))."
        [ -f "$CALFILE" ] && { echo "Calibração:"; cat "$CALFILE"; }
    else
        echo "Parado."
    fi
}

install_self() {
    echo "Instalando joyfix em /usr/local/bin..."
    sudo install -m 755 "$0" /usr/local/bin/joyfix

    echo "Desativando mecanismos antigos conflitantes..."
    sudo systemctl disable --now xbox-disable-ls.service 2>/dev/null || true
    pkill -f "xbox-drift-fix.sh" 2>/dev/null || true
    pkill -f "xbox-disable-ls.py" 2>/dev/null || true
    sudo pkill -f "evsieve --input.*grab=force" 2>/dev/null || true

    echo "Pronto. Use: joyfix calibrate && joyfix start"
    echo "(Scripts antigos em /usr/local/bin/xbox-drift-fix.sh e xbox-disable-ls.py"
    echo " continuam no disco mas não estão mais ativos — remova-os quando quiser.)"
}

case "${1:-}" in
    start)
        shift || true
        if [ "${1:-}" = "--deadzone" ]; then DEADZONE_MARGIN="$2"; fi
        start
        ;;
    stop)      stop ;;
    status)    status ;;
    calibrate) calibrate ;;
    show)      show ;;
    install)   install_self ;;
    *)
        echo "Uso: $0 {start [--deadzone N]|stop|status|calibrate|show|install}"
        exit 1
        ;;
esac
