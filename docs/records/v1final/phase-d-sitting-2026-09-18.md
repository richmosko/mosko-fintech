# Phase D sitting sheet — ADR-072 Amendment 7 live exercise, 2026-09-18

Source: `docs/deployment-runbook.md` §6.4/§6.5/§6.7, `scripts/provision-vps.sh`, `scripts/migrator-orchestrate.sh`, `.github/workflows/migrator-trigger.yml`, and `BACKLOG.md` items 51/52, all as merged on `origin/main` at `114690ec` (PRs #800–#804, all merged). Same discipline as the re-bootstrap command sheet: exact text with real values substituted, expected output, STOP conditions named, passwords/tokens referenced **by name only, never printed here**.

**Real values substituted throughout** (from the repo-root `.env`, non-secret):
- Box IP: `188.245.166.206`
- Supabase-stack Coolify resource UUID (`MIGRATOR_SERVICE_UUID`): `nz7mbexygw9lesjlazcxeltn`
- Migrator Scheduled Task UUID (`MIGRATOR_TASK_UUID`): `y6wn3s9yjqqg8tuchd0i3k6w`
- V1 web-app Coolify resource UUID (`APP_UUID`): `nzfkslmj8cm6ba86bdizuvd8`
- `fail-probe`'s Scheduled Task UUID (permanent positive control, §6.5/§6.7): `hffv8um6zruwslmndqc5su2l`
- `ci_only` keypair public half: `/Users/mosko/.ssh/id_ed25519_ci_migrate.pub` (private half lives only as the `CI_MIGRATE_SSH_PRIVATE_KEY` GitHub Actions secret — never on disk on your Mac for this sheet's steps)
- `DEPLOY_ON_SUCCESS`: not set in `.env` → defaults to `0` (deploy suppressed) — this is the expected state for every step below except a later, separate §7-step-7 exercise, not part of this sheet.
- **Passwords/tokens: never printed here, by name only.** `COOLIFY_API_TOKEN` (in `/etc/pfin/migrator-coolify-token.env` on the box) is read by name, on the box, and never leaves it as text in this sheet.

**"Where it runs" tags:**
- **Mac** — your own terminal, repo root as `cwd`.
- **Mac → box (SSH, non-interactive)** — a one-shot `ssh` command; output returns to your terminal.
- **Box-as-root (interactive)** — an `ssh root@188.245.166.206` session you stay inside for a few commands (item 2's token read-back needs this — `ci-migrate`'s own SSH session is a forced command and cannot run an ad hoc `curl`).
- **GitHub UI / `gh` CLI** — items 4–6, dispatching or watching Actions runs.

---

## STOP discipline

Every STOP below means: **do not run the next step.** Fix the named cause and re-measure, or route to Sec/DevOps as named, before continuing. Nothing in this sheet auto-repairs anything.

---

## 1. `git pull` + `scripts/provision-vps.sh --apply` — bring the box up to #800–#804

**Where:** Mac.

```sh
git checkout main && git pull
BOX_IP=188.245.166.206 scripts/provision-vps.sh --apply
```

**Expect — the lines to paste back** (this run is idempotent; most steps will read "already matches" if a prior `--apply` already ran post-merge — paste back whichever of these actually print):

- Orchestrator script install:
  ```
  ok scripts/migrator-orchestrate.sh installed on box (root:root 0755, not writable by ci-migrate)
  ```
  (exact wording may say "already matches" instead of "installed" — either is a pass; the STOP condition below is what to watch for, not the exact verb.)
- `MIGRATOR_TASK_COMMAND` written to the trigger conf:
  ```
  ok /etc/pfin/migrator-trigger.conf written (root:ci-migrate, 0640 -- ci-migrate reads via group, cannot write)
  ```
  or `ok /etc/pfin/migrator-trigger.conf already matches`.
- Tmpfiles lock directory (new in #804):
  ```
  ok /etc/tmpfiles.d/pfin-migrator-orchestrate.conf written
  ok systemd-tmpfiles --create applied -- /run/lock/pfin exists, ci-migrate:ci-migrate 0750
  ```
  (the second `ok` line prints on **every** `--apply` run, by design — it is not conditional on the conf file having changed.)
- Lock file itself:
  ```
  ok /run/lock/pfin/pfin-migrator-orchestrate.lock already ci-migrate:ci-migrate 0600
  ```
  or `... created --` on a first-ever run.
- sshd `Match` block (unchanged since #791, re-verify it's still there):
  ```
  ok sshd drop-in already matches
  ```
  Its content, for reference (do not need to paste this — just confirm the `ok` line, not a `die`):
  ```
  Match User ci-migrate
      AcceptEnv MIGRATOR_EXPECT_SHA
  Match all
  ```

**STOP condition:** any `die` (nonzero exit), or an `sshd -t` rejection reported by the script. Do not proceed to any step below with a half-applied box — report the exact `die` line back before doing anything else.

---

## 1b. Propagate the (B) short command into Coolify's live Scheduled Task — run this ONLY after PR #812 has merged

**⚠ Supersedes this step's own earlier text (kept in git history, not here).** The original 357-byte tagged literal (Amendment 7) could not be saved into Coolify's UI at all — `scheduled_tasks.command` is `character varying(255)` in Coolify v4.3.18, measured, never widened; the literal was 357 bytes, 102 over. **Resolution: ADR-072 Amendment 8 (F/CTO-ratified option (B), PR #812)** bakes the full tagged logic into the migrator image (`infra/supabase/migrator/pfin-task.sh`) and replaces the Coolify command with a 26-byte invocation, `sh /workspace/pfin-task.sh`, which fits the column with no trimming and no lost evidence.

**Do not run this step until PR #812 has actually merged to `main`** — it changes the Dockerfile, the migrator-scheduled-task.md Command row, and provision-vps.sh's literal all at once; running these steps against a pre-merge box state will not match what `git pull` gives you.

**Where:** Mac → box, per step (`docs/deployment-runbook.md` §6.5 step 2a is the durable version of this — this is the sitting-sheet's own copy of it, with real values substituted).

1. **Pull + `provision-vps.sh --apply`** (repeats sitting-sheet step 1, now with #812's changes present):
   ```sh
   git checkout main && git pull
   BOX_IP=188.245.166.206 scripts/provision-vps.sh --apply
   ```
   **Expect:** `/etc/pfin/migrator-trigger.conf` written (or "already matches") with `MIGRATOR_TASK_COMMAND=sh /workspace/pfin-task.sh`.

2. **Redeploy the Supabase-stack resource** (Coolify UI → the resource `nz7mbexygw9lesjlazcxeltn` → **Deploy**). Wait for the build to finish — this is what actually lands `pfin-task.sh` inside the running container; nothing in step 1 rebuilds the image.

3. **Confirm the image carries the change — BOTH checks, before touching the Coolify UI's command field:**
   ```sh
   ssh root@188.245.166.206 \
     "docker compose --project-name nz7mbexygw9lesjlazcxeltn exec -T migrator cat /workspace/.build-sha"
   git rev-parse origin/main
   ssh root@188.245.166.206 \
     "docker compose --project-name nz7mbexygw9lesjlazcxeltn exec -T migrator test -x /workspace/pfin-task.sh && echo PRESENT"
   ```
   **Expect:** the first two values match character for character; the third line prints `PRESENT`.

   **STOP condition:** either check fails → STOP. Do not proceed to step 4 — switching the Coolify command now would point the task at a script that either doesn't exist yet or is the wrong version.

4. **Only now: Coolify UI → the Supabase-stack resource → Scheduled Tasks tab → the `migrator-db-push` task → Command field.** Set it to exactly:
   ```
   sh /workspace/pfin-task.sh
   ```
   **Save.**

5. **B2 read-back — require MATCH** (as root on the box):
   ```sh
   ssh root@188.245.166.206
   ```
   Then, inside that session:
   ```sh
   grep -m1 '^MIGRATOR_TASK_COMMAND=' /etc/pfin/migrator-trigger.conf | cut -d= -f2- > /tmp/expected_cmd.txt
   COOLIFY_API_TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /etc/pfin/migrator-coolify-token.env | cut -d= -f2-)"
   umask 077
   CURL_CFG="$(mktemp)"
   printf 'header = "Authorization: Bearer %s"\n' "$COOLIFY_API_TOKEN" > "$CURL_CFG"
   chmod 0600 "$CURL_CFG"
   curl -fsS --config "$CURL_CFG" \
     "http://localhost:8000/api/v1/applications/nz7mbexygw9lesjlazcxeltn/scheduled-tasks" \
     | python3 -c "
   import json, sys
   d = json.load(sys.stdin)
   rows = d if isinstance(d, list) else d.get('data', d)
   m = [r for r in (rows or []) if r.get('uuid') == 'y6wn3s9yjqqg8tuchd0i3k6w']
   print(m[0].get('command','') if m else '<TASK NOT FOUND>')
   " > /tmp/live_cmd.txt
   diff /tmp/expected_cmd.txt /tmp/live_cmd.txt && echo "B2: MATCH" || echo "B2: MISMATCH -- see the diff above"
   rm -f "$CURL_CFG" /tmp/expected_cmd.txt /tmp/live_cmd.txt
   unset COOLIFY_API_TOKEN
   exit
   ```
   **Expect:** `B2: MATCH`, no diff output above it.

   **STOP condition:** `B2: MISMATCH` → STOP. Re-check the Command field was actually saved (reload the page, re-read the field) before assuming step 4 was wrong. Do not proceed to step 3 (the manual fire) below until this reads MATCH.

**Runbook reference:** this exact sequence — image first, command second, B2 as the only pass criterion — is now written down permanently at `docs/deployment-runbook.md` §6.5 step 2a (PR #812).

---

## 2. Item 52 AC(3) — `GET /api/v1/teams` as the trigger token

**Why:** confirms what the trigger token itself can see. **Read the limitation before running this:** Coolify's `/teams` route filters to the team baked into the token at mint time (`getTeamIdFromToken()` → `auth()->user()->teams->where('id', $teamId)`) — so this call is **expected to return exactly 1 row, always**, regardless of whether a second Coolify team exists on the box. It does not (and cannot) prove there is no second team; it only proves what this specific token can see, which is the AC's own scope.

**Where:** Box-as-root (interactive) — `ci-migrate`'s own session is a forced command and cannot run an ad hoc `curl`; this must run as root, reading the token file root already owns.

```sh
ssh root@188.245.166.206
```
Then, inside that session:
```sh
COOLIFY_API_TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /etc/pfin/migrator-coolify-token.env | cut -d= -f2-)"
umask 077
CURL_CFG="$(mktemp)"
printf 'header = "Authorization: Bearer %s"\n' "$COOLIFY_API_TOKEN" > "$CURL_CFG"
chmod 0600 "$CURL_CFG"
curl -fsS --config "$CURL_CFG" http://localhost:8000/api/v1/teams \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
rows = d if isinstance(d, list) else d.get('data', d)
print('team_count=', len(rows))
print('team_ids=', [r.get('id') for r in rows])
"
rm -f "$CURL_CFG"
unset COOLIFY_API_TOKEN
exit
```

**Credential-handling constraints this satisfies (item 52 AC(3), all three, mandatory):** (i) token read by name via `grep`/`cut`, never `source`d, never dumped; (ii) handed to `curl` via `--config` (mode `0600`, removed immediately after use), never an argv-visible `-H` (which would put the token in `ps` output for any local user for the life of the call, and in shell history); (iii) only `team_count`/`team_ids` are printed — never the token, never the raw response body.

**Expect:** `team_count= 1`, `team_ids= [<some integer>]`. This is a **PASS**, not a partial result — see the limitation note above.

**STOP condition:** `team_count` != `1`, or the `curl` fails (non-2xx / connection error) → STOP. A count other than 1 means either the token is scoped wider than Amendment 2's design says, or something is misconfigured; route to Sec before treating it as "good news" (more teams visible is not obviously safer or less safe without grading it).

---

## 3. Verify the read-back literal — manual fire, `DEPLOY_ON_SUCCESS=0`, first real execution of the new assertions as `ci-migrate`

**✅ PASSED, 2026-09-18.** Fired with `MIGRATOR_EXPECT_SHA=2603ea61e8b162fd3093ae7f94a083b6c662d2ee`. Full chain: pre-fire task-command integrity check OK → pre-fire execution-uuid snapshot → execute (response keys: `message`) → bound to execution uuid **`w1t08e1sn8rfpr6vzcayvcwn`** by set difference (PR #814) → status polled to `success` → *"outcome verified via the execution's own message: build-sha (2603ea61...) matches the triggering commit, ledger top row (119) matches the newest migration file (119)"* → *"migration apply SUCCEEDED — app deploy SUPPRESSED"* → **exit code: 0**. Recorded at `docs/deployment-runbook.md` §6.5's status line and `docs/records/v1final/standup-log.md`.

**⚠ Step 1b above must read `B2: MATCH` before this step runs.** This step's own pre-fire check does the exact same comparison step 1b's B2 read-back does — if 1b was skipped, PR #812 hasn't merged yet, or 1b came back MISMATCH, this step will correctly exit 10 (or 11/12, depending on exactly what's malformed), not because of anything new, but because 1b's job was never finished.

**Why this is the load-bearing first run:** every assertion Amendment 7 built (tag parsing, sha compare, ledger compare, the pre-fire task-command integrity check) has been strike-tested in a container as `ci-migrate`, but **never yet executed for real, as `ci-migrate`, against the real box and the real Coolify API.** This step is that first execution. `DEPLOY_ON_SUCCESS=0` (the box's current default, confirmed in step 1) means this fires the migrator task for real but withholds the app deploy — the migrator task itself should apply **nothing** (ledger is already at `119`, no new migration file exists yet — item 6 below is what advances it).

**⚠ A redeploy is REQUIRED before this step, not optional — state it as its own step, not a parenthetical.** `git rev-parse origin/main` reads `95b8fc92`. The box's migrator container was last built at `ecfa5aaa` (§6.5 Phase A step 3a's own measured-pass record). Those two shas differ, so the sha assertion (exit 3) **will** fire on a real, correctness-irrelevant mismatch if you skip straight to the fire below. **Step 1 (`provision-vps.sh --apply`) does NOT rebuild the migrator image** — it only rewrites the orchestrator script, the trigger conf, the lock provisioning, and the sshd drop-in on the box; none of that touches the Supabase-stack container image. The image is rebuilt only by a Coolify deploy of that resource.

1. **Redeploy the Supabase-stack resource** (Coolify UI → the resource `nz7mbexygw9lesjlazcxeltn` → **Deploy**). Wait for the build to finish.
2. **Confirm the rebuild landed the sha you expect, before firing anything:**
   ```sh
   ssh root@188.245.166.206 \
     "docker compose --project-name nz7mbexygw9lesjlazcxeltn exec -T migrator cat /workspace/.build-sha"
   git rev-parse origin/main
   ```
   **STOP condition:** the two values printed above do not match, character for character → STOP. Either the build didn't pull the sha you expected (check the Coolify resource's branch/commit config) or `origin/main` moved again since you read it — re-fetch and re-compare before proceeding. Do not run step 3 below on an unconfirmed sha.

**Where:** Mac (you need the `ci_only` **private** key locally for this one manual fire — this is the same key GitHub Actions holds as a secret; do not commit it, do not leave it lying around after this step if it's not normally kept on your Mac).

3. **Fire:**
```sh
ssh -i <ci_only private key path> \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o SetEnv="MIGRATOR_EXPECT_SHA=$(git rev-parse origin/main)" \
    ci-migrate@188.245.166.206
echo "exit code: $?"
```

**Expect:** the SSH command's own stderr (this is `migrator-orchestrate.sh`'s `log()` output, all on stderr) should show, in order: the lock acquired, the pre-fire task-command integrity check passing (`"task command integrity check OK: live Scheduled Task command matches MIGRATOR_TASK_COMMAND in /etc/pfin/migrator-trigger.conf"`), the execute + poll, then on `success`: `"outcome verified via the execution's own message: build-sha (<sha>) matches the triggering commit, ledger top row (119) matches the newest migration file (119)"`, then `"migration apply SUCCEEDED — app deploy SUPPRESSED (DEPLOY_ON_SUCCESS!=1)"`. **`echo "exit code: $?"` must print `0`.**

**This IS all three tagged lines (`PFIN-BUILD-SHA=`, `PFIN-LEDGER-TOP=`, `PFIN-NEWEST-FILE=`) parsed for real for the first time as `ci-migrate`** — the log line above only prints once all three were extracted, validated, and compared successfully.

**STOP condition:** any exit code other than `0`. Read which exit code (3/4/5/6/7/8/9/10 each mean something different — see `migrator-orchestrate.sh`'s own header, or `BACKLOG.md` item 51) before doing anything else; do not re-fire blind.

---

## 4. Sha-assertion RED through Actions — `gh workflow run` against a deliberately wrong sha

**✅ PASSED (RED as expected), 2026-09-18.** Run `35392806793`, execution uuid `7pdx8y6seiynedkvjs0ufnyg`. Exit **3**, both shas named in the log, exactly per the exit-3 message's own text. Confirms the Actions `workflow_dispatch` path (not just the manual SSH fire in step 3) surfaces a real sha mismatch as a red job through the whole SSH → forced-command → orchestrator chain.

**Why:** exercises exit 3 (sha mismatch) through the **real GitHub Actions path**, not the manual SSH fire above — confirming the workflow's own `-o SetEnv="MIGRATOR_EXPECT_SHA=$GITHUB_SHA"` line reaches the box and that a genuine mismatch surfaces as a red job with a message naming both shas, not a silent pass.

⚠ **This strike is a WRITE against production, not a read-only probe (Sec, `sec-record-step4-sha-mismatch.md`).** Full write-hazard note and the canonical recipe now live at `docs/deployment-runbook.md` §6.7's new "Sha-mismatch strike" sub-recipe (this sheet is job-scratch and does not survive; the runbook does) — short form: under Amendment 7's post-hoc design the Scheduled Task runs a real `supabase db push` before the mismatch is caught, harmless this run only because the ledger was already current (`119 == 119`), not because of the strike itself.

**Where:** Mac, then GitHub UI (for the `production-migrator` environment's required-reviewer approval).

⚠ **Which old sha to dispatch, corrected 2026-09-18 — not just "anything old":** the workflow's `workflow_dispatch` trigger and its `production-migrator` environment gate exist only from PR #790 onward (merged `eea2fdab`) — a ref that predates that merge has no `workflow_dispatch` event to receive at all, so `gh workflow run` against it would fail before ever reaching the box. The dispatched ref must therefore be a commit **after** #790's merge and **before** the migrator image's actual build sha (`2603ea61`, the current `origin/main`) — **`95b8fc92` (merge of #805) is the recommended ref**: it is on `main`, after #790, and before `2603ea61`, so it dispatches cleanly and its own baked sha genuinely differs from what the container was last built from.

```sh
gh workflow run migrator-trigger.yml --ref 95b8fc92
```

(If `95b8fc92` no longer predates the migrator image's actual build sha by the time you run this — check `git rev-parse origin/main` and the box's `/workspace/.build-sha` first — pick any other commit satisfying the same two bounds: after #790's merge `eea2fdab`, before the image's current build sha.)

**Then:** the run will pause for the `production-migrator` GitHub Environment's required-reviewer approval (Actions tab → the waiting run → **Review deployments** → approve). Approve it.

⚠ **Under Amendment 7 the sha assertion is POST-HOC, not a precondition — this step DOES execute the real migrator task before exiting 3, it does not refuse to fire.** Nothing in the pre-fire chain (the task-command integrity check) reads or compares `MIGRATOR_EXPECT_SHA` — that check only confirms Coolify's stored command matches `$CONF_FILE`'s literal, unrelated to which commit the image was built from. So this dispatch **will** execute `pfin-task.sh` for real (idempotent — the ledger is already at `119`, so the `db push` this triggers no-ops cleanly) and the deploy gate evaluates to suppressed (`DEPLOY_ON_SUCCESS=0`) **before** the sha comparison fires and exits 3. Expect to see the same `"outcome verified..."`-shaped success text for the ledger/newest-file half in the log, immediately followed by the sha-mismatch exit — not a refusal before the task ever runs.

**Expect:** the job goes **RED**. The "SSH to ci-migrate" step's log (via the SSH exit code reaching the Actions step) should show `migrator-orchestrate.sh`'s exit-3 message: *"the migrator container's baked sha, as reported by this execution's own output (`<actual-sha>`), does NOT match the sha this run was triggered for (`<the-old-sha-you-dispatched-with>`)"* — **both shas named**, per the exit-3 message's own text (`migrator-orchestrate.sh`, the `PFIN_BUILD_SHA_TAG != MIGRATOR_EXPECT_SHA` branch).

**STOP condition:** the job goes GREEN, or fails with any exit code other than `3`, or the message does not name both shas → STOP, this is exactly the "hops (d)/(e) not gradable from source" concern §6.7 exists for — report the exact log line back before treating this control as proven.

**Cleanup:** `git push origin --delete tmp/sha-mismatch-strike` once the run is done.

---

## 5. `fail-probe` RED through Actions — with Amendment 7's own read-back accounted for

**✅ PASSED (RED as expected), 2026-09-18.** Run `35393823600`, execution `bfkoc73s5i71yynplft6ftda`, orchestrator `fail()` branch (exit **1**, *"status=failed — app deploy NOT triggered"*). Pre-fire read-back OK against the swapped literal — `fail-probe`'s live command (`sh -c 'echo probe; exit 3'`) was read correctly via the list route (this step's own earlier route fix, above), confirming the integrity check does not false-positive on a deliberately-swapped-but-consistent conf. **✅ Restoration PROVEN.** `grep -c` = `1` against the restored `MIGRATOR_TASK_UUID`, `diff` against the pre-swap copy empty, `/etc/pfin/migrator-trigger.conf` confirmed `root:ci-migrate 0640`. Token-file mtime unchanged (credential untouched by this recipe, per this step's own scope discipline).

⚠ **What this step does NOT cover (Sec):** the read-back's MISMATCH branch (exit 10, AC (4d)'s tamper/drift detection) — both `MIGRATOR_TASK_UUID` and `MIGRATOR_TASK_COMMAND` were swapped together, so the comparison agreed. That is a genuinely strong incidental result (it proves the comparison reads `$CONF_FILE`'s live value, not a hardcoded expectation) but it is the AGREEMENT path, not the DISAGREEMENT path — exit 10 remains unmeasured on the box.

⚠ **Consequence for BACKLOG item 52's audit manifest (Sec):** `fail-probe` now exists as a permanent production Scheduled Task and must be listed in item 52's audit manifest as an EXPECTED task with its expected command — otherwise the audit's first run RED-flags the positive control itself as drift. Booked into item 52's AC in the batch record PR.

**⚠ Answering the "say which" question directly: swap BOTH `MIGRATOR_TASK_UUID` and `MIGRATOR_TASK_COMMAND`, not the UUID alone.** §6.7's existing recipe (written before Amendment 7) only swaps `MIGRATOR_TASK_UUID`. Under Amendment 7, `migrator-orchestrate.sh` now does a **pre-fire GET-and-compare** of the live task's `command` against `MIGRATOR_TASK_COMMAND` in `/etc/pfin/migrator-trigger.conf` — if you swap only the UUID, the orchestrator will `GET` `fail-probe`'s definition, find its `command` does **not** match the still-unswapped migrator-task literal, and exit **10** (task-command integrity failure) **before `fail-probe`'s own deliberately-failing command ever runs.** That is a real RED, but it is the **wrong** RED for this recipe's purpose (hops (d)/(e) — the forced command's exit code reaching Actions — need `fail-probe`'s own task to actually execute and fail with exit **1**, not get refused pre-fire with exit 10).

**Where:** Box-as-root (interactive, for the conf edit — same scope discipline as §6.7: the credential file is never touched), then GitHub UI / `gh`.

1. **Read `fail-probe`'s live command first**, from the box (as root, via the same `--config`-file curl pattern as step 2 — do not put the token on argv here either):
   ```sh
   ssh root@188.245.166.206
   COOLIFY_API_TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /etc/pfin/migrator-coolify-token.env | cut -d= -f2-)"
   umask 077
   CURL_CFG="$(mktemp)"
   printf 'header = "Authorization: Bearer %s"\n' "$COOLIFY_API_TOKEN" > "$CURL_CFG"
   chmod 0600 "$CURL_CFG"
   curl -fsS --config "$CURL_CFG" \
     "http://localhost:8000/api/v1/applications/nz7mbexygw9lesjlazcxeltn/scheduled-tasks" \
     | python3 -c "
   import json, sys
   d = json.load(sys.stdin)
   rows = d if isinstance(d, list) else d.get('data', d)
   m = [r for r in (rows or []) if r.get('uuid') == 'hffv8um6zruwslmndqc5su2l']
   print(m[0].get('command','') if m else '<TASK NOT FOUND>')
   "
   # ⚠ CORRECTED 2026-09-18 (Sec/coordinator caught) -- this step
   # previously called GET .../scheduled-tasks/hffv8um6zruwslmndqc5su2l,
   # a single-task route that does not exist at Coolify v4.3.18 (the
   # same #808 404 class). Coolify has no bare single-task GET; the
   # list route + select-by-uuid shape above (identical to step 1b's B2
   # read-back and step 2's team-count check) is the only route that
   # exists.
   rm -f "$CURL_CFG"
   unset COOLIFY_API_TOKEN
   ```
   **Copy the printed command text exactly** — this is what step 2 below writes into the conf.

2. **Read the current conf, keep an exact copy, then swap both lines:**
   ```sh
   cp /etc/pfin/migrator-trigger.conf /tmp/migrator-trigger.conf.orig
   grep -n '^MIGRATOR_TASK_UUID=\|^MIGRATOR_TASK_COMMAND=' /tmp/migrator-trigger.conf.orig
   sed -i 's/^MIGRATOR_TASK_UUID=.*/MIGRATOR_TASK_UUID=hffv8um6zruwslmndqc5su2l/' /etc/pfin/migrator-trigger.conf
   ```
   For `MIGRATOR_TASK_COMMAND`, edit the file directly (a `sed` one-liner is unsafe here — the value contains `/` and `&`, both `sed`-special) — open `/etc/pfin/migrator-trigger.conf` with an editor on the box and replace the `MIGRATOR_TASK_COMMAND=` line's value with the exact text step 1 printed, byte-for-byte.
   ```sh
   grep -n '^MIGRATOR_TASK_UUID=\|^MIGRATOR_TASK_COMMAND=' /etc/pfin/migrator-trigger.conf
   ```
   Confirm both printed lines now show the swapped values before proceeding.
   ```sh
   exit
   ```

3. **Dispatch on `main`:**
   ```sh
   gh workflow run migrator-trigger.yml --ref main
   ```
   Approve the `production-migrator` environment gate when it pauses (same as step 4).

**Expect:** the job goes **RED**, exit **1** — `fail()`'s generic message (`"migration apply FAILED (Scheduled Task execution status=failed) — app deploy NOT triggered..."`), **not** exit 10. If you see exit 10 instead, the command swap in step 2 was incomplete or byte-inexact — go back and re-copy step 1's output exactly (including quoting).

4. **Restore both — by name, not by eyeballing** (as root on the box):
   ```sh
   cp /etc/pfin/migrator-trigger.conf /etc/pfin/migrator-trigger.conf.pre-restore.bak
   sed -i 's/^MIGRATOR_TASK_UUID=.*/MIGRATOR_TASK_UUID=y6wn3s9yjqqg8tuchd0i3k6w/' /etc/pfin/migrator-trigger.conf
   ```
   Restore the `MIGRATOR_TASK_COMMAND` line the same way as step 2 (edit directly, paste back the real migrator command from `/tmp/migrator-trigger.conf.orig`'s copy of that line), then:
   ```sh
   grep -c '^MIGRATOR_TASK_UUID=y6wn3s9yjqqg8tuchd0i3k6w$' /etc/pfin/migrator-trigger.conf
   diff <(grep '^MIGRATOR_TASK_COMMAND=' /tmp/migrator-trigger.conf.orig) <(grep '^MIGRATOR_TASK_COMMAND=' /etc/pfin/migrator-trigger.conf)
   ```
   **The `grep -c` must print `1`, and the `diff` must print nothing.** That is the restoration proof — not a visual check.

**STOP condition:** the `fail-probe` run does not go RED with exit 1, or either restoration check above fails → STOP before doing anything else; do not re-run step 5 or proceed to step 6 with the conf in an unknown state.

**Credential file untouched, per §6.7's own scope discipline:** confirm `ls -l /etc/pfin/migrator-coolify-token.env`'s mtime is unchanged from before step 1 of this section.

---

## 6. The real fire — PR #806 (migration 120) merges, the push trigger fires

**✅ PASSED, 2026-09-18. PHASE D IS PROVEN, BOTH TRANSPORT AND CONTENT.** PR #806 merged at `9030a62b`. The real **`push`-triggered** run (`35394373476` — not a manual dispatch) paused at the `production-migrator` gate; redeploy confirmed before approval (`.build-sha == 9030a62b`, `120_account_comment_linked_source_correction.sql` last in the container); approved; orchestrator: integrity OK → pre-fire uuid snapshot → execute → bound to execution `qxtjevwmpms2swokbkjqwwam` by set difference → *"outcome verified via the execution's own message: build-sha (9030a62b...) matches the triggering commit, ledger top row (120) matches the newest migration file (120)"* → SUCCEEDED, deploy SUPPRESSED. **First non-degenerate delivery-assertion pass — something was actually applied (`119` → `120`).** F/CTO's own independent `supabase_admin` read confirms from two further angles: `select max(version) from supabase_migrations.schema_migrations` → `120`; `obj_description('pfin.account'::regclass, 'pg_class') like '%was DEFERRED%'` → `t`. Full detail: `docs/deployment-runbook.md` §6.5, `docs/records/v1final/standup-log.md`.

**Where:** GitHub UI (the merge, the environment approval) → Coolify UI (the redeploy) → box (the pre-approval confirm, then post-fire checks).

**⚠ Ruling: the `production-migrator` environment approval IS the rebuild pause — do not approve until the rebuild is confirmed on the box.** The job pauses for approval *before* the SSH step runs; that pause is where the redeploy belongs, not a step squeezed in before or after it. Exact order:

1. **Merge PR #806 (migration 120) to `main`** as normal — Sec/QA review per the usual gate, nothing special about this merge beyond what any migration PR already requires.
2. **The push trigger fires and pauses at the `production-migrator` required-reviewer gate. Do NOT approve yet.** Leave the run sitting in "Waiting" in the Actions tab.
3. **Coolify UI → the Supabase-stack resource (`nz7mbexygw9lesjlazcxeltn`) → Deploy.** Wait for the build to finish.
4. **On the box, confirm the rebuild actually landed the merge commit — both checks, not one:**
   ```sh
   ssh root@188.245.166.206 \
     "docker compose --project-name nz7mbexygw9lesjlazcxeltn exec -T migrator cat /workspace/.build-sha"
   git rev-parse origin/main
   ssh root@188.245.166.206 \
     "docker compose --project-name nz7mbexygw9lesjlazcxeltn exec -T migrator ls /workspace/supabase/migrations" | tail -1
   ```
   **Expect:** the first two values match character for character (the merge commit's sha), and the third line shows `120_...sql`.

   **STOP condition:** either check fails to match → **STOP. Do NOT approve the waiting run.** Diagnose (wrong build source/branch, or the deploy pulled a different commit than the merge) before touching the approval.

5. **Only then: approve the waiting run** (Actions tab → the waiting run → **Review deployments** → approve).

**Expect (once approved):** the job goes **SUCCEEDED**, with the same log shape as step 3 above, except the tagged line now reads `PFIN-LEDGER-TOP=120` and `PFIN-NEWEST-FILE=120` (both matching, numeric-safe compare), and `PFIN-BUILD-SHA=<the merge commit's sha>` matching `$GITHUB_SHA`. Deploy **SUPPRESSED** (`DEPLOY_ON_SUCCESS` is still `0`).

**STOP condition:** anything other than SUCCEEDED + SUPPRESSED + ledger at `120` → STOP, do not proceed to the runbook's post-fire checks below with an unclear outcome.

**⚠ STOP condition, load-bearing, before step 1 even starts: nothing else may merge to `main` between step (1) and step (3).** The redeploy in step 3 builds from whatever `main` currently is at *that moment* — if a second, unrelated PR merges after PR #806 but before the step-3 redeploy, the rebuilt image's sha will not match `$GITHUB_SHA` (which is fixed to the commit that fired *this* workflow run, i.e. PR #806's merge commit), and step 4's confirm will correctly fail even though nothing is actually broken. Hold `main` between (1) and (3), or re-derive which sha you're actually confirming against before running step 4.

**Failure mode if step 3 is skipped (recorded, not treated as a defect if it happens):** the approved run's sha assertion exits **3** — legitimate, not a defect, exactly the same class the redeploy-before-fire ordering in item 3 above exists to prevent. **Recovery is a workflow re-run, not a second merge:** redeploy the Supabase-stack resource now, confirm per step 4, then re-run the same failed workflow run from the Actions UI ("Re-run failed jobs" / "Re-run all jobs") — `$GITHUB_SHA` is unchanged (still PR #806's merge commit), so a re-run after the redeploy is the correct fix, not merging anything again.

**Post-fire checks (runbook's own, unchanged by this sheet):**
```sh
ssh root@188.245.166.206 \
  "docker compose --project-name nz7mbexygw9lesjlazcxeltn exec -T db psql -U supabase_admin -d postgres" <<'SQL'
select max(version) from supabase_migrations.schema_migrations;
SQL
```
**Expect:** `120`. This is the same query the migrator task's own `PFIN-LEDGER-TOP=` line already ran inside the container — this is a second, independent read confirming the two agree.

---

## What remains unmeasured after this sitting (steps 1–6 complete)

Phase D's orchestrator path is now proven end to end, both transport (SSH → forced command → Coolify API → GitHub Actions, both `workflow_dispatch` and real `push`) and content (a non-degenerate apply, ledger `119` → `120`, independently confirmed by F/CTO's own `psql` read). Three things this sitting deliberately did not exercise:

- **The pre-fire read-back's MISMATCH branch (exit 10, AC (4d)'s tamper/drift detection).** Step 5 swapped both `MIGRATOR_TASK_UUID` and `MIGRATOR_TASK_COMMAND` together, so the comparison agreed — only the read-back's AGREEMENT path has run live.
- **Exits 13/14/15 and the ≥2-new-uuid branch** (PR #814's fail-closed binding paths) — the set-difference binding bound cleanly on the first attempt every time it ran; none of these branches has been reached outside DevOps's own strikes.
- **The `DEPLOY_ON_SUCCESS=1` leg** — the actual app-deploy call (`GET /deploy?uuid=$APP_UUID`) — deliberately never fired this sitting; proven separately at `docs/deployment-runbook.md` §7 step 7.

## Residuals this sheet does not close (named, not silently assumed closed)

- **Item 52 gap (a):** the pre-fire read-back (step 5's own mechanism, exercised in reverse in step 3) covers only the **migrator** task. A rewrite of any **other** scheduled task on this Coolify install — on this or any other application/service the trigger token's team owns — is unobserved by anything in this sheet. Booked, not blocking Phase D (F/CTO ruling, `BACKLOG.md` item 52).
- **Item 52 gap (b):** the read-back is at fire time only; a rewrite reverted between samples leaves no trace. Same booking.
- **Step 2's own limitation:** `GET /teams` as the trigger token can only ever report the token's own team — it is not, and cannot be turned into, proof that no second Coolify team exists on this box.
- **Premise-inventory box measurements, recorded 2026-09-18** (see `trigger-chain-premises.md` for the full context): **B2 MISMATCH** (Coolify's live command still pre-Amendment-7) — root cause and fix is step 1b, above. **B1** corroborated (most recent execution's `message` has no `PFIN-*` lines, consistent with a pre-Amendment-7 command). **B8** `fs.protected_symlinks=1` — PASS, the FLAG-1 kernel-level assumption holds on this box. **B9** systemd 255; `systemd-tmpfiles-setup.service` reads `static` — this is the NORMAL state for this unit (pulled in by `sysinit.target`, not meant to be independently enabled/disabled), not a defect — but it also means the AT-BOOT half of #804's tmpfiles fix (the directory actually being recreated by a REAL reboot, not just a manual `--create`) remains unobserved on this box; nothing in this sheet exercises a real reboot.
