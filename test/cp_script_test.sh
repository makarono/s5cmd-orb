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

SCRIPT="$(dirname "$0")/../src/scripts/cp.sh"

ORB_EVAL_FROM="local.txt" ORB_EVAL_TO="s3://bucket/local.txt" \
ORB_STR_ARGUMENTS="" ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="" ORB_STR_NUMWORKERS="" \
sh "$SCRIPT"
EXPECTED="cp local.txt s3://bucket/local.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case1: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

ORB_EVAL_FROM="local.txt" ORB_EVAL_TO="s3://bucket/local.txt" \
ORB_STR_ARGUMENTS="--acl public-read --cache-control max-age=86400" \
ORB_STR_PROFILE_NAME="myprofile" ORB_STR_ENDPOINT_URL="https://minio.local" ORB_STR_NUMWORKERS="" \
sh "$SCRIPT"
EXPECTED="--profile myprofile --endpoint-url https://minio.local cp --acl public-read --cache-control max-age=86400 local.txt s3://bucket/local.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case2: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

# --numworkers is a global s5cmd flag: it MUST land before the "cp" subcommand,
# never after it (s5cmd rejects "cp --numworkers N ..." with "flag provided but not defined").
ORB_EVAL_FROM="local.txt" ORB_EVAL_TO="s3://bucket/local.txt" \
ORB_STR_ARGUMENTS="--acl public-read" \
ORB_STR_PROFILE_NAME="myprofile" ORB_STR_ENDPOINT_URL="https://minio.local" ORB_STR_NUMWORKERS="16" \
sh "$SCRIPT"
EXPECTED="--profile myprofile --endpoint-url https://minio.local --numworkers 16 cp --acl public-read local.txt s3://bucket/local.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case3 (numworkers placement): got '$ACTUAL' want '$EXPECTED'"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: cp_script_test.sh"
