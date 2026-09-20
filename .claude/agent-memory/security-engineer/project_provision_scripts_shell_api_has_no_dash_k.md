---
name: provision-scripts-shell-api-has-no-dash-k
description: The two provision-*.sh shell api() helpers put the Coolify token in a box-side curl -H argv, NOT in a -K - stdin config — unlike every other Coolify-calling script in the repo.
metadata:
  type: project
---

`scripts/provision-migrator-app.sh` and `scripts/provision-supabase-stack.sh` each define a **shell**
`api()` that builds, inside an `sshx` command string:
`curl -fsS -X $method -H "Authorization: Bearer $TOKEN" … http://localhost:8000/api/v1$path`.
Token is expanded **remotely** (`\$TOKEN` from `/root/.pfin/coolify.env`), so it never enters the
operator's LOCAL argv — it enters the BOX-side curl argv. That is the booked BACKLOG §7.36 item-60
class, plus the `/tmp/$$` half.

⚠ **`-K -` is NOT this code path.** The `-K -` stdin-config convention lives in `coolify-env.sh`,
`migrator-cutover-verify.sh`, `migrator-scheduled-task.sh`, `mint-supabase-jwt-keys.sh`,
`push-production-secrets.sh`, and in `provision-supabase-stack.sh`'s **embedded Python** `api()`
(same file, different helper) — which is why the same file appears to carry both conventions.

**Why:** a review brief (PR #827, 2026-09-19) asserted "token handling matches the scripts' existing
`-K -` stdin pattern" and asked me to confirm it. Confirming would have laundered a false premise
into a GREEN. The same file carrying two `api()` helpers with different token postures is exactly
what makes the wrong premise plausible.

**How to apply:** when grading a new Coolify API call in these two scripts, `grep -n '^api()' -A 14`
the **shell** helper before saying anything about `-K -`. New calls that reuse the shell `api()` add
no new class but DO widen item 60's site count — say so (see
[[an-accepted-residual-must-not-silently-widen]]). Related: [[credential-in-host-argv-and-the-named-vehicle]],
[[subprocess-argv-token-leak-via-calledprocesserror]].
