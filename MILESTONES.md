# mosko-fintech — MILESTONES

Compact state ledger for mosko-fintech. **The head — everything above the `AUTOLOAD-CUTOFF` marker — is auto-loaded by the SessionStart hook** per [ADR-009](DECISIONS.md#adr-009) Decision 6 (compact-ledger auto-load model — `MILESTONES.md` is the auto-load anchor; everything else consult-on-demand). `## Roadmap` and below are consult-on-demand.

**⚠ This ledger carries CURRENT STATE ONLY — what phase we are in, what is being built, what landed recently.** It is not a findings queue. `## Pending (immediate)` was removed on 2026-08-12 after growing to ~90% of a 141 KB auto-load that was then truncated to ~2 KB, so the head arrived empty while looking fine. **Work awaiting an owner goes to [`BACKLOG.md`](BACKLOG.md) §7 or Linear; a standing constraint goes to the file whose reader would get it wrong — never here.** Session state (`main` sha, open PRs, worktrees) is one command away and is not recorded anywhere.

**Conventions:**
- Milestones tracked at two scales per [ADR-009](DECISIONS.md#adr-009) Decision 7: **meta-process** (M0 / M1 / M2 / M3 = R / P / I+V / Deploy) and **product** (V1.0 / V1.1 / V1.final / V2-X).
- Sprint = Linear cycle (orthogonal pacing wrapper, not a hierarchy level).
- Feature = Linear Issue = one PR = one I↔V loop.
- Last updated: 2026-08-13. ⚠ **This line carries a DATE ONLY, deliberately.** It used to restate session state — `main` sha, PR counts, worktree list — which is derivable from one command and was measured false while sitting in the auto-loaded head: it named a `main` four merges stale and a CHANGELOG version that does not exist. **Do not put state back here.**

## Project / Initiative

| Field | Value |
|---|---|
| Project name | mosko-fintech |
| Linear Initiative | _TBD — created at Phase 4 entry per ADR-009 Decision 7_ |
| Status | Active |
| Owner | F/CTO |
| Target ship date | _TBD — V1 sub-version sequencing defined as M1's "Populate product milestones" output_ |
| Health | On track |

## Current Phase

| Field | Value |
|---|---|
| **Phase** | **Phase 6 (Build Loop) — entered 2026-06-29 per [ADR-020](DECISIONS.md#adr-020) Phase 5 close + Phase 6 entry approval.** Phase 5 (Workshop Setup) ✅ Complete 2026-06-29 — all 7 exit criteria PASS + mosko extensions; **SELF-186 V1.0 first-implementation smoke-test PASSED** (validated the full Architect→Sec→DevOps-CI→branch-protection→F/CTO build loop; `001_pfin_foundation.sql` live on main, db-tests green); branch protection on main configured (was assumed-but-absent — caught at the exit walk); 9 steps across PRs #97–#116. **Meta-process M2 (Implement + Verify) Active.** Phase 4.5 (Agentic Flow Ramp) SKIPPED per [ADR-018](DECISIONS.md#adr-018). |
| **Active work surface** | **Phase 6 (Build Loop):** team-lead orchestrates per-issue; execution agents (Backend / Frontend / Architect / QA / Sec / DevOps) dispatched per Linear issue through the validated build loop (role-agent → QA + Sec joint-review → DevOps CI → branch-protected PR → F/CTO ratify); milestone-rotation per [ADR-017](DECISIONS.md#adr-017) D2. Consumes locked PRD + ARCH + SECURITY + DESIGN + Linear V1.0–V1.4 (89 issues) + BACKLOG §7 (V1.5 + V1.final). **Foundation live:** `001_pfin_foundation` (`pfin` schema + `fn_refresh_updated_at`); first base-table work = SELF-187+ (V1.0 — Platform foundation + Onboarding + Net worth §2.1.1). |
| **Entry-gate items** | (1) **Phase 4.5 disposition F/CTO-ratified SKIP** at Phase 4 close per [ADR-018](DECISIONS.md#adr-018) — Phase 4 6-Wave execution materially exercised the agentic loop. (2) **SELF-186 (B1 Apply migration `001_users_id_rename.sql`) ratified as Phase 5 close-gate V1.0 first-implementation-issue smoke-test** per [ADR-018](DECISIONS.md#adr-018). (3) Wave 1 A1-A5 Linear-issue verification (SELF-181-185 scaffold + auth + CI + Coolify + Discord) at Phase 5 Step 1 verification. |
| **Phase 5 progress** | **Steps 1–8 landed.** Step 1 (entry gates + team setup) ✅. Step 2 (build-time agent defs DevOps → Backend → Frontend → QA; PRs #97–#100) ✅. Step 3 (Architect/PM/Sec refinements; PRs #101–#103) ✅. Step 4 (CI test-fixture + per-Wave RLS battery; PRs #104 W1 / #105 W0 / #106 W2+W3) **substantially closed** — closes SD-15 + RT-15 implicit gaps. Step 5 (per-directory CLAUDE.md `supabase`/`workers`/`api`/`web`; PR #108) ✅ — Sec joint-review GREEN, §10 three-axis CLEAN; `api`/`web` forward-looking. Step 6 (skills library — 4 skills: `brief-drift-catch` CoS / `milestone-rotation` DevOps / `apply-migration` Architect / `spawn-sec-joint-review` PM; PR #110) ✅ — role-owned, each boundary-checked via `brief-drift-catch` (counts clean: D3=7, D4 ledger=2, DEFINER 3→2). Step 7 (Linear MCP verify + milestone-rotation rehearsal; PR #112) ✅ — `docs/linear-setup.md` lands; rotation gate dry-run validated (1/16-Done milestone → correctly blocks); write-path permission proof on SELF-269 (reverted clean); milestone model verified live (native project-milestones V1.0–V1.5 + V1.x + V1.final). Step 8 (pre-commit hooks + secrets management; PR #114) ✅ — `.husky/` (ruff + hadolint; JS deferred to Phase 6) + 3 per-surface `.env.example` + `secrets-manifest.yml` CI/production non-overlap fence (fail-closed); **Sec joint-review GREEN** (AMBER→GREEN, TBC present-tense→forward-discipline reword); §10 ledger untouched (Path B). Step 9 (exit-criteria walk + SELF-186 close-gate smoke-test; branch protection; PRs #116 + close PR) ✅ — 7/7 exit criteria PASS; SELF-186 PASSED (full build loop validated, db-tests green); branch protection on main configured (was absent — exit-walk catch); ADR-020 phase-gate. **Phase 5 ✅ COMPLETE 2026-06-29; Phase 6 (Build Loop) entered.** |
| **Authoritative state files** | [`docs/PRD/index.html`](docs/PRD/index.html) + [`docs/ARCH/index.html`](docs/ARCH/index.html) v1.0 + [`docs/SECURITY/index.html`](docs/SECURITY/index.html) (Wave 6 Gate E SD-10 + SD-12 storage-surface extensions per PR #95) + [`docs/DESIGN/`](docs/DESIGN/) + [`BACKLOG.md`](BACKLOG.md) §5 + §7 + [`DECISIONS.md`](DECISIONS.md) + [`supabase/migrations/`](supabase/migrations/) (⚠ ADR count and latest-migration number are read from those files at the moment of use — both were pinned here once and each was measured badly stale on 2026-08-11) + [`docs/linear-setup.md`](docs/linear-setup.md). Linear V1.0–V1.4 + BACKLOG §7 V1.5 + V1.final are the live work-tracking layer; rotation per [ADR-017](DECISIONS.md#adr-017) Decision 2. |
| **Team task trackers** | `phase-4-scoping` (torn down at Phase 4 close-PR merge per [ADR-003](DECISIONS.md#adr-003)). `phase-5-workshop-setup` (torn down 2026-06-25 after Step 4 substantial close). |
| **Outer category** | **I+V (Phase 6)** per [ADR-009](DECISIONS.md#adr-009) Decision 2 — mosko Phases 5–6 sit under template's Implement+Verify outer frame; M2 (Implement + Verify) Active. |
| **Started** | 2026-06-04 (Phase 5 entry); Phase 4 entry 2026-06-02 → close 2026-06-04 (3 calendar days; fastest phase-completion in mosko history per Phase 4 lessons-learned). |
| **Driver agents** | **Phase 5:** CoS (lead on workshop setup + build-time agent definitions + per-directory CLAUDE.md); DevOps (CI test-fixture + secrets-non-overlap + milestone-rotation skill; bootstrapped first per WORKFLOW.md); Architect (consult on schema-migration ordering + per-directory CLAUDE.md technical content); Sec joint-review at build-time agent posture review + secrets-manifest lock + RT-15 parity-fixture posture lock; PM consult on per-agent Linear permission scope; F/CTO sign-off on every agent definition + skills + secrets manifest. |
| **Gate criteria** | **Phase 5 exit: ✅ 7/7 PASS + extensions** (2026-06-29 per [ADR-020](DECISIONS.md#adr-020)) — task assignable end-to-end ✅ (SELF-186); CI on clean checkout ✅; branch protection on main ✅ (configured at close — was absent); 10 agent defs w/ Linear scope ✅; Phase 0.5 re-signed-off ✅; invoke-by-name ✅; agent+Linear-issue end-to-end ✅ (SELF-186); §10 discipline preserved ✅ (grain-count reconciliation carried); SD-15 + RT-15 closed ✅; rotation rehearsal ✅; SELF-186 smoke-test ✅ PASSED; lessons-learned (8 patterns) added ✅. **Phase 6 gate** (per WORKFLOW.md Phase 6 scaffold): V1 issues ship through the build loop; per-issue QA + Sec joint-review on V1-SHIP-BLOCK surfaces; milestone-rotation at milestone close. |
| **New memory entries this session** | None pending at Phase 4 close. Phase 4 lessons-learned subsection codifies 12 durable patterns in WORKFLOW.md; candidate memory codifications (brief-vs-canonical-ADR cross-check boundary class; 2-teammate independent verification) may surface at Phase 5+ application sites. |

## Active Feature

| Field | Value |
|---|---|
| **Current build** | **V1.1 — Net worth full.** Phase 6 build loop. |
| **Next deliverable** | **SELF-221** — §2.1.3.a multi-horizon NAV-delta backend (team-lead recommendation at the 2026-08-13 close; F/CTO confirms at pickup). Natural pair with SELF-222 (§2.1.3.b panel UI), same backend→UI shape SELF-218→220 just ran; the freshly-seeded decade of real history is exactly what multi-horizon deltas compute over. Remaining V1.1 set at close: SELF-221 / SELF-222 / SELF-223 (§2.1.4 three reference dates) / SELF-229 (staleness-framework ramp) / SELF-228 (close-gate, stays LAST). |
| **Milestone close-gate** | **SELF-228** — the §2.1.7 multi-function cross-tenant RLS battery. It gates the WHOLE V1.1 milestone, so it is the LAST item, not the next one. |
| **Issue state** | Read it from Linear, not from here. No known Linear-vs-reality divergence as of 2026-08-13 close (SELF-220 auto-closed Done on PR #448 merge, verified via liaison). The formerly-pending SELF-217 seeding run is DONE — executed by F/CTO 2026-08-13; record at [`docs/records/self217-nav-seeding-run.md`](docs/records/self217-nav-seeding-run.md). |

## Recent activity (last 5 entries)

Convention per [ADR-017](DECISIONS.md#adr-017): last 5 entries; 1 sentence each; **detail lives in the PR, which GitHub keeps.** ⚠ This line used to point at [`CHANGELOG.md`](CHANGELOG.md); that file was frozen on 2026-08-12 and takes no new entries (see [`WORKFLOW.md`](WORKFLOW.md) § Artifact list).

- **2026-08-13 (Phase 6 — SELF-220 shipped AND the historical seeding run executed; PR #448, `main` `928425a`)** — the §2.1.2.d NAV chart (LayerCake, F/CTO-ratified over LayerChart) merged with migration `069` (`fn_first_cron_checkpoint`, three-field boundary signal) through a **three-round Sec gate** — round 1 added the catalog-posture battery leg (nothing had watched `prosecdef`/`provolatile`/`proconfig`), round 2 caught the imported-era fix failing OPEN on a boundary read failure (markers suppressed + no disclosure = the inverse of suppress-and-disclose), round 3 GREEN — and Architect's contract spot-check separately caught the imported-only state collapsing at the consumer before first render; both fixes shipped with RED-then-GREEN catching tests. Chart URL params were namespaced `chart_` (subset-then-strict, F/CTO option-A ratify) so tracker params no longer disable the chart; AC5's perf anchor re-homed to the Phase-7 deploy gate (BACKLOG §7.15). ⚠ **The SELF-217 seeding run is DONE** — F/CTO executed it same day against the local dev DB (128 imported rows, one transaction, role re-disarmed; the surviving pre-import-boundary record is [`docs/records/self217-nav-seeding-run.md`](docs/records/self217-nav-seeding-run.md)) — and the local DB now stands at migration `069`.
- **2026-08-12 (Phase 6 — V1.1 build day: SELF-218 AND SELF-217 shipped, the component-history decision made durable; PRs #443 / #445 / #444, `main` `aa6086d`)** — `067` (`fn_nav_series_inflation_adjusted`, return shape C, deflate-at-point_date) merged through QA 40/40 + Sec GREEN; the historical-NAV import machinery (ADR-053 + comment-only `068` + the all-or-nothing `workers/etl` importer + 40 tests) merged through a twice-held Sec gate whose catches included an unrecoverable-partial-backfill seam and a stale ledger tally shipping into `pg_description`; ADR-054 was **Accepted** at the doc-PR double gate with both Decision-5 questions ruled (no V1.x read helper; documented parity property, F/CTO rider recorded verbatim) and BACKLOG gained A9 + the §5.1 deferral + §7.13 (CoA design question). ⚠ **Two operational facts:** the real `pfin_etl` password was overwritten cluster-wide by a QA scratch-harness incident (roles are cluster-level), disarmed at NOLOGIN, and REISSUED by F/CTO the same day — and the production seeding run remains F/CTO-gated with its preconditions on the Linear issue. The morning's effort-binding question CLOSED (`effort:` never binds; agents inherit session `/effort`; auto-compact now pinned at 80% via settings env); follow-ups from both Sec reviews live in [`BACKLOG.md`](BACKLOG.md) §7.14, deliberately not restated here.
- **2026-08-12 (Phase 6 — the whole agent roster rewritten, F/CTO-reviewed file-by-file, and VALIDATED by live spawns; PRs #440–#441)** — the 9 not-yet-revised agent definitions went through the security-engineer/team-lead revision pass (1647 → 840 lines; every pinned count replaced by a read-live pointer; Linear routed via liaison; per-agent model/effort assigned), `chief-of-staff` was retired with the WORKFLOW.md roster + glossary following, the root `README.md` the artifact list had promised since Phase 0 finally exists, the team-lead role gained a Session-close section, and #440 de-pinned the ledger's own ADR/migration counts after both were measured stale in this auto-loaded head. ⚠ **Post-merge spawns proved the definition BODY loads fresh at spawn while `model:` binds only after a lazy registry refresh (first post-merge spawn raced it and ran the old model) and `effort:` did not bind at all under an explicit session `/effort`** — whether it binds when `/effort` is untouched is the FIRST ACTION of the next session, before anyone touches `/effort`: spawn `linear-liaison` + `qa`, F/CTO reads the tiers, expected `haiku-low` / `sonnet-low` if effort binds.
- **2026-08-12 (Phase 6 — the session-context surfaces: hand-off protocol, portable paths, and the ledger auto-load; PRs #432–#437)** — the `security-engineer` definition was rewritten against the template schema and an agent **hand-off protocol** (*return conclusions, not evidence*) landed verbatim in [`WORKFLOW.md`](WORKFLOW.md) and all 11 agent files, hardcoded worktree paths gave way to a derivation that resolves in any clone (the shared-path guard had been refusing a commit and then telling the developer to `cd` somewhere that need not exist), `team-lead.md` was created in `.claude/roles/` with its own `SessionStart` loader, and the ledger auto-load went **141 KB → 14 KB** while `## Pending` was retired **127 KB → 8 KB** with [`CHANGELOG.md`](CHANGELOG.md) frozen rather than deleted. ⚠ **The finding that shaped all of it: `SessionStart` hooks REACH SUBAGENTS** — measured independently by two agents after everyone had assumed otherwise, which is why the role definition went to `roles/` rather than `agents/` (every `.md` there becomes a spawnable `subagent_type`) and why the orientation imperatives came out of the hook, where every teammate had been reading them as its own instructions.
- **2026-08-11 (Phase 6 — session close: 26 PRs merged, TWO touching shipping code; `main` `8dcabd6`, v1.192)** — the day's output was documentation, CI, tests and process apart from **#411** (`063`–`066` + battery) and **#412** (the ETL transport lift), and the **Husky pre-commit set was found never to have executed** since its 2026-06-28 ratify — now armed, self-restoring, behind a live fail-closed shared-path commit guard; **ADR-052** ratified and `WORKFLOW.md` gained Verification + Coordination discipline sections. ⚠ **The rule that ends this loop: a finding gets RECORDED unless it has runtime effect or blocks a ship gate** — the remainder are in [`BACKLOG.md`](BACKLOG.md) §7.11, deliberately not restated.
<!-- AUTOLOAD-CUTOFF — the SessionStart hook emits everything ABOVE this line and stops here. Do not delete: the hook falls back to the '## Pending' heading, and if that is renamed too it emits the whole head and says so loudly at the top. Moving this line changes what every session sees. -->

## Pending (immediate) — RETIRED, awaiting three rulings

⚠ **This section was removed on 2026-08-12 and is not coming back. Do not add to it.** It held 49 blocks / 202 lines / 127 KB with no defined purpose, no size bound and no owner, and it had grown to ~90% of an auto-load the session-start channel then truncated to ~2 KB — so the ledger head was arriving empty while looking healthy. Its contents were routed: session state deleted (one command answers it), completed work deleted (GitHub holds the PR record), work-awaiting-an-owner to [`BACKLOG.md`](BACKLOG.md) §7.12, current build to `## Active Feature` above, and every standing constraint to **the file whose reader would get it wrong**.

**Three items survive here because routing them would have meant guessing.** F/CTO rules on each; the section goes when the last one lands.

**(i) Sec — the Class D residual.** Sec should place this; it is the only item whose destination depends on how the label is used rather than on what it says.

> - **Class D residual** — *"vacuous satisfaction is satisfaction"* holds, but **D1's protective content over a global table is nil** (its purpose is tenant-correctness where there is no JWT, and there is no tenant), so *"this is a D1 surface"* now signals less than it did. Fine as recorded; **revisit only if D1 is ever used as a filter** (*"enumerate all D1 surfaces"*) rather than as a citation.

**(ii) and (iii) — the two Phase 5 inventory blocks, verbatim below.** (ii) needs an F/CTO call on whether the consolidation workstream survived Phase 5's close on 2026-06-29; the candidate artifact `docs/PHASE-5-INVENTORY.md` was never created. (iii) is 28 bullets of which a visible fraction **shipped during Phase 5** — the CI tooling selection, the RT-26 / `TenantBoundConnection` / RT-22 fences, `secrets-manifest.yml`, branch protection — so it needs a per-bullet shipped/open verdict before it moves. Carrying it wholesale into §7 would import completed work as if it were open.

2. **Phase 5 detail-design inventory consolidation workstream** — formal status as of §8.6 close annotation (PR #74; updated to "22+" at PR-C row #3): "Architect follow-up workstream at Phase 4 entry; candidate artifact `docs/PHASE-5-INVENTORY.md` (per-territory tables grouping Plaid implementation items + observability items + concurrency items + settings-store items + tenant-isolation tests + other Phase 5 detail-design surfaces)." Per-§-source forward-pointer commitment is durable in ARCH §8.6 + every in-line Phase 5 forward-pointer at the source-§. Item count **22+ items** spread across §3.2 + §4 Observability + §5 + §7.1 + §6 + §6.1 + §8.3 (see inventory below). Question shape: "execute the workstream at Phase 4 entry" (PR #74+ framing). No change post-PR-79.

**Phase 5 V1-SHIP-BLOCK + non-V1-SHIP-BLOCK detail-design inventory** (accumulating across PRs #67/#68/#69/#71/#72-candidate; **19+ items** spread across §3.2 + §4 Observability + §5 + §7.1 + §6 + §6.1):
- **PR #67 / §3.2:** PDF-JWT-to-RLS binding mechanism (`SET LOCAL request.jwt.claims` vs parametric `WHERE users_id = $1` vs other; constrained by RT-21(e) no-service_role-escalation per Lock 13 mod #1) — substantive deferral.
- **PR #67 / §3.2:** V1-web-app TypeScript-side privileged-context helper class name (parallel to pfin_back_etl Python `TenantBoundConnection`).
- **PR #68 / §4 Observability V1-SHIP-BLOCK:** F1 Coolify Discord payload PII audit (conditional flip-gate to Shape C fallback if verification fails).
- **PR #68 / §4 Observability V1-SHIP-BLOCK:** F3 RT-21 PDF-JWT-rejection audit-log commitment.
- **PR #68 / §4 Observability:** F4 notification-target access posture (Discord channel privacy + webhook URL secrets + retention; Shape C receiver auth + flat-file permissions + log-rotation).
- **PR #68 / §4 Observability:** Coolify-cron-status visibility verification.
- **PR #68 / §4 Observability:** Optional structured-JSON-to-stdout log-format conventions.
- **PR #69 / §5:** Staging environment ramp (V2-onboarding-triggers).
- **PR #69 / §5:** Network topology detail (port allocations / reverse-proxy / TLS termination per Coolify defaults vs custom).
- **PR #69 / §5:** F2 inter-container network isolation evaluation (RT-22 credential-absence sole barrier vs explicit network isolation defense-in-depth).
- **PR #69 / §5:** Operational/admin auth mechanism (Coolify defaults vs custom hardening + SSH key/passphrase posture + Coolify privileged-mode posture).
- **PR #71 / §7.1 V1-SHIP-BLOCK:** Sec-fallback posture binding at Phase 5 — Plaid error-code taxonomy distinguishing institution-side-grant-revoked + user-side-grant-revoked sub-classes (Sec-joint-collapse to 3-class OR deferred-discriminator-via-user-flow as escape paths; Sec joint-review-mandatory).
- **PR #71 / §7.1:** Per-endpoint audit-hook table completion — Sec-consult-mandatory at Phase 5 audit-hook lock.
- **PR #71 / §7.1:** Plaid-error-code → V1-state discriminator concrete assignment — Sec joint-review-mandatory per App B §2.4 (h) routing flag (bound to Sec-fallback above).
- **PR #71 / §7.1:** `pfin_back_etl` worker-concurrency posture for Plaid scheduled-poll — Sec-consult-mandatory at Phase 5 concurrency lock (intersects Plaid rate-limit budget sharing + `TenantBoundConnection` discipline cohesion + SD-19 row-growth observability).
- **PR #71 / §7.1:** Plaid product-tier quota concrete sizing — Phase 5 reconciliation against actual Plaid bill per PRD §7.1 (a) Architect-Phase-3 cost-shape forward-pointer.
- **PR #71 / ADR-016:** Concrete `+server.ts` file paths for canonical second + third allowlist entries (`/item/public_token/exchange` + `/item/remove` — Phase 5 routing convention).
- **PR #72-candidate / §6 (a):** Specific CI tooling selection (Vitest / pytest / ESLint / Prettier / ruff / hadolint / dep scanners / secrets scanner).
- **PR #72-candidate / §6 (b) Sec-consult-mandatory:** GitHub Actions workflow YAML authoring + secret-store config; `secrets-manifest.yml` + CI-automated overlap check golden-test fixture per Sec-2 (b)3.
- **PR #72-candidate / §6 (c) V1-SHIP-BLOCK + Sec-consult-mandatory:** RT-26 grep fence script authoring + golden-test fixture per Sec-2 (a)2 (deliberately-out-of-allowlist file referencing `SUPABASE_SERVICE_ROLE_KEY`).
- **PR #72-candidate / §6 (d) V1-SHIP-BLOCK + Sec-consult-mandatory:** `TenantBoundConnection` grep fence script authoring per Lock 13 mod #3 + golden-test fixture per Sec-2 (a)2 (deliberately-outside-class `psycopg2.connect()` invocation).
- **PR #72-candidate / §6 (e) Sec-consult-mandatory:** RT-22 Dockerfile audit script authoring + golden-test fixture per Sec-2 (a)2 (deliberately-violation-shaped Dockerfile with `ENV SUPABASE_*` + `RUN apt-get install postgresql-client`).
- **PR #72-candidate / §6 (f) Sec-consult-mandatory:** Coolify auto-deploy webhook configuration + 4 posture commitments per Sec-2 (a)3 (Coolify-watches-main-only / GitHub branch protection admin-bypass restricted/disabled / webhook URL is a secret / auto-deploy permission boundaries documented).
- **PR #72-candidate / §6 (g):** Branch protection + required status checks configuration (GitHub admin operation).
- **PR #74 / §8.3 (b)2 Sec-consult-mandatory:** `auth.uid()` provenance discipline implementation at metadata recommendation engine read path — `users_id` parameter bound from `auth.uid()` not `req.body` per Lock 14 user-facing-layer discipline.
- **PR #74 / §8.3 (b)3 Sec-consult-mandatory:** Per-tenant scope migration writeup for `pfin.merchant_subcat_mapping` (Lock 7 `user_taxonomy` precedent; `users_id`-keyed mapping; first-login bootstrap seed from F/CTO's existing Master.CashFlowCategories as one-time per-tenant write).
- **PR #74 / §8.3 (b)5 Sec-consult-mandatory:** Plaid `merchant_name` adversarial-input validation library selection + integration (length cap + Unicode-control-char strip + normalization) applied across all algorithm shapes at the validation layer.

## Roadmap

[awk cutoff for SessionStart hook lives at this `## Roadmap` line per template's auto-load pattern. Content above this line is auto-loaded; content below is consult-on-demand.]

### Meta-process milestones

| # | Milestone | Status | Gate | Linear Project | Notes |
|---|---|---|---|---|---|
| **M0** | Research (PRD lock) | ✅ COMPLETE 2026-05-26 | PRD locked at end of mosko Phase 1 (Step 4 ratified + close-work merged via PRs #51 / #52 / #53 / #54 + this PR) | _TBD on /setup-linear-team_ | Retro-tagged issues: Step 3 + Step 3.5 PRs (see [Completed Features](#completed-m0-retro-tagged) below). Plus the ADR-009 brainstorm-adoption arc (PRs #39–#42). Plus the Step 4 architectural drilling cycle ratifying 16 locks + 4 meta-patterns + candidate P3 disposition per [ADR-011](DECISIONS.md#adr-011) (PRs #51–#55 close-work sequence). |
| **M1** | Plan (ARCH + SECURITY docs) | Active (Phase 3 entry-ready) | ARCH + SECURITY docs locked at end of mosko Phase 3 | _TBD_ | Initial issues: (a) Draft `docs/ARCH/index.html` consuming ADR-011 + 13 Phase 3 carry-over tasks; (b) Extend `docs/SECURITY/index.html` with Phase 3 architectural decisions (V1 Sec posture already landed via ADR-008 + ADR-011 + PRs #45 / #52 / #53 — Phase 3 extends with implementation-detail Sec decisions); (c) Populate product milestones in MILESTONES.md → see [`docs/MILESTONE-FRAMING.md`](docs/MILESTONE-FRAMING.md); (d) Plaid production-tier monthly minimum confirmation (out-of-band Phase 3 entry-gate); (e) further granularity TBD. Also catches Phase 4 (Project Scoping) work as part of issue (c). |
| **M2** | Build (V1.0 → V1.final) | Pending | V1 ship | _TBD; defined as M1 issue (c) output_ | Product milestones (V1.0 / V1.1 / V1.final) get defined as M1's "Populate product milestones" output. M2 then decomposes into sprints. |
| **M3** | Deploy & Iterate | Pending | V1 in production | _TBD_ | mosko Phase 7 territory; ongoing project-scale I+V loops post-V1 ship. V2 candidates from [`BACKLOG.md`](BACKLOG.md) feed here. |

### Product milestones

| Milestone | Status | Gate | Notes |
|---|---|---|---|
| V1.0 / V1.1 / V1.final / V2-X | _NOT YET DEFINED_ | _Defined by M1 issue (c) output_ | See [`docs/MILESTONE-FRAMING.md`](docs/MILESTONE-FRAMING.md) for the V1 sub-version convention + drop-replace migration pattern + Phase 4 handoff anchor per ADR-004. |

## Sprints (Linear cycles)

| Sprint | Milestone | Start | End | Features | Status | Notes |
|---|---|---|---|---|---|---|
| _none yet — sprints activate at Phase 6 entry per ADR-009 Decision 7_ | | | | | | |

## Features

### Completed (M0 retro-tagged)

Issues retroactively tagged under M0 (Research milestone). Full PR history at [`CHANGELOG.md`](CHANGELOG.md).

| Feature | PR | Merged | Notes |
|---|---|---|---|
| ADR-010 PR 2 — comments-sidecar pass 2 (server + widget + `/serve-docs`) | #48 | 2026-05-24 | Closes the ADR-010 two-PR landing. Python stdlib HTTP server + JS widget + `/serve-docs` skill + asset wiring in all three HTML docs (PRD / ARCH / SECURITY) + WORKFLOW.md Inline-authoring subsection. Both `/refine-doc` and `/serve-docs` now available; Step 4 PRD review can begin with widget support. |
| ADR-010 PR 1 — comments-sidecar pass 1 (convention + `/refine-doc`) | #47 | 2026-05-24 | Adopted comments-sidecar feature from `richmosko/project_template` per ADR-009 Decision 8 selective-adoption framework. Pass 1 of 2: convention + skill + gitignore + WORKFLOW.md Doc-review-loop section + ADR-010. |
| PR B — PRD content migration to HTML artifact set | #45 | 2026-05-23 | Tasks #12 + #13 + #14 (ADR-009 Decision 4 second stage; closes the architectural shift). Migrated §1/§2/§3/§6/§7/appendices to `docs/PRD/index.html`; §4 → `docs/SECURITY/`; §5 → `BACKLOG.md`; §8 → `docs/MILESTONE-FRAMING.md`; `PRD.md` archived. |
| PR C — SessionStart hook → MILESTONES.md head | #44 | 2026-05-23 | Task #11 (ADR-009 Decision 6 mechanics; compact-ledger auto-load) |
| MILESTONES.md initial ledger | #43 | 2026-05-23 | Tasks #7 + #15 (this file's creation) |
| Adapt doc-update skills + retire /ship-branch | #42 | 2026-05-23 | Task #17 (ADR-009 Decision 9 implementation) |
| Extract WORKFLOW.md changelog to CHANGELOG.md | #41 | 2026-05-23 | Task #10 (orthogonal cleanup) |
| PR A — HTML doc scaffolding for PRD/ARCH/SECURITY | #40 | 2026-05-23 | Task #18 (ADR-009 Decision 4 first stage) |
| ADR-009 — selective project_template adoption | #39 | 2026-05-23 | Task #9 (9-Decision synthesis ADR) |
| Step 3.5 PR 11 — post-rewrite verify pass closure | #38 | 2026-05-20 | v1.30; 14-gate VP walk; 3 surgical edits; Sec hard-line preserved |
| Step 3.5 PR 10 — Step 3.5 closure + Appendix B consolidation | #37 | 2026-05-19 | v1.29; 114-entry App B body lifted + classified |
| Step 3.5 PR 9 — §8 rewrite | #36 | 2026-05-19 | v1.28; last PM-led drafting task in Phase 1 Step 3 |
| Step 3.5 PR 8 — §7 rewrite | (prior PR) | 2026-05-19 | v1.27 |
| Step 3.5 PR 7 — §6 rewrite | (prior PR) | 2026-05-19 | v1.26 |
| Step 3.5 PR 6 — §5 rewrite | (prior PR) | 2026-05-19 | v1.24 |
| Step 3.5 PR 5 — §4 rewrite (Sec primary author) | (prior PR) | 2026-05-19 | v1.23 |
| Step 3.5 PR 4 — §3 rewrite | (prior PR) | 2026-05-19 | v1.22 |
| Step 3.5 PR 3 — §2 rewrite + Appendix C | (prior PR) | 2026-05-18 | v1.21; 32 story traces extracted |
| Step 3.5 PR 2 — §1 rewrite | (prior PR) | 2026-05-18 | v1.20 |
| Step 3.5 PR 1 — Step 3.5 kickoff + archive | (prior PR) | 2026-05-18 | v1.19; PRD-v1.18 source archived |
| Step 3 §1–§8 PRD section drafting | PRs #10–#24 | 2026-05-09 → 2026-05-18 | Initial PRD drafting + ADRs 002–008 + Sec at-lock passes |
| Step 2 + Step 1 + Phase 0 / 0.5 bootstrap | PRs #1–#9 | 2026-04-24 → 2026-05-09 | Operating model + agent roster + WORKFLOW.md / DECISIONS.md / CLAUDE.md foundations |

### In Flight (M1)

| Feature | PR | Milestone | Branch | Status |
|---|---|---|---|---|
| _none active — between PRs; Step 4 (Architect PRD ratification) is the immediate next deliverable_ | | | | |
| _Substantive M1 features open after Step 4 ratifies / Phase 3 entry_ | | | | |

### Backlog (M1+)

Pulled from Linear once activated. Until then, M1's initial issues are listed in the [Meta-process milestones](#meta-process-milestones) table above. V2 candidates live in [`BACKLOG.md`](BACKLOG.md).

## Releases

| Version | Date | Milestone shipped | Notes |
|---|---|---|---|
| _none yet — first tagged release at V1.0 ship (defined by M1 issue (c) output)_ | | | |

## Decisions

The Decision Log lives in [`DECISIONS.md`](DECISIONS.md) (consult-on-demand per [ADR-009](DECISIONS.md#adr-009) Decision 6). Hybrid ADR format policy (consolidation vs terse) per ADR-009 Decision 8.

**Most recent ADRs:**

- **[ADR-010](DECISIONS.md#adr-010)** (2026-05-24; terse) — Adopt comments-sidecar feature from project_template. Two-PR landing: pass 1 (convention + `/refine-doc` skill); pass 2 (server + widget + `/serve-docs` skill).
- **[ADR-009](DECISIONS.md#adr-009)** (2026-05-23; consolidation) — Selective adoption of richmosko/project_template patterns. 9 Decisions consolidating the template-adoption brainstorm.
- **[ADR-008](DECISIONS.md#adr-008)** (2026-05-18; consolidation) — Phase 1 Step 3 §4 lock: V1 security posture canonical reference. 5 Decisions including 14-entry SD matrix + 15-entry RT catalog.
- **[ADR-007](DECISIONS.md#adr-007)** (2026-05-17; terse amendment) — Amendment to ADR-002 Finding (b): tax-loss-harvesting reclassified V2+ → permanent non-goal.
- **[ADR-006](DECISIONS.md#adr-006)** (2026-05-17; terse amendment) — Amendment to ADR-004 Decision D: V1 input-layer characterization (bracket schedules + tax_character enum).
- **[ADR-005](DECISIONS.md#adr-005)** (2026-05-13; terse amendment) — Amendment to ADR-002 §1.2: planning-targets V1 static reference-value rendering.

Full ADR list and historical entries at [`DECISIONS.md`](DECISIONS.md).
