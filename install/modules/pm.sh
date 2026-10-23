#!/usr/bin/env bash

PM_SDDM_WAYLAND_DEFAULT=true

PM_BOOTSTRAP_TOOLS=(gum jq curl git pciutils unzip fontconfig base-devel)

pm_prepare_repos() {
    if [ -f /etc/pacman.conf ]; then
        if grep -q "^#\[multilib\]" /etc/pacman.conf; then
            sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
            sudo pacman -Sy --noconfirm >/dev/null 2>&1 || true
        fi
    fi
}

pm_bootstrap_install() {
    sudo pacman -Sy --noconfirm --needed "$@"
}

pm_bootstrap_helper() {
    if command -v yay &>/dev/null || command -v paru &>/dev/null; then
        return 0
    fi

    local helper
    if ! helper=$(gum choose --label-delimiter="|" --header="$(t "installer.deps.aur_helper_header")" \
        "$(t "installer.deps.aur_helper_yay")|yay" "$(t "installer.deps.aur_helper_paru")|paru"); then
        echo "$(t "installer.deps.aur_helper_cancelled")" >&2
        exit 1
    fi

    # Prefer a repo build when the distro ships one (CachyOS does), otherwise build the -bin package from the AUR.
    if pacman -Si "$helper" &>/dev/null; then
        sudo pacman -S --noconfirm --needed "$helper"
        return 0
    fi

    local cache_build="${XDG_CACHE_HOME:-"$HOME/.cache"}/mochibyte-$helper-bin"
    rm -rf "$cache_build"
    mkdir -p "$cache_build"
    git clone "https://aur.archlinux.org/$helper-bin.git" "$cache_build"
    (cd "$cache_build" && makepkg -si --noconfirm)
    rm -rf "$cache_build"
}

pm_full_upgrade() {
    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deps.syncing")"
    sudo pacman -Syyu --noconfirm
}

pm_missing_pkgs() {
    pacman -T "$@" 2>/dev/null || true
}

pm_is_installed() {
    pacman -Q "$1" &>/dev/null
}

pm_install_pkg() {
    local pkg="$1"
    local safe_jobs="$2"

    if pacman -Si "$pkg" &>/dev/null; then
        sudo pacman -S --noconfirm --needed "$pkg"
    elif command -v yay &>/dev/null; then
        env CARGO_BUILD_JOBS="$safe_jobs" MAKEFLAGS="-j$safe_jobs" yay -S --noconfirm --needed "$pkg"
    elif command -v paru &>/dev/null; then
        env CARGO_BUILD_JOBS="$safe_jobs" MAKEFLAGS="-j$safe_jobs" paru -S --noconfirm --needed "$pkg"
    else
        sudo pacman -S --noconfirm --needed "$pkg"
    fi
}

pm_upgrade_quickshell() {
    if sudo pacman -Syu --noconfirm --needed --ask=4 quickshell && quickshell_is_current; then
        return 0
    fi

    local helper
    for helper in yay paru; do
        command -v "$helper" &>/dev/null || continue
        "$helper" -S --noconfirm --needed --ask=4 quickshell-git && quickshell_is_current && return 0
        break
    done
    return 0
}

pm_remove_conflicting_pkg() {
    local pkg="$1"
    if pm_is_installed "$pkg"; then
        yay -R --noconfirm "$pkg" 2>/dev/null || sudo pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
    fi
}
