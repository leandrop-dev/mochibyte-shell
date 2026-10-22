#!/usr/bin/env bash

RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
C_BLUE=$'\e[34m'
C_CYAN=$'\e[36m'
C_GREEN=$'\e[32m'
C_YELLOW=$'\e[33m'
C_RED=$'\e[31m'
C_MAGENTA=$'\e[35m'

IS_REINSTALL=false

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

# Keep the user's own login manager unless it is already the Mochibyte theme
# or there is none; the SDDM menu lets them switch either way.
if [ -f /etc/sddm.conf.d/10-material-you.conf ] || [ -z "$CURRENT_DM" ]; then
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
GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs)
[[ -z "$GPU_INFO" ]] && GPU_INFO="$(t "installer.os.unknown_gpu")"

cleanup_terminal() {
    printf "\e[?25h" 2>/dev/null || true
    stty echo icanon 2>/dev/null || true
}
trap cleanup_terminal EXIT INT TERM

read_key() {
    local key=""
    local rest=""
    IFS= read -rsn1 key 2>/dev/null
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.05 rest 2>/dev/null
        if [[ "$rest" == "[A" || "$rest" == "OA" ]]; then
            echo "UP"
            return
        elif [[ "$rest" == "[B" || "$rest" == "OB" ]]; then
            echo "DOWN"
            return
        elif [[ "$rest" == "[C" || "$rest" == "OC" ]]; then
            echo "RIGHT"
            return
        elif [[ "$rest" == "[D" || "$rest" == "OD" ]]; then
            echo "LEFT"
            return
        elif [[ "$rest" == *"["* ]]; then
            local trailing=""
            while read -rsn1 -t 0.05 trailing 2>/dev/null; do
                [[ -z "$trailing" ]] && break
            done
            echo "ESC"
            return
        elif [[ -z "$rest" ]]; then
            echo "ESC"
            return
        fi
        echo "ESC"
        return
    elif [[ -z "$key" || "$key" == $'\n' || "$key" == $'\r' ]]; then
        echo "ENTER"
        return
    elif [[ "$key" == " " ]]; then
        echo "SPACE"
        return
    fi
    echo "$key"
}

draw_banner() {
    clear
    printf "%s%s" "$BOLD" "$C_CYAN"
    cat << "BANNER"
███╗   ███╗ ██████╗  ██████╗██╗  ██╗██╗██████╗ ██╗   ██╗████████╗███████╗
████╗ ████║██╔═══██╗██╔════╝██║  ██║██║██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
██╔████╔██║██║   ██║██║     ███████║██║██████╔╝ ╚████╔╝    ██║   █████╗  
██║╚██╔╝██║██║   ██║██║     ██╔══██║██║██╔══██╗  ╚██╔╝     ██║   ██╔══╝  
██║ ╚═╝ ██║╚██████╔╝╚██████╗██║  ██║██║██████╔╝   ██║      ██║   ███████╗
╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
BANNER
    printf "%s\n" "$RESET"

    local OSC8_GH=$'\e]8;;https://github.com/'"${REPO_SLUG}"$'\a'
    local OSC8_END=$'\e]8;;\a'

    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s%s $(t "installer.ui.github")%s   %shttps://github.com/%s%s\n" "$BOLD" "$C_GREEN" "$RESET" "$OSC8_GH" "$REPO_SLUG" "$OSC8_END"
    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s $(t "installer.ui.user")%s %-25s | %s$(t "installer.ui.os")%s %s\n" "$BOLD" "$RESET" "$USER_NAME" "$BOLD" "$RESET" "$OS_NAME"
    printf "\033[K%s $(t "installer.ui.cpu")%s  %-25s | %s$(t "installer.ui.gpu")%s %s\n" "$BOLD" "$RESET" "$CPU_INFO" "$BOLD" "$RESET" "$GPU_INFO"
    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s $(t "installer.ui.target_commit")%s %-18s | %s$(t "installer.ui.install_mode")%s %s\n" "$BOLD" "$RESET" "$TARGET_COMMIT" "$BOLD" "$RESET" "$INSTALL_STATE"
    printf "\033[K%s================================================================================%s\n\n" "$C_BLUE" "$RESET"
}

