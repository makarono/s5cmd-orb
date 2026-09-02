#!/usr/bin/env bash
set -eu
TEST_DIR="$(mktemp -d)"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -o) DEST="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: > "$DEST"
EOF

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

chmod +x "$STUB_BIN/curl" "$STUB_BIN/tar"
PATH="$STUB_BIN:$PATH"
export PATH
SUDO=""
export SUDO

# shellcheck source=/dev/null
. "$(dirname "$0")/../src/scripts/linux/install.sh"
get_architecture() { echo "x86_64"; }

S5CMD_EVAL_INSTALL_DIR="$TEST_DIR/install"
S5CMD_EVAL_BINARY_DIR="$TEST_DIR/bin-target"

Install_S5CMD_CLI "1.2.3"

[ -x "$S5CMD_EVAL_BINARY_DIR/s5cmd" ] || { echo "FAIL: binary not installed at $S5CMD_EVAL_BINARY_DIR/s5cmd"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: linux_install_test.sh"
