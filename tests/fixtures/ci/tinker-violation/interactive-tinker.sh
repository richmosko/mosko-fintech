#!/usr/bin/env bash
#
# Interactive-tinker golden fixture — POSITIVE CONTROL. This file exists
# ONLY to prove fence-tinker-no-echo.sh actually catches what it claims to:
# an interactive/piped `artisan tinker` invocation, the exact shape that
# leaked a Coolify automation token's plaintext on 2026-09-11 (see
# scripts/provision-vps.sh's incident comment and
# scripts/ci/fence-tinker-no-echo.sh's header for the full account).
#
# This is NOT real provisioning code and is never executed by anything —
# the CI job runs the fence AGAINST this directory in inversion-mode and
# asserts a non-zero exit. If this file is ever "fixed" to use --execute,
# the fence's inversion-mode CI leg goes green on an empty scope instead of
# a caught violation, which is exactly the vacuous-fence failure this
# fixture exists to prevent — do not "fix" it.
set -euo pipefail

TOKEN_SCRIPT='$token = $user->createToken("example", ["root"]);
echo $token->plainTextToken;
null;'

echo "$TOKEN_SCRIPT" | ssh root@example.invalid "docker exec -i coolify php artisan tinker"
