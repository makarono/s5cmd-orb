orb_name := "aduro-orbs/s5cmd-orb"
orb_file := "/tmp/s5cmd-orb.yml"
dev_tag  := "dev:first"

export CIRCLE_TOKEN := `cat ~/.circleci/cli.yml | yq ".token"`

# Show available commands
default:
    @just --list

# Pack src/ into a single orb YAML
pack:
    circleci orb pack src > {{ orb_file }}
    @echo "Packed → {{ orb_file }}"

# Validate the packed orb
validate: pack
    circleci orb validate {{ orb_file }}

# Publish a dev version (used before promoting to production)
publish-dev: validate
    circleci orb publish {{ orb_file }} {{ orb_name }}@{{ dev_tag }}

# Promote dev version to production — usage: just release patch|minor|major
release bump="patch": publish-dev
    circleci orb publish promote {{ orb_name }}@{{ dev_tag }} --bump {{ bump }}

# List all published versions
list:
    circleci orb list aduro-orbs --uncertified

# Show source of a specific version — usage: just source 1.0.0
source version:
    circleci orb source {{ orb_name }}@{{ version }}

# Run local unit tests (same as CI)
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in test/*.sh; do
        echo "== $f =="
        sh "$f" || bash "$f"
    done
