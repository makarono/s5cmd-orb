#!/usr/bin/env bash

declare -a PACKAGES=("bash" "curl" "tar" "gzip")
declare -a SHOULD_INSTALL_PACKAGES

log() {
    local message="$1"
    local line=""
    local message_length=${#message}
    for ((i = 0; i < message_length; i++)); do
        line+="="
    done
    local first; first=$(printf '%s' "${message:0:1}" | tr '[:lower:]' '[:upper:]')
    echo "${first}${message:1}"
    echo "$line"
}

check-packages() {
    log "Checking installed packages"
    for program in "${PACKAGES[@]}"; do
        if ! command -v "$program" >/dev/null 2>&1; then
            log "warning dependency: $program is not installed."
            SHOULD_INSTALL_PACKAGES+=("$program")
        fi
    done
    log "packages for installation: ${SHOULD_INSTALL_PACKAGES[*]}"
}

install_check() {
    if [ $? -eq 0 ]; then
        echo "[INSTALLATION]: complete"
    else
        echo "[INSTALLATION]: error"
    fi
}

install_dependencies() {
    if ! command -v brew >/dev/null 2>&1; then
        log "Homebrew not found - skipping dependency check (curl/tar/gzip/bash ship with macOS by default)."
        return 0
    fi

    check-packages
    log "Installing dependencies..."
    [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || brew install "${SHOULD_INSTALL_PACKAGES[@]}"
    install_check
}

install_dependencies
