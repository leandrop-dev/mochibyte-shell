#!/usr/bin/env bash

# Configs the installer can place in ~/.config/<name>: name|label|source in the repo|mode.
# "mirror" also removes files the shell does not ship; "merge" only adds and overwrites.
MANAGED_CONFIGS=(
    "hypr|Hyprland|compositors/hyprland|mirror"
    "kitty|Kitty|config/kitty|merge"
    "cava|Cava|config/cava|merge"
    "fastfetch|Fastfetch|config/fastfetch|merge"
)

declare -A DEPLOY_CONFIGS=()
for _entry in "${MANAGED_CONFIGS[@]}"; do
    DEPLOY_CONFIGS["${_entry%%|*}"]=true
done
unset _entry

BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/mochibyte/backups/$(date +%Y%m%d_%H%M%S)"

# Copies a file or directory into this run's backup folder before it gets replaced.
# Returns non-zero when the copy fails, so the caller leaves the original untouched.
backup_path() {
    local src="$1"
    local name="$2"
    local use_sudo="${3:-false}"

    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        return 0
    fi
    if [ -d "$src" ] && [ -r "$src" ] && [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
        return 0
    fi

    local dest="$BACKUP_ROOT/$name"
    mkdir -p "$(dirname "$dest")"

    local ok=true
    if [ "$use_sudo" = true ]; then
        if sudo cp -a "$src" "$dest"; then
            sudo chown -R "$(id -u):$(id -g)" "$dest" || true
        else
            ok=false
        fi
    elif ! cp -a "$src" "$dest"; then
        ok=false
    fi

    if [ "$ok" != true ]; then
        echo -e "  \e[31m[ ERROR ]\e[0m $(t "installer.deploy.backup_failed" "src=$src")" >&2
        return 1
    fi
    echo -e "  \e[36m[ BACKUP ]\e[0m $(t "installer.deploy.backed_up" "src=$src" "dest=$dest")"
}

deploy_managed_config() {
    local repo_root="$1"
    local name="$2"
    local src_rel="$3"
    local mode="$4"
    local src="$repo_root/$src_rel"
    local dest="$HOME/.config/$name"

    if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
        return 0
    fi

    backup_path "$dest" "config/$name" || return 0

    mkdir -p "$dest"
    cp -r "$src/." "$dest/"

    if [ "$mode" = "mirror" ]; then
        find "$dest" -type f -o -type l | while IFS= read -r dest_file; do
            local rel_path="${dest_file#$dest/}"
            if [ ! -e "$src/$rel_path" ] && [ ! -L "$src/$rel_path" ]; then
                rm -f "$dest_file"
            fi
        done
        find "$dest" -depth -type d -empty ! -path "$dest" -delete 2>/dev/null || true
    fi
}

get_wallpaper_dir() {
    local user_pics=""
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        user_pics=$(grep '^XDG_PICTURES_DIR' "$HOME/.config/user-dirs.dirs" 2>/dev/null | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
    fi
    if [[ -z "$user_pics" || "$user_pics" == "$HOME" ]]; then
        if command -v xdg-user-dir &>/dev/null; then
            user_pics="$(xdg-user-dir PICTURES 2>/dev/null || true)"
        fi
    fi
    if [[ -z "$user_pics" || "$user_pics" == "$HOME" ]]; then
        user_pics="$HOME/Pictures"
    fi
    user_pics="${user_pics%/}"
    echo "$user_pics/Wallpapers"
}

resolve_sddm_backend() {
    local requested_wayland="${1:-false}"
    local wayland_cmd="" bin

    if bin="$(find_sddm_binary weston)"; then
        wayland_cmd="$bin --shell=kiosk"
    elif bin="$(find_sddm_binary kwin_wayland)"; then
        wayland_cmd="$bin --no-global-shortcuts --no-lockscreen --locale1"
    fi

    local has_xorg=false
    if sddm_has_xorg; then
        has_xorg=true
    fi

    if [ "$requested_wayland" = true ]; then
        if [ -n "$wayland_cmd" ]; then
            printf 'wayland\n%s\n' "$wayland_cmd"
            return 0
        elif [ "$has_xorg" = true ]; then
            echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_no_wayland_compositor")" >&2
            echo "x11"
            return 0
        fi
    else
        if [ "$has_xorg" = true ]; then
            echo "x11"
            return 0
        elif [ -n "$wayland_cmd" ]; then
            echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_no_xorg" "compositor=${wayland_cmd%% *}")" >&2
            printf 'wayland\n%s\n' "$wayland_cmd"
            return 0
        fi
    fi

    echo -e "  \e[31m[ ERROR ]\e[0m $(t "installer.deploy.sddm_no_backend")" >&2
    return 1
}

setup_sddm() {
    local project_root="$1"
    local install_state="${2:-$INSTALL_STATE}"
    local is_reinstall="${3:-$IS_REINSTALL}"

    if [ "$OPT_SDDM" != true ]; then
        return 0
    fi

    local sddm_display_server=""
    local sddm_compositor_cmd=""
    local backend_output=""
    if ! backend_output=$(resolve_sddm_backend "$SDDM_WAYLAND"); then
        echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_skipped")" >&2
        return 0
    fi

    {
        read -r sddm_display_server
        read -r sddm_compositor_cmd || true
    } <<< "$backend_output"

    local is_update=false
    if [[ "$install_state" == "current" && "$is_reinstall" != "true" ]]; then
        is_update=true
    fi

    local init_sys="generic"
    if declare -f detect_init_system >/dev/null; then
        init_sys=$(detect_init_system)
    fi

    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deploy.configuring_sddm")"

    if ! backup_path /etc/sddm.conf "sddm/sddm.conf" true \
        || ! backup_path /etc/sddm.conf.d "sddm/sddm.conf.d" true \
        || ! backup_path /usr/share/sddm/themes/material-you "sddm/themes/material-you" true \
        || ! backup_path /usr/share/sddm/themes/matugen-minimal "sddm/themes/matugen-minimal" true; then
        echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_backup_skipped")" >&2
        return 0
    fi

    if [ "$is_update" != true ] && [ "$REPLACE_DM" = true ]; then
        local dms=("gdm" "gdm3" "lightdm" "lxdm" "lxdm-gtk3" "ly" "greetd" "emptty")
        for dm in "${dms[@]}"; do
            pm_is_installed "$dm" || continue
            echo "  $(t "installer.deploy.disabling_dm" "dm=$dm")"
            disable_system_service "$dm" "$init_sys"
            mkdir -p "$BACKUP_ROOT"
            echo "$dm" >> "$BACKUP_ROOT/disabled-display-managers.txt"
        done
    fi

    sudo rm -rf /usr/share/sddm/themes/matugen-minimal
    sudo rm -rf /usr/share/sddm/themes/material-you
    sudo rm -f /etc/sddm.conf.d/*matugen*.conf
    sudo rm -f /etc/sddm.conf.d/*material-you*.conf

    if [ "$is_update" != true ]; then
        sudo rm -f /etc/sddm.conf
    fi

    local sddm_theme_src="$project_root/config/sddm/themes/material-you"
    local sddm_theme_dest="/usr/share/sddm/themes/material-you"

    if [ -d "$sddm_theme_src" ]; then
        sudo mkdir -p "$sddm_theme_dest"
        sudo cp -r "$sddm_theme_src/." "$sddm_theme_dest/"
        sudo chmod -R 755 "$sddm_theme_dest"
        if [ -d "$sddm_theme_src/font" ]; then
            sudo mkdir -p /usr/share/fonts/TTF
            sudo cp -r "$sddm_theme_src/font/"*.ttf /usr/share/fonts/TTF/ 2>/dev/null || true
            fc-cache -f /usr/share/fonts >/dev/null 2>&1 || true
        fi
    fi

    sudo mkdir -p /etc/sddm.conf.d

    if [ "$sddm_display_server" = "wayland" ]; then
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-material-you.conf > /dev/null
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
InputMethod=

[Wayland]
CompositorCommand=$sddm_compositor_cmd
EOF
    else
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-material-you.conf > /dev/null
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
DisplayServer=x11
InputMethod=
EOF
    fi

    if declare -f enable_system_service >/dev/null; then
        enable_system_service "sddm" "$init_sys"
    else
        case "$init_sys" in
            systemd)
                sudo systemctl enable --now sddm.service 2>/dev/null || sudo systemctl enable -f sddm.service 2>/dev/null || sudo systemctl enable sddm 2>/dev/null || true
                ;;
            openrc)
                sudo rc-update add sddm default 2>/dev/null || true
                sudo rc-service sddm start 2>/dev/null || true
                ;;
            dinit)
                sudo dinitctl enable sddm 2>/dev/null || sudo dinitctl start sddm 2>/dev/null || true
                ;;
            runit)
                if [ -d "/etc/sv/sddm" ]; then
                    sudo ln -sf "/etc/sv/sddm" /var/service/ 2>/dev/null || true
                fi
                ;;
            s6)
                sudo s6-rc-bundle-update -b add default sddm 2>/dev/null || true
                ;;
            *)
                sudo systemctl enable sddm.service -f 2>/dev/null || true
                ;;
        esac
    fi

    echo -e "  \e[32m$(t "installer.deploy.sddm_success")\e[0m"
}

setup_pam_service() {
    local pam_dir="/etc/pam.d"
    local target="$pam_dir/mochibyte"
    local base=""

    [ -d "$pam_dir" ] || return 0

    for candidate in system-auth login; do
        if [ -f "$pam_dir/$candidate" ]; then
            base="$candidate"
            break
        fi
    done
    [ -n "$base" ] || return 0

    local content=""
    if ! grep -qs "pam_fprintd" "$pam_dir/$base"; then
        content+="-auth       sufficient   pam_fprintd.so"$'\n'
    fi
    content+="auth        include      $base"$'\n'
    content+="account     include      $base"$'\n'

    if [ -f "$target" ] && [ "$(cat "$target" 2>/dev/null)" = "${content%$'\n'}" ]; then
        return 0
    fi

    printf '%s' "$content" | sudo tee "$target" >/dev/null 2>&1 || true
    sudo chmod 644 "$target" 2>/dev/null || true
}

install_desktop_entry() {
    local REPO_ROOT="$1"
    local BIN_DIR="$2"
    local src_dir="$REPO_ROOT/packaging/desktop"
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local apps_dir="$data_home/applications"
    local icons_dir="$data_home/icons/hicolor/scalable/apps"

    [ -f "$src_dir/mochibyte-settings.desktop" ] || return 0

    mkdir -p "$apps_dir" "$icons_dir"
    sed "s|^Exec=.*|Exec=\"$BIN_DIR/mochibyte\" settings|" "$src_dir/mochibyte-settings.desktop" > "$apps_dir/mochibyte-settings.desktop"
    chmod 644 "$apps_dir/mochibyte-settings.desktop"

    if [ -f "$src_dir/mochibyte-settings.svg" ]; then
        cp "$src_dir/mochibyte-settings.svg" "$icons_dir/mochibyte-settings.svg"
        chmod 644 "$icons_dir/mochibyte-settings.svg"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
    fi
}

deploy_package() {
    local REPO_ROOT="$1"
    local OLD_COMMIT="$2"
    local NEW_COMMIT="$3"
    local IS_REINSTALL="$4"
    local INSTALL_STATE="$5"

    local TARGET_BASE="$HOME/.local/share/mochibyte"
    local BIN_DIR="$HOME/.local/bin"

    local is_update=false
    if [[ "$INSTALL_STATE" == "current" && "$IS_REINSTALL" != "true" ]]; then
        is_update=true
    fi

    local do_full_deploy=true

    if [ "$IS_REINSTALL" != "true" ] && [ -n "$OLD_COMMIT" ] && [ "$OLD_COMMIT" != "unknown" ] && [ -d "$REPO_ROOT/.git" ]; then
        if git -C "$REPO_ROOT" cat-file -e "$OLD_COMMIT" 2>/dev/null; then
            do_full_deploy=false
        fi
    fi

    if [ "$do_full_deploy" = true ]; then
        rm -rf "$TARGET_BASE"
        mkdir -p "$TARGET_BASE/bin" "$TARGET_BASE/src" "$BIN_DIR"

        if [ -d "$REPO_ROOT/bin" ] && [ "$(ls -A "$REPO_ROOT/bin" 2>/dev/null)" ]; then
            cp -r "$REPO_ROOT/bin/." "$TARGET_BASE/bin/"
            chmod +x "$TARGET_BASE/bin/"* 2>/dev/null || true
        fi

        if [ -d "$REPO_ROOT/src" ] && [ "$(ls -A "$REPO_ROOT/src" 2>/dev/null)" ]; then
            cp -r "$REPO_ROOT/src/." "$TARGET_BASE/src/"
            find "$TARGET_BASE/src/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
        fi

        if [ "$is_update" != "true" ]; then
            local entry name label src_rel mode
            for entry in "${MANAGED_CONFIGS[@]}"; do
                IFS='|' read -r name label src_rel mode <<< "$entry"
                [ "${DEPLOY_CONFIGS[$name]}" = true ] || continue
                deploy_managed_config "$REPO_ROOT" "$name" "$src_rel" "$mode"
            done
        fi
    else
        mkdir -p "$TARGET_BASE/bin" "$TARGET_BASE/src" "$BIN_DIR"

        local changed_files=""
        local deleted_files=""

        if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
            changed_files=$(git -C "$REPO_ROOT" diff --name-only --no-renames --diff-filter=AM "$OLD_COMMIT" "$NEW_COMMIT" 2>/dev/null || true)
            deleted_files=$(git -C "$REPO_ROOT" diff --name-only --no-renames --diff-filter=D "$OLD_COMMIT" "$NEW_COMMIT" 2>/dev/null || true)
        fi

        if [ -n "$deleted_files" ]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if [[ "$file" == bin/* ]]; then
                    rm -f "$TARGET_BASE/$file"
                elif [[ "$file" == src/* ]]; then
                    rm -f "$TARGET_BASE/$file"
                fi
            done <<< "$deleted_files"
        fi

        if [ -n "$changed_files" ]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if [[ "$file" == bin/* ]]; then
                    mkdir -p "$(dirname "$TARGET_BASE/$file")"
                    cp "$REPO_ROOT/$file" "$TARGET_BASE/$file"
                    chmod +x "$TARGET_BASE/$file" 2>/dev/null || true
                elif [[ "$file" == src/* ]]; then
                    mkdir -p "$(dirname "$TARGET_BASE/$file")"
                    cp "$REPO_ROOT/$file" "$TARGET_BASE/$file"
                    if [[ "$file" == *.sh ]]; then
                        chmod +x "$TARGET_BASE/$file" 2>/dev/null || true
                    fi
                fi
            done <<< "$changed_files"
        fi
    fi

    if [ -f "$TARGET_BASE/bin/mochibyte" ]; then
        ln -sf "$TARGET_BASE/bin/mochibyte" "$BIN_DIR/mochibyte"
        sudo ln -sf "$TARGET_BASE/bin/mochibyte" /usr/local/bin/mochibyte 2>/dev/null || true
    fi

    if [ -f "$TARGET_BASE/bin/mochibyted" ]; then
        ln -sf "$TARGET_BASE/bin/mochibyted" "$BIN_DIR/mochibyted"
        sudo ln -sf "$TARGET_BASE/bin/mochibyted" /usr/local/bin/mochibyted 2>/dev/null || true
    fi

    install_desktop_entry "$REPO_ROOT" "$BIN_DIR"

    setup_pam_service
}
