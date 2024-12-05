#!/usr/bin/env bash
#shellcheck disable=SC1090

set -ex

get_architecture() {
  uname -m
}

download_and_extract() {
  local url="$1"
  local temp_tar="$2"

  echo "Downloading $url..."
  curl -L -o "$temp_tar" "$url"

  echo "Extracting $temp_tar..."
  tar -xzf "$temp_tar" -C "$TEMP_DIR"
}

install_binary() {
  local binary_source="$1"
  local binary_target="$2"

  echo "Installing s5cmd..."
  $SUDO mv "$binary_source" "$binary_target"
  $SUDO chmod +x "$binary_target"
}

Install_S5CMD_CLI() {
  VERSION="${1:-2.2.2}"
  BASE_URL="https://github.com/peak/s5cmd/releases/download/v${VERSION}/"
  TEMP_DIR="${S5CMD_CLI_EVAL_INSTALL_DIR}"
  BINARY_TARGET="${S5CMD_CLI_EVAL_BINARY_DIR}"

  declare -A SUPPORTED_ARCHIVE_FILES=(
    ["x86_64"]="s5cmd_${VERSION}_Linux-64bit.tar.gz"
    ["i686"]="s5cmd_${VERSION}_Linux-32bit.tar.gz"
    ["armv7l"]="s5cmd_${VERSION}_Linux-armv6.tar.gz"
    ["aarch64"]="s5cmd_${VERSION}_Linux-arm64.tar.gz"
    ["ppc64le"]="s5cmd_${VERSION}_Linux-ppc64le.tar.gz"
  )

  ARCH=$(get_architecture)
  echo "Detected architecture: $ARCH"

  ARCHIVE_NAME=${SUPPORTED_ARCHIVE_FILES[$ARCH]}
  if [ -z "$ARCHIVE_NAME" ]; then
    echo "Unsupported architecture: $ARCH"
    exit 1
  fi

  DOWNLOAD_URL="${BASE_URL}${ARCHIVE_NAME}"
  TEMP_TAR="${TEMP_DIR}/${ARCHIVE_NAME}"

  mkdir -p "$TEMP_DIR"
  download_and_extract "$DOWNLOAD_URL" "$TEMP_TAR"

  BINARY_SOURCE="${TEMP_DIR}/s5cmd"
  if [ ! -f "$BINARY_SOURCE" ]; then
    echo "Error: Binary not found after extraction."
    exit 1
  fi

  install_binary "$BINARY_SOURCE" "$BINARY_TARGET"

  echo "Verifying s5cmd installation..."
  "$BINARY_TARGET" version

  echo "s5cmd installation completed successfully."
}

Uninstall_S5CMD_CLI() {
  S5CMD_CLI_PATH=$(command -v s5cmd)
  echo "$S5CMD_CLI_PATH"
  if [ -n "$S5CMD_CLI_PATH" ]; then
    EXISTING_AWS_VERSION=$(s5cmd version)
    echo "Uninstalling ${EXISTING_AWS_VERSION}"
    # shellcheck disable=SC2012
    if [ -L "$S5CMD_CLI_PATH" ]; then
      S5CMD_SYMLINK_PATH=$(ls -l "$S5CMD_CLI_PATH" | sed -e 's/.* -> //')
    fi
    $SUDO rm -rf "$S5CMD_CLI_PATH" "$S5CMD_SYMLINK_PATH"
  else
    echo "No s5cmd install found"
  fi
}
