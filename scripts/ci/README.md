# `scripts/ci/` — CI fence scripts (Phase 5 Step 4 W1)

This directory holds the V1 CI fence scripts that gate `mosko-fintech` PRs against
three classes of security-load-bearing regressions:

- **RT-22** — PDF worker Dockerfile zero-DB-isolation audit.
- **RT-26** — `SUPABASE_SERVICE_ROLE_KEY` allowlist grep fence on the V1 web-app
  server-side source surface.
- **TBC** — `TenantBoundConnection` grep fence on `pfin_back_etl` Python source
  tree (cross-repo; see [Cross-repo TBC posture](#cross-repo-tbc-posture) below).

The fences are invoked from `.github/workflows/security-scan.yml`. Each fence ships
with a paired golden-test fixture under `tests/fixtures/ci/` and a CI inversion-mode
check — the fence MUST report violation against the fixture; if the fence reports
clean against the fixture, CI fails closed (the fence is unverified/broken).

## §10 catalogued-instance ledger cross-reference

Per ADR-011 Decision 4:

- **RT-22** is the **first catalogued §10 instance** (infrastructure-credential-
  presence layer; Lock 13 mod #2).
- **RT-26** is the **second catalogued §10 instance** (code-layer on V1-web-app
  server-side source; SECURITY §4.2 axis vi; HIGH + V1-SHIP-BLOCK).
- **TBC** is the **Privileged-context-surfaces bullet at Decision 4** (code-layer
  parallel to RT-26 on `pfin_back_etl`; Lock 13 mod #3 V1-SHIP-BLOCK). **NOT in
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
├── fence-rt26-service-role-allowlist.sh  # RT-26 grep fence (γ-hybrid)
├── fence-tbc-pfin-back-etl.sh            # TBC grep fence (cross-repo consumable)
├── rt26-allowlist.txt                    # RT-26 allowlist registry (3 ADR-016 D1 file paths)
└── README.md                             # (this file)
```

## RT-22 — PDF worker Dockerfile audit

**Lock:** ADR-011 Decision 4 + Decision 17 / Lock 13 mod #2 + SECURITY §4.5 RT-22.

Catches BOTH (i) `SUPABASE_*` env vars (ENV/ARG) and (ii) Postgres client install
(psycopg2 / psycopg2-binary / asyncpg / pg / node-postgres / postgresql-client) in
the PDF worker Dockerfile.

**Explicitly NOT catching at CI** (covered by human PR-review per ARCH §6.1 RT-22
row verbatim *"human PR-review stays second-line for non-CI-detectable shape
drift"*):

- `COPY package.json` / `COPY requirements.txt` (install intent revealed at RUN
  time; manifest inspection is human-second-line).
- **Transitive Postgres client via base image** — the fence does NOT inspect the
  base image. If a future base-image change inherits `postgresql-client`
  transitively, the fence won't catch it. This is the canonical second-line
  surface for human PR-review per ARCH §6.1 RT-22 row.

Local invocation:

```bash
bash scripts/ci/fence-rt22-pdf-worker-dockerfile.sh workers/pdf-render/Dockerfile
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

### Cross-repo TBC posture

Per F/CTO α + paired-PR ratify (2026-06-08), TBC enforcement lives across two
repos:

- **`mosko-fintech` repo (this repo)** holds the source-of-truth fence script +
  golden fixture + cross-repo docs (this section). CI runs the fence in
  **inversion mode only** against the local golden fixture.
- **`pfin_back_etl` repo** (sibling at `~/Projects/pfin_back_etl/`) holds a
  vendored literal copy of the fence script + golden fixture + a workflow YAML
  that runs the fence in **production mode** against the actual Python source
  tree + inversion mode redundantly.

Both repos' workflows MUST land + merge before V1 ship.

#### Paired `pfin_back_etl` PR file map

When drafting the paired PR in `pfin_back_etl`, land these files (literal copies
of the mosko-fintech-side artifacts unless noted):

```
pfin_back_etl/
├── .github/
│   └── workflows/
│       └── security-scan-tbc.yml         # NEW — see skeleton below
├── scripts/
│   └── ci/
│       └── fence-tbc-pfin-back-etl.sh    # VENDORED COPY (identical content + single-source-of-truth header)
├── tests/
│   └── fixtures/
│       └── ci/
│           └── tbc-violation.py          # VENDORED COPY (identical content + single-source-of-truth header)
├── .dockerignore                          # UPDATED — adds `tests/fixtures/` exclusion
└── pyproject.toml OR setup.py             # UPDATED — `tests/fixtures/` outside `packages` declaration
```

#### Paired `pfin_back_etl` workflow YAML skeleton

```yaml
# pfin_back_etl/.github/workflows/security-scan-tbc.yml
name: Security scan — TBC fence
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
jobs:
  fence-tbc:
    name: TBC — TenantBoundConnection grep
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: TBC production-mode (pfin_back_etl source tree)
        # Vendored copy of fence script + golden fixture from mosko-fintech repo.
        # Single source of truth: <mosko-fintech>/scripts/ci/fence-tbc-pfin-back-etl.sh
        run: bash scripts/ci/fence-tbc-pfin-back-etl.sh .
      - name: TBC inversion-mode (vendored golden fixture; expects violation)
        run: |
          set +e
          bash scripts/ci/fence-tbc-pfin-back-etl.sh tests/fixtures/ci/
          rc=$?
          set -e
          if [ $rc -eq 0 ]; then
            echo "FATAL: TBC fence reported clean against violation fixture — fence is broken; failing closed."
            exit 1
          fi
          echo "OK: TBC fence caught fixture violation (exit $rc)."
```

#### Vendored-copy header convention

When vendoring the fence script + fixture into `pfin_back_etl`, prepend a header
comment marking the single source of truth:

```bash
# VENDORED COPY — single source of truth at:
#   <mosko-fintech>/scripts/ci/fence-tbc-pfin-back-etl.sh
# Update this copy IN LOCKSTEP with the source-of-truth file. Drift detection is
# F/CTO-discipline at paired-PR time at V1; automated drift detection deferred to
# V2-or-later.
```

#### Fixture path isolation requirements (paired-PR responsibility)

Per Sec rubric (b)3 #2: the TBC fixture's path MUST NOT be on `pfin_back_etl`'s
production code-loading path. The paired PR is responsible for:

1. `.dockerignore` excludes `tests/fixtures/` from `pfin_back_etl`'s production
   build context.
2. `pyproject.toml` / `setup.py` `packages` declaration excludes
   `tests/fixtures/` from Python module discovery.
3. `__pycache__` cleanup pattern in place so test runs don't accidentally ship
   compiled bytecode to production.

Without these exclusions, the raw `psycopg2.connect()` in `tbc-violation.py` would
be runtime-loadable — fixture-as-attack-surface is exactly what Sec rubric (b)3
#2 catches.

Local invocation (in `pfin_back_etl` repo against actual Python tree):

```bash
bash scripts/ci/fence-tbc-pfin-back-etl.sh .
```

Local invocation (in either repo against the golden fixture):

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
