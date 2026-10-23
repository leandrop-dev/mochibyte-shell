#!/usr/bin/env bash

# Installer interface, built on Charm's gum. Works in a desktop terminal and on a bare TTY.

IS_REINSTALL=false

# Palette: lipgloss downgrades these automatically on terminals with fewer colours.
UI_ACCENT="#F5A3C7"
UI_ACCENT_ALT="#9AD9C2"
UI_TEXT="#E6E1F0"
UI_MUTED="#8E8AA0"
UI_WARN="#F2CD8C"
UI_ERROR="#F28FAD"
UI_OK="#A6E3A1"

# The Linux console font lacks rounded corners and check marks, so fall back to plain glyphs there.
if [ "${TERM:-}" = "linux" ]; then
    UI_BORDER="normal"
    UI_CHECK="[x] "
    UI_UNCHECK="[ ] "
    UI_CURSOR="> "
else
    UI_BORDER="rounded"
    UI_CHECK="✓ "
    UI_UNCHECK="○ "
    UI_CURSOR="› "
fi

export GUM_CHOOSE_CURSOR="$UI_CURSOR"
export GUM_CHOOSE_CURSOR_PREFIX="$UI_UNCHECK"
export GUM_CHOOSE_SELECTED_PREFIX="$UI_CHECK"
export GUM_CHOOSE_UNSELECTED_PREFIX="$UI_UNCHECK"
export GUM_CHOOSE_CURSOR_FOREGROUND="$UI_ACCENT"
export GUM_CHOOSE_SELECTED_FOREGROUND="$UI_ACCENT_ALT"
export GUM_CHOOSE_HEADER_FOREGROUND="$UI_MUTED"
export GUM_CONFIRM_PROMPT_FOREGROUND="$UI_TEXT"
export GUM_CONFIRM_SELECTED_BACKGROUND="$UI_ACCENT"
export GUM_CONFIRM_SELECTED_FOREGROUND="#1E1E2E"

detect_active_dm() {
    local dm
    for dm in gdm gdm3 lightdm sddm lxdm lxdm-gtk3 ly greetd emptty; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            echo "$dm"
            return
        fi
    done
}

CURRENT_DM="$(detect_active_dm)"

# Keep the user's own login manager unless it is already the Mochibyte login screen
# or there is none; the login screen menu lets them switch either way.
if [ -f /etc/sddm.conf.d/10-mochibyte.conf ] || [ -z "$CURRENT_DM" ]; then
    OPT_SDDM=true
else
    OPT_SDDM=false
fi
REPLACE_DM=false
SDDM_WAYLAND="$PM_SDDM_WAYLAND_DEFAULT"

USER_NAME="${USER:-$(whoami)}"
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
[[ -z "$OS_NAME" ]] && OS_NAME="$(t "installer.os.default_os")"
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || true)
[[ -z "$CPU_INFO" ]] && CPU_INFO="$(t "installer.os.unknown_cpu")"

GPU_RAW=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
GPU_INFO=$(echo "$GPU_RAW" | sed -E 's/^[^]]*\]: //; s/ \[[0-9a-f]{4}:[0-9a-f]{4}\]//; s/ \(rev [0-9a-f]+\)//' | paste -sd, - | sed 's/,/, /g')
[[ -z "$GPU_INFO" ]] && GPU_INFO="$(t "installer.os.unknown_gpu")"

ui_label() {
    gum style --foreground "$UI_MUTED" -- "$1"
}

ui_value() {
    gum style --foreground "$UI_TEXT" --bold -- "$1"
}

# Two-column "label  value" row for the info and review cards.
ui_row() {
    gum join --horizontal "$(gum style --width 16 --foreground "$UI_MUTED" -- "$1")" "$(gum style --foreground "$UI_TEXT" -- "$2")"
}

ui_card_width() {
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    [ "$cols" -gt 92 ] && cols=92
    echo $(( cols - 4 ))
}

ui_card() {
    local title="$1"
    shift
    gum style --border "$UI_BORDER" --border-foreground "$UI_ACCENT" --padding "0 2" --margin "0 1" \
        --width "$(ui_card_width)" \
        "$(gum style --foreground "$UI_ACCENT" --bold -- "$title")" "" "$@"
}

