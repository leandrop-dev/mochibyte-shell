#!/usr/bin/env bash

# Only the installer writes both of these, so running the shell from a checkout
# (or merely sourcing its scripts) never makes a fresh system look installed.
detect_install_state() {
    if [[ -f "$HOME/.local/state/mochibyte/version" && -x "$HOME/.local/share/mochibyte/bin/mochibyte" ]]; then
        echo "current"
    else
        echo "fresh"
    fi
}
