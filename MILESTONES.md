# mosko-fintech — MILESTONES

Compact state ledger for mosko-fintech. **The head — everything above the `AUTOLOAD-CUTOFF` marker — is auto-loaded by the SessionStart hook** per [ADR-009](DECISIONS.md#adr-009) Decision 6 (compact-ledger auto-load model — `MILESTONES.md` is the auto-load anchor; everything else consult-on-demand). `## Roadmap` and below are consult-on-demand.

**⚠ This ledger carries CURRENT STATE ONLY — what phase we are in, what is being built, what landed recently.** It is not a findings queue. `## Pending (immediate)` was removed on 2026-08-12 after growing to ~90% of a 141 KB auto-load that was then truncated to ~2 KB, so the head arrived empty while looking fine. **Work awaiting an owner goes to [`BACKLOG.md`](BACKLOG.md) §7 or Linear; a standing constraint goes to the file whose reader would get it wrong — never here.** Session state (`main` sha, open PRs, worktrees) is one command away and is not recorded anywhere.

**Conventions:**
- Milestones tracked at two scales per [ADR-009](DECISIONS.md#adr-009) Decision 7: **meta-process** (M0 / M1 / M2 / M3 = R / P / I+V / Deploy) and **product** (V1.0 / V1.1 / V1.final / V2-X).
- Sprint = Linear cycle (orthogonal pacing wrapper, not a hierarchy level).
- Feature = Linear Issue = one PR = one I↔V loop.
- Last updated: 2026-08-16. ⚠ **This line carries a DATE ONLY, deliberately.** It used to restate session state — `main` sha, PR counts, worktree list — which is derivable from one command and was measured false while sitting in the auto-loaded head: it named a `main` four merges stale and a CHANGELOG version that does not exist. **Do not put state back here.**

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
| **Current build** | **V1.1 — Net worth full: ✅ COMPLETE 2026-08-16.** All 13 milestone issues Done in Linear (liaison-swept); the close-gate battery merged in PR #464 (`main` `e49def2`); the ADR-047 amendment + BACKLOG §7.18 deferral landed in PR #465 (`main` `65bd9f1`). Phase 6 build loop continues into V1.2 after rotation. |
| **Next deliverable** | **Milestone-rotation to V1.2** per `/milestone-rotation` + [ADR-017](DECISIONS.md#adr-017) Decision 2 — the completion gate is verified (all 13 V1.1 issues Done, liaison-swept 2026-08-16), but rotation's booking step is gated on an F/CTO decision: **no V1.2 milestone exists in Linear** and the workspace free-issue limit remains the standing booking constraint (§7.6 framing note (1) — capture in BACKLOG §7 works regardless). Still-queued F/CTO ruling from earlier sessions: terse-ADR home for the `072` real-percent base. The db-reset mechanical guard is **ACTIVE** (fresh-session four-probe proof on PR #463); `supabase db reset` remains banned outright for all agents; `account`/`linked_source`/`user_settings` stay empty by design (BACKLOG §7.17). |
| **Milestone close-gate** | **DISCHARGED.** SELF-228 (the §2.1.7 six-function cross-tenant RLS battery, plan 34) merged through Sec joint-review AMBER→GREEN (AC4 record on PR #464); the ADR-047 end-to-end condition was discharged on F/CTO's Option-B ruling (DB-layer provenance proof; the chart-render half is deferred visibly to BACKLOG §7.18, NOT absorbed — Sec's condition). |
| **Issue state** | Read it from Linear, not from here. ⚠ One known divergence, surfaced 2026-08-16 and deliberately NOT reconciled: **SELF-217 reads Done in Linear (auto-completed 2026-08-13) but the record says PARKED-foreclosed** — ADR-040's forward-only decision forecloses it and its draft ACs are schema-impossible; do not read its Done as "built." Awaiting F/CTO's call on a clarifying comment. The SELF-217 seeding run's DATA remains restored (128 rows byte-identical to the preserved run log; run record at [`docs/records/self217-nav-seeding-run.md`](docs/records/self217-nav-seeding-run.md)). |

## Recent activity (last 5 entries)

Convention per [ADR-017](DECISIONS.md#adr-017): last 5 entries; 1 sentence each; **detail lives in the PR, which GitHub keeps.** ⚠ This line used to point at [`CHANGELOG.md`](CHANGELOG.md); that file was frozen on 2026-08-12 and takes no new entries (see [`WORKFLOW.md`](WORKFLOW.md) § Artifact list).

- **2026-08-15/16 (Phase 6 — SELF-228 shipped and V1.1 COMPLETE; PRs #463 + #464 + #465, `main` `65bd9f1`)** — the db-reset mechanical guard went **ACTIVE** (fresh-session four-probe proof recorded on PR #463 — the proof itself hit the documented over-block and used `--body-file`, as Sec predicted the documenters would); the §2.1.7 close-gate battery landed at plan 34 after F/CTO ratified a full AC reconciliation (**THIRD schema-impossible PM-draft instance** — `p_scope pfin.scope[]` was ratified out at `049`/`051`; the battery set grew to SIX functions when the Linear upstream mapping surfaced `067`) through a one-round Sec AMBER→GREEN whose blocking catch was structural non-vacuity: the same-date two-tenant fixture read through `062`'s untied `order by … limit 1` left the two series functions' isolation legs not *guaranteed* to fail under a leak — fixed with two-sided positive legs that cannot both hold. The ADR-047 ship-gate closed on F/CTO's **Option-B ruling** (the DB-layer provenance proof — 128 real-worker-path `nav_daily` rows read through the six functions as the real tenant — discharges the clause; the chart-render half is a distinct UI property deferred **visibly** to new BACKLOG §7.18, which also absorbs the §7.17 auth extension with its F/CTO checkpoint re-armed), and PR #465 gave the 2026-08-07 end-to-end condition its **first repo-tracked home** in ADR-047 — the condition sentence landed byte-verified against the Linear source (three independent liaison reads + a pre-commit `cmp`) after the relay channel measurably drifted three times on that one sentence. ⚠ Rotation-prep sweep: all 13 V1.1 issues Done, but **SELF-217 reads Done vs the PARKED-foreclosed record** (surfaced, not reconciled) and **no V1.2 milestone exists in Linear** (free-issue limit, standing F/CTO cost decision).
- **2026-08-15 (Phase 6 — SELF-229 shipped: the staleness-framework ramp AND the framework-root fail-closed rework; PR #461, `main` `8963875`; F/CTO's team-lead-tone edit landed separately as PR #460)** — the SELF-208 badge ramped to all four V1.1 NW surfaces via prop-threading of the single whole-user load (the drafted AC's `(p_users_id, p_scope_filter)` signature was schema-impossible — 046 is zero-arg — the SECOND consecutive instance of that drafting shape; AC corrected in Linear post-hoc, PM adopted a copied-DDL-or-marked-provisional rule), composition per-leaf staleness landed as an RLS-scoped server-side join (no migration, INVOKER throughout), and mid-item F/CTO ruled option (a): the framework ROOT's shipped fail-open (silent `{is_stale:false}` on RPC error, live since SELF-208) got the tri-state treatment on the same branch — `UNKNOWN_STALENESS` distinct from empty, REQUIRED props with no defaults (Sec option B: the compiler is the watcher, CI-enforced, proven fail-closed in both directions). **Sec joint-review ran three rounds (AMBER→GREEN→GREEN final no-findings; durable record posted on the PR)** — catches included a malformed-payload trap, a render cell showing silence, tenant data in application logs (now proven absent by a planted-canary spy leg), and a pair-consistency gap; QA separately caught a stale-diff base that would have silently reverted landed work, a CSS class collision summing two staleness signals, and a SELF-223-era fixture testing the wrong January pairing. The two-sided freeze ack caught a real in-flight hand-off AGAIN (QA's 11 wiring legs). January-family copy shipped PM-reviewed with one voice across both panels. Battery: 880 green at merge.
- **2026-08-14 latest (recovery — the wiped local dev DB restored, supervised per F/CTO option (b); PR #458 + the closure sweep)** — backend re-ran the full seed path with F/CTO holding the two ADR-053-reserved gates (`pfin_etl` arming; `--ack-delta`, ratified at −100.00% after the empty-`account` comparand cause was verified from the DB): `seed.sql`, BLS CPI re-pull (138 rows + one real 2025-10 nonpublication), then the backfill — whose FIRST committed attempt failed CLEAN (ADR-053 all-or-nothing held, zero rows) on the recovery plan's own gap: nothing recreated the tenant's `auth.users` row, and preflight had checked count, not identity. F/CTO ratified a bare-id stub on the exact original uuid (option (a), `seed.sql`'s own precedent, auth fields addable later on the same row); the re-run landed 128 rows **byte-identical to the preserved run log**, and `pfin_etl` was re-disarmed. ⚠ En route, PR #458 corrected the incident record: its claim that `baseline_nav.csv` "ends 2025-09-30 / is NOT the run's input" was **false against the file** (the CSV is the exact, complete input, sha256-identical to the `temp/nav-history` original) — backend inherited the false premise from the record and nearly launched an unnecessary reconstruction before team-lead refuted it from the file. Follow-ups: BACKLOG §7.17.
- **2026-08-14 late (Phase 6 — SELF-223 shipped: `073 fn_nav_reference_dates` AND the §2.1.4 Reference NAV panel UI; PRs #455 + #456, `main` `d2d370a`)** — reconciliation-first caught the drafted ACs stale on four axes before any DDL (schema-impossible `(p_users_id, p_scope)` signature, nonexistent `pfin.nav` relation, a date-dependent "≥1yr history" predicate replaced by the per-row structural one, and an unscoped AC6 equality claim false on the CPI-unresolvable row — the `072` biconditional class caught at AC-draft cost); F/CTO ratified the package + the Prior-Month reading (most recent completed month-end = `072`'s `v_base`), and the resulting on-screen levels-vs-deltas reconciliation identities were **measured, not argued** (This−Prior ≡ month delta; This−PriorYE ≡ ytd delta; shared current checkpoint). The battery (plan 38) is **calendar-swept across 25 synthetic run days** (a first-draft leg was a Jan–May time bomb — green only because it was August), the leak canary aims at the FUNCTION rather than the table (Sec flag taken on-branch; `071`'s sibling booked in §7.16), and Sec went GREEN at `354e69f` carried to `cb7653f`. ⭐ **The January family is now three documented members** (booked as one copy problem on the staleness-ramp issue): duplicate ROWS (prior_month = prior_year_end reference date), duplicate COLUMNS under CPI arrears (all three rows exact — production-normal), and the `072` carried-basis case — all render as the calendar, never as an incident.
- **2026-08-14 (Phase 6 — SELF-222 shipped: the §2.1.3.b NAV-delta panel UI AND the `072` real-terms-percent amendment; PRs #452 + #453, `main` `697453f`)** — the panel (5 fixed rows × NAV Delta / Inflation Adjusted, mounted per the ADR-013 number-first lock) renders every state off `fn_nav_delta_panel`'s structural discriminators with **zero client-side inference** and discloses current-side staleness as a literal `current_checkpoint_date` basis line (never a client-clock comparison); mid-item, frontend's refusal to back-derive an AC3 percent exposed that the drafted "dollar + percent" AC was schema-impossible AND parity-load-bearing (the incumbent panel is percent-only; PRD §3.3 clause (ii) fixture cells are percents — PM evidence, F/CTO Option-B ratify), so **migration `072`** added `delta_inflation_adjusted_percent` (deflated-prior-YE-anchor base; DROP+CREATE with the ACL/comment re-issue as the perimeter) through a one-round Sec AMBER→GREEN whose catches included a false biconditional at THREE sites (Sec found two, Architect's re-grep found the third in his own text) and a fail-open `isnt(NULL,…)` corrupt-the-control leg rewritten fail-closed (battery now 44 legs incl. an anon EXECUTE leg). ⚠ **Incident, separate from the branch work: QA's `supabase db reset --db-url <scratch>` reset the SHARED local stack — the flag does not scope — wiping all local data** (schema survived); the command is banned outright for agents, recovery assets are preserved + dual-verified outside the repo, the re-seed is F/CTO-gated, and a mechanical guard (Sec recommends a permission deny rule) is a pending F/CTO ruling.
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