ui_step() {
    echo
    gum style --foreground "$UI_ACCENT" --bold -- "━━ $1"
}

draw_banner() {
    gum style --foreground "$UI_ACCENT" --bold --margin "1 1 0 1" -- "$(cat << "BANNER"
███╗   ███╗ ██████╗  ██████╗██╗  ██╗██╗██████╗ ██╗   ██╗████████╗███████╗
████╗ ████║██╔═══██╗██╔════╝██║  ██║██║██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
██╔████╔██║██║   ██║██║     ███████║██║██████╔╝ ╚████╔╝    ██║   █████╗
██║╚██╔╝██║██║   ██║██║     ██╔══██║██║██╔══██╗  ╚██╔╝     ██║   ██╔══╝
██║ ╚═╝ ██║╚██████╔╝╚██████╗██║  ██║██║██████╔╝   ██║      ██║   ███████╗
╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
BANNER
)"
    gum style --foreground "$UI_MUTED" --italic --margin "0 2 1 2" -- "$(t "installer.ui.tagline")  ·  github.com/${REPO_SLUG}"
}

install_mode_label() {
    if [[ "$INSTALL_STATE" == "current" ]]; then
        t "installer.ui.mode_current"
    else
        t "installer.ui.mode_fresh"
    fi
}

draw_system_card() {
    ui_card "$(t "installer.ui.system_title")" \
        "$(ui_row "$(t "installer.ui.user")" "$USER_NAME")" \
        "$(ui_row "$(t "installer.ui.os")" "$OS_NAME")" \
        "$(ui_row "$(t "installer.ui.cpu")" "$CPU_INFO")" \
        "$(ui_row "$(t "installer.ui.gpu")" "$GPU_INFO")" \
        "$(ui_row "$(t "installer.ui.target_commit")" "$TARGET_COMMIT")" \
        "$(ui_row "$(t "installer.ui.install_mode")" "$(install_mode_label)")"
}

all_target_packages() {
    printf '%s\n' "${REQUIRED_PKGS[@]}"
    if [ "$OPT_SDDM" = true ]; then
        sddm_packages
    fi
}

missing_packages() {
    local pkgs=()
    mapfile -t pkgs < <(all_target_packages)
    pm_missing_pkgs "${pkgs[@]}"
}

# Package counts only change with the login screen choice, so they are cached per choice.
declare -A UI_PKG_COUNT_CACHE=()
package_counts() {
    if [ -z "${UI_PKG_COUNT_CACHE[$OPT_SDDM]}" ]; then
        local total missing
        total=$(all_target_packages | grep -c .)
        missing=$(missing_packages | grep -c . || true)
        UI_PKG_COUNT_CACHE[$OPT_SDDM]="$missing $total"
    fi
    echo "${UI_PKG_COUNT_CACHE[$OPT_SDDM]}"
}