show_package_overview() {
    local target_list=("${REQUIRED_PKGS[@]}")
    if [ "$OPT_SDDM" = true ]; then
        local sddm_pkgs=()
        mapfile -t sddm_pkgs < <(sddm_packages)
        target_list+=("${sddm_pkgs[@]}")
    fi

    local missing_raw
    missing_raw=$(pm_missing_pkgs "${target_list[@]}")

    declare -A is_missing
    while IFS= read -r p; do
        [[ -n "$p" ]] && is_missing["$p"]=1
    done <<< "$missing_raw"

    local overview_items=()
    for pkg in "${target_list[@]}"; do
        if [[ -n "${is_missing[$pkg]}" ]]; then
            overview_items+=("$(t "installer.ui.package_missing" "pkg=$pkg")")
        else
            overview_items+=("$(t "installer.ui.package_installed" "pkg=$pkg")")
        fi
    done

    cleanup_terminal
    printf "%s\n" "${overview_items[@]}" | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --margin=1,2 \
        --height=25 \
        --prompt="$(t "installer.ui.packages_prompt")" \
        --header="$(t "installer.ui.packages_header")" > /dev/null || true
    stty -echo icanon 2>/dev/null || true
    printf "\e[?25l"
}

manage_sddm_menu() {
    draw_banner
    stty -echo 2>/dev/null || true
    printf "\e[?25l"
    printf "%s%s$(t "installer.ui.sddm_title")%s\n\n" "$BOLD" "$C_CYAN" "$RESET"

    local current_dm="$CURRENT_DM"

    if [ -n "$current_dm" ]; then
        printf "$(t "installer.ui.sddm_detected_active" "dm=${BOLD}${C_YELLOW}%s${RESET}")\n\n" "$current_dm"
    else
        printf "%s\n\n" "$(t "installer.ui.sddm_detected_none")"
    fi

    local cursor=0
    local rendered_lines=0

    while true; do
        local S_SDDM="${DIM}[Disabled]${RESET}"
        local S_RDM="${DIM}[No]${RESET}"
        local S_WAY="${DIM}[X11/Default]${RESET}"

        [ "$OPT_SDDM" = true ] && S_SDDM="${C_GREEN}[Enabled]${RESET}"
        [ "$REPLACE_DM" = true ] && S_RDM="${C_GREEN}[Yes]${RESET}"
        [ "$SDDM_WAYLAND" = true ] && S_WAY="${C_GREEN}[Wayland]${RESET}"

        local items=()
        items+=("1. $(t "installer.ui.sddm_opt_install") $S_SDDM")
        if [ -n "$current_dm" ] && [ "$current_dm" != "sddm" ]; then
            items+=("2. $(t "installer.ui.sddm_opt_disable" "dm=$current_dm") $S_RDM")
        fi
        items+=("3. $(t "installer.ui.sddm_opt_wayland") $S_WAY")
        items+=("4. ${BOLD}${C_GREEN}$(t "installer.ui.done")${RESET}")

        if [ "$rendered_lines" -gt 0 ]; then
            printf "\033[%dA" "$rendered_lines"
        fi

        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cursor" ]; then
                printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
            else
                printf "\r\033[K    %s\n" "${items[$i]}"
            fi
        done
        rendered_lines=${#items[@]}

        local key
        key=$(read_key)

        case "$key" in
            UP|[kK])
                if [ "$cursor" -gt 0 ]; then
                    cursor=$(( cursor - 1 ))
                else
                    cursor=$(( ${#items[@]} - 1 ))
                fi
                ;;
            DOWN|[jJ])
                if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                    cursor=$(( cursor + 1 ))
                else
                    cursor=0
                fi
                ;;
            ENTER|SPACE)
                local selected_str="${items[$cursor]}"
                case "$selected_str" in
                    *"1."*)
                        OPT_SDDM=$([ "$OPT_SDDM" = true ] && echo false || echo true)
                        if [ "$OPT_SDDM" = true ] && [ -n "$current_dm" ] && [ "$current_dm" != "sddm" ]; then
                            REPLACE_DM=true
                        elif [ "$OPT_SDDM" != true ]; then
                            REPLACE_DM=false
                        fi
                        ;;
                    *"2."*)
                        REPLACE_DM=$([ "$REPLACE_DM" = true ] && echo false || echo true)
                        ;;
                    *"3."*)
                        SDDM_WAYLAND=$([ "$SDDM_WAYLAND" = true ] && echo false || echo true)
                        ;;
                    *"4."*)
                        break
                        ;;
                esac
                ;;
            ESC|[qQ])
                break
                ;;
        esac
    done
}

toggle_config() {
    local name="$1"
    if [ "${DEPLOY_CONFIGS[$name]}" = true ]; then
        DEPLOY_CONFIGS[$name]=false
    else
        DEPLOY_CONFIGS[$name]=true
    fi
}

