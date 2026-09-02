# s5cmd Orb Completion - Design

## Context

The s5cmd orb currently only ships an `install` command (installs the
s5cmd binary). It has no S3-interaction commands, no jobs, and no
orb-level executor - it does not do what its name promises yet. The
official `circleci/aws-s3` orb (`/tmp/aws-s3-orb`) was used as the
reference pattern for a complete, publishable S3-interaction orb.

Reference pattern (`aws-s3-orb`):
- `executors/default.yml` - a shared Docker executor with `tag` and
  `resource_class` parameters.
- `commands/*.yml` - one command per S3 operation. Each command takes
  its inputs as CircleCI parameters, passes them into the step via
  `environment:`, and delegates to a POSIX shell script
  (`scripts/*.sh`) included with `<<include(...)>>`. Values are run
  through `circleci env subst` inside the script rather than
  interpolated directly into the command string, to avoid injection.
- `jobs/*.yml` - a ready-to-use job per command: `checkout` -> run the
  user-supplied `auth` steps (a `steps`-typed parameter) -> call the
  command. Lets a user skip writing jobs by hand.
- `auth` parameter - type `steps`, default `[]`, wrapped in a `when:
  condition: <<parameters.auth>>` block. The orb knows nothing about
  credentials; the caller supplies their own login step (e.g.
  `aws-cli/setup` with OIDC role or static keys).
- `test-deploy.yml` - real integration test against a live S3 bucket
  using an OIDC test role, run as a job matrix, gating
  `orb-tools/publish`.

## Goal

Bring the s5cmd orb to feature parity with this pattern: install +
`cp`, `sync`, `rm`, `mv`, `ls` commands and jobs, a shared executor,
the same `auth`/`profile_name` pattern, real integration tests, and
fixes to the bugs found in the existing `install` implementation (the
new jobs depend on `install` working correctly, so these are
prerequisites, not a separate follow-up).

## Scope

In scope:
- New commands: `cp`, `sync`, `rm`, `mv`, `ls`.
- New jobs of the same names, each wrapping checkout + auth + install
  + the command.
- New `default` executor (`cimg/aws:stable`, parameterized
  `resource_class`).
- Bug fixes in `install` (listed below) required for the above to
  work.
- Updated `test-deploy.yml` integration tests and `README.md`/example
  usage.

Out of scope (not requested): `mb`/`rb` (bucket create/remove), a
generic passthrough/`run` command, Windows support (already
unsupported, stays that way).

## Components

### Executor - `src/executors/default.yml`

Mirrors `aws-s3`'s executor exactly:

```yaml
parameters:
  tag:
    type: string
    default: "stable"
  resource_class:
    type: enum
    enum: ["small", "medium", "medium+", "large", "xlarge"]
    default: "medium"
docker:
  - image: cimg/aws:<<parameters.tag>>
resource_class: <<parameters.resource_class>>
```

`cimg/aws` does not ship s5cmd, so every job installs it via the
`install` command before use.

### Commands - `src/commands/{cp,sync,rm,mv,ls}.yml`

Parameters per command:

| command | params |
|---|---|
| `cp` | `from`, `to`, `arguments`, `profile_name`, `endpoint_url`, `when` |
| `sync` | `from`, `to`, `arguments`, `profile_name`, `endpoint_url`, `when` |
| `mv` | `from`, `to`, `arguments`, `profile_name`, `endpoint_url`, `when` |
| `rm` | `target`, `arguments`, `profile_name`, `endpoint_url`, `when` |
| `ls` | `target`, `arguments`, `profile_name`, `endpoint_url`, `when` |

`endpoint_url` (default `""`) targets S3-compatible services (MinIO,
R2, etc) instead of AWS S3 - maps to s5cmd's `--endpoint-url` global
flag / `S3_ENDPOINT_URL` env var.

Same shape as `aws-s3`'s `copy`/`sync` commands: values go in via
`environment:` (`ORB_EVAL_FROM`, `ORB_EVAL_TO`, `ORB_EVAL_TARGET`,
`ORB_STR_ARGUMENTS`, `ORB_STR_PROFILE_NAME`, `ORB_STR_ENDPOINT_URL`),
script does `circleci env subst`, then builds the argv array before
exec.

**`arguments` is a single free-form string, not a list param** -
matches `aws-s3-orb` exactly rather than inventing a new mechanism.
s5cmd exposes 20-40 flags per command (`--acl`, `--sse`,
`--cache-control`, `--exclude`, `--metadata`, ...) - too many to
expose as individual orb parameters, so `arguments` is the escape
hatch, and the caller can put as many flags in it as they want,
space-separated, e.g.:

```yaml
arguments: --acl public-read --cache-control "max-age=86400" --exclude "*.tmp"
```

The script splits this into separate argv entries by word-splitting
on spaces, exactly like `aws-s3-orb`'s `copy.sh`/`sync.sh`:

```sh
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    set --
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
```

The `sed 's/,[ ]*/,/g'` collapses `", "` down to `","` first, so a
comma-separated value inside one flag (e.g. a tag list) survives as
one word instead of being split apart - same subtlety as the
reference orb.

**Key difference from aws cli**: s5cmd takes `--profile` and
`--endpoint-url` as *global* flags, before the subcommand
(`s5cmd --profile x --endpoint-url y cp ...`), not after it like
`aws s3 cp ... --profile x`. Each script must place them accordingly:

