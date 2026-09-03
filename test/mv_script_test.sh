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
  if [ "$#" -ge 3 ]; then printf '%s' "$3"; else cat; fi
fi
EOF
chmod +x "$STUB_BIN/circleci"

PATH="$STUB_BIN:$PATH"
export PATH

SCRIPT="$(dirname "$0")/../src/scripts/mv.sh"

ORB_EVAL_FROM="s3://bucket/a.txt" ORB_EVAL_TO="s3://bucket/b.txt" \
ORB_STR_ARGUMENTS="" ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="mv s3://bucket/a.txt s3://bucket/b.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case1: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

ORB_EVAL_FROM="s3://bucket/a.txt" ORB_EVAL_TO="s3://bucket/b.txt" \
ORB_STR_ARGUMENTS="--exclude *.tmp" \
ORB_STR_PROFILE_NAME="myprofile" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="--profile myprofile mv --exclude *.tmp s3://bucket/a.txt s3://bucket/b.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case2: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: mv_script_test.sh"
