#!/usr/bin/env bash
#
# fence-config-toml-migrations-enabled — asserts supabase/config.toml's
# [db.migrations] `enabled` key is committed as `true` (ADR-072 Amendment 5
# Decision K).
#
# WHY THIS EXISTS. CI's own bring-up (db-tests.yml / security-scan.yml's
# "Start local stack" step) flips this key to `false` for the duration of a
# single job — a local, scratch-copy toggle, restored on EXIT — because the
# key is the only lever that suppresses `supabase start`'s unconditional
# migration apply (internal/migration/apply/apply.go's applyMigrationFiles,
# gated by this setting) long enough to run supabase/auth-grants.sql as
# supabase_admin before the migrations that need it. THE SAME FUNCTION IS
# WHAT `supabase db push` CALLS. If `false` ever lands in the COMMITTED
# supabase/config.toml (a bad merge, a runner crash before its trap fires
# and its own working-tree copy is inadvertently committed, a hand-edit),
# a production `db push` would apply NOTHING and exit 0 — the same silent-
# success shape as the WARNING-01007 defect Decision K names, one layer up,
# and with no error at all to notice it by.
#
# CATCH CRITERION: read the [db.migrations] section of the given config.toml
# (section-scoped, the same way the CI bring-up step's own toggle is scoped
# — a bare `grep enabled` would false-positive on any of this file's dozen
# other `enabled = ` keys) and assert its `enabled` value is `true`.
#
# Usage: fence-config-toml-migrations-enabled.sh <path-to-config.toml>
# Exit 0: enabled = true (or key absent -- CLI default is true; absent is
#         not itself a violation, but see the "not found" warning below).
# Exit 1: enabled = false -- VIOLATION, fail closed.
# Exit 2: file not found / [db.migrations] section not found -- environment
#         problem, distinct from a caught violation (mirrors this repo's
#         other fences' 1-vs-2 convention).
set -euo pipefail

CONFIG_FILE="${1:?Usage: fence-config-toml-migrations-enabled.sh <path-to-config.toml>}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "FATAL: config file not found: $CONFIG_FILE" >&2
  exit 2
fi

VALUE="$(awk '
  /^\[db\.migrations\]/ { insec=1; next }
  /^\[/ { insec=0 }
  insec && /^enabled[[:space:]]*=/ { found=1; print; exit }
  END { if (!found) exit 3 }
' "$CONFIG_FILE")" || {
  echo "FATAL: [db.migrations] section (or its enabled key) not found in $CONFIG_FILE — did the section get renamed or removed? Update this fence's parser to match." >&2
  exit 2
}

if printf '%s' "$VALUE" | grep -qE '=\s*false\s*$'; then
  echo "VIOLATION: $CONFIG_FILE's [db.migrations] enabled = false, committed." >&2
  echo "" >&2
  echo "This is the same setting CI's own bring-up step toggles false for a single job, then restores on EXIT (ADR-072 Amendment 5 Decision K). The function it gates -- applyMigrationFiles -- is also what 'supabase db push' calls. Committed false here means a production db push applies NOTHING and exits 0, silently -- the exact failure shape this decision exists to prevent, one layer up." >&2
  echo "Fix: set it back to 'enabled = true' in $CONFIG_FILE and never commit false." >&2
  exit 1
fi

if ! printf '%s' "$VALUE" | grep -qE '=\s*true\s*$'; then
  echo "FATAL: [db.migrations] enabled has an unrecognized value in $CONFIG_FILE: $VALUE" >&2
  exit 2
fi

echo "config-toml-migrations-enabled fence: $CONFIG_FILE clean ([db.migrations] enabled = true)."
exit 0