selected_config_count() {
    local count=0 name
    for name in "${!DEPLOY_CONFIGS[@]}"; do
        [ "${DEPLOY_CONFIGS[$name]}" = true ] && count=$(( count + 1 ))
    done
    echo "$count"
}

manage_configs_menu() {
    draw_banner
    stty -echo 2>/dev/null || true
    printf "\e[?25l"
    printf "%s%s$(t "installer.ui.configs_title")%s\n" "$BOLD" "$C_CYAN" "$RESET"
    printf "%s\n" "$(t "installer.ui.configs_hint")"
    printf "%s%s%s\n\n" "$DIM" "$(t "installer.ui.configs_backup_dir" "path=$BACKUP_ROOT")" "$RESET"

    local cursor=0
    local rendered_lines=0

    while true; do
        local items=()
        local names=()
        local entry name label src_rel mode
        for entry in "${MANAGED_CONFIGS[@]}"; do
            IFS='|' read -r name label src_rel mode <<< "$entry"
            local mark="${DIM}[ ]${RESET}"
            [ "${DEPLOY_CONFIGS[$name]}" = true ] && mark="${C_GREEN}[✓]${RESET}"
            local state="${DIM}$(t "installer.ui.config_missing")${RESET}"
            if [ -e "$HOME/.config/$name" ]; then
                if [ "${DEPLOY_CONFIGS[$name]}" = true ]; then
                    state="${C_YELLOW}$(t "installer.ui.config_backed_up")${RESET}"
                else
                    state="${DIM}$(t "installer.ui.config_kept")${RESET}"
                fi
            fi
            items+=("$(( ${#items[@]} + 1 )). $mark $label  ${DIM}~/.config/$name${RESET}  $state")
            names+=("$name")
        done
        items+=("$(( ${#items[@]} + 1 )). ${BOLD}${C_GREEN}$(t "installer.ui.done")${RESET}")

        if [ "$rendered_lines" -gt 0 ]; then
            printf "\033[%dA" "$rendered_lines"
        fi

        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cursor" ]; then
                printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
            else
                printf "\r\033[K    %s\n" "${items[$i]}"
            fi
        done
        rendered_lines=${#items[@]}

        local key
        key=$(read_key)

        local pick=-1
        case "$key" in
            UP|[kK])
                if [ "$cursor" -gt 0 ]; then
                    cursor=$(( cursor - 1 ))
                else
                    cursor=$(( ${#items[@]} - 1 ))
                fi
                ;;
            DOWN|[jJ])
                if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                    cursor=$(( cursor + 1 ))
                else
                    cursor=0
                fi
                ;;
            [1-9])
                pick=$(( key - 1 ))
                ;;
            ENTER|SPACE)
                pick=$cursor
                ;;
            ESC|[qQ])
                break
                ;;
        esac

        if [ "$pick" -ge 0 ]; then
            if [ "$pick" -lt "${#names[@]}" ]; then
                toggle_config "${names[$pick]}"
            elif [ "$pick" -eq "${#names[@]}" ]; then
                break
            fi
        fi
    done
}

# Returns 0 to proceed with the install, 1 to redraw the menu.
run_menu_action() {
    local action="$1"
    case "$action" in
        overview)
            show_package_overview
            return 1
            ;;
        configs)
            manage_configs_menu
            return 1
            ;;
        sddm)
            manage_sddm_menu
            return 1
            ;;
        install|update)
            IS_REINSTALL=false
            cleanup_terminal
            return 0
            ;;
        reinstall)
            IS_REINSTALL=true
            cleanup_terminal
            return 0
            ;;
        exit)
            cleanup_terminal
            clear
            exit 0
            ;;
    esac
    return 1
}

