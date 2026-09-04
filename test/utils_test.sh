#!/bin/sh
set -eu
# shellcheck disable=SC1091
. "$(dirname "$0")/../src/scripts/utils.sh"

is_true "true" || { echo "FAIL: is_true(true) should succeed"; exit 1; }
if is_true "false"; then echo "FAIL: is_true(false) should fail"; exit 1; fi
if is_true ""; then echo "FAIL: is_true('') should fail"; exit 1; fi

RESULT="$(printf '{"tag_name":"v2.3.0","name":"v2.3.0"}' | resolve_latest_version)"
[ "$RESULT" = "2.3.0" ] || { echo "FAIL: resolve_latest_version got '$RESULT', want 2.3.0"; exit 1; }

TEST_DIR="$(mktemp -d)"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/id" <<'EOF'
#!/bin/sh
[ "$1" = "-u" ] || exit 1
printf '%s\n' "${STUB_UID}"
EOF
chmod +x "$STUB_BIN/id"
PATH="$STUB_BIN:$PATH"
export PATH

SYS_ENV_PLATFORM=linux STUB_UID=0 sh -c '. "'"$(dirname "$0")"'/../src/scripts/utils.sh"; set_sudo; [ "$SUDO" = "" ]' \
  || { echo "FAIL: set_sudo as root should leave SUDO empty"; exit 1; }
SYS_ENV_PLATFORM=linux STUB_UID=1000 sh -c '. "'"$(dirname "$0")"'/../src/scripts/utils.sh"; set_sudo; [ "$SUDO" = "sudo" ]' \
  || { echo "FAIL: set_sudo as non-root should set SUDO=sudo"; exit 1; }
# Regression: linux_alpine used to check the unrelated/unset $ID variable
# instead of the real uid, so root always got SUDO=sudo on Alpine.
SYS_ENV_PLATFORM=linux_alpine STUB_UID=0 sh -c '. "'"$(dirname "$0")"'/../src/scripts/utils.sh"; set_sudo; [ "$SUDO" = "" ]' \
  || { echo "FAIL: set_sudo as root on Alpine should leave SUDO empty"; exit 1; }

rm -rf "$TEST_DIR"

echo "PASS: utils_test.sh"
