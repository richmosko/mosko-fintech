# mosko-fintech — MILESTONES

Compact state ledger for mosko-fintech. **The head — everything above the `AUTOLOAD-CUTOFF` marker — is auto-loaded by the SessionStart hook** per [ADR-009](DECISIONS.md#adr-009) Decision 6 (compact-ledger auto-load model — `MILESTONES.md` is the auto-load anchor; everything else consult-on-demand). `## Roadmap` and below are consult-on-demand.

**⚠ This ledger carries CURRENT STATE ONLY — what phase we are in, what is being built, what landed recently.** It is not a findings queue. `## Pending (immediate)` was removed on 2026-08-12 after growing to ~90% of a 141 KB auto-load that was then truncated to ~2 KB, so the head arrived empty while looking fine. **Work awaiting an owner goes to [`BACKLOG.md`](BACKLOG.md) §7 or Linear; a standing constraint goes to the file whose reader would get it wrong — never here.** Session state (`main` sha, open PRs, worktrees) is one command away and is not recorded anywhere.

**Conventions:**
- Milestones tracked at two scales per [ADR-009](DECISIONS.md#adr-009) Decision 7: **meta-process** (M0 / M1 / M2 / M3 = R / P / I+V / Deploy) and **product** (V1.0 / V1.1 / V1.final / V2-X).
- Sprint = Linear cycle (orthogonal pacing wrapper, not a hierarchy level).
- Feature = Linear Issue = one PR = one I↔V loop.
- Last updated: 2026-09-03 (V1.3→V1.4 rotation). ⚠ **This line carries a DATE ONLY, deliberately.** It used to restate session state — `main` sha, PR counts, worktree list — which is derivable from one command and was measured false while sitting in the auto-loaded head: it named a `main` four merges stale and a CHANGELOG version that does not exist. **Do not put state back here.**

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
| **Current build** | **V1.4 — Estimated taxes full (§2.5), rotated in 2026-09-03** per `/milestone-rotation` + [ADR-017](DECISIONS.md#adr-017) Decision 2 (**V1.3 ✅ COMPLETE 2026-09-03** — 15 issues all Done, verified against live Linear; close-gate SELF-257 discharged at PR #596 with Sec GREEN as its own AC11; final merge `1601366`). **The pre-flight recalibration sitting RAN 2026-09-03** ([`docs/records/v14-preflight/sitting-log.md`](docs/records/v14-preflight/sitting-log.md) — 12 rulings, F/CTO direct on R1–R4, delegated on R5–R12; measured 0 of 13 buildable as drafted, same as V1.3): **V1.4's set is now NAMED, not counted — SELF-263 (re-scoped to the §7.28 item 3 inventory carrier) · 259 · 267 · 260 · 262 · 265 · 264 · 266 · 268 · 269**; 259/260/262 promoted in from Platform (R7); 302/303 moved OUT to Platform V1.x (R6); 261 closed unbuilt (R2). Close-gate **SELF-269** LAST. V1.5 (Monthly report) sits in Linear as SELF-345–362 from the rotation; P11 stays in §7 for the next rotation. ⚠ Dispatch runs against the **re-derived ACs** ([`rederived-acs.md`](docs/records/v14-preflight/rederived-acs.md)) applied to Linear in the close-out, never against the Wave-5 drafts. |
| **Next deliverable** | **V1.4 is COMPLETE pending the close-gate merge — `/milestone-rotation`** (V1.final promotes from BACKLOG §7 P11 per ADR-017 D2; V1.5 already sits in Linear as SELF-345–362). All ten V1.4 issues shipped 2026-09-04 under the F/CTO delegation recorded at the head of [`docs/records/v14-execution/log.md`](docs/records/v14-execution/log.md) (E1–E44, every ruling with its losing side; reversal window closes at the close-gate): 263 `e89cc9a` · 267 `a9d4347` · 259 `e4eae27` · 260 `957b6fc` · 262 `346d204` · 265 `26b72c3` · 264 `7c81dda` · 266 `48bbcb7` · 268 `c8b02d5` · 269 `a1d5dc0`; plus the hygiene batch `2c7c8a5`. Also on deck: the CA-2026 schedule seed when FTB publishes (SELF-363) · PM's PRD §2.5.3 amendments (SELF-364: the installment-count definition, rollover copy, the §2.5 staleness question, the copy pass) · the `fn_gl_entries`/`fn_holdings_as_of` volatility pin (SELF-326 — Done in Linear but NOT on the tree; F/CTO to reopen or record the descoping) · a latency probe on `fn_compute_tax_liability` behind every §2.1 read · Sec's re-scoped D19 doc PR (F/CTO ruling OPEN) · the ADR-025 CHECK-vs-WITH-CHECK correction (F/CTO ruling OPEN) · the restore/bulk-load runbook (DevOps) · the ADR-063-citation sweep (§7.31). |
| **Milestone close-gate** | **SELF-269** — the §2.5.5 RLS verification battery. It gates the WHOLE V1.4 milestone, so it is the LAST item (the SELF-244 / SELF-228 / SELF-257 pattern). On its close: V1.final promotes from §7 (P11) per ADR-017 D2. |
| **Issue state** | Read it from Linear, not from here. Both known divergences are RESOLVED by clarifying comments (2026-08-16): **SELF-217** — Done means "outcome discharged by the supervised seeding run," NOT implemented-as-drafted (ADR-040 forecloses the drafted ACs; do not resurrect them); **SELF-236** — built-then-retired-at-`048`; successor = SELF-325. The SELF-217 seeding DATA remains restored (128 rows byte-identical to the preserved run log; [`docs/records/self217-nav-seeding-run.md`](docs/records/self217-nav-seeding-run.md)). |

## Recent activity (last 5 entries)

Convention per [ADR-017](DECISIONS.md#adr-017): last 5 entries; 1 sentence each; **detail lives in the PR, which GitHub keeps.** ⚠ This line used to point at [`CHANGELOG.md`](CHANGELOG.md); that file was frozen on 2026-08-12 and takes no new entries (see [`WORKFLOW.md`](WORKFLOW.md) § Artifact list).

- **2026-09-04 (Phase 6 — V1.4 COMPLETE UNDER DELEGATION: 268 `c8b02d5` (PR #618), 269 `a1d5dc0` (PR #619), the read surfaces 264 `7c81dda` / 266 `48bbcb7`, the hygiene batch `2c7c8a5`)** — the second half of the milestone shipped the same day as the first: the two §2.5 read surfaces over the keystone (a route module that 500'd every request while svelte-check and vitest were green — a framework validator neither tool exercises — now has a watcher over every route module; the quarterly tables render tax money to the cent and carry the prior-year Q4 row through a second gated read), then **the §2.5.4 NAV flip, R3 (A′), walked as the one-way door it is** — migration `105` replaces all four zero literals with `104`'s envelopes carried verbatim (E41: the envelope IS the key, so a consumer's `?? 0` meets an object), the headline moves to the composed reader with the watcher rider 0 named but which did not exist on the tree built in-issue (call-shape + a differing-value inversion), Sec's pre-ruling re-read of R3 found five drifts in the AC block and nineteen pre-conditions, the freeze found the DB-resident sign comment instructing the double-negation it warned against (E44: the ladder now negates all three subtractive rows at one site so the column foots and an overpayment renders as an add-back; negative zero suppressed with rendered-string watchers), the tax CTE materialized after a measured 4→1 evaluation count, and QA re-confirmed the DB chain and rendered strings on the shipped runtime — then the close-gate battery composed over the per-issue batteries and pinned the genuinely-missing cross-tenant legs; two of Sec's four derived render strings were measured (both negative-zero paths), two remain derivations under legs, stated rather than rounded. **Next: `/milestone-rotation` (V1.final from §7 P11).**
- **2026-09-04 (Phase 6 — V1.4 STEPS 1–6 LANDED UNDER DELEGATION; PRs #606 `e89cc9a` · #605 `a9d4347` · #607 `e4eae27` · #611 `957b6fc` · #612 `346d204` · #613 `26b72c3`; log PRs #603/#610 + this)** — F/CTO delegated V1.4 execution end-to-end ("go with your rec … authorized to merge PRs") and six issues shipped in one day through the full loop with every ruling logged and its losing side named (E1–E38): the tax-value inventory delta (`100`), the tax-authority designation + YTD-Paid primitive (`102`), the bracket tables at grain (C) with the deferred set fence and D3 label #18 (`101`), the Federal/CA seed with per-user provisioning (`103`), **the §2.5 keystone reader `fn_compute_tax_liability` (`104`, ADR-067 — Sec AMBER → eight ruled fixes incl. the PRD's "funds due through the NEXT due date" reading → GREEN under an inversion sweep where every struck control had a watcher)**, and the tax-brackets settings editor (walk RED on a post-save reset and a self-undoing delete of a provisioned seed row → the seed set ruled a FLOOR the server refuses to delete → GREEN); the day's catches kept the streak: Sec stopped a "four direct callees" count I wrote from recall (three), Sec caught the 265 branch carrying 262's superseded `104` from a stale integration cut (byte-identity against `main` is now the standing predicate), QA nearly reported a cross-tenant write that was its own shared cookie jar and caught itself by re-verifying identity inline; the npm bulk-advisory outage held four merges for ~3h and was WAITED out (E34: no admin-merge, no fence loosening); two doc records corrected for an inherited ADR-049 mis-citation (E36). **Next: 264 ∥ 266 → 268 → 269.**
- **2026-09-03 (Phase 6 — THE V1.4 PRE-FLIGHT SITTING RAN; findings PR #601 `5ac042d`, sitting log + close-out on `meta/v14-sitting`)** — the ADR-063 protocol-1 pass measured **0 of 13 buildable as drafted** (9 V1.4 + 4 Platform dependencies; V1.3's precedent held exactly) and F/CTO ruled twelve items in one sitting — R1–R4 one at a time (§2.5.1's capital-gains columns render UNAVAILABLE keyed to the missing sale writer; no V1 wash-sale flag with the `basis_adjust` route recorded as the V1.x path; **the NAV composition flip ruled A′ as a one-way door** — tax-adjusted NAV on the two live surfaces only, `nav_daily` stays gross forever, the tax-authority exclusion folded in with one extracted predicate and the composed gap named in copy, Sec's backfill VETO recorded; **the bracket-table grain ruled (C)** so the Decision-3 fence is falsifiable, label allocated at the migration) and R5–R12 by delegation to the team-lead recommendations (263 re-scoped to the inventory carrier over BOTH default tables; 302/303 out to Platform with 262 carrying a named residual; 259/260/262 promoted in; the prior-year Q4 window extended; Unrealized clamps at zero; the `tax_relevant` DEFAULT kept with a scoping comment; unmatched sells ST fail-closed for the record; 268 walks after the read surfaces); the ruled order is Step 1 = the inventory session, F/CTO time.
- **2026-09-03 (Phase 6 — V1.3 COMPLETE + THE FIRST REAL MILESTONE ROTATION; close-gate PR #596 `1601366`, D4 amendment PR #597 `5a6e6ff`)** — SELF-257's 35-leg close-gate battery merged with Sec GREEN as its own AC11 (three AC-text defects clarified on the issue rather than absorbed; the RT-25 legs authored from D19-as-amended with the poisoned source verifiably dodged; the replica-role probe resolved into the merged ADR-011 D4 consolidation amendment + the pg_parameter_acl watcher + a booked restore-runbook), all 15 V1.3 issues verified Done against live Linear, `/milestone-rotation` executed: **V1.4 (Estimated taxes) is CURRENT, and V1.5 (Monthly report) promoted from BACKLOG §7 as SELF-345–362** — 18 issues verbatim-with-links, per-issue verified, §7 annotated, P11 held for the next rotation; recommended first act of V1.4: the pre-flight recalibration sitting, on V1.3's measured precedent.
- **2026-09-03 (Phase 6 — LOOP-MECHANICS A+B LANDED; PRs #593 `50f4e62` + #594 `e2034c4`)** — the F/CTO-ratified process pair executed between the last build item and the close-gate: **ADR-066 + the WORKFLOW Phase 6 light-loop tier** (scoped loop for no-DB / no-money / Sec-not-mandatory issues; the MID-ARC RE-EVALUATION clause is its own decision with SELF-258 as the worked example; the expected-red-header retirement convention beside it) and **the template-DB snapshot tooling** (`pfin_tmpl` + fenced one-command clones under a second; staleness fence = migrations-tree sha + container image id; destructive-path guards) — with the honest measured rationale that the historical sink was per-agent recipe re-derivation, not raw wall-clock; the arc's catches kept the streak alive: Architect caught team-lead's false-composite Gates-header citation, DevOps counter-corrected team-lead's §7.14 mis-read against the live tree, Sec's advisory fetched its own bootstrap baseline and forced the inversion probe that DEMONSTRATED the `--no-privileges` hazard (85 privilege lines dropped — now a committed regression fixture at `scripts/fixtures/`), closing the §7.14 ACL-parity fix half with proof; landing bookings at §7.31 (the 093/094 dormant labeling hazard · 086's sibling fail-open · the malformed ADR-063-citation sweep).
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