selected_configs_text() {
    local entry name label src_rel mode list=()
    for entry in "${MANAGED_CONFIGS[@]}"; do
        IFS='|' read -r name label src_rel mode <<< "$entry"
        [ "${DEPLOY_CONFIGS[$name]}" = true ] && list+=("$label")
    done
    if [ ${#list[@]} -eq 0 ]; then
        t "installer.ui.summary_configs_none"
    else
        local IFS=,
        echo "${list[*]}" | sed 's/,/, /g'
    fi
}

login_screen_text() {
    if [ "$OPT_SDDM" = true ]; then
        local server="X11"
        [ "$SDDM_WAYLAND" = true ] && server="Wayland"
        t "installer.ui.login_mochibyte" "server=$server"
    elif [ -n "$CURRENT_DM" ]; then
        t "installer.ui.login_keep" "dm=$CURRENT_DM"
    else
        t "installer.ui.login_none"
    fi
}

draw_review_card() {
    local missing total
    read -r missing total <<< "$(package_counts)"

    local rows=(
        "$(ui_row "$(t "installer.ui.summary_packages")" "$(t "installer.ui.summary_packages_value" "missing=$missing" "total=$total")")"
        "$(ui_row "$(t "installer.ui.summary_configs")" "$(selected_configs_text)")"
        "$(ui_row "$(t "installer.ui.summary_login")" "$(login_screen_text)")"
    )
    if [ "$OPT_SDDM" = true ] && [ "$REPLACE_DM" = true ] && [ -n "$CURRENT_DM" ]; then
        rows+=("$(ui_row "" "$(gum style --foreground "$UI_WARN" -- "$(t "installer.ui.summary_dm_disabled" "dm=$CURRENT_DM")")")")
    fi
    rows+=("$(ui_row "$(t "installer.ui.summary_backups")" "$(t "installer.ui.summary_backups_value")")")

    ui_card "$(t "installer.ui.review_title")" "${rows[@]}"
}

show_package_overview() {
    declare -A is_missing=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && is_missing["$p"]=1
    done < <(missing_packages)

    {
        gum style --foreground "$UI_ACCENT" --bold -- "$(t "installer.ui.packages_title")"
        echo
        while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            if [[ -n "${is_missing[$p]}" ]]; then
                gum style --foreground "$UI_WARN" -- "  + $(t "installer.ui.package_missing" "pkg=$p")"
            else
                gum style --foreground "$UI_MUTED" -- "    $(t "installer.ui.package_installed" "pkg=$p")"
            fi
        done < <(all_target_packages)
    } | gum pager --soft-wrap
}

manage_configs_menu() {
    local entry name label src_rel mode options=() selected=()
    for entry in "${MANAGED_CONFIGS[@]}"; do
        IFS='|' read -r name label src_rel mode <<< "$entry"
        local state
        if [ -e "$HOME/.config/$name" ]; then
            state="$(t "installer.ui.config_exists")"
        else
            state="$(t "installer.ui.config_missing")"
        fi
        local option_label
        option_label="$(printf '%-10s %-22s %s' "$label" "~/.config/$name" "$state")"
        options+=("$option_label|$name")
        [ "${DEPLOY_CONFIGS[$name]}" = true ] && selected+=("$option_label")
    done

    local selected_csv=""
    if [ ${#selected[@]} -gt 0 ]; then
        selected_csv="$(IFS=,; echo "${selected[*]}")"
    fi

    local picked
    if ! picked=$(gum choose --no-limit --label-delimiter="|" --selected="$selected_csv" \
        --header="$(t "installer.ui.configs_header")" "${options[@]}"); then
        return 0
    fi

    for entry in "${MANAGED_CONFIGS[@]}"; do
        DEPLOY_CONFIGS["${entry%%|*}"]=false
    done
    while IFS= read -r name; do
        [[ -n "$name" ]] && DEPLOY_CONFIGS[$name]=true
    done <<< "$picked"
}

manage_sddm_menu() {
    local keep_label use_label
    if [ -n "$CURRENT_DM" ]; then
        keep_label="$(t "installer.ui.sddm_keep" "dm=$CURRENT_DM")"
    else
        keep_label="$(t "installer.ui.sddm_keep_none")"
    fi
    use_label="$(t "installer.ui.sddm_use")"

    local current_label="$keep_label"
    [ "$OPT_SDDM" = true ] && current_label="$use_label"

    local choice
    if ! choice=$(gum choose --label-delimiter="|" --selected="$current_label" \
        --header="$(t "installer.ui.sddm_header")" "$keep_label|keep" "$use_label|mochibyte"); then
        return 0
    fi

    if [ "$choice" != "mochibyte" ]; then
        OPT_SDDM=false
        REPLACE_DM=false
        return 0
    fi

    if [ -n "$CURRENT_DM" ] && [ "$CURRENT_DM" != "sddm" ]; then
        if gum confirm --default=true "$(t "installer.ui.sddm_replace_confirm" "dm=$CURRENT_DM")"; then
            REPLACE_DM=true
        else
            OPT_SDDM=false
            REPLACE_DM=false
            return 0
        fi
    fi
    OPT_SDDM=true

    local x11_label wayland_label server_current
    x11_label="$(t "installer.ui.sddm_server_x11")"
    wayland_label="$(t "installer.ui.sddm_server_wayland")"
    server_current="$x11_label"
    [ "$SDDM_WAYLAND" = true ] && server_current="$wayland_label"

    local server
    if server=$(gum choose --label-delimiter="|" --selected="$server_current" \
        --header="$(t "installer.ui.sddm_server_header")" "$wayland_label|wayland" "$x11_label|x11"); then
        if [ "$server" = "wayland" ]; then
            SDDM_WAYLAND=true
        else
            SDDM_WAYLAND=false
        fi
    fi
}

confirm_start() {
    local prompt affirm
    if [[ "$1" == "update" ]]; then
        prompt="$(t "installer.ui.confirm_update")"
        affirm="$(t "installer.ui.menu_update")"
    elif [[ "$1" == "reinstall" ]]; then
        prompt="$(t "installer.ui.confirm_reinstall")"
        affirm="$(t "installer.ui.menu_reinstall")"
    else
        prompt="$(t "installer.ui.confirm_install")"
        affirm="$(t "installer.ui.menu_install")"
    fi
    gum confirm --default=true --affirmative="$affirm" --negative="$(t "installer.ui.confirm_back")" "$prompt"
}

run_installer_ui() {
    local last_choice=""
    local header
    header="$(draw_banner; draw_system_card)"

    while true; do
        local review
        review="$(draw_review_card)"
        clear
        printf '%s\n\n%s\n' "$header" "$review"
        echo

        # Review and choose first, then act.
        local options=()
        options+=("$(t "installer.ui.menu_configs")|configs")
        options+=("$(t "installer.ui.menu_sddm")|sddm")
        options+=("$(t "installer.ui.menu_packages")|packages")
        if [[ "$INSTALL_STATE" == "current" ]]; then
            options+=("$(t "installer.ui.menu_update")|update")
            options+=("$(t "installer.ui.menu_reinstall")|reinstall")
        else
            options+=("$(t "installer.ui.menu_install")|install")
        fi
        options+=("$(t "installer.ui.menu_exit")|exit")

        local cursor_label=""
        if [ -n "$last_choice" ]; then
            local opt
            for opt in "${options[@]}"; do
                [[ "${opt##*|}" == "$last_choice" ]] && cursor_label="${opt%|*}"
            done
        fi

        local choice
        if ! choice=$(gum choose --label-delimiter="|" --selected="$cursor_label" \
            --header="$(t "installer.ui.menu_header")" "${options[@]}"); then
            choice="exit"
        fi
        last_choice="$choice"

        case "$choice" in
            install|update|reinstall)
                # Configs are only placed on a fresh install or a reinstall.
                if [[ "$choice" == "update" ]]; then
                    IS_REINSTALL=false
                elif [[ "$choice" == "reinstall" ]]; then
                    IS_REINSTALL=true
                fi
                if confirm_start "$choice"; then
                    clear
                    return 0
                fi
                ;;
            configs)
                manage_configs_menu
                ;;
            sddm)
                manage_sddm_menu
                ;;
            packages)
                show_package_overview
                ;;
            exit)
                clear
                exit 0
                ;;
        esac
    done
}

