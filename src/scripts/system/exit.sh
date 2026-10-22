#!/usr/bin/env bash

rm -f /tmp/mochibyted.lock /tmp/mochibyted.pid 2>/dev/null

if command -v systemctl &>/dev/null; then
    systemctl --user stop graphical-session.target 2>/dev/null
    systemctl --user stop graphical-session-pre.target 2>/dev/null
fi

if command -v dinitctl &>/dev/null; then
    dinitctl --user stop graphical-session 2>/dev/null
fi

sleep 0.2

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || pgrep -x Hyprland &>/dev/null; then
    hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || \
    pkill -SIGTERM -x Hyprland 2>/dev/null
else
    if command -v loginctl &>/dev/null; then
        loginctl terminate-session "${XDG_SESSION_ID:-self}" 2>/dev/null || \
        loginctl terminate-user "$USER" 2>/dev/null
    fi
fi