```sh
set -- s5cmd
[ -n "$ORB_STR_PROFILE_NAME" ] && set -- "$@" --profile "$ORB_STR_PROFILE_NAME"
[ -n "$ORB_STR_ENDPOINT_URL" ] && set -- "$@" --endpoint-url "$ORB_STR_ENDPOINT_URL"
set -- "$@" cp "$ORB_EVAL_FROM" "$ORB_EVAL_TO"
# + arguments appended same way copy.sh in aws-s3 does it
"$@"
```

### Jobs - `src/jobs/{cp,sync,rm,mv,ls}.yml`

Same shape as `aws-s3`'s `jobs/copy.yml`:

```yaml
parameters:
  <command params...>
  auth:
    type: steps
    default: []
  executor:
    type: executor
    default: default
  s5cmd_version:
    type: string
    default: latest
executor: <<parameters.executor>>
steps:
  - checkout
  - when:
      condition: <<parameters.auth>>
      steps: <<parameters.auth>>
  - install:
      version: <<parameters.s5cmd_version>>
  - cp: # or sync/rm/mv/ls
      from: <<parameters.from>>
      to: <<parameters.to>>
      arguments: <<parameters.arguments>>
      profile_name: <<parameters.profile_name>>
```

### Bug fixes in `install` (prerequisite work)

All found during the earlier code review, confirmed still present:

1. `macos/install.sh` is a byte-for-byte copy of `linux/install.sh` -
   downloads `*_Linux-64bit.tar.gz` on macOS. Fix: correct archive map
   using s5cmd's actual macOS release names (`Darwin-64bit`,
   `Darwin-arm64`), and add `arm64` to the Linux map's Mac counterpart
   (Apple Silicon runners report `uname -m` = `arm64`, not `aarch64`
   there).
2. Variable name mismatch: `install.sh` exports
   `S5CMD_EVAL_INSTALL_DIR` / `S5CMD_EVAL_BINARY_DIR`, but
   `linux/install.sh` and `macos/install.sh` read
   `S5CMD_CLI_EVAL_INSTALL_DIR` / `S5CMD_CLI_EVAL_BINARY_DIR`. Fix:
   rename to match on both sides.
3. `override_installed` is a boolean CircleCI parameter (substitutes
   as the words `true`/`false`) but is compared with
   `[ "$S5CMD_BOOL_OVERRIDE" -eq 1 ]`, which is an integer comparison
   and errors out on `true`/`false`. Fix: `[ "$S5CMD_BOOL_OVERRIDE" =
   "true" ]`.
4. `version: latest` (the default) is used literally in the download
   URL (`.../download/vlatest/...`), which 404s. Fix: when version is
   `latest`, resolve it first via the GitHub releases API
   (`curl -fsSL https://api.github.com/repos/peak/s5cmd/releases/latest`,
   parse `tag_name`, strip leading `v`).
5. `macos/deps-install-script.sh` exists but is never wired into
   `install.yml`'s `environment:` block (`SCRIPT_INSTALL_DEPENDENCY_MACOS`
   is missing), and its current content is a copy of the Linux
   apt/yum branch logic, not brew. Fix: rewrite it to check for
   `bash`/`curl`/`tar`/`gzip` and `brew install` any that are missing
   (mirroring the existing `check-packages` / `SHOULD_INSTALL_PACKAGES`
   shape from the Linux script), then wire it into `install.yml` and
   call it from the macOS branch of `install.sh`.
6. `test-deploy.yml`: `integration-test-install` job references a
   `set_aws_env_vars` parameter that is declared nowhere (not on the
   job, not on `install`) - pipeline fails on an undefined parameter
   reference. Fix: remove it (or add the parameter if a real use
   turns up - none was identified).
7. `test-deploy.yml`: publishes as `orb_name: circleci/aws-cli`
   (leftover from copying the aws-cli orb's test-deploy). Fix: correct
   orb name/namespace for this orb.
8. `examples/install_s5cmd.yml` calls a command `s5cmd/setup` that
   doesn't exist (only `install` does). Fix: correct the example to
   use `s5cmd/install` (+ new commands once they exist).

## Testing (`.circleci/test-deploy.yml`)

Mirrors `aws-s3-orb`'s pattern:
- `integration-test` job: checkout, create a local test file/dir,
  auth via `aws-cli/setup` against an OIDC test role, then run
  `s5cmd-orb/sync`, `s5cmd-orb/cp`, `s5cmd-orb/ls`, `s5cmd-orb/mv`,
  `s5cmd-orb/rm` against a real test bucket, run as a job matrix over
  `linux` and `macos` executors.
- Needs a real AWS test account/OIDC role ARN and bucket name (same
  as `aws-s3-orb`'s `arn:aws:iam::122211685980:role/CPE_S3_OIDC_TEST`
  / `s3://orb-testing-1`) - **this repo's own values, to be supplied
  before the integration test job can actually run** (placeholder
  values will be used until then).
- `orb-tools/publish` requires all integration test jobs to pass
  first.

## Docs

- `README.md`: replace the 2-line stub with orb-tools-style usage
  docs (badges, install/usage examples for each job).
- `src/examples/`: fix the existing example and add 2-3 more
  mirroring `aws-s3-orb`'s three examples (static credentials, auth
  via a job's `auth` param, OIDC sync+copy) adapted to s5cmd's
  cp/sync/rm/mv/ls commands.

## Error handling

Same as `aws-s3-orb`: no custom retry/error-handling logic in the
commands themselves - `set -e`-style shell scripts, s5cmd's own exit
code determines step pass/fail, and the `when:` parameter (`on_success`
/ `on_fail` / `always`) lets the caller control execution like any
other CircleCI step.

## Unresolved questions

- Real AWS test account details (OIDC role ARN, test bucket name) for
  `test-deploy.yml` integration tests - needed before those tests can
  actually run in CI.
