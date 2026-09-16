#!/usr/bin/env bash
#
# source-credential-violation golden fixture — POSITIVE CONTROL. This file
# exists ONLY to prove fence-no-source-credential-files.sh actually catches
# what it claims to: a box-side config file read via `source` instead of
# the grep-based contract, the exact shape that disclosed the
# migrator-trigger Coolify token on 2026-09-16 (see
# scripts/migrator-orchestrate.sh's incident comment and
# scripts/ci/fence-no-source-credential-files.sh's header for the full
# account).
#
# This is NOT real provisioning code and is never executed by anything --
# the CI job runs the fence AGAINST this directory in inversion-mode and
# asserts a non-zero exit. If this file is ever "fixed" to stop sourcing,
# the fence's inversion-mode CI leg goes green on an empty scope instead of
# a caught violation, which is exactly the vacuous-fence failure this
# fixture exists to prevent -- do not "fix" it.
set -euo pipefail

TOKEN_FILE="/etc/pfin/example-credential.env"

set -a
source "$TOKEN_FILE"
set +a

echo "example only, never runs: $EXAMPLE_TOKEN"