draw_completion_screen() {
    local target_commit="$1"
    echo
    local lines=(
        "$(gum style --foreground "$UI_OK" --bold -- "$(t "installer.ui.installed_success" "commit=$target_commit")")"
        ""
        "$(gum style --foreground "$UI_TEXT" -- "$(t "installer.ui.restart_prompt")")"
    )

    if [ -d "$BACKUP_ROOT" ]; then
        lines+=("" "$(ui_label "$(t "installer.ui.backups_saved" "path=${BACKUP_ROOT/#$HOME/\~}")")")
        if [ -f "$BACKUP_ROOT/disabled-display-managers.txt" ]; then
            lines+=("$(gum style --foreground "$UI_WARN" -- "$(t "installer.ui.dm_disabled_note" "dms=$(paste -sd, "$BACKUP_ROOT/disabled-display-managers.txt")")")")
        fi
    fi

    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        lines+=("" "$(gum style --foreground "$UI_ERROR" --bold -- "$(t "installer.ui.failed_packages")")")
        local fp
        for fp in "${FAILED_PKGS[@]}"; do
            lines+=("$(gum style --foreground "$UI_WARN" -- "  • $fp")")
        done
    fi

    gum style --border "$UI_BORDER" --border-foreground "$UI_OK" --padding "1 2" --margin "0 1" --width "$(ui_card_width)" "${lines[@]}"
    echo

    if gum confirm --default=false "$(t "installer.ui.confirm_reboot")"; then
        sudo reboot now
    fi
}
