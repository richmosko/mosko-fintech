---
name: subprocess-argv-token-leak-via-calledprocesserror
description: A secret as an element of a Python subprocess.run(check=True) argv leaks via CalledProcessError's default string (embeds whole argv); the fix + how to fence it without false-positiving the benign bash-remote form
metadata:
  type: feedback
---

A secret passed as a `subprocess.run(cmd, check=True)` **argv element** (e.g. `["curl","-H",f"Authorization: Bearer {token}"]`) leaks the moment the call fails: `CalledProcessError`'s default `str()`/unhandled traceback embeds the **entire argv**, so the token reaches the operator terminal / run-log / team-lead context. This is the 2026-09-10 provision incident's second mechanism, distinct from the interactive-tinker one ([[interactive-tinker-echoes-transcript]], RT-33). Both live in the §4.2 provisioning secret-in-transcript class in docs/SECURITY.

**The fix, graded PASS on #734 (mint-supabase-jwt-keys.sh) + #735 (provision-supabase-stack.sh):**
- Token moved OUT of argv → fed to curl as a `header = "Authorization: Bearer <token>"` config directive over STDIN (`curl -K -`, `input=config`). Impossible-by-construction: never in argv, never in `ps`, never in the exception.
- EVERY call site wrapped `try/except CalledProcessError` → `die(f"... exit {exc.returncode} ({exc.stderr.strip()[:200]})")`. The sanitizer keys on `returncode` + `stderr` ONLY — never `exc.cmd`/argv/`str(exc)`. This is what protects the `-d json.dumps(body)` argv (which BOTH PRs deliberately LEAVE in argv, carrying every stack secret) — the wrapper controls what prints regardless of what `cmd` holds. curl `-fsS` stderr is URL/HTTP-status only, never request headers or `-d` body, so it is safe to surface.

**Three coexisting bearer-header shapes — grade the CONSTRUCT, not the substring:**
1. `["-H", f"Authorization: Bearer {token}"]` in a Python `subprocess.run` list = **the leak** (value in local/box argv + traceback).
2. `sshx "... curl -H \"Authorization: Bearer \$TOKEN\" ..."` = **benign bash-remote**: `\$TOKEN` expands ON THE BOX, LOCAL argv holds the literal `$TOKEN`; no Python, no traceback, `set -e` (not `set -x`) doesn't echo. Cannot surface the value locally.
3. `'header = "Authorization: Bearer ' + token` fed via `-K -` = **the fix**.

**Why this matters for fencing:** a blunt grep for `Authorization: Bearer` false-positives on (2) and (3). RT-33's tinker predicate (`artisan tinker` without `--execute`) does NOT catch this class at all — different construct. A tractable fail-closed predicate keys on the Python-list header form: `"(-H|--header)",\s*f?["'][^"']*Bearer` over `scripts/` — matches (1), skips (2) [no `,` comma-quote] and (3) [no `-H`]. Residual gap the grep can't see: a future `-d`/argv secret whose `try/except` wrapper is also removed — the real invariant is "every `subprocess.run(check=True)` that can carry a secret in argv is wrapped so no CalledProcessError string escapes" (AST-level, not grep). Pair any fence with a golden positive-control fixture + inversion mode, like RT-33.

**Ruling shape I gave:** fence = FOLLOW-UP (both instances fixed → class closed in tree; a rushed blunt fence is theater), NOT a merge blocker. RT id is an F/CTO §4.5 ratify act — document UNLABELED until ratified; adding to the CI-fenced RT set is a fence-boundary escalation. NOT §10-catalogued (§10 stays at 3) — same reasoning RT-33 carries. Doc: extend §4.2 + add RT row WITH the fence, not before (no dangling reference).

**How to apply:** on any provisioning/deploy review, grep `scripts/` for `subprocess.run(` + `check=True` and confirm (a) no secret in argv OR (b) the value can't surface on failure (wrapped, sanitizer avoids argv). Spot-check sibling scripts — the class travels in twins (provision-vps.sh was 0-Python-subprocess: Hetzner token is bash-only LOCAL argv, `set -e` no echo, explicit `set -x`-off guard before the password step). Related: [[feedback_exception_logging_leaks_the_credential_in_the_url]], [[feedback_measure_the_fence_regex_not_its_comment]], [[feedback_a_prose_described_fence_is_wrong_twice]], [[project_rt_id_assignment_is_fcto_ratify_act]].
