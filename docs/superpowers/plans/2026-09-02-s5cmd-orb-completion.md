# s5cmd Orb Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the s5cmd CircleCI orb to feature parity with the reference `circleci/aws-s3` orb pattern: a working `install`, plus `cp`/`sync`/`mv`/`rm`/`ls` commands and jobs, a shared executor, `auth`/`profile_name`/`endpoint_url` parameters, real integration tests, fixed examples/README.

**Architecture:** Same 4-layer orb shape as `aws-s3`: `executors/default.yml` (shared Docker executor) -> `commands/*.yml` (thin YAML wrapping a `<<include(scripts/*.sh)>>` shell script per s5cmd operation) -> `jobs/*.yml` (checkout + optional `auth` steps + `install` + the command) -> `test-deploy.yml` (real integration tests gating `orb-tools/publish`). Every command script takes its parameters via `environment:` and resolves them with `circleci env subst` inside the script, never by interpolating directly into the command string.

**Tech Stack:** CircleCI Orb DSL (YAML, `circleci orb pack`), POSIX `sh` for command scripts, `bash` for the existing install scripts (unchanged shell dialect), `circleci` CLI + plain `sh`/`bash` scripts for local testing (no test framework is present in this repo and none is being introduced).

**Spec:** `docs/superpowers/specs/2026-09-02-s5cmd-orb-completion-design.md`

## Global Constraints

- Every user-supplied parameter value that reaches a shell script goes in via `environment:` and is resolved with `circleci env subst` inside the script - never interpolated directly into a command string (injection safety, matches `aws-s3-orb`).
- s5cmd takes `--profile` and `--endpoint-url` as **global** flags, before the subcommand (`s5cmd --profile x --endpoint-url y cp ...`), not after it like `aws s3 cp ... --profile x`.
- The `arguments` parameter on every S3-operation command is a single free-form string, not a list type - space-separated flags, split into argv with the same `IFS=' '` + `sed 's/,[ ]*/,/g'` mechanism `aws-s3-orb` uses, so comma-joined values inside one flag survive as one token.
- Every job installs s5cmd itself (`install` step) before calling its command - the `default` executor (`cimg/aws:stable`) does not ship s5cmd.
- Out of scope (per spec): `mb`/`rb`, a generic passthrough/`run` command, Windows support.
- **Open question carried into this plan:** the orb's registered CircleCI namespace is unknown. Examples, `test-deploy.yml`, and the README use the placeholder `<your-orb-namespace>` - replace it with the real namespace before publishing. This does not block implementing or locally testing the orb.
- **Open question carried into this plan:** real AWS OIDC role ARN + test bucket name for `test-deploy.yml`'s S3-operation integration tests - placeholders (`PLACEHOLDER_ACCOUNT_ID`, `PLACEHOLDER_S5CMD_TEST_ROLE`, `PLACEHOLDER_S5CMD_TEST_BUCKET`) are used; these tests won't actually pass in CI until real values are substituted.
- **New bug found while planning Task 1** (not in the original 8-item list, same category, folding it in): in both `linux/install.sh` and `macos/install.sh`, `install_binary()`'s final verification line runs `"$BINARY_TARGET" version` where `$BINARY_TARGET` is a *directory* (the `binary_dir` parameter, default `/usr/local/bin`) - executing a directory always fails. Fixed by installing to `"$binary_target_dir/$binary_name"` and verifying that exact file path.

---

## Task 1: Fix `install.sh` core bugs (boolean check, `latest` version resolution) + Linux binary-path bug

**Files:**
- Modify: `src/scripts/utils.sh`
- Modify: `src/scripts/install.sh`
- Modify: `src/scripts/linux/install.sh`
- Test: `test/utils_test.sh`
- Test: `test/linux_install_test.sh`

**Interfaces:**
- Produces: `is_true(value)` (utils.sh) - shell function, returns 0 if `value` is the literal string `true`, 1 otherwise. Used everywhere a CircleCI boolean parameter is checked in shell.
- Produces: `resolve_latest_version` (utils.sh) - shell function, reads a GitHub releases-API JSON response on stdin, writes the `tag_name` value (leading `v` stripped) to stdout.
- Produces: `Install_S5CMD_CLI(version)` (linux/install.sh) - now installs to `"${S5CMD_EVAL_BINARY_DIR}/s5cmd"` instead of treating `S5CMD_EVAL_BINARY_DIR` itself as the binary path.

- [ ] **Step 1: Write the failing test for `utils.sh` helpers**

Create `test/utils_test.sh`:

```sh
#!/bin/sh
set -eu
. "$(dirname "$0")/../src/scripts/utils.sh"

is_true "true" || { echo "FAIL: is_true(true) should succeed"; exit 1; }
if is_true "false"; then echo "FAIL: is_true(false) should fail"; exit 1; fi
if is_true ""; then echo "FAIL: is_true('') should fail"; exit 1; fi

RESULT="$(printf '{"tag_name":"v2.3.0","name":"v2.3.0"}' | resolve_latest_version)"
[ "$RESULT" = "2.3.0" ] || { echo "FAIL: resolve_latest_version got '$RESULT', want 2.3.0"; exit 1; }

echo "PASS: utils_test.sh"
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh test/utils_test.sh`
Expected: FAIL - `is_true: command not found` (function doesn't exist yet).

- [ ] **Step 3: Add the helpers to `utils.sh`**

Append to `src/scripts/utils.sh`:

```sh
is_true() {
  [ "$1" = "true" ]
}

resolve_latest_version() {
  sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `sh test/utils_test.sh`
Expected: `PASS: utils_test.sh`

- [ ] **Step 5: Write the failing test for the Linux binary-path fix**

Create `test/linux_install_test.sh`:

```sh
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
```

- [ ] **Step 6: Run it, verify it fails**

Run: `bash test/linux_install_test.sh`
Expected: FAIL - either an empty-path `mkdir`/`mv` error (var name mismatch) or, once that's masked, `$S5CMD_EVAL_BINARY_DIR/s5cmd` not found because the current code moves the binary to a file literally named after the directory.

- [ ] **Step 7: Fix `src/scripts/linux/install.sh`**

Replace the whole file with:

```sh
# shellcheck disable=SC2148
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
  local binary_target_dir="$2"
  local binary_name
  binary_name="$(basename "$binary_source")"

  echo "Installing s5cmd..."
  mkdir -p "$binary_target_dir"
  $SUDO mv "$binary_source" "$binary_target_dir/$binary_name"
  $SUDO chmod +x "$binary_target_dir/$binary_name"
}

