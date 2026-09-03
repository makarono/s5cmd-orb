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

## Development

Prerequisites: [just](https://github.com/casey/just), [CircleCI CLI](https://circleci.com/docs/local-cli/) configured with a personal API token (`circleci setup`).

The `CIRCLE_TOKEN` is read automatically from `~/.circleci/cli.yml` — no manual export needed.

### Recipes

| Command | Description |
|---------|-------------|
| `just test` | Run the full unit test suite locally |
| `just pack` | Pack `src/` into a single `orb.yml` file |
| `just validate` | Pack and validate the orb YAML |
| `just publish-dev` | Pack, validate, and publish as `dev:first` |
| `just release` | Full release: pack → validate → publish dev → promote as **patch** |
| `just release minor` | Same flow, promote as **minor** |
| `just release major` | Same flow, promote as **major** |
| `just list` | List all published versions in the `aduro-orbs` namespace |
| `just source 1.0.0` | Print the source of a specific published version |

### Release workflow

```sh
just test             # verify all tests pass
just release          # publish patch release (e.g. 0.0.1 → 0.0.2)
just release minor    # publish minor release (e.g. 0.0.x → 0.1.0)
just release major    # publish major release (e.g. 0.x.x → 1.0.0)
```

### How to Contribute

Issues and pull requests are welcome against this repository.
