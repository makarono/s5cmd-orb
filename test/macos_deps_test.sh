#!/usr/bin/env bash
set -eu
TEST_DIR="$(mktemp -d)"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/brew" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$STUB_BIN/brew"

OUTPUT="$(PATH="$STUB_BIN:$PATH" bash "$(dirname "$0")/../src/scripts/macos/deps-install-script.sh")"
echo "$OUTPUT" | grep -q "\[INSTALLATION\]: complete" || { echo "FAIL: expected successful install_check output, got:"; echo "$OUTPUT"; exit 1; }

NO_BREW_PATH="/usr/bin:/bin"
OUTPUT2="$(PATH="$NO_BREW_PATH" bash "$(dirname "$0")/../src/scripts/macos/deps-install-script.sh")"
echo "$OUTPUT2" | grep -q "Homebrew not found" || { echo "FAIL: expected Homebrew-not-found branch, got:"; echo "$OUTPUT2"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: macos_deps_test.sh"
