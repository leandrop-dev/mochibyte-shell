#!/usr/bin/env bash
set -e

main() {
    local slug="${REPO_SLUG:-leandrop-dev/mochibyte-shell}"
    local branch="${MOCHIBYTE_BRANCH:-main}"
    local dir
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' EXIT
    curl -fsSL "https://raw.githubusercontent.com/${slug}/${branch}/install/install.sh" -o "$dir/install.sh"
    if [ -t 0 ]; then
        bash "$dir/install.sh" "$@"
    elif [ -r /dev/tty ]; then
        bash "$dir/install.sh" "$@" < /dev/tty
    else
        bash "$dir/install.sh" "$@"
    fi
}

main "$@"