run_installer_ui() {
    local cursor=0

    while true; do
        draw_banner
        stty -echo 2>/dev/null || true
        printf "\e[?25l"

        local rendered_lines=0

        while true; do
            local S_SDDM="${DIM}[$(t "installer.ui.sddm_keep_current")${CURRENT_DM:+: $CURRENT_DM}]${RESET}"
            [ "$OPT_SDDM" = true ] && S_SDDM="${C_GREEN}[$(t "installer.ui.sddm_use_mochibyte")]${RESET}"

            local items=()
            local actions=()
            items+=("1. $(t "installer.ui.menu_overview" "count=${#REQUIRED_PKGS[@]}")"); actions+=("overview")
            items+=("2. $(t "installer.ui.menu_configs" "selected=$(selected_config_count)" "total=${#MANAGED_CONFIGS[@]}")"); actions+=("configs")
            items+=("3. $(t "installer.ui.menu_sddm") $S_SDDM"); actions+=("sddm")

            if [[ "$INSTALL_STATE" == "current" ]]; then
                items+=("4. ${BOLD}${C_GREEN}$(t "installer.ui.menu_update")${RESET}"); actions+=("update")
                items+=("5. ${BOLD}${C_YELLOW}$(t "installer.ui.menu_reinstall")${RESET}"); actions+=("reinstall")
                items+=("6. ${DIM}$(t "installer.ui.menu_exit")${RESET}"); actions+=("exit")
            else
                items+=("4. ${BOLD}${C_GREEN}$(t "installer.ui.menu_install")${RESET}"); actions+=("install")
                items+=("5. ${DIM}$(t "installer.ui.menu_exit")${RESET}"); actions+=("exit")
            fi

            if [ "$rendered_lines" -gt 0 ]; then
                printf "\033[%dA" "$rendered_lines"
            fi

            for i in "${!items[@]}"; do
                if [ "$i" -eq "$cursor" ]; then
                    printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
                else
                    printf "\r\033[K    %s\n" "${items[$i]}"
                fi
            done
            rendered_lines=${#items[@]}

            local key
            key=$(read_key)

            local selected=""
            case "$key" in
                UP|[kK])
                    if [ "$cursor" -gt 0 ]; then
                        cursor=$(( cursor - 1 ))
                    else
                        cursor=$(( ${#items[@]} - 1 ))
                    fi
                    ;;
                DOWN|[jJ])
                    if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                        cursor=$(( cursor + 1 ))
                    else
                        cursor=0
                    fi
                    ;;
                [1-9])
                    if [ "$key" -le "${#items[@]}" ]; then
                        selected="${actions[$(( key - 1 ))]}"
                    fi
                    ;;
                ENTER|SPACE)
                    selected="${actions[$cursor]}"
                    ;;
                ESC|[qQ])
                    selected="exit"
                    ;;
            esac

            if [ -n "$selected" ]; then
                run_menu_action "$selected" && return 0
                break
            fi
        done
    done
}

draw_completion_screen() {
    local target_commit="$1"
    cleanup_terminal
    clear 2>/dev/null || true
    printf "%s%s" "$BOLD" "$C_GREEN"
    cat << "EOF2"
 ___ _  _ ___ _____ _   _     _ _____ ___ ___  _  _    ___ ___  __  __ ___ _    ___ _____ ___ 
|_ _| \| / __|_   _/_\ | |   /_\_   _|_ _/ _ \| \| |  / __/ _ \ | \/  | _ \ |  | __|_   _| __|
 | || .` \__ \ | |/ _ \| |__| _ \| |  | | (_) | .` | | (_| (_) | |\/| |  _/ |__| _|  | | | _| 
|___|_|\_|___/ |_/_/ \_\____/_/ \_\_| |___\___/|_|\_|  \___\___/|_|  |_|_| |____|___| |_| |___|
EOF2
    printf "%s\n\n" "$RESET"
    printf "%s%s  %s%s\n\n" "$BOLD" "$C_CYAN" "$(t "installer.ui.tagline")" "$RESET"
    printf "%s%s%s\n" "$C_GREEN" "$(t "installer.ui.installed_success" "commit=$target_commit")" "$RESET"
    if [ -d "$BACKUP_ROOT" ]; then
        printf "\n%s\n" "$(t "installer.ui.backups_saved" "path=$BACKUP_ROOT")"
        if [ -f "$BACKUP_ROOT/disabled-display-managers.txt" ]; then
            printf "%s\n" "$(t "installer.ui.dm_disabled_note" "dms=$(paste -sd, "$BACKUP_ROOT/disabled-display-managers.txt")")"
        fi
    fi
    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        printf "\n%s%s%s%s\n" "$BOLD" "$C_RED" "$(t "installer.ui.failed_packages")" "$RESET"
        for fp in "${FAILED_PKGS[@]}"; do
            printf "  - %s%s%s\n" "$C_YELLOW" "$fp" "$RESET"
        done
    fi
    printf "\n%s\n\n" "$(t "installer.ui.restart_prompt")"

    local restart_choice=""
    local prompt_msg
    prompt_msg="$(t "installer.ui.ask_reboot")"

    if [ -t 0 ]; then
        read -r -p "$prompt_msg" restart_choice
    elif [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" restart_choice < /dev/tty
    fi

    if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
        sudo reboot now
    fi
}
