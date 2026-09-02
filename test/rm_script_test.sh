#!/bin/sh
set -eu
TEST_DIR="$(mktemp -d)"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"
LOG="$TEST_DIR/s5cmd.log"

cat > "$STUB_BIN/s5cmd" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$LOG"
EOF
chmod +x "$STUB_BIN/s5cmd"

cat > "$STUB_BIN/circleci" <<'EOF'
#!/bin/sh
if [ "$1" = "env" ] && [ "$2" = "subst" ]; then
  if [ -n "${3:-}" ]; then printf '%s' "$3"; else cat; fi
fi
EOF
chmod +x "$STUB_BIN/circleci"

PATH="$STUB_BIN:$PATH"
export PATH

SCRIPT="$(dirname "$0")/../src/scripts/rm.sh"

ORB_EVAL_TARGET="s3://bucket/prefix/*" \
ORB_STR_ARGUMENTS="" ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="rm s3://bucket/prefix/*"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case1: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

ORB_EVAL_TARGET="s3://bucket/prefix/*" \
ORB_STR_ARGUMENTS="--all-versions" \
ORB_STR_PROFILE_NAME="myprofile" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="--profile myprofile rm --all-versions s3://bucket/prefix/*"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case2: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: rm_script_test.sh"
