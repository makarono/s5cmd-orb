#!/usr/bin/env bash


# Array of dependencies
declare -a PACKAGES=("bash" "curl" "tar" "gzip")
declare -a SHOULD_INSTALL_PACKAGES

# Function to print a message with formatting
log() {
    local message="$1"
    local line=""

    # Calculate the length of the message
    local message_length=${#message}

    # Build the separator line based on the message length
    for ((i = 0; i < message_length; i++)); do
        line+="="
    done

    #echo "$line"
    #uppercase first letter of a message
    echo "${message^}"
    echo "$line"
}

function check-packages() {
    log "Checking installed packages"

    # Loop through each program
    for program in "${PACKAGES[@]}"; do
        # Check if program is installed
        if ! command -v "$program" >/dev/null 2>&1; then
            log "warning dependency: $program is not installed."
            #push to array. Array with packages for instalation
            SHOULD_INSTALL_PACKAGES+=("$program")
        fi
    done
    log "packages for installation: ${SHOULD_INSTALL_PACKAGES[*]}"
}

install_check() {
    # This function checks the exit status of the last command and prints appropriate message.
    if [ $? -eq 0 ]; then
        echo "[INSTALLATION]: complete"
    else
        echo "[INSTALLATION]: error"
    fi
}

install_dependencies() {
    # Detect the Linux distribution
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO=$ID
    else
        log "Unable to detect Linux distribution."
        return 1
    fi

    log "Detected distribution: $DISTRO"

    # Install packages based on the distribution
    case "$DISTRO" in
    ubuntu | debian)
        check-packages
        log "Installing dependencies..."
        #if array SHOULD_INSTALL_PACKAGES has no lenght (is empyty) do not run package manager
        [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || (apt update -y -qq && apt install -y "${SHOULD_INSTALL_PACKAGES[@]}")
        install_check
        ;;
    centos | rhel | rocky | almalinux | fedora)
        check-packages
        log "Installing dependencies..."
        #if array SHOULD_INSTALL_PACKAGES has no lenght (is empyty) do not run package manager
        [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || (yum update -y && yum install -y "${SHOULD_INSTALL_PACKAGES[@]}")
        install_check
        ;;
    arch | manjaro)
        check-packages
        log "Installing dependencies..."
        #if array SHOULD_INSTALL_PACKAGES has no lenght (is empyty) do not run package manager
        [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || pacman -Syu --noconfirm "${SHOULD_INSTALL_PACKAGES[@]}"
        install_check
        ;;
    opensuse* | sles)
        check-packages
        log "Installing dependencies..."
        #if array SHOULD_INSTALL_PACKAGES has no lenght (is empyty) do not run package manager
        [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || zypper install -y "${SHOULD_INSTALL_PACKAGES[@]}"
        install_check
        ;;
    alpine)
        check-packages
        log "Installing dependencies..."
        #if array SHOULD_INSTALL_PACKAGES has no lenght (is empyty) do not run package manager
        [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || apk --update --no-cache add "${SHOULD_INSTALL_PACKAGES[@]}"
        install_check
        ;;
    *)
        log "Unsupported distribution: $DISTRO"
        return 1
        ;;
    esac

}

install_dependencies
