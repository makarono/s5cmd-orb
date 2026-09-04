#!/bin/sh
set -e
S5CMD_STR_S5CMD_VERSION="$(echo "${S5CMD_STR_S5CMD_VERSION}" | circleci env subst)"
S5CMD_EVAL_INSTALL_DIR="$(eval echo "${S5CMD_EVAL_INSTALL_DIR}" | circleci env subst)"
S5CMD_EVAL_BINARY_DIR="$(eval echo "${S5CMD_EVAL_BINARY_DIR}" | circleci env subst)"

eval "$SCRIPT_UTILS"
detect_os
set_sudo

if [ "$S5CMD_STR_S5CMD_VERSION" = "latest" ]; then
    S5CMD_STR_S5CMD_VERSION="$(curl -fsSL https://api.github.com/repos/peak/s5cmd/releases/latest | resolve_latest_version)"
fi

if [ -z "$S5CMD_STR_S5CMD_VERSION" ]; then
    echo "Error: failed to resolve latest s5cmd version from GitHub." >&2
    exit 1
fi

# Install per platform
if [ "$SYS_ENV_PLATFORM" = "linux" ] || [ "$SYS_ENV_PLATFORM" = "linux_alpine" ]; then
    # deps-install-script.sh uses bash arrays. Musl-based images like Alpine
    # ship no bash, and their /bin/sh (ash) cannot "eval" bash-only syntax --
    # run the whole Linux install flow through an explicit bash process
    # instead of eval-ing it into whatever shell happens to be interpreting
    # this file.
    if [ "$SYS_ENV_PLATFORM" = "linux_alpine" ] && ! command -v bash >/dev/null 2>&1; then
        apk add --no-cache bash
    fi
    LINUX_INSTALL_SCRIPT="$(mktemp)"
    trap 'rm -f "$LINUX_INSTALL_SCRIPT"' EXIT
    {
        printf '%s\n' "$SCRIPT_UTILS"
        printf '%s\n' "$SCRIPT_INSTALL_DEPENDENCY_LINUX"
        printf '%s\n' "$SCRIPT_INSTALL_LINUX"
        printf '%s\n' "$SCRIPT_DECIDE_INSTALL"
    } > "$LINUX_INSTALL_SCRIPT"
    bash "$LINUX_INSTALL_SCRIPT"
    exit $?
elif [ "$SYS_ENV_PLATFORM" = "windows" ]; then
    echo "This orb does not currently support your platform."
    exit 1
elif [ "$SYS_ENV_PLATFORM" = "macos" ]; then
    eval "$SCRIPT_INSTALL_DEPENDENCY_MACOS"
    eval "$SCRIPT_INSTALL_MACOS"
else
    echo "This orb does not currently support your platform."
    exit 1
fi

eval "$SCRIPT_DECIDE_INSTALL"
