# shellcheck disable=SC2148
if ! command -v s5cmd >/dev/null 2>&1; then
    install_dependencies
    Install_S5CMD_CLI "${S5CMD_STR_S5CMD_VERSION}"
elif s5cmd version | grep "${S5CMD_STR_S5CMD_VERSION}"; then
    echo "s5cmd CLI version ${S5CMD_STR_S5CMD_VERSION} already installed. Skipping installation"
    exit 0
elif is_true "$S5CMD_BOOL_OVERRIDE"; then
    Uninstall_S5CMD_CLI
    install_dependencies
    Install_S5CMD_CLI "${S5CMD_STR_S5CMD_VERSION}"
else
    echo "s5cmd CLI is already installed, skipping installation."
    s5cmd version
fi
