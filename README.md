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
