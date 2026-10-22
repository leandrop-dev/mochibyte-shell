#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == */* ]]; then
    SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
else
    SCRIPT_DIR="$(pwd -P)"
fi

source "$SCRIPT_DIR/caching.sh" 2>/dev/null || true

FORCE_WINDOW=0
if [[ "$1" == "--window" ]]; then
    FORCE_WINDOW=1
    shift
fi

ACTION="open"
case "$1" in
    open|toggle|close) ACTION="$1"; shift ;;
esac
TAB="$1"
SUBTAB="$2"

SETTINGS_QML="$QS_DIR/SettingsApp.qml"
APP_ID="mochibyte-settings"
GUIDE_MODE_FILE="${QS_CACHE_GUIDE:-$QS_CACHE_DIR/guide}/last_tab.txt"

if [[ ! -f "$SETTINGS_QML" ]]; then
    echo "settings: $SETTINGS_QML not found" >&2
    exit 1
fi

separate_window_enabled() {
    [[ -f "$QS_SETTINGS" ]] && command -v jq >/dev/null 2>&1 || return 1
    [[ "$(jq -r '.general.settingsSeparateWindow // false' "$QS_SETTINGS" 2>/dev/null)" == "true" ]]
}

main_ipc() {
    if [[ -n "$MAIN_QML" ]]; then
        quickshell -p "$MAIN_QML" ipc call main "$@" >/dev/null 2>&1
    else
        quickshell ipc call main "$@" >/dev/null 2>&1
    fi
}

embedded_open() {
    command -v jq >/dev/null 2>&1 && jq -e '.widget == "guide"' "$QS_RUN_DIR/current_widget" >/dev/null 2>&1
}

settings_ipc() {
    quickshell -p "$SETTINGS_QML" ipc call settings "$@" >/dev/null 2>&1
}

is_running() {
    settings_ipc ping
}

focus_window() {
    settings_ipc focus
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch focuswindow "class:^(${APP_ID})$" >/dev/null 2>&1 \
            || hyprctl dispatch 'hl.dsp.focus({ window = "class:^('"$APP_ID"')$" })' >/dev/null 2>&1
    fi
}

write_tab() {
    [[ -n "$TAB" ]] || return 0
    mkdir -p "$(dirname "$GUIDE_MODE_FILE")"
    if [[ -n "$SUBTAB" ]]; then
        echo "$TAB:$SUBTAB" > "$GUIDE_MODE_FILE"
    else
        echo "$TAB" > "$GUIDE_MODE_FILE"
    fi
}

if [[ "$FORCE_WINDOW" != 1 ]] && { embedded_open || { ! separate_window_enabled && ! is_running; }; }; then
    main_ipc embeddedSettings "$ACTION" "${TAB}${SUBTAB:+:$SUBTAB}"
    exit 0
fi

if [[ "$ACTION" == "close" ]]; then
    settings_ipc close
    exit 0
fi

if is_running; then
    if [[ "$ACTION" == "toggle" ]]; then
        settings_ipc close
        exit 0
    fi
    write_tab
    [[ -n "$TAB" ]] && settings_ipc goto "$TAB" "$SUBTAB"
    focus_window
    exit 0
fi

write_tab
exec setsid quickshell -n -p "$SETTINGS_QML"
