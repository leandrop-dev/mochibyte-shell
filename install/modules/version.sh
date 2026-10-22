#!/usr/bin/env bash

MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
if [ -z "$MOCHIBYTE_DIR" ]; then
    if [ -d "$(dirname "$(dirname "$MODULE_DIR")")/src" ]; then
        export MOCHIBYTE_DIR="$(dirname "$(dirname "$MODULE_DIR")")/src"
    fi
fi

if [ -n "$MOCHIBYTE_DIR" ] && [ -f "$MOCHIBYTE_DIR/scripts/caching.sh" ]; then
    source "$MOCHIBYTE_DIR/scripts/caching.sh"
fi

STATE_DIR="${QS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mochibyte}"
VERSION_FILE="$STATE_DIR/version"

get_installed_commit() {
    if [ -f "$VERSION_FILE" ]; then
        awk -F= '/^MOCHIBYTE_COMMIT=/{gsub(/"/, "", $2); print $2}' "$VERSION_FILE"
    fi
}

get_target_commit() {
    local repo_root="$1"
    local repo_slug="${2:-"${REPO_SLUG:-"leandrop-dev/mochibyte-shell"}"}"
    local target_commit=""

    if [ -d "$repo_root/.git" ] && command -v git &>/dev/null; then
        target_commit=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || true)
    fi

    if [[ -z "$target_commit" || "$target_commit" == "null" ]]; then
        if command -v curl &>/dev/null && command -v jq &>/dev/null; then
            target_commit=$(curl -s "https://api.github.com/repos/${repo_slug}/commits/HEAD" 2>/dev/null | jq -r '.sha[:7] // empty')
        fi
    fi

    if [[ -z "$target_commit" || "$target_commit" == "null" ]]; then
        target_commit="unknown"
    fi

    echo "$target_commit"
}

write_version_state() {
    local commit="${1:-"unknown"}"

    if [[ -z "$commit" || "$commit" == "null" ]]; then
        commit="unknown"
    fi

    mkdir -p "$STATE_DIR"
    local tmp_file="${VERSION_FILE}.tmp.$$"
    cat <<EOT > "$tmp_file"
MOCHIBYTE_COMMIT="$commit"
EOT
    mv -f "$tmp_file" "$VERSION_FILE"
}
