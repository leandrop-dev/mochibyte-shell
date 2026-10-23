#!/usr/bin/env bash

set -e

setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

RAW_SLUG="${REPO_SLUG:-leandrop-dev/mochibyte-shell}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/mochibyte-installer"
export REPO_SLUG

if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
else
    INSTALL_DIR=""
    PROJECT_ROOT=""
fi

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    if ! command -v git &>/dev/null; then
        sudo pacman -Sy --noconfirm --needed git
    fi
    if [ ! -d "$CACHE_BASE/.git" ]; then
        rm -rf "$CACHE_BASE"
        mkdir -p "$CACHE_BASE"
        git clone "https://github.com/${REPO_SLUG}.git" "$CACHE_BASE"
    else
        git -C "$CACHE_BASE" remote set-url origin "https://github.com/${REPO_SLUG}.git" 2>/dev/null || true
        git -C "$CACHE_BASE" fetch origin 2>/dev/null || true
        git -C "$CACHE_BASE" reset --hard origin/HEAD 2>/dev/null || git -C "$CACHE_BASE" reset --hard origin/main 2>/dev/null || true
    fi
    INSTALL_DIR="$CACHE_BASE/install"
    PROJECT_ROOT="$CACHE_BASE"
fi

export MOCHIBYTE_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

MODULES_DIR="$INSTALL_DIR/modules"

source "$PROJECT_ROOT/src/scripts/i18n.sh"
source "$MODULES_DIR/pm.sh"
source "$MODULES_DIR/deps.sh"
source "$MODULES_DIR/state.sh"
source "$MODULES_DIR/deploy.sh"
source "$MODULES_DIR/version.sh"
source "$MODULES_DIR/config.sh"
source "$MODULES_DIR/service.sh"
source "$MODULES_DIR/ui.sh"

check_supported_os
bootstrap_installer_deps

INSTALL_STATE=$(detect_install_state)
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")
OLD_COMMIT=""
if [[ "$INSTALL_STATE" == "current" ]]; then
    OLD_COMMIT=$(get_installed_commit)
fi

run_installer_ui

TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")

ui_step "$(t "installer.ui.step_packages")"
install_dependencies "$INSTALL_STATE" "$IS_REINSTALL"

ui_step "$(t "installer.ui.step_deploy")"
deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE"

if [ "$OPT_SDDM" = true ]; then
    ui_step "$(t "installer.ui.step_login")"
fi
setup_sddm "$PROJECT_ROOT" "$INSTALL_STATE" "$IS_REINSTALL"

ui_step "$(t "installer.ui.step_finish")"
WALLPAPER_DIR=$(get_wallpaper_dir)
mkdir -p "$WALLPAPER_DIR"
init_mochibyte_config "$PROJECT_ROOT" "$WALLPAPER_DIR" "$INSTALL_STATE" "$IS_REINSTALL"

setup_services
write_version_state "$TARGET_COMMIT"

if [[ "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    rm -f "$HOME/.local/state/mochibyte/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
fi

draw_completion_screen "$TARGET_COMMIT"
