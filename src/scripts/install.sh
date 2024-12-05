#!/bin/sh
S5CMD_STR_S5CMD_VERSION="$(echo "${S5CMD_STR_S5CMD_VERSION}" | circleci env subst)"
S5CMD_EVAL_INSTALL_DIR="$(eval echo "${S5CMD_EVAL_INSTALL_DIR}" | circleci env subst)"
S5CMD_EVAL_BINARY_DIR="$(eval echo "${S5CMD_EVAL_BINARY_DIR}" | circleci env subst)"

eval "$SCRIPT_UTILS"
detect_os
set_sudo

# Install per platform
if [ "$SYS_ENV_PLATFORM" = "linux" ] || [ "$SYS_ENV_PLATFORM" = "linux_alpine" ]; then
    eval "$SCRIPT_INSTALL_DEPENDENCY_LINUX"
    eval "$SCRIPT_INSTALL_LINUX"

elif [ "$SYS_ENV_PLATFORM" = "windows" ]; then
    echo "This orb does not currently support your platform."
elif [ "$SYS_ENV_PLATFORM" = "macos" ]; then
    eval "$SCRIPT_INSTALL_MACOS"
else
    echo "This orb does not currently support your platform."
    exit 1
fi


if ! command -v s5cmd >/dev/null 2>&1; then
    install_dependencies
    Install_S5CMD_CLI "${S5CMD_STR_S5CMD_VERSION}"
elif s5cmd version | grep "${S5CMD_STR_S5CMD_VERSION}"; then
    echo "s5cmd CLI version ${S5CMD_STR_S5CMD_VERSION} already installed. Skipping installation"
    exit 0
elif [ "$S5CMD_BOOL_OVERRIDE" -eq 1 ]; then
    Uninstall_S5CMD_CLI
    install_dependencies
    Install_S5CMD_CLI "${S5CMD_STR_S5CMD_VERSION}"
else
    echo "s5cmd CLI is already installed, skipping installation."
    s5cmd version
fi