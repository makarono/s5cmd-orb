#!/usr/bin/env bash
set -eu
TEST_DIR="$(mktemp -d)"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"
URL_LOG="$TEST_DIR/urls.log"

cat > "$STUB_BIN/curl" <<EOF
#!/bin/sh
DEST=""
URL=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) DEST="\$2"; shift 2 ;;
    -L) shift ;;
    *) URL="\$1"; shift ;;
  esac
done
printf '%s\n' "\$URL" >> "$URL_LOG"
: > "\$DEST"
EOF
chmod +x "$STUB_BIN/curl"

cat > "$STUB_BIN/tar" <<'EOF'
#!/bin/sh
DIR=""
PREV=""
for arg in "$@"; do
  if [ "$PREV" = "-C" ]; then DIR="$arg"; fi
  PREV="$arg"
done
mkdir -p "$DIR"
printf '#!/bin/sh\necho stub-s5cmd\n' > "$DIR/s5cmd"
chmod +x "$DIR/s5cmd"
EOF
chmod +x "$STUB_BIN/tar"

PATH="$STUB_BIN:$PATH"
export PATH
SUDO=""
export SUDO

# shellcheck source=/dev/null
. "$(dirname "$0")/../src/scripts/macos/install.sh"
get_architecture() { echo "arm64"; }

# shellcheck disable=SC2034  # used by sourced Install_S5CMD_CLI
S5CMD_EVAL_INSTALL_DIR="$TEST_DIR/install"
S5CMD_EVAL_BINARY_DIR="$TEST_DIR/bin-target"

Install_S5CMD_CLI "1.2.3"

grep -q "Darwin-arm64" "$URL_LOG" || { echo "FAIL: expected Darwin-arm64 archive in download URL, got: $(cat "$URL_LOG")"; exit 1; }
[ -x "$S5CMD_EVAL_BINARY_DIR/s5cmd" ] || { echo "FAIL: binary not installed at $S5CMD_EVAL_BINARY_DIR/s5cmd"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: macos_install_test.sh"
