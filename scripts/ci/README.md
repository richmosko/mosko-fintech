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
  Decision 4's catalogued numbered list** — the numbered list stays 2-instance per
  the discipline-preservation guard. V1-SHIP-BLOCK axis (Lock 13 mod #3) is
  orthogonal to the §10 catalogued-instance axis.

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
├── check-dedup-hash-identical.sh         # import_hash canonical↔copy drift fence (SELF-204 / ADR-034 D4)
├── check-tz-sweep-identical.py           # TimeZone role-sweep query drift fence (runbook §4.1 ↔ (T3); R3 Part A)
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
