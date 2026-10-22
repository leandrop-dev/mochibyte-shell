#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

RUN_DIR="${QS_RUN_FOCUSTIME:-${XDG_RUNTIME_DIR:-/run/user/${UID:-$(id -u)}}/mochibyte/focustime}"
mkdir -p "$RUN_DIR" 2>/dev/null

PID_FILE="$RUN_DIR/current_focus.pid"
LOG_FILE="$RUN_DIR/focus_events.jsonl"
STATE_FILE="$RUN_DIR/focus_state.json"
: >> "$LOG_FILE"
: >> "$STATE_FILE"

# Prevent tmpfs unbounded memory growth by trimming existing log file to last 200 lines
if [ -f "$LOG_FILE" ]; then
    tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
log_append_count=0

# Clean termination of old instance via PID file instead of heavy proc-scanning
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$old_pid" ] && [ "$old_pid" != "$$" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill -TERM "$old_pid" 2>/dev/null
        for _ in 1 2 3 4 5; do
            kill -0 "$old_pid" 2>/dev/null || break
            sleep 0.01 2>/dev/null || :
        done
        kill -9 "$old_pid" 2>/dev/null || :
    fi
fi
echo "$$" > "$PID_FILE"

cleanup() {
    trap - EXIT SIGTERM SIGINT
    rm -f "$PID_FILE" 2>/dev/null
    pkill -P $$ 2>/dev/null
    exit 0
}
trap cleanup EXIT SIGTERM SIGINT

cls=""
title=""
active_addr=""

get_active_window() {
    local data raw cls_lower title_lower
    data=$(timeout 0.4 hyprctl activewindow -j 2>/dev/null)
    if [ -z "$data" ] || [ "$data" = "{}" ]; then
        active_addr=""
        cls="Desktop"
        title="Desktop"
        return
    fi
    raw=$(jq -r '(.initialClass // .class // "Unknown") as $c | "\(.address // "")|\($c)|\(.initialTitle // .title // $c)"' <<< "$data" 2>/dev/null)
    IFS='|' read -r active_addr cls title <<< "$raw"
    cls="${cls:-Desktop}"
    title="${title:-Desktop}"
    cls_lower="${cls,,}"
    title_lower="${title,,}"
    if [[ "$cls_lower" == *quickshell* ]] || [[ "$title_lower" == *qs-master* ]] || [[ "$cls_lower" == *qs-master* ]]; then
        cls="Quickshell"
        title="Quickshell"
    fi
}

last_cls=""
last_title=""

emit_state() {
    local target_cls="$1" target_title="$2" ts esc_cls esc_title json_payload

    if [ "$target_cls" = "$last_cls" ] && [ "$target_title" = "$last_title" ]; then
        return
    fi
    last_cls="$target_cls"
    last_title="$target_title"

    printf -v ts '%(%s)T' -1

    esc_cls="${target_cls//\\/\\\\}"
    esc_cls="${esc_cls//\"/\\\"}"
    esc_cls="${esc_cls//$'\n'/\\n}"
    esc_cls="${esc_cls//$'\r'/\\r}"
    esc_cls="${esc_cls//$'\t'/\\t}"

    esc_title="${target_title//\\/\\\\}"
    esc_title="${esc_title//\"/\\\"}"
    esc_title="${esc_title//$'\n'/\\n}"
    esc_title="${esc_title//$'\r'/\\r}"
    esc_title="${esc_title//$'\t'/\\t}"

    json_payload="{\"timestamp\":$ts,\"app_class\":\"$esc_cls\",\"app_title\":\"$esc_title\"}"

    # Direct stdout output for instant IPC delivery to Quickshell Process listener
    printf '%s\n' "$json_payload"

    # In-place write preserving file inode to prevent inotify watcher disconnection
    printf '%s\n' "$json_payload" > "$STATE_FILE"
    printf '%s\n' "$json_payload" >> "$LOG_FILE"

    log_append_count=$((log_append_count + 1))
    if [ "$log_append_count" -ge 100 ]; then
        log_append_count=0
        if [ -f "$LOG_FILE" ]; then
            tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi
}

listen_events() {
    local sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    if [ ! -S "$sock" ]; then
        sock="/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    fi
    socat -u UNIX-CONNECT:"$sock" - 2>/dev/null
}

get_active_window
emit_state "$cls" "$title"

while true; do
    while read -r line; do
        case "$line" in
            activewindowv2*|closewindow*)
                target="$line"
                closed=false
                [[ "$line" == closewindow* ]] && closed=true
                while read -t 0.02 -r extra_line; do
                    case "$extra_line" in
                        activewindowv2*) target="$extra_line" ;;
                        closewindow*) closed=true ;;
                    esac
                done
                if [ "$closed" = false ] && [ "${target#activewindowv2>>}" = "${active_addr#0x}" ]; then
                    continue
                fi
                get_active_window
                emit_state "$cls" "$title"
                ;;
        esac
    done < <(listen_events)
    sleep 1
done
