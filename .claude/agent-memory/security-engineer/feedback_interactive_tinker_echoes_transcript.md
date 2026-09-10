---
name: interactive-tinker-echoes-transcript
description: Interactive `docker exec -i ... php artisan tinker` echoes input lines + return values to stdout — a secret-in-transcript leak class; fence = ban tinker without --execute
metadata:
  type: feedback
---

Interactive/piped `php artisan tinker` (`echo "$s" | docker exec -i ... tinker`, no `--execute`) is a REPL: it echoes each **input line** (`> ...`) AND each expression's **return value** (`= ...`) to its own stdout. Any secret in the piped script — or a minted token returned by an expression — lands in that transcript and reaches the operator terminal / run-log / session context. `tinker --execute=<code>` is non-interactive and does not echo; end the code on `null;` as a load-bearing guard against last-expression echo (not belt-and-suspenders).

**Why:** the 2026-09-10/11 provision-vps incident (PR #721). A Coolify API token's plaintext leaked via this exact echo; the leak-check was gated on holding the value (`[[ -n "$TOKEN_VALUE" ]]`), the capture failed, so the watcher was SKIPPED while the plaintext sat in the captured log. Vacuous-watcher + wrong-stream in one.

**How to apply:** in any provisioning/deploy script review, grep `scripts/` for `artisan tinker` lines lacking `--execute` — each is a candidate secret-in-transcript leak. The CI fence predicate (RT-32, in security-scan.yml): `grep -rnE 'artisan tinker' scripts/ --include='*.sh' | grep -v -- '--execute'` must be EMPTY; pair with a golden positive-control fixture (an interactive-tinker line it MUST flag RED). Sibling still open at review time: `scripts/coolify-materialize-supabase-mounts.sh` pipes base64 Supabase mount contents through interactive tinker. A structural (shape-based) leak-check on a token needs a positive-control fixture too — `[0-9]+\|[A-Za-z0-9]{20,}` matches Sanctum `id|Str::random(40)` but rots silently if the token format changes. Related: [[feedback_probe_that_only_asserts_failure_goes_vacuous]], [[feedback_exception_logging_leaks_the_credential_in_the_url]], [[feedback_measure_the_fence_regex_not_its_comment]].
