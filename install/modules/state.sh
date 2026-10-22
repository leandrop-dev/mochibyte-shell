#!/usr/bin/env bash

detect_install_state() {
    if [[ -f "$HOME/.local/state/mochibyte/version" ]]; then
        echo "current"
    else
        echo "fresh"
    fi
}
