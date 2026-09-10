# `scripts/ci/` — CI fence scripts (Phase 5 Step 4 W1)

This directory holds the V1 CI fence scripts that gate `mosko-fintech` PRs against
three classes of security-load-bearing regressions:

- **RT-22** — PDF worker Dockerfile zero-DB-isolation audit.
- **RT-22-manifest** — PDF worker `package.json` + lockfile dependency-manifest
  audit (SELF-350 A6, re-scoped at R6 2026-09-04); the sibling fence that closes
  the gap the Dockerfile fence's own header names as its non-catch.
- **RT-26** — `SUPABASE_SERVICE_ROLE_KEY` allowlist grep fence on the V1 web-app
  server-side source surface.
- **TBC** — `TenantBoundConnection` grep fence on the `workers/etl/` Python source
  tree (single-repo post-W0; see [Single-repo TBC posture (post-W0)](#single-repo-tbc-posture-post-w0) below).
- **TBC-node** — `TenantBoundClient` grep fence on the `workers/provider-sync/` Node/TS
  source tree (ADR-019 amendment; the first DB-touching Node worker). The Node analogue
  of TBC — a separate fence because the Python patterns don't match TypeScript. Two legs:
  **(1)** raw-client construction (`postgres()`/`new Pool()`/`new Client()`) or any
  `@supabase/supabase-js` import/`createClient()` outside the `TenantBoundClient` class;
  **(2)** a Sec-condition `SUPABASE_SERVICE_ROLE_KEY` *absence* tripwire (assert-absent,
  zero-hit) — together they enforce direct-Postgres-only and keep provider-sync off the
  RT-26 allowlist (asserts absence; does NOT amend ADR-016 D2).
- **Gitleaksignore inversion** — golden inversion fixture proving the fingerprint-
  scoped `.gitleaksignore` suppression (SELF-358 / P6) is scoped to the ONE pinned
  finding it names, not to the whole file it lives in. See
  [Gitleaksignore inversion — fingerprint-scoping golden fixture](#gitleaksignore-inversion--fingerprint-scoping-golden-fixture)
  below.
- **RT-27** — admission-endpoint private-bind config-lint over committed Coolify
  Compose manifests (`expose:`-only; no `ports:`; no proxy Domain/Host() label;
  no `network_mode: host`). Generic over its target by a sentinel line, not a
  hardcoded path — covers `workers/provider-sync/docker-compose.yaml` (SELF-212,
  original) and `workers/pdf-render/docker-compose.yaml` (SELF-348 A4 item 4c,
  intra-instance coverage expansion — a wiring change, not a new fence).
- **entity-grep** — HTML-entity-obscured `§`/`#` fence over `docs/PRD/index.html`,
  `docs/SECURITY/index.html`, `docs/ARCH/index.html` (F/CTO-authorized
  2026-09-09). Catches `&sect;`/`&#35;` used in place of a literal `§`/`#` —
  both render identically in HTML but the entity form is invisible to a
  byte-literal `grep '§10'` / `grep 'mod #'`, which this project runs as a
  standing discipline. NOT a §10-catalogued instance (a doc-hygiene fence, not
  a security-boundary one); see
  [entity-grep — HTML-entity-obscured §/# fence](#entity-grep--html-entity-obscured--fence)
  below.

The fences are invoked from `.github/workflows/security-scan.yml`. Each fence ships
with a paired golden-test fixture under `tests/fixtures/ci/` and a CI inversion-mode
check — the fence MUST report violation against the fixture; if the fence reports
clean against the fixture, CI fails closed (the fence is unverified/broken).

## §10 catalogued-instance ledger cross-reference

Per ADR-011 Decision 4:

- **RT-22** is the **first catalogued §10 instance** (infrastructure-credential-
  presence layer; Lock 13 mod #2). The RT-22-manifest fence (below) extends
  RT-22's CI coverage; per SELF-350 (A6) R6, this adds, removes, reorders and
  renumbers nothing in Decision 4 — read it live, never from a count pinned
  here.
- **RT-26** is the **second catalogued §10 instance** (code-layer on V1-web-app
  server-side source; SECURITY §4.2 axis vi; HIGH + V1-SHIP-BLOCK).
- **TBC** is the **Privileged-context-surfaces bullet at Decision 4** (code-layer
  parallel to RT-26 on `workers/etl/` Python source; Lock 13 mod #3 V1-SHIP-BLOCK). **NOT in
  Decision 4's catalogued numbered list** — TBC is a Privileged-context-surfaces-bullet
  mechanism, not a catalogued instance, per the discipline-preservation guard; read
  the list's membership live from ADR-011 Decision 4, never from a count pinned
  here. V1-SHIP-BLOCK axis (Lock 13 mod #3) is orthogonal to the §10
  catalogued-instance axis.
- **RT-27** is the **third catalogued §10 instance** (network-exposure/config
  layer; SELF-212 C6-1 limb (b)). The `workers/pdf-render/docker-compose.yaml`
  coverage added at SELF-348 A4 item 4c is an **intra-instance expansion of this
  same instance on the CI-fenced side only** — see SECURITY §4.5's RT-30 entry,
  cited **by pointer, never by quotation** (the pre-sitting draft's quoted form
  was a false composite and must not be restored). NO new §10 instance, NO
  ordinal, NO count change in Decision 4.

This directory is the **enforcement venue** for these mechanisms — it is NOT a §10
attribution surface. Decision 4's canonical catalogued numbered list is unchanged
by anything in this directory.

## File map

```
scripts/ci/
├── fence-rt22-pdf-worker-dockerfile.sh   # RT-22 audit script
├── fence-rt22-pdf-worker-manifest.sh     # RT-22-manifest audit script (SELF-350 A6)
├── fence-rt26-service-role-allowlist.sh  # RT-26 grep fence (γ-hybrid)
├── fence-tbc-pfin-back-etl.sh            # TBC grep fence (single-repo; scans workers/etl/src/)
├── fence-admission-private-bind.sh       # RT-27 private-bind config-lint (generic over target via sentinel)
├── check-dedup-hash-identical.sh         # import_hash canonical↔copy drift fence (SELF-204 / ADR-034 D4)
├── check-tz-sweep-identical.py           # TimeZone role-sweep query drift fence (runbook §4.1 ↔ (T3); R3 Part A)
├── check-report-css-identical.sh         # report.css build-vs-committed-artifact drift fence (SELF-358 / P6)
├── fence-gitleaksignore-inversion.sh     # .gitleaksignore fingerprint-scoping golden inversion fixture (SELF-358 / P6)
├── fence-entity-grep.sh                  # entity-grep fence (&sect;/&#35; over the three HTML doc artifacts)
├── rt26-allowlist.txt                    # RT-26 allowlist registry (3 ADR-016 D1 file paths)
└── README.md                             # (this file)
```

## RT-22 — PDF worker Dockerfile audit

**Lock:** ADR-011 Decision 4 + Decision 17 / Lock 13 mod #2 + SECURITY §4.5 RT-22.

Catches BOTH (i) `SUPABASE_*` env vars (ENV/ARG) and (ii) Postgres client install
(psycopg2 / psycopg2-binary / asyncpg / pg / node-postgres / postgresql-client) in
the PDF worker Dockerfile.

**Explicitly NOT catching at CI:**

- `COPY package.json` / `COPY requirements.txt` (install intent revealed at RUN
  time, not COPY time; this Dockerfile fence does not open the manifest it
  COPYs). **This gap is now closed by the sibling RT-22-manifest fence below**,
  which opens and parses the manifest directly (SELF-350 A6, R6
  2026-09-04) — kept covered by human PR-review only until A4 lands the
  manifest (pass-if-absent; see below).
- **Transitive Postgres client via base image** — neither this fence nor
  RT-22-manifest inspects the base image. If a future base-image change
  inherits `postgresql-client` transitively, nothing at CI catches it. This
  stays the canonical second-line surface for human PR-review per ARCH §6.1
  RT-22 row verbatim *"human PR-review stays second-line for non-CI-detectable
  shape drift"*.

Local invocation:

```bash
bash scripts/ci/fence-rt22-pdf-worker-dockerfile.sh workers/pdf-render/Dockerfile
```

## RT-22-manifest — PDF worker dependency-manifest audit

**Lock:** ADR-011 Decision 17 / Lock 13 mod #2 + SECURITY §4.5 RT-22. Ledger
effect NONE — see the §10 cross-reference above; this is CI-coverage
extension, not a new catalogued instance.

Closes the gap the Dockerfile fence's own header names as a deliberate
non-catch (quoted above, verbatim): *"COPY of package.json / requirements.txt
manifests (install intent revealed at RUN time, not COPY time; manifest
inspection is human-second-line)."* This fence opens
`workers/pdf-render/package.json` and its lockfile (`package-lock.json`)
directly and rejects a Postgres-client or DB-driver-bundling ORM package
anywhere in the resolved tree: `pg`, `postgres`, `node-postgres`,
`@supabase/supabase-js`, `knex`, `sequelize`.

**Pass-if-absent (deliberately DIFFERS from the Dockerfile fence's exit-2-on-
missing-target):** `workers/pdf-render/package.json` does not exist yet — the
PDF worker's dependencies land in a later issue (A4). This fence exits 0 with
a "target absent — pass" line until that file exists, then bites on its first
commit. An absent lockfile with a present manifest is handled the same way
(pass on the lockfile half only) — a lockfile is only generated once npm has
run against a real manifest. This shape is a ruled substitute for a sequencing
dependency between issues: a convention stated in an AC ("land the fence after
the manifest") has no mechanism and rots silently, so the ordering constraint
is designed out instead of documented.

Fails closed on its own dependency: this fence parses JSON with `node`; if
`node` is unavailable, or either JSON file fails to parse, the fence exits 1
rather than silently passing an unverifiable target.

**Explicitly NOT catching at CI** (unchanged second-line surface — see the
Dockerfile fence section above): a Postgres client pulled in transitively
through the base image.

Local invocation:

```bash
bash scripts/ci/fence-rt22-pdf-worker-manifest.sh workers/pdf-render/package.json
```

## RT-26 — `SUPABASE_SERVICE_ROLE_KEY` allowlist (γ-hybrid)

**Lock:** ADR-011 Decision 4 + ADR-015 D1 + ADR-016 D1 + D2 + SECURITY §4.2 axis vi
+ ARCH §4.1.

Per F/CTO γ-hybrid ratify (2026-06-08), audit-scope and allowlist registry are
semantically separate:

- **Audit scope** (what the fence SCANS) = `src/**` + repo-root config files.
  The 5 SvelteKit globs from ADR-015 D1 frame the audit-scope structure but are
  NOT themselves the allowlist.
- **Allowlist registry** (what's PERMITTED within audit scope) = 3 ADR-016 D1
  file paths enumerated at `rt26-allowlist.txt`.

The allowlist is **exact-file-path-shaped, NOT glob-shaped**. Adding a 4th entry
requires Sec-consult + ADR-016 amendment per ADR-016 D2 (webhook-allowlist
annotation convention durably ratified). Glob-shape would silently admit new
files; exact-path enforces ADR amendment by-construction.

**Open at Phase 5 implementation** (factory-file question; captured in
`rt26-allowlist.txt` header): if Phase 5 detail design lands a Supabase admin
client factory at `src/lib/server/supabase-admin.ts` referencing
`SUPABASE_SERVICE_ROLE_KEY` directly, that introduces a 4th allowlist surface
requiring ADR-016 amendment.

Local invocation:

```bash
bash scripts/ci/fence-rt26-service-role-allowlist.sh src/ scripts/ci/rt26-allowlist.txt
```

## TBC — `TenantBoundConnection` grep fence

**Lock:** ADR-011 Decision 17 / Lock 13 mod #3 (V1-SHIP-BLOCK) + Decision 4
Privileged-context-surfaces bullet.

Catches raw `psycopg2.connect()` / `psycopg.connect()` (psycopg3) /
`asyncpg.connect()` invocations outside the file declaring the
`TenantBoundConnection` class. Class-allowlisting is via class-declaration
discovery, NOT hardcoded path (per Sec rubric (a)3 #4).

### Single-repo TBC posture (post-W0)

Per ADR-019 (Phase 5 Step 4 W0), `pfin_back_etl` source was absorbed into this
monorepo at `workers/etl/`. The cross-repo paired-PR pattern **retires**:

- Production-mode + inversion-mode both run in **one job** (`fence-tbc`) in
  `.github/workflows/security-scan.yml`, mirroring the `fence-rt22` dual-mode
  shape. Production-mode scans `workers/etl/src/` (the Python package);
  inversion-mode scans `tests/fixtures/ci/` (the golden violation fixture).
- Production-mode scope `workers/etl/src/` is the **faithful 1:1 migration** of
  the pre-W0 `pfin_back_etl` CI posture, which scanned `src/` and excluded
  `tests/` — where the violation fixture lives and would otherwise self-trip
  production-mode. The fixture is exercised under inversion-mode instead. Catch
  criterion is unchanged: raw `psycopg2`/`psycopg`/`asyncpg` `.connect()` outside
  the `TenantBoundConnection` class.
- The **vendored-copy convention retires** — there is no second repo to vendor the
  fence script or fixture into. `scripts/ci/fence-tbc-pfin-back-etl.sh` and
  `tests/fixtures/ci/tbc-violation.py` are the single source of truth; the
  "VENDORED COPY" source-of-truth banner no longer applies.
- Fixture isolation is now **stronger by-construction**: each production container's
  build context is scoped by Coolify **Base Directory** (`workers/etl/` for the ETL
  container), so the repo-root `tests/fixtures/` tree is outside every production
  build context automatically — a stronger guarantee than the paired-PR
  `.dockerignore` + `packages`-exclusion convention it replaces.

Local invocation (production-mode against the ETL package):

```bash
bash scripts/ci/fence-tbc-pfin-back-etl.sh workers/etl/src/
```

Local invocation (inversion-mode against the golden fixture):

```bash
bash scripts/ci/fence-tbc-pfin-back-etl.sh tests/fixtures/ci/
# Expect non-zero exit.
```

## RT-27 — admission-endpoint private-bind config-lint

**Lock:** SELF-212 Option-C C6-1 limb (b) + SECURITY §4.5 RT-27 entry + ADR-011
Decision 4 (third catalogued §10 instance).

Over a COMMITTED Coolify Compose manifest, the fence enforces that the target's
admission/render endpoint stays INTERNAL-ONLY: `expose:` is allowed (sibling-
container reach on the project network); a published `ports:` mapping, a
reverse-proxy Domain / Traefik `Host()` label / Coolify `SERVICE_FQDN_*` /
`SERVICE_URL_*` magic, or `network_mode: host` are each a committed exposure
vector and fail closed (exit 1).

**Generic over its target, by construction:** the fence takes the compose path
as an argument and does not hardcode which service it audits. It finds its
target by an **in-file sentinel** (`# fence-admission-private-bind: target`)
and **exits 2** if that sentinel is absent — refusing to emit a clean pass over
an unmarked or renamed file. Adding coverage for a new container is therefore a
**wiring change** (ship the manifest with the sentinel; add a job step), never a
new fence.

**Instances wired (both in the `fence-admission-bind` job,
`.github/workflows/security-scan.yml`):**

- `workers/provider-sync/docker-compose.yaml` — the original SELF-212 target.
- `workers/pdf-render/docker-compose.yaml` — added at SELF-348 A4 item 4c. The
  R2 (C) app→worker direction gives this container a render endpoint reachable
  only from the app container; before this manifest existed, the fence had no
  compose target for `workers/pdf-render/` to audit, so that endpoint would
  have come up with no private-bind fence over it at all. **Ledger effect
  NONE** — see the §10 cross-reference above; this is intra-instance coverage
  expansion of the SAME catalogued RT-27 instance, not a new one.

Each instance ships a paired golden violation fixture and a CI inversion-mode
step; per Sec F-2 (SELF-350), the inversion step for a given fixture asserts
the SPECIFIC violation token the fence emits for that vector, not just a
non-zero exit code — a structural error (e.g. a missing sentinel) also exits
non-zero and would otherwise let a broken fixture read as a caught violation.

Local invocation:

```bash
bash scripts/ci/fence-admission-private-bind.sh workers/provider-sync/docker-compose.yaml
bash scripts/ci/fence-admission-private-bind.sh workers/pdf-render/docker-compose.yaml
```

## Gitleaksignore inversion — fingerprint-scoping golden fixture

**Lock:** Sec's grading criterion (pre-brief, 2026-09-07, P6 mandatory read), verbatim:
*"plant a new fake secret in a file that already has a suppressed fingerprint and
confirm the scan still REDs ... as a golden fixture rather than a claim — a green
run cannot distinguish caught-nothing from scanned-nothing."*

`.gitleaksignore` (repo root) currently carries one entry, pinned to the single
INTRODUCING COMMIT of the `generic-api-key` false-positive on
`api/vite.report-css.config.mjs`'s `outDir` line (SELF-358 / P6). A gitleaks
fingerprint (`commit:file:rule:line`) is supposed to suppress ONLY that one
already-reviewed finding — not blanket-suppress every future secret-shaped string
that happens to land in the same file. A green `scanner-gitleaks` run cannot tell
those two apart from the outside; this fence turns the ambiguity into a
deterministic three-leg probe, entirely inside a throwaway clone (never the
working tree):

1. **Positive control** — run gitleaks over the exact commit range and command
   shape `scanner-gitleaks`'s `gitleaks-action@v2` uses internally
   (`gitleaks detect --redact --exit-code=2 --log-opts="--no-merges --first-parent
   <base>^..<head>"`) against the real repo at HEAD. Expect exit 0.
2. **Inversion** — in the same clone, append a synthetic AWS-access-key-id-shaped
   fake secret (clearly labelled FAKE; never a real credential) to the END of the
   SAME file the fingerprint entry covers, commit it in the clone, and re-run the
   identical command. Expect exit 2, with the finding naming that file — proof the
   suppression is fingerprint-scoped, not file-scoped.
3. **Shape check** — every non-comment line of the real `.gitleaksignore` must be
   a well-formed four-part `commit:file:rule:line` fingerprint (no bare path, no
   bare rule id), and no fingerprint's file component may name `.env*`,
   `.github/workflows/**`, `secrets-manifest.yml`, or `docker-compose*`.

Either assertion failing = the fence REDs with a message naming which leg failed.

**Fingerprints fail loud when the file moves, by design:** a fingerprint is
`commit:file:rule:line`. If `api/vite.report-css.config.mjs` is ever renamed or
the suppressed line moves, the pinned fingerprint stops matching gitleaks'
recomputed finding for that commit, and `scanner-gitleaks` goes RED again on the
original (already-reviewed) finding — never silently green. This fence does not
special-case that; a stale suppression re-surfacing for human review is the
intended behavior of fingerprint-scoping, not a defect.

This job is wired beside `scanner-gitleaks` in `.github/workflows/security-scan.yml`
as `fence-gitleaksignore-inversion` and is NOT (yet) added to
`.github/required-contexts.tsv` — that is a branch-protection change outside this
fixture's scope.

Local invocation (installs no binary itself — point `--gitleaks-bin` at a pinned
gitleaks 8.24.3, or put it on `PATH`):

```bash
bash scripts/ci/fence-gitleaksignore-inversion.sh
# or, to pin the base explicitly (mirrors the PR job):
bash scripts/ci/fence-gitleaksignore-inversion.sh --base <base-sha>
```

## entity-grep — HTML-entity-obscured §/# fence

**Lock:** F/CTO authorization (2026-09-09; fence-boundary additions escalate to
F/CTO per agent-def Deciding — "one-way door, slow down" does not apply here,
this is a new fence, not a weakening of an existing one). Measured by
Architect, spot-verified by team-lead, re-measured by DevOps before landing.

**Problem:** `docs/PRD/index.html`, `docs/SECURITY/index.html`, and
`docs/ARCH/index.html` are HTML. A literal `§` or `#` can legally be written as
the HTML entity `&sect;` or `&#35;` and renders identically in a browser — but
this project runs standing byte-literal greps over the doc *source*
(`grep '§10'` for the §10-catalogued-instance ledger discipline; `grep 'mod #'`
for Lock-amendment sweeps). An entity-obscured occurrence is invisible to
both. Measured pre-fix (raw vs. entity-normalized grep, over `main` at
`0c681f0d`):

| file | `&sect;` | `&#35;` | `§10` raw → normalized | `mod #` raw → normalized |
|---|---|---|---|---|
| `docs/PRD/index.html` | 0 | 0 | 3 → 3 | 0 → 0 |
| `docs/SECURITY/index.html` | 2 | 0 | 45 → 46 | 74 → 74 |
| `docs/ARCH/index.html` | 2 | 6 | 43 → 44 | 53 → 59 |

(These counts are over the FULL raw `§10`/`mod #` occurrence set in each file
— not merely a ledger-row count — so they run higher than a hand count of
ledger rows would; they are not comparable to §10's catalogued-instance count,
which is read live from `DECISIONS.md` per standing discipline, never pinned
here.) All 10 `&sect;`/`&#35;` occurrences sat in prose/body text — none in an
`href=`/`id=`/`class=` attribute; confirmed by a full sweep before the
normalization edit (an attribute hit would have been a link-integrity
question, not a text substitution, and would have stopped this work for a
report rather than a fix).

**One-time normalization:** every `&sect;` → literal `§`, every `&#35;` →
literal `#`, across the three files above (`docs/PRD/index.html` had zero
occurrences of either — untouched). Rendered output is unchanged (the entity
and literal forms render identically in HTML); no anchor (`id`/`href`)
resolves differently, since none of the occurrences were ever in an anchor
attribute.

**Catch criterion:** the literal strings `&sect;` and `&#35;` MUST NOT appear
anywhere in the target file(s) — zero-hit, fail-closed, per file. Fails closed
on its own dependency (missing/unreadable target file is exit 2, same severity
class as a caught violation — never reported clean) and uses only
`grep`/`bash` builtins, so it carries no external-parser dependency to fail
open on.

**Explicitly OUT of scope — `&nbsp;`:** deliberately NOT fenced or stripped.
It is load-bearing typography (keeps figures like *"8 ARM vCores / 16 GB"*
from breaking across a line-wrap) and has no §-anchor/lock-mod meaning; the
whole point of this narrow fence is that `§`/`#` have zero typographic
purpose, so widening the pattern set to `&nbsp;` would defeat that framing.
The golden fixture (below) plants `&nbsp;` as a negative control and the CI
job asserts it is never named in the violation list.

**Golden fixture:** `tests/fixtures/ci/entity-grep-violation.html` plants one
`&sect;` and one `&#35;` occurrence in ordinary prose, plus an `&nbsp;`
negative control. The `fence-entity-grep` job in
`.github/workflows/security-scan.yml` asserts (Sec F-2 discipline applied
here): exit 1 exactly (not merely non-zero — a missing-target error is also
non-zero and would prove nothing); the violation list names BOTH the `&sect;`
and `&#35;` hits by file:line; and the violation list never names the `&nbsp;`
line. A separate probe asserts exit 2 (never a silent pass) when pointed at a
nonexistent target.

**NOT added to `.github/required-contexts.tsv`** — promoting a job into
branch-protection-required status is a separate F/CTO decision (there are
already two other jobs awaiting that call); tracked as a follow-up, not done
here.

Local invocation:

```bash
bash scripts/ci/fence-entity-grep.sh docs/PRD/index.html docs/SECURITY/index.html docs/ARCH/index.html
# inversion:
bash scripts/ci/fence-entity-grep.sh tests/fixtures/ci/entity-grep-violation.html
# Expect non-zero exit, naming both &sect; and &#35; (never &nbsp;).
```

## Convention — fence design discipline

Per DevOps agent definition defining-behavior (1) — fail-closed CI fence
discipline — every fence in this directory:

1. Is **fail-closed**: non-zero exit on any violation; CI uses exit code to block
   PR merge.
2. Ships with a **paired golden-test fixture** at `tests/fixtures/ci/` that the
   fence catches deterministically.
3. Has a **CI inversion-mode check** in the workflow YAML — if the fence reports
   clean against the fixture, CI fails closed (the fence is unverified).
4. Is **locally executable** (bash; no special CI-only mechanisms) so developers
   can smoke-test before pushing.
5. **References** rather than absorbs canonical content per Sec rubric (c)3 +
   `feedback_decision_4_instance_ledger_cross_check`: links to ADR-011 Decision 4
   + ADR-015 + ADR-016 + Lock 13 mods; does NOT re-state their canonical text.

Fence additions or changes require **Sec-consult-mandatory** per agent definition
joint-review-mandatory triggers (RT-22 / RT-26 / TBC are explicitly named in the
non-negotiable list).