Install_S5CMD_CLI() {
  VERSION="${1:-2.2.2}"
  BASE_URL="https://github.com/peak/s5cmd/releases/download/v${VERSION}/"
  TEMP_DIR="${S5CMD_EVAL_INSTALL_DIR}"
  BINARY_TARGET_DIR="${S5CMD_EVAL_BINARY_DIR}"

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

  install_binary "$BINARY_SOURCE" "$BINARY_TARGET_DIR"

  echo "Verifying s5cmd installation..."
  "$BINARY_TARGET_DIR/s5cmd" version

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
```

- [ ] **Step 8: Run it, verify it passes**

Run: `bash test/linux_install_test.sh`
Expected: `PASS: linux_install_test.sh`

- [ ] **Step 9: Fix `src/scripts/install.sh`**

Replace the file with:

```sh
#!/bin/sh
S5CMD_STR_S5CMD_VERSION="$(echo "${S5CMD_STR_S5CMD_VERSION}" | circleci env subst)"
S5CMD_EVAL_INSTALL_DIR="$(eval echo "${S5CMD_EVAL_INSTALL_DIR}" | circleci env subst)"
S5CMD_EVAL_BINARY_DIR="$(eval echo "${S5CMD_EVAL_BINARY_DIR}" | circleci env subst)"

eval "$SCRIPT_UTILS"
detect_os
set_sudo

if [ "$S5CMD_STR_S5CMD_VERSION" = "latest" ]; then
    S5CMD_STR_S5CMD_VERSION="$(curl -fsSL https://api.github.com/repos/peak/s5cmd/releases/latest | resolve_latest_version)"
fi

# Install per platform
if [ "$SYS_ENV_PLATFORM" = "linux" ] || [ "$SYS_ENV_PLATFORM" = "linux_alpine" ]; then
    eval "$SCRIPT_INSTALL_DEPENDENCY_LINUX"
    eval "$SCRIPT_INSTALL_LINUX"

elif [ "$SYS_ENV_PLATFORM" = "windows" ]; then
    echo "This orb does not currently support your platform."
elif [ "$SYS_ENV_PLATFORM" = "macos" ]; then
    eval "$SCRIPT_INSTALL_MACOS"
else
    echo "This orb does not currently support your platform."
    exit 1
fi


if ! command -v s5cmd >/dev/null 2>&1; then
    install_dependencies
    Install_S5CMD_CLI "${S5CMD_STR_S5CMD_VERSION}"
elif s5cmd version | grep "${S5CMD_STR_S5CMD_VERSION}"; then
    echo "s5cmd CLI version ${S5CMD_STR_S5CMD_VERSION} already installed. Skipping installation"
    exit 0
elif is_true "$S5CMD_BOOL_OVERRIDE"; then
    Uninstall_S5CMD_CLI
    install_dependencies
    Install_S5CMD_CLI "${S5CMD_STR_S5CMD_VERSION}"
else
    echo "s5cmd CLI is already installed, skipping installation."
    s5cmd version
fi
```

(Only three changes from the original: the new `latest`-resolution block, `is_true "$S5CMD_BOOL_OVERRIDE"` replacing `[ "$S5CMD_BOOL_OVERRIDE" -eq 1 ]`, and nothing else touched - the macOS branch keeps calling only `SCRIPT_INSTALL_MACOS` here, `SCRIPT_INSTALL_DEPENDENCY_MACOS` is wired in by Task 3.)

- [ ] **Step 10: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output (packing is silent on success).

- [ ] **Step 11: Commit**

```bash
git add src/scripts/utils.sh src/scripts/install.sh src/scripts/linux/install.sh test/utils_test.sh test/linux_install_test.sh
git commit -m "fix: resolve latest version, fix boolean check, fix Linux binary install path"
```

---

## Task 2: Fix macOS install script (wrong archive names, wrong arch map, same binary-path bug)

**Files:**
- Modify: `src/scripts/macos/install.sh`
- Test: `test/macos_install_test.sh`

**Interfaces:**
- Consumes: nothing from Task 1 (this file is fully rewritten, independent of `linux/install.sh`).
- Produces: `Install_S5CMD_CLI(version)` (macos/install.sh) - downloads the macOS (`Darwin-*`) release asset for `x86_64`/`arm64`, installs to `"${S5CMD_EVAL_BINARY_DIR}/s5cmd"`.

- [ ] **Step 1: Write the failing test**

Create `test/macos_install_test.sh`:

```sh
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

S5CMD_EVAL_INSTALL_DIR="$TEST_DIR/install"
S5CMD_EVAL_BINARY_DIR="$TEST_DIR/bin-target"

Install_S5CMD_CLI "1.2.3"

grep -q "Darwin-arm64" "$URL_LOG" || { echo "FAIL: expected Darwin-arm64 archive in download URL, got: $(cat "$URL_LOG")"; exit 1; }
[ -x "$S5CMD_EVAL_BINARY_DIR/s5cmd" ] || { echo "FAIL: binary not installed at $S5CMD_EVAL_BINARY_DIR/s5cmd"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: macos_install_test.sh"
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bash test/macos_install_test.sh`
Expected: FAIL - `Unsupported architecture: arm64` (current map only has Linux arch names) or a `Linux-64bit` URL if run with `x86_64` instead.

- [ ] **Step 3: Fix `src/scripts/macos/install.sh`**

Replace the whole file with:

```sh
# shellcheck disable=SC2148
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
  local binary_target_dir="$2"
  local binary_name
  binary_name="$(basename "$binary_source")"

  echo "Installing s5cmd..."
  mkdir -p "$binary_target_dir"
  $SUDO mv "$binary_source" "$binary_target_dir/$binary_name"
  $SUDO chmod +x "$binary_target_dir/$binary_name"
}

Install_S5CMD_CLI() {
  VERSION="${1:-2.2.2}"
  BASE_URL="https://github.com/peak/s5cmd/releases/download/v${VERSION}/"
  TEMP_DIR="${S5CMD_EVAL_INSTALL_DIR}"
  BINARY_TARGET_DIR="${S5CMD_EVAL_BINARY_DIR}"

  declare -A SUPPORTED_ARCHIVE_FILES=(
    ["x86_64"]="s5cmd_${VERSION}_Darwin-64bit.tar.gz"
    ["arm64"]="s5cmd_${VERSION}_Darwin-arm64.tar.gz"
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

  install_binary "$BINARY_SOURCE" "$BINARY_TARGET_DIR"

  echo "Verifying s5cmd installation..."
  "$BINARY_TARGET_DIR/s5cmd" version

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
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bash test/macos_install_test.sh`
Expected: `PASS: macos_install_test.sh`

- [ ] **Step 5: Commit**

```bash
git add src/scripts/macos/install.sh test/macos_install_test.sh
git commit -m "fix: correct macOS archive names/arch map and binary install path"
```

---

## Task 3: Rewrite macOS dependency script for brew and wire it in

**Files:**
- Modify: `src/scripts/macos/deps-install-script.sh`
- Modify: `src/commands/install.yml`
- Modify: `src/scripts/install.sh`
- Test: `test/macos_deps_test.sh`

**Interfaces:**
- Produces: `install_dependencies` (macos/deps-install-script.sh) - checks for `bash`/`curl`/`tar`/`gzip`, `brew install`s any missing, no-ops with a message if `brew` itself isn't present.
- Consumes: `install.yml`'s `environment:` block gains `SCRIPT_INSTALL_DEPENDENCY_MACOS`, evaluated the same way `SCRIPT_INSTALL_DEPENDENCY_LINUX` already is.

- [ ] **Step 1: Write the failing test**

Create `test/macos_deps_test.sh`:

```sh
#!/usr/bin/env bash
set -eu

OUTPUT="$(bash "$(dirname "$0")/../src/scripts/macos/deps-install-script.sh")"
echo "$OUTPUT" | grep -q "\[INSTALLATION\]: complete" || { echo "FAIL: expected successful install_check output, got:"; echo "$OUTPUT"; exit 1; }

NO_BREW_PATH="/usr/bin:/bin"
OUTPUT2="$(PATH="$NO_BREW_PATH" bash "$(dirname "$0")/../src/scripts/macos/deps-install-script.sh")"
echo "$OUTPUT2" | grep -q "Homebrew not found" || { echo "FAIL: expected Homebrew-not-found branch, got:"; echo "$OUTPUT2"; exit 1; }

echo "PASS: macos_deps_test.sh"
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bash test/macos_deps_test.sh`
Expected: FAIL - current script runs the Linux apt/yum/pacman/zypper/apk `case` on macOS's `$ID` (unset on macOS, since `/etc/os-release` doesn't exist there), hits the `*)` branch, prints `Unsupported distribution` and `return 1`, so `[INSTALLATION]: complete` never appears.

- [ ] **Step 3: Rewrite `src/scripts/macos/deps-install-script.sh`**

```sh
#!/usr/bin/env bash

declare -a PACKAGES=("bash" "curl" "tar" "gzip")
declare -a SHOULD_INSTALL_PACKAGES

log() {
    local message="$1"
    local line=""
    local message_length=${#message}
    for ((i = 0; i < message_length; i++)); do
        line+="="
    done
    echo "${message^}"
    echo "$line"
}

check-packages() {
    log "Checking installed packages"
    for program in "${PACKAGES[@]}"; do
        if ! command -v "$program" >/dev/null 2>&1; then
            log "warning dependency: $program is not installed."
            SHOULD_INSTALL_PACKAGES+=("$program")
        fi
    done
    log "packages for installation: ${SHOULD_INSTALL_PACKAGES[*]}"
}

install_check() {
    if [ $? -eq 0 ]; then
        echo "[INSTALLATION]: complete"
    else
        echo "[INSTALLATION]: error"
    fi
}

install_dependencies() {
    if ! command -v brew >/dev/null 2>&1; then
        log "Homebrew not found - skipping dependency check (curl/tar/gzip/bash ship with macOS by default)."
        return 0
    fi

    check-packages
    log "Installing dependencies..."
    [[ ${#SHOULD_INSTALL_PACKAGES[@]} -eq 0 ]] || brew install "${SHOULD_INSTALL_PACKAGES[@]}"
    install_check
}

install_dependencies
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bash test/macos_deps_test.sh`
Expected: `PASS: macos_deps_test.sh`

- [ ] **Step 5: Wire the script into `install.yml`**

In `src/commands/install.yml`, in the `environment:` block of the `run` step, add a line alongside the existing `SCRIPT_INSTALL_MACOS` entry:

```yaml
            SCRIPT_INSTALL_MACOS: << include(scripts/macos/install.sh) >>
            SCRIPT_INSTALL_DEPENDENCY_MACOS: << include(scripts/macos/deps-install-script.sh) >>
```

- [ ] **Step 6: Call it from the macOS branch in `install.sh`**

In `src/scripts/install.sh`, change:

```sh
elif [ "$SYS_ENV_PLATFORM" = "macos" ]; then
    eval "$SCRIPT_INSTALL_MACOS"
```

to:

```sh
elif [ "$SYS_ENV_PLATFORM" = "macos" ]; then
    eval "$SCRIPT_INSTALL_DEPENDENCY_MACOS"
    eval "$SCRIPT_INSTALL_MACOS"
```

- [ ] **Step 7: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 8: Commit**

```bash
git add src/scripts/macos/deps-install-script.sh src/commands/install.yml src/scripts/install.sh test/macos_deps_test.sh
git commit -m "fix: implement real macOS dependency install via brew and wire it in"
```

---

## Task 4: Fix existing `test-deploy.yml` bugs (undefined parameter, wrong orb name)

**Files:**
- Modify: `.circleci/test-deploy.yml`

**Interfaces:**
- None (config-only fix, no new interfaces).

- [ ] **Step 1: Reproduce the failure**

Run: `circleci config validate .circleci/test-deploy.yml`
Expected: FAIL with `Arguments referenced without declared parameters: parameters.set_aws_env_vars`.

- [ ] **Step 2: Remove the undefined parameter reference**

In `.circleci/test-deploy.yml`, in the `integration-test-install` job's steps, remove this line from the `s5cmd-orb/install` call:

```yaml
          set_aws_env_vars: <<parameters.set_aws_env_vars>>
```

- [ ] **Step 3: Fix the publish orb name**

Change:

```yaml
      - orb-tools/publish:
          orb_name: circleci/aws-cli
```

to:

```yaml
      - orb-tools/publish:
          orb_name: s5cmd-orb
```

(matches the name already used by `orb-tools/continue` in `.circleci/config.yml`.)

- [ ] **Step 4: Verify it validates**

Run: `circleci config validate .circleci/test-deploy.yml`
Expected: `Config file at ".circleci/test-deploy.yml" is valid.`

- [ ] **Step 5: Commit**

```bash
git add .circleci/test-deploy.yml
git commit -m "fix: remove undefined parameter and correct publish orb name in test-deploy.yml"
```

---

## Task 5: Add the shared `default` executor

**Files:**
- Create: `src/executors/default.yml`

**Interfaces:**
- Produces: executor `default` - parameters `tag` (string, default `stable`) and `resource_class` (enum, default `medium`). Consumed by every job added in Tasks 6-10.

- [ ] **Step 1: Create `src/executors/default.yml`**

```yaml
description: |
  An image with the AWS CLI preinstalled, used as the base for s5cmd-orb jobs.
  s5cmd itself is installed by the orb's `install` command/job step, not by this image.
parameters:
  tag:
    description: >
      Select any of the available tags here: https://circleci.com/developer/images/image/cimg/aws.
    type: string
    default: "stable"
  resource_class:
    description: Configure the executor resource class
    type: enum
    enum: ["small", "medium", "medium+", "large", "xlarge"]
    default: "medium"

docker:
  - image: cimg/aws:<<parameters.tag>>
resource_class: <<parameters.resource_class>>
```

- [ ] **Step 2: Verify the orb packs and the executor is present**

Run: `circleci orb pack src | grep -A4 "^executors:"`
Expected: shows a `default:` executor block with `tag` and `resource_class` parameters.

- [ ] **Step 3: Commit**

```bash
git add src/executors/default.yml
git commit -m "feat: add shared default executor (cimg/aws)"
```

---

## Task 6: Add `cp` command, script, and job

**Files:**
- Create: `src/commands/cp.yml`
- Create: `src/scripts/cp.sh`
- Create: `src/jobs/cp.yml`
- Test: `test/cp_script_test.sh`

**Interfaces:**
- Consumes: `install` command (`src/commands/install.yml`, existing/fixed in Tasks 1-3), `default` executor (Task 5).
- Produces: command `cp` with parameters `from`, `to`, `arguments`, `profile_name`, `endpoint_url`, `when`. Job `cp` with the same parameters plus `auth` (steps, default `[]`), `executor` (executor, default `default`), `s5cmd_version` (string, default `latest`).

- [ ] **Step 1: Write the failing script test**

Create `test/cp_script_test.sh`:

```sh
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

SCRIPT="$(dirname "$0")/../src/scripts/cp.sh"

ORB_EVAL_FROM="local.txt" ORB_EVAL_TO="s3://bucket/local.txt" \
ORB_STR_ARGUMENTS="" ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="cp local.txt s3://bucket/local.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case1: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

ORB_EVAL_FROM="local.txt" ORB_EVAL_TO="s3://bucket/local.txt" \
ORB_STR_ARGUMENTS="--acl public-read --cache-control max-age=86400" \
ORB_STR_PROFILE_NAME="myprofile" ORB_STR_ENDPOINT_URL="https://minio.local" \
sh "$SCRIPT"
EXPECTED="--profile myprofile --endpoint-url https://minio.local cp --acl public-read --cache-control max-age=86400 local.txt s3://bucket/local.txt"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case2: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: cp_script_test.sh"
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh test/cp_script_test.sh`
Expected: FAIL - `src/scripts/cp.sh: No such file or directory`.

- [ ] **Step 3: Create `src/scripts/cp.sh`**

```sh
#!/bin/sh
ORB_EVAL_FROM="$(circleci env subst "${ORB_EVAL_FROM}")"
ORB_EVAL_TO="$(circleci env subst "${ORB_EVAL_TO}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
set -- "$@" cp
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
set -- "$@" "${ORB_EVAL_FROM}" "${ORB_EVAL_TO}"

set -x
"$@"
set +x
```

- [ ] **Step 4: Run it, verify it passes**

Run: `sh test/cp_script_test.sh`
Expected: `PASS: cp_script_test.sh`

- [ ] **Step 5: Create `src/commands/cp.yml`**

```yaml
description: >
  Copies a local file or S3 object to another location locally or in S3, using s5cmd. https://github.com/peak/s5cmd#5-examples
parameters:
  from:
    type: string
    description: A local file or source s3 object
  to:
    type: string
    description: A local target or s3 destination
  arguments:
    type: string
    default: ""
    description: >
      Additional s5cmd cp flags, space-separated (e.g. --acl public-read --sse aws:kms).
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL (e.g. for MinIO or Cloudflare R2).
  when:
    description: |
      Add the when attribute to a job step to override its default behavior
      and selectively run or skip steps depending on the status of the job.
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
steps:
  - run:
      name: s5cmd cp << parameters.from >> -> << parameters.to >>
      when: <<parameters.when>>
      environment:
        ORB_EVAL_FROM: <<parameters.from>>
        ORB_EVAL_TO: <<parameters.to>>
        ORB_STR_ARGUMENTS: <<parameters.arguments>>
        ORB_STR_PROFILE_NAME: <<parameters.profile_name>>
        ORB_STR_ENDPOINT_URL: <<parameters.endpoint_url>>
      command: <<include(scripts/cp.sh)>>
```

- [ ] **Step 6: Create `src/jobs/cp.yml`**

```yaml
description: >
  Checkout code, optionally authenticate, install s5cmd, and copy a local file or S3 object to another location.
parameters:
  from:
    type: string
    description: A local file or source s3 object
  to:
    type: string
    description: A local target or s3 destination
  arguments:
    type: string
    default: ""
    description: Additional s5cmd cp flags, space-separated.
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL.
  when:
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
  auth:
    description: |
      The authentication method used to access your AWS account. Import the aws-cli orb in your config and
      provide the aws-cli/setup command to authenticate with your preferred method. View examples for more information.
      If not provided, authentication will be handled by the environment (e.g., IAM roles, environment variables).
    type: steps
    default: []
  executor:
    description: The executor to use for this job. By default, this uses the "default" executor provided by this orb.
    type: executor
    default: default
  s5cmd_version:
    type: string
    default: latest
    description: s5cmd version to install before running this job's command.
executor: <<parameters.executor>>
steps:
  - checkout
  - when:
      condition: <<parameters.auth>>
      steps: <<parameters.auth>>
  - install:
      version: <<parameters.s5cmd_version>>
  - cp:
      when: <<parameters.when>>
      from: <<parameters.from>>
      to: <<parameters.to>>
      arguments: <<parameters.arguments>>
      profile_name: <<parameters.profile_name>>
      endpoint_url: <<parameters.endpoint_url>>
```

- [ ] **Step 7: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 8: Commit**

```bash
git add src/commands/cp.yml src/scripts/cp.sh src/jobs/cp.yml test/cp_script_test.sh
git commit -m "feat: add s5cmd cp command and job"
```

---

## Task 7: Add `mv` command, script, and job

**Files:**
- Create: `src/commands/mv.yml`
- Create: `src/scripts/mv.sh`
- Create: `src/jobs/mv.yml`
- Test: `test/mv_script_test.sh`

**Interfaces:**
- Consumes: `install` command, `default` executor (Task 5). Same shape as Task 6's `cp`.
- Produces: command/job `mv` with parameters `from`, `to`, `arguments`, `profile_name`, `endpoint_url`, `when` (+ job-only `auth`, `executor`, `s5cmd_version`).

- [ ] **Step 1: Write the failing script test**

Create `test/mv_script_test.sh` (identical structure to `test/cp_script_test.sh`, subcommand `mv`):

```sh
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
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh test/mv_script_test.sh`
Expected: FAIL - `src/scripts/mv.sh: No such file or directory`.

- [ ] **Step 3: Create `src/scripts/mv.sh`**

```sh
#!/bin/sh
ORB_EVAL_FROM="$(circleci env subst "${ORB_EVAL_FROM}")"
ORB_EVAL_TO="$(circleci env subst "${ORB_EVAL_TO}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
set -- "$@" mv
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
set -- "$@" "${ORB_EVAL_FROM}" "${ORB_EVAL_TO}"

set -x
"$@"
set +x
```

- [ ] **Step 4: Run it, verify it passes**

Run: `sh test/mv_script_test.sh`
Expected: `PASS: mv_script_test.sh`

- [ ] **Step 5: Create `src/commands/mv.yml`**

```yaml
description: >
  Moves/renames a local file or S3 object to another location locally or in S3, using s5cmd. https://github.com/peak/s5cmd#5-examples
parameters:
  from:
    type: string
    description: A local file or source s3 object
  to:
    type: string
    description: A local target or s3 destination
  arguments:
    type: string
    default: ""
    description: Additional s5cmd mv flags, space-separated.
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL (e.g. for MinIO or Cloudflare R2).
  when:
    description: |
      Add the when attribute to a job step to override its default behavior
      and selectively run or skip steps depending on the status of the job.
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
steps:
  - run:
      name: s5cmd mv << parameters.from >> -> << parameters.to >>
      when: <<parameters.when>>
      environment:
        ORB_EVAL_FROM: <<parameters.from>>
        ORB_EVAL_TO: <<parameters.to>>
        ORB_STR_ARGUMENTS: <<parameters.arguments>>
        ORB_STR_PROFILE_NAME: <<parameters.profile_name>>
        ORB_STR_ENDPOINT_URL: <<parameters.endpoint_url>>
      command: <<include(scripts/mv.sh)>>
```

- [ ] **Step 6: Create `src/jobs/mv.yml`**

```yaml
description: >
  Checkout code, optionally authenticate, install s5cmd, and move/rename a local file or S3 object.
parameters:
  from:
    type: string
    description: A local file or source s3 object
  to:
    type: string
    description: A local target or s3 destination
  arguments:
    type: string
    default: ""
    description: Additional s5cmd mv flags, space-separated.
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL.
  when:
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
  auth:
    description: |
      The authentication method used to access your AWS account. Import the aws-cli orb in your config and
      provide the aws-cli/setup command to authenticate with your preferred method. View examples for more information.
      If not provided, authentication will be handled by the environment (e.g., IAM roles, environment variables).
    type: steps
    default: []
  executor:
    description: The executor to use for this job. By default, this uses the "default" executor provided by this orb.
    type: executor
    default: default
  s5cmd_version:
    type: string
    default: latest
    description: s5cmd version to install before running this job's command.
executor: <<parameters.executor>>
steps:
  - checkout
  - when:
      condition: <<parameters.auth>>
      steps: <<parameters.auth>>
  - install:
      version: <<parameters.s5cmd_version>>
  - mv:
      when: <<parameters.when>>
      from: <<parameters.from>>
      to: <<parameters.to>>
      arguments: <<parameters.arguments>>
      profile_name: <<parameters.profile_name>>
      endpoint_url: <<parameters.endpoint_url>>
```

- [ ] **Step 7: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 8: Commit**

```bash
git add src/commands/mv.yml src/scripts/mv.sh src/jobs/mv.yml test/mv_script_test.sh
git commit -m "feat: add s5cmd mv command and job"
```

---

## Task 8: Add `sync` command, script, and job

**Files:**
- Create: `src/commands/sync.yml`
- Create: `src/scripts/sync.sh`
- Create: `src/jobs/sync.yml`
- Test: `test/sync_script_test.sh`

**Interfaces:**
- Consumes: `install` command, `default` executor (Task 5). Same shape as `cp`/`mv`.
- Produces: command/job `sync` with parameters `from`, `to`, `arguments`, `profile_name`, `endpoint_url`, `when` (+ job-only `auth`, `executor`, `s5cmd_version`).

- [ ] **Step 1: Write the failing script test**

Create `test/sync_script_test.sh`:

```sh
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
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh test/sync_script_test.sh`
Expected: FAIL - `src/scripts/sync.sh: No such file or directory`.

- [ ] **Step 3: Create `src/scripts/sync.sh`**

```sh
#!/bin/sh
ORB_EVAL_FROM="$(circleci env subst "${ORB_EVAL_FROM}")"
ORB_EVAL_TO="$(circleci env subst "${ORB_EVAL_TO}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
set -- "$@" sync
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
set -- "$@" "${ORB_EVAL_FROM}" "${ORB_EVAL_TO}"

set -x
"$@"
set +x
```

- [ ] **Step 4: Run it, verify it passes**

Run: `sh test/sync_script_test.sh`
Expected: `PASS: sync_script_test.sh`

- [ ] **Step 5: Create `src/commands/sync.yml`**

```yaml
description: >
  Syncs directories and S3 prefixes, using s5cmd. https://github.com/peak/s5cmd#5-examples
parameters:
  from:
    type: string
    description: A local directory path or S3 prefix to sync from
  to:
    type: string
    description: A local directory path or S3 prefix to sync to
  arguments:
    type: string
    default: ""
    description: Additional s5cmd sync flags, space-separated (e.g. --delete --acl public-read).
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL (e.g. for MinIO or Cloudflare R2).
  when:
    description: |
      Add the when attribute to a job step to override its default behavior
      and selectively run or skip steps depending on the status of the job.
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
steps:
  - run:
      name: s5cmd sync << parameters.from >> -> << parameters.to >>
      when: <<parameters.when>>
      environment:
        ORB_EVAL_FROM: <<parameters.from>>
        ORB_EVAL_TO: <<parameters.to>>
        ORB_STR_ARGUMENTS: <<parameters.arguments>>
        ORB_STR_PROFILE_NAME: <<parameters.profile_name>>
        ORB_STR_ENDPOINT_URL: <<parameters.endpoint_url>>
      command: <<include(scripts/sync.sh)>>
```

- [ ] **Step 6: Create `src/jobs/sync.yml`**

```yaml
description: >
  Checkout code, optionally authenticate, install s5cmd, and sync a local directory with an S3 prefix.
parameters:
  from:
    type: string
    description: A local directory path or S3 prefix to sync from
  to:
    type: string
    description: A local directory path or S3 prefix to sync to
  arguments:
    type: string
    default: ""
    description: Additional s5cmd sync flags, space-separated.
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL.
  when:
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
  auth:
    description: |
      The authentication method used to access your AWS account. Import the aws-cli orb in your config and
      provide the aws-cli/setup command to authenticate with your preferred method. View examples for more information.
      If not provided, authentication will be handled by the environment (e.g., IAM roles, environment variables).
    type: steps
    default: []
  executor:
    description: The executor to use for this job. By default, this uses the "default" executor provided by this orb.
    type: executor
    default: default
  s5cmd_version:
    type: string
    default: latest
    description: s5cmd version to install before running this job's command.
executor: <<parameters.executor>>
steps:
  - checkout
  - when:
      condition: <<parameters.auth>>
      steps: <<parameters.auth>>
  - install:
      version: <<parameters.s5cmd_version>>
  - sync:
      when: <<parameters.when>>
      from: <<parameters.from>>
      to: <<parameters.to>>
      arguments: <<parameters.arguments>>
      profile_name: <<parameters.profile_name>>
      endpoint_url: <<parameters.endpoint_url>>
```

- [ ] **Step 7: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 8: Commit**

```bash
git add src/commands/sync.yml src/scripts/sync.sh src/jobs/sync.yml test/sync_script_test.sh
git commit -m "feat: add s5cmd sync command and job"
```

---

## Task 9: Add `rm` command, script, and job

**Files:**
- Create: `src/commands/rm.yml`
- Create: `src/scripts/rm.sh`
- Create: `src/jobs/rm.yml`
- Test: `test/rm_script_test.sh`

**Interfaces:**
- Consumes: `install` command, `default` executor (Task 5).
- Produces: command/job `rm` with parameters `target`, `arguments`, `profile_name`, `endpoint_url`, `when` (+ job-only `auth`, `executor`, `s5cmd_version`). `target` replaces `from`/`to` since `rm` takes a single target.

- [ ] **Step 1: Write the failing script test**

Create `test/rm_script_test.sh`:

```sh
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
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh test/rm_script_test.sh`
Expected: FAIL - `src/scripts/rm.sh: No such file or directory`.

- [ ] **Step 3: Create `src/scripts/rm.sh`**

```sh
#!/bin/sh
ORB_EVAL_TARGET="$(circleci env subst "${ORB_EVAL_TARGET}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
set -- "$@" rm
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
set -- "$@" "${ORB_EVAL_TARGET}"

set -x
"$@"
set +x
```

- [ ] **Step 4: Run it, verify it passes**

Run: `sh test/rm_script_test.sh`
Expected: `PASS: rm_script_test.sh`

- [ ] **Step 5: Create `src/commands/rm.yml`**

```yaml
description: >
  Removes one or more S3 objects, using s5cmd. https://github.com/peak/s5cmd#5-examples
parameters:
  target:
    type: string
    description: An S3 URI or wildcard pattern of object(s) to remove, e.g. s3://bucket/prefix/*
  arguments:
    type: string
    default: ""
    description: Additional s5cmd rm flags, space-separated (e.g. --all-versions).
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL (e.g. for MinIO or Cloudflare R2).
  when:
    description: |
      Add the when attribute to a job step to override its default behavior
      and selectively run or skip steps depending on the status of the job.
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
steps:
  - run:
      name: s5cmd rm << parameters.target >>
      when: <<parameters.when>>
      environment:
        ORB_EVAL_TARGET: <<parameters.target>>
        ORB_STR_ARGUMENTS: <<parameters.arguments>>
        ORB_STR_PROFILE_NAME: <<parameters.profile_name>>
        ORB_STR_ENDPOINT_URL: <<parameters.endpoint_url>>
      command: <<include(scripts/rm.sh)>>
```

- [ ] **Step 6: Create `src/jobs/rm.yml`**

```yaml
description: >
  Checkout code, optionally authenticate, install s5cmd, and remove one or more S3 objects.
parameters:
  target:
    type: string
    description: An S3 URI or wildcard pattern of object(s) to remove.
  arguments:
    type: string
    default: ""
    description: Additional s5cmd rm flags, space-separated.
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL.
  when:
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
  auth:
    description: |
      The authentication method used to access your AWS account. Import the aws-cli orb in your config and
      provide the aws-cli/setup command to authenticate with your preferred method. View examples for more information.
      If not provided, authentication will be handled by the environment (e.g., IAM roles, environment variables).
    type: steps
    default: []
  executor:
    description: The executor to use for this job. By default, this uses the "default" executor provided by this orb.
    type: executor
    default: default
  s5cmd_version:
    type: string
    default: latest
    description: s5cmd version to install before running this job's command.
executor: <<parameters.executor>>
steps:
  - checkout
  - when:
      condition: <<parameters.auth>>
      steps: <<parameters.auth>>
  - install:
      version: <<parameters.s5cmd_version>>
  - rm:
      when: <<parameters.when>>
      target: <<parameters.target>>
      arguments: <<parameters.arguments>>
      profile_name: <<parameters.profile_name>>
      endpoint_url: <<parameters.endpoint_url>>
```

- [ ] **Step 7: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 8: Commit**

```bash
git add src/commands/rm.yml src/scripts/rm.sh src/jobs/rm.yml test/rm_script_test.sh
git commit -m "feat: add s5cmd rm command and job"
```

---

## Task 10: Add `ls` command, script, and job

**Files:**
- Create: `src/commands/ls.yml`
- Create: `src/scripts/ls.sh`
- Create: `src/jobs/ls.yml`
- Test: `test/ls_script_test.sh`

**Interfaces:**
- Consumes: `install` command, `default` executor (Task 5).
- Produces: command/job `ls` with parameters `target` (optional, default `""` = list all buckets), `arguments`, `profile_name`, `endpoint_url`, `when` (+ job-only `auth`, `executor`, `s5cmd_version`).

- [ ] **Step 1: Write the failing script test**

Create `test/ls_script_test.sh`:

```sh
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

SCRIPT="$(dirname "$0")/../src/scripts/ls.sh"

ORB_EVAL_TARGET="" ORB_STR_ARGUMENTS="" ORB_STR_PROFILE_NAME="" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="ls"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case1: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

ORB_EVAL_TARGET="s3://bucket/prefix/" \
ORB_STR_ARGUMENTS="--humanize" \
ORB_STR_PROFILE_NAME="myprofile" ORB_STR_ENDPOINT_URL="" \
sh "$SCRIPT"
EXPECTED="--profile myprofile ls --humanize s3://bucket/prefix/"
ACTUAL="$(tail -n1 "$LOG")"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "FAIL case2: got '$ACTUAL' want '$EXPECTED'"; exit 1; }

rm -rf "$TEST_DIR"
echo "PASS: ls_script_test.sh"
```

- [ ] **Step 2: Run it, verify it fails**

Run: `sh test/ls_script_test.sh`
Expected: FAIL - `src/scripts/ls.sh: No such file or directory`.

- [ ] **Step 3: Create `src/scripts/ls.sh`**

```sh
#!/bin/sh
ORB_EVAL_TARGET="$(circleci env subst "${ORB_EVAL_TARGET}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
set -- "$@" ls
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
if [ -n "${ORB_EVAL_TARGET}" ]; then
    set -- "$@" "${ORB_EVAL_TARGET}"
fi

set -x
"$@"
set +x
```

- [ ] **Step 4: Run it, verify it passes**

Run: `sh test/ls_script_test.sh`
Expected: `PASS: ls_script_test.sh`

- [ ] **Step 5: Create `src/commands/ls.yml`**

```yaml
description: >
  Lists S3 buckets or objects, using s5cmd. https://github.com/peak/s5cmd#5-examples
parameters:
  target:
    type: string
    default: ""
    description: An S3 URI to list (bucket, prefix, or wildcard). Leave empty to list all buckets.
  arguments:
    type: string
    default: ""
    description: Additional s5cmd ls flags, space-separated (e.g. --humanize --etag).
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL (e.g. for MinIO or Cloudflare R2).
  when:
    description: |
      Add the when attribute to a job step to override its default behavior
      and selectively run or skip steps depending on the status of the job.
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
steps:
  - run:
      name: s5cmd ls << parameters.target >>
      when: <<parameters.when>>
      environment:
        ORB_EVAL_TARGET: <<parameters.target>>
        ORB_STR_ARGUMENTS: <<parameters.arguments>>
        ORB_STR_PROFILE_NAME: <<parameters.profile_name>>
        ORB_STR_ENDPOINT_URL: <<parameters.endpoint_url>>
      command: <<include(scripts/ls.sh)>>
```

- [ ] **Step 6: Create `src/jobs/ls.yml`**

```yaml
description: >
  Checkout code, optionally authenticate, install s5cmd, and list S3 buckets or objects.
parameters:
  target:
    type: string
    default: ""
    description: An S3 URI to list. Leave empty to list all buckets.
  arguments:
    type: string
    default: ""
    description: Additional s5cmd ls flags, space-separated.
  profile_name:
    type: string
    default: ""
    description: AWS profile name to be configured.
  endpoint_url:
    type: string
    default: ""
    description: Custom S3-compatible endpoint URL.
  when:
    type: enum
    enum: ["on_success", "on_fail", "always"]
    default: "on_success"
  auth:
    description: |
      The authentication method used to access your AWS account. Import the aws-cli orb in your config and
      provide the aws-cli/setup command to authenticate with your preferred method. View examples for more information.
      If not provided, authentication will be handled by the environment (e.g., IAM roles, environment variables).
    type: steps
    default: []
  executor:
    description: The executor to use for this job. By default, this uses the "default" executor provided by this orb.
    type: executor
    default: default
  s5cmd_version:
    type: string
    default: latest
    description: s5cmd version to install before running this job's command.
executor: <<parameters.executor>>
steps:
  - checkout
  - when:
      condition: <<parameters.auth>>
      steps: <<parameters.auth>>
  - install:
      version: <<parameters.s5cmd_version>>
  - ls:
      when: <<parameters.when>>
      target: <<parameters.target>>
      arguments: <<parameters.arguments>>
      profile_name: <<parameters.profile_name>>
      endpoint_url: <<parameters.endpoint_url>>
```

- [ ] **Step 7: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 8: Commit**

```bash
git add src/commands/ls.yml src/scripts/ls.sh src/jobs/ls.yml test/ls_script_test.sh
git commit -m "feat: add s5cmd ls command and job"
```

---

## Task 11: Extend `test-deploy.yml` with real S3 integration tests and gate publish

**Files:**
- Modify: `.circleci/test-deploy.yml`

**Interfaces:**
- Consumes: jobs `cp`, `sync`, `mv`, `rm`, `ls` (Tasks 6-10), `aws-cli/setup` (from the `aws-cli` orb).

This task deliberately keeps the new S3-operation integration tests on the `default` (Linux) executor only - running the same OIDC-authenticated S3 calls again on macOS would double real AWS API usage for no additional coverage of the *command* logic (already covered by Tasks 6-10's local script tests and the macOS *install* path, which is what actually differs by OS). `integration-test-install` keeps its macOS coverage since that's the OS-specific code path.

- [ ] **Step 1: Reproduce current state**

Run: `circleci config validate .circleci/test-deploy.yml`
Expected: valid (Task 4 already fixed the blocking bug).

- [ ] **Step 2: Replace the `workflows:` block**

Replace the entire `workflows:` block in `.circleci/test-deploy.yml` with:

```yaml
workflows:
  test-deploy:
    jobs:
      - integration-test-install:
          name: integration-test-install-<<matrix.executor>>
          matrix:
            alias: integration-test-install
            parameters:
              executor: [docker-base, macos]
      - s5cmd-orb/sync:
          name: integration-test-sync
          pre-steps:
            - run: mkdir -p /tmp/s5cmd-test-bucket && echo "lorem ipsum" > /tmp/s5cmd-test-bucket/build_asset.txt
          auth:
            - aws-cli/setup:
                role_arn: arn:aws:iam::PLACEHOLDER_ACCOUNT_ID:role/PLACEHOLDER_S5CMD_TEST_ROLE
                role_session_name: "s5cmd-orb-test-session"
                profile_name: "OIDC-User"
          from: "/tmp/s5cmd-test-bucket"
          to: "s3://PLACEHOLDER_S5CMD_TEST_BUCKET/s5cmd-orb"
          profile_name: "OIDC-User"
          context: [CPE-OIDC]
          filters: *filters
      - s5cmd-orb/cp:
          name: integration-test-cp
          pre-steps:
            - run: mkdir -p /tmp/s5cmd-test-bucket && echo "lorem ipsum" > /tmp/s5cmd-test-bucket/build_asset.txt
          auth:
            - aws-cli/setup:
                role_arn: arn:aws:iam::PLACEHOLDER_ACCOUNT_ID:role/PLACEHOLDER_S5CMD_TEST_ROLE
                role_session_name: "s5cmd-orb-test-session"
                profile_name: "OIDC-User"
          from: "/tmp/s5cmd-test-bucket/build_asset.txt"
          to: "s3://PLACEHOLDER_S5CMD_TEST_BUCKET/s5cmd-orb/build_asset.txt"
          profile_name: "OIDC-User"
          context: [CPE-OIDC]
          filters: *filters
      - s5cmd-orb/ls:
          name: integration-test-ls
          auth:
            - aws-cli/setup:
                role_arn: arn:aws:iam::PLACEHOLDER_ACCOUNT_ID:role/PLACEHOLDER_S5CMD_TEST_ROLE
                role_session_name: "s5cmd-orb-test-session"
                profile_name: "OIDC-User"
          target: "s3://PLACEHOLDER_S5CMD_TEST_BUCKET/s5cmd-orb/"
          profile_name: "OIDC-User"
          context: [CPE-OIDC]
          filters: *filters
          requires:
            - integration-test-cp
      - s5cmd-orb/mv:
          name: integration-test-mv
          auth:
            - aws-cli/setup:
                role_arn: arn:aws:iam::PLACEHOLDER_ACCOUNT_ID:role/PLACEHOLDER_S5CMD_TEST_ROLE
                role_session_name: "s5cmd-orb-test-session"
                profile_name: "OIDC-User"
          from: "s3://PLACEHOLDER_S5CMD_TEST_BUCKET/s5cmd-orb/build_asset.txt"
          to: "s3://PLACEHOLDER_S5CMD_TEST_BUCKET/s5cmd-orb/build_asset_moved.txt"
          profile_name: "OIDC-User"
          context: [CPE-OIDC]
          filters: *filters
          requires:
            - integration-test-ls
      - s5cmd-orb/rm:
          name: integration-test-rm
          auth:
            - aws-cli/setup:
                role_arn: arn:aws:iam::PLACEHOLDER_ACCOUNT_ID:role/PLACEHOLDER_S5CMD_TEST_ROLE
                role_session_name: "s5cmd-orb-test-session"
                profile_name: "OIDC-User"
          target: "s3://PLACEHOLDER_S5CMD_TEST_BUCKET/s5cmd-orb/*"
          profile_name: "OIDC-User"
          context: [CPE-OIDC]
          filters: *filters
          requires:
            - integration-test-mv
      - orb-tools/pack:
          filters: *release-filters
      - orb-tools/publish:
          orb_name: s5cmd-orb
          vcs_type: << pipeline.project.type >>
          pub_type: production
          enable_pr_comment: true
          requires:
            - orb-tools/pack
            - integration-test-install
            - integration-test-sync
            - integration-test-cp
            - integration-test-ls
            - integration-test-mv
            - integration-test-rm
          context: orb-publisher
          filters: *release-filters
```

- [ ] **Step 3: Add the `aws-cli` orb import**

At the top of `.circleci/test-deploy.yml`, in the `orbs:` block, add it alongside the existing `orb-tools` and `s5cmd-orb` entries:

```yaml
orbs:
  orb-tools: circleci/orb-tools@12.0
  aws-cli: circleci/aws-cli@5.1.1
  s5cmd-orb: {}
```

- [ ] **Step 4: Verify it validates**

Run: `circleci config validate .circleci/test-deploy.yml`
Expected: `Config file at ".circleci/test-deploy.yml" is valid.`

- [ ] **Step 5: Verify the full orb + test-deploy compile together**

Run:
```bash
circleci orb pack src > /tmp/s5cmd-orb-packed.yml
circleci orb validate /tmp/s5cmd-orb-packed.yml
```
Expected: `Orb is valid.`

- [ ] **Step 6: Commit**

```bash
git add .circleci/test-deploy.yml
git commit -m "test: add real S3 integration tests for cp/sync/mv/rm/ls and gate publish on them"
```

---

## Task 12: Fix and extend examples

**Files:**
- Modify: `src/examples/install_s5cmd.yml`
- Create: `src/examples/static_credentials.yml`
- Create: `src/examples/authentication_with_jobs.yml`
- Create: `src/examples/sync_and_copy_with_oidc.yml`

**Interfaces:**
- None (documentation-only; `circleci orb pack` renders these into the packed orb's `examples:` section, which is the verification mechanism).

- [ ] **Step 1: Reproduce the current bug**

Run: `circleci orb pack src | grep -A8 "install_s5cmd:"`
Note: the example currently calls a non-existent `s5cmd/setup` command with an unsupported `profile_name` parameter, and references an executor (`s5cmd/default`) that doesn't exist yet (it does now, after Task 5) - `circleci orb pack` doesn't type-check example bodies, so this needs manual review, not a validate command.

- [ ] **Step 2: Fix `src/examples/install_s5cmd.yml`**

```yaml
description: Easily install s5cmd and use it to interact with S3 in your jobs.
usage:
  version: 2.1

  orbs:
    s5cmd-orb: <your-orb-namespace>/s5cmd-orb@1.0.0

  jobs:
    s5cmd-example:
      executor: s5cmd-orb/default
      steps:
        - checkout
        - s5cmd-orb/install
        - run: echo "Run your code here"

  workflows:
    s5cmd:
      jobs:
        - s5cmd-example:
            context: aws
```

- [ ] **Step 3: Create `src/examples/static_credentials.yml`**

```yaml
description: >
  How to use the s5cmd orb with static credentials.
usage:
  version: 2.1
  orbs:
    s5cmd-orb: <your-orb-namespace>/s5cmd-orb@1.0.0
    # Importing aws-cli orb is required
    aws-cli: circleci/aws-cli@5.1.1
  jobs:
    build:
      docker:
        - image: cimg/base:current
      steps:
        - checkout
        - run: mkdir bucket && echo "lorem ipsum" > bucket/build_asset.txt
        - aws-cli/install
        - s5cmd-orb/install
        - s5cmd-orb/sync:
            from: bucket
            to: "s3://my-s3-bucket-name/prefix"
            arguments: --acl public-read --cache-control max-age=86400
        - s5cmd-orb/cp:
            from: bucket/build_asset.txt
            to: "s3://my-s3-bucket-name"
  workflows:
    s5cmd-example:
      jobs:
        - build:
            context: AWS_CREDENTIALS
```

- [ ] **Step 4: Create `src/examples/authentication_with_jobs.yml`**

```yaml
description: >
  The s5cmd orb provides ready-to-use "cp" and "sync" jobs. This example demonstrates OIDC authentication
  in a job using the required "auth" parameter. The aws-cli orb must be imported and the aws-cli/setup
  command must be used with a valid AWS role_arn.
usage:
  version: 2.1
  orbs:
    s5cmd-orb: <your-orb-namespace>/s5cmd-orb@1.0.0
    # Importing aws-cli orb is required
    aws-cli: circleci/aws-cli@5.1.1
  workflows:
    s5cmd-example:
      jobs:
        - s5cmd-orb/cp:
            auth:
              # Add authentication step with OIDC using aws-cli/setup command
              - aws-cli/setup:
                  role_arn: arn:aws:iam::123456789012:role/VALID-S3-ROLE
                  profile_name: "OIDC-User"
            from: PATH/TO/FILE
            to: "s3://my-s3-bucket-name"
            # Profile name must be the same as authentication step if specified
            profile_name: "OIDC-User"
        - s5cmd-orb/sync:
            auth:
              # Add authentication step with OIDC using aws-cli/setup command
              - aws-cli/setup:
                  role_arn: arn:aws:iam::123456789012:role/VALID-S3-ROLE
            from: bucket
            to: "s3://my-s3-bucket-name/prefix"
```

- [ ] **Step 5: Create `src/examples/sync_and_copy_with_oidc.yml`**

```yaml
description: >
  The s5cmd orb allows you to "sync" directories or "cp" files to an S3 bucket.
  This example shows a typical CircleCI job where a file "bucket/build_asset.txt" is created,
  then synced and copied. It also demonstrates OIDC authentication by importing the aws-cli orb
  and providing the aws-cli/setup command with a valid AWS role_arn and profile name.
  If a profile name is specified with authentication, it must be specified in the s5cmd commands too.
usage:
  version: 2.1
  orbs:
    s5cmd-orb: <your-orb-namespace>/s5cmd-orb@1.0.0
    # Importing aws-cli orb is required
    aws-cli: circleci/aws-cli@5.1.1
  jobs:
    sync_and_copy:
      docker:
        - image: cimg/base:current
      steps:
        - checkout
        - run: mkdir bucket && echo "lorem ipsum" > bucket/build_asset.txt
        - aws-cli/setup:
            role_arn: arn:aws:iam::123456789012:role/VALID-S3-ROLE
            profile_name: "OIDC-User"
        - s5cmd-orb/install
        - s5cmd-orb/sync:
            # Profile name must be the same as authentication step
            profile_name: "OIDC-User"
            from: bucket
            to: "s3://my-s3-bucket-name/prefix"
            arguments: --acl public-read --cache-control max-age=86400
        - s5cmd-orb/cp:
            # Profile name must be the same as authentication step
            profile_name: "OIDC-User"
            from: bucket/build_asset.txt
            to: "s3://my-s3-bucket-name"
  workflows:
    s5cmd-example:
      jobs:
        - sync_and_copy
```

- [ ] **Step 6: Verify the orb still packs cleanly**

Run: `circleci orb pack src > /dev/null`
Expected: exits 0, no output.

- [ ] **Step 7: Commit**

```bash
git add src/examples/install_s5cmd.yml src/examples/static_credentials.yml src/examples/authentication_with_jobs.yml src/examples/sync_and_copy_with_oidc.yml
git commit -m "docs: fix broken example and add static-credentials/auth-job/OIDC examples"
```

---

## Task 13: Update README

**Files:**
- Modify: `README.md`

**Interfaces:**
- None (documentation-only).

- [ ] **Step 1: Replace `README.md`**

```markdown
# s5cmd Orb

Install [s5cmd](https://github.com/peak/s5cmd) and use it to copy, sync, move, remove, and list S3 objects in your CircleCI pipelines - a faster, more parallel alternative to the AWS CLI for S3 operations.

## Usage

Example use-cases are provided on the orb's registry page once published, and as source in the `src/examples` directory:
- `install_s5cmd.yml` - install s5cmd and run your own commands
- `static_credentials.yml` - sync/copy using credentials already present in the environment (e.g. a context)
- `authentication_with_jobs.yml` - use the ready-made `cp`/`sync` jobs with OIDC auth via the `auth` parameter
- `sync_and_copy_with_oidc.yml` - a custom job authenticating via OIDC, then calling the `sync`/`cp` commands directly

## Resources

[CircleCI Orb Docs](https://circleci.com/docs/2.0/orb-intro/#section=configuration) - Docs for using and creating CircleCI Orbs.

s5cmd docs: https://github.com/peak/s5cmd

### How to Contribute

Issues and pull requests are welcome against this repository.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: replace README stub with usage overview"
```

---

## Final Verification

- [ ] Run every test file: `for f in test/*.sh; do echo "== $f =="; sh "$f" 2>/dev/null || bash "$f"; done` - all print `PASS`.
- [ ] Run `circleci orb pack src > /tmp/s5cmd-orb-packed.yml && circleci orb validate /tmp/s5cmd-orb-packed.yml` - prints `Orb is valid.`
- [ ] Run `circleci config validate .circleci/config.yml` and `circleci config validate .circleci/test-deploy.yml` - both valid.
- [ ] If `shellcheck` is available (`brew install shellcheck` if not), run `shellcheck src/scripts/*.sh src/scripts/linux/*.sh src/scripts/macos/*.sh` and fix anything it flags - this also runs automatically in `.circleci/config.yml`'s `shellcheck/check` job.
- [ ] Confirm the two open questions from Global Constraints are still tracked: real orb namespace (examples/test-deploy still say `<your-orb-namespace>` / `PLACEHOLDER_*`) and real AWS OIDC role/bucket for `test-deploy.yml`.
