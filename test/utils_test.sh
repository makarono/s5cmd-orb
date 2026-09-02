#!/bin/sh
set -eu
. "$(dirname "$0")/../src/scripts/utils.sh"

is_true "true" || { echo "FAIL: is_true(true) should succeed"; exit 1; }
if is_true "false"; then echo "FAIL: is_true(false) should fail"; exit 1; fi
if is_true ""; then echo "FAIL: is_true('') should fail"; exit 1; fi

RESULT="$(printf '{"tag_name":"v2.3.0","name":"v2.3.0"}' | resolve_latest_version)"
[ "$RESULT" = "2.3.0" ] || { echo "FAIL: resolve_latest_version got '$RESULT', want 2.3.0"; exit 1; }

echo "PASS: utils_test.sh"
