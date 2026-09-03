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

SCRIPT="$(dirname "$0")/../src/scripts/sync.sh"

ORB_EVAL_FROM="bucket/" ORB_EVAL_TO="s3://bucket/prefix" \
ORB_STR_ARGUMENTS="" ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="sync bucket/ s3://bucket/prefix"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case1: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

ORB_EVAL_FROM="bucket/" ORB_EVAL_TO="s3://bucket/prefix" \
ORB_STR_ARGUMENTS="--delete --acl public-read" \
ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="https://minio.local" \
sh "$SCRIPT"
EXPECTED="--endpoint-url https://minio.local sync --delete --acl public-read bucket/ s3://bucket/prefix"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case2: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: sync_script_test.sh"
