# V1.4 pre-flight recalibration — sitting log

**Baseline: `origin/main` @ `5ac042d`** (2026-09-03, the findings + agenda merge, PR #601). The findings files hold `2cd94ae`; `git diff --stat 2cd94ae 5ac042d -- supabase/ api/ docs/PRD docs/ARCH docs/SECURITY DECISIONS.md` was read at the sitting's open and touches no schema, source, or doc artifact, so every finding carries unchanged.

**Provenance convention** per [ADR-063](../../../DECISIONS.md#adr-063) Decision 3: each entry is marked **F/CTO RULING** or **DEFAULT-AND-NOTIFY** (team-lead, reversal window open until the amendment batch merges). Never flattened.

Agenda: [`sitting-agenda.md`](sitting-agenda.md). Rulings are numbered as there (R1–R12).

---

## Rulings

### R1 — Seam J: §2.5.1's capital-gains columns have no V1 input path · **F/CTO RULING: (A)** · 2026-09-03

**Ruled.** Ship §2.5.1 with the capital-gains section rendering UNAVAILABLE-with-reason; Ordinary Income fully live. Option (B) (pull the manual-sale writer + `lot_match` activation into V1.4) and (C) (PRD amendment to Ordinary-Income-only) not taken.

**Riders adopted with the ruling (Architect, Seam J):**
1. The banner keys on the **structural** fact — no sale writer exists on the tree — not on a `lot_match` row count for the tax year. A row-count predicate reads as "you had no gains" the day the writer lands.
2. The UNAVAILABLE copy names the **missing capability** (recording a sale), not a milestone name.

**Consequences recorded:**
- Sec F-2 (unmatched sell's ST/LT disposition) has **no V1 instance**; it is ruled for the record at R11 and cited at the sale-writer milestone, not built at V1.4.
- §2.5.3's Federal LT-CG bracket walk stays live over `qualified_dividend`-tagged Ordinary contributions (step 4); not dead code.
- SELF-262's §2.5.1 payload carries an explicit `capital_gains: unavailable` shape, never zeros (PM / Sec M-11).
- SELF-269: any battery leg over the CG columns is vacuous under (A); the battery pins the UNAVAILABLE shape instead.
- **The window's closing item is not yet homed.** BACKLOG §7.3 G3 names the manual-sale writer only in its Dependencies; the sentence *"GL-substrate milestone scoping should confirm the manual-sale writer's home (it is a named dependency of §7.3 G3)"* lives in **§7.19's known-pre-sweep-finding note (2026-08-26 securities-edit sitting)**, not in G3. *(Attribution corrected 2026-09-03 after PM's read-back; the quote was right, the location was wrong.)* No milestone is named here because none is assigned; booking carried to §6 of the agenda (Seam J `lot_match` write-enabled-and-unreachable) for the close-out PR.

**Consuming issues:** SELF-264 (CG section) · SELF-266 (LT-CG walk basis) · SELF-269 · SELF-262 AC2.

### R2 — Seam W / G: no user-marked wash-sale flag in V1 · **F/CTO RULING: (A), with (B) recorded as the V1.x path** · 2026-09-03

**Ruled.** V1.4 ships no wash-sale adjustment. §2.5.1's user-marked-flag sentence is amended to: wash-sale treatment lands with the manual-sale writer (the same unhomed item R1 names). Option (C) — build SELF-261's annotation table as handed off — rejected: it would be built against nothing.

**Recorded V1.x path: PM's (B), the `basis_adjust` route.** The user records a dated `basis_adjust` (`reason = 'wash_sale'`, disallowed loss as `cost_basis`) against the replacement lot; SELF-302 posts its P&L (disallowed loss → replacement-lot basis) and becomes §2.5.1 fuel at that milestone. Coherent with [ADR-031](../../../DECISIONS.md#adr-031) Decision 4 (an economic adjustment is a new dated transaction). Costs a `basis_adjust` writer (none exists) and a GL design PM characterizes as *"its own tax-complex mini-design"* (pm-findings Seam W — PM's phrase, attributed there to Sec but appearing nowhere in sec-findings; attribution corrected 2026-09-03 on Sec's drift-check) — both owed at that milestone, not here.

**Sec's placement rider — DORMANT under the ruled `basis_adjust` V1.x path, LIVE at any future user-marked-flag surface (sec-findings §10.4; attachment corrected 2026-09-03 on Sec's drift-check: a `basis_adjust` is a new dated `account_trans` row inside the audited ledger under ADR-031 D4, not an overlay beside it, so the rider has no application to that route).** If a wash-sale mark is ever built, it goes on `pfin.account_trans_annotation` (`023`) as additive columns, not on a new table: the `031` `fn_reclass_history_insert` capture (an ADR-011 D9 DEFINER allowlist entry) is scoped to that one table, so a second overlay would hold income-changing marks mutable and untracked beside audited Sub-Cat reclassifications. A separate table would owe the `031`-equivalent capture in the same migration — a new DEFINER function and a Sec gate. Sec's draft-shape catches on SELF-261 (parent column is `trans_id`, not `id`; a genuine D3 hybrid member carrying its own `users_id` beside `account_trans_id`; `DEFAULT false` semantics owed a `comment on column`) stand for whoever builds it.

**Consequences recorded:**
- **SELF-261 closes unbuilt** (Platform V1.x; not promoted at R7). Its design rationale is preserved as the account of why `023` has its shape — agenda §6 booking; closing comment on the issue cites this entry and the V1.x path.
- **SELF-302 leaves V1.4** (its consumer is the (B) path); placement settled at R6.
- **SELF-264 AC12** (wash-sale exclusion) struck; replaced by the amended §2.5.1 sentence.
- **SELF-262 AC2** `is_wash_sale` clause struck. Sec 10.5c's ordering hazard (262 before 302 = a vanished loss) has no V1 instance under (A) and is cited at the V1.x path.
- **SELF-269 AC8** struck (Architect Seam G: under (A) the leg is struck, not retargeted).

### R3 — Seam E + E-2: the NAV composition flip and the tax-authority NAV exclusion, ruled together · **F/CTO RULING: (A′)** · 2026-09-03 · ONE-WAY DOOR

**Ruled.** PM's A′ (pm-findings A-10, refining Architect Seam E Option A): the tax-adjusted four-component NAV lives on the two **live** surfaces that share one composed value — the §2.1.1 headline and the §2.1.5 foot — composed at read time. ⚠ **Mechanism corrected 2026-09-03 on Sec's drift-check (RED → resolved; see rider 0 below):** the one composed value is **`051`'s buildup over the exclusion-filtered leaf set minus the two tax scalars** — it is NOT `fn_compute_nav`'s value plus tax, because the E-2 exclusion lands in `051`'s leaf set and `fn_compute_nav` is untouched. **The §2.1.1 headline therefore stops reading `fn_compute_nav(asOf, true)` directly (`api/src/lib/server/queries/netWorth.ts:160` at 5d59a4a) and reads the composed value** — the same reader the foot uses. As first written, the entry left the headline on `fn_compute_nav`, which would have retained the exact A-9 double-count E-2 was ruled to fix (pay the IRS $P, headline rises by $P) while the foot did not — Sec §9.1 branch (ii) written up as if branch (i) had been taken. SELF-226's foot-to-headline reconciliation is the watcher that goes red if the headline is left behind; it stays in the battery. The **checkpointed** series (`nav_daily` → §2.1.2 chart / §2.1.3 deltas / §2.1.4 reference dates) stays the gross pre-tax definition **permanently** and is labeled as such. Option (B) (a `nav_definition` discriminator on `nav_daily`) not taken; Option (C) (backfill) **Sec VETO**, recorded, reached independently by Architect (Seam E), Sec (D-4 + §9.4), PM (SELF-268 note).

**E-2 (PM A-9, Architect-verified, Sec-confirmed) ruled in the same act: PM's (A)** — accounts designated as a tax authority's ledger are excluded from the §2.1.5 composition buildup; their effect on NAV arrives through the Realized Tax Liabilities line; §2.5.4 stays net-of-payments as locked. Under (A) an overpayment is a genuine receivable (Realized negative, NAV up by the excess only). The exclusion lands in **`051`'s leaf set only** (Architect round-2 rider i); `fn_compute_nav` is not touched.

**Riders adopted:**
0. **The headline and the foot read ONE composed value from ONE reader** (`051`, or a thin reader over it); no surface composes its own. `fn_compute_nav` keeps its gross definition, keeps writing `nav_daily`, and is read by no live surface. *(Added on the drift-check correction above.)*
0b. **The exclusion's DEFAULT state is the bug** (Sec §9.1 item 1, carried verbatim in substance): the exclusion is gated on a nullable, user-set attribute, so an **unmarked** IRS account is simultaneously excluded from YTD Paid (Funds Due **overstated**) and included in the buildup (NAV **overstated**) — the two halves fail in opposite directions from one omission, and neither number visibly contradicts the other. Consequence: the designation is part of the SELF-267 walk (mark → both figures move together), and the §2.1.5 rendering of the exclusion (rider 6) is what makes an unmarked ledger visible as "not excluded."
0c. **One account per jurisdiction per user is enforced, not assumed** (Sec F-1 live caveat, X-1): nothing in a nullable `account.tax_jurisdiction` column prevents two accounts marked `'irs'`, and a YTD-Paid sum over both double-counts → Funds Due understated → Realized understated → **NAV overstated**. **DEFAULT-AND-NOTIFY (team-lead): the partial unique index `unique (users_id, tax_jurisdiction) where tax_jurisdiction is not null` ships in SELF-267's migration**, matching the PRD §2.4.2 text PM landed in the same close-out ("one account per authority per user"). The alternative — declaring multi-account-per-jurisdiction legal — is not taken; reversal window open until the amendment batch merges.
1. **One extracted predicate** — `tax_jurisdiction is not null` — stated once, shared by the §2.1.5 exclusion and the §2.5.3 YTD-Paid designation ([ADR-063](../../../DECISIONS.md#adr-063) Decision 2). Zero copies.
2. **The composed gap is named in copy** (Sec §9.1, re-aimed): with rider 0 the headline and foot agree by construction, and the gap that needs copy is **headline/foot vs the checkpointed chart** — **both tax lines PLUS the designated ledgers' balances**, not "tax only." Sec's §9.1 stated the gap as headline-vs-foot under the un-corrected mechanism; rider 0 collapses that gap to zero and moves it to the chart boundary. PRD §2.1.2 basis sentence per A-10 is drafted against the composed gap; §2.1.3/§2.1.4 by pointer.
3. **`051`'s `comment on function` is rewritten** in the same migration: it currently asserts `nav = … = fn_compute_nav(p_as_of, true)`, an identity this ruling deliberately breaks (Architect round-2 rider i). The `V1.4 ramp` literal comments go with it (Sec catch 4).
4. **Same as-of date, one request**: both functions take the one `fn_server_today()` value threaded through (Seam C; Architect rider ii).
5. **All four layers demonstrated on one walk, one session** (Sec §9.4 item 5): `051` emits ≠ 0 · `nav-composition.ts` drops `isTaxPlaceholder` · `NavCompositionTable.svelte` renders `displayValue` not a literal zero · the browser figure matches the DB value. Part 3 is Frontend's and is the silent one.
6. **Rendered, not just applied** ([ADR-049](../../../DECISIONS.md#adr-049)): the exclusion is visible on the §2.1.5 surface, and the §2.1.2 chart names its gross basis.
7. **Volatility declared explicitly** in the replacing `051` migration, per signature (`051`/`049` default VOLATILE today; a `stable` caller of a `volatile` callee is an unbacked promise).

**Consequences recorded:**
- **SELF-268 AC1** rewritten against A′ (as drafted it puts the tax leg into `fn_compute_nav` → `nav_daily`). **AC4 struck**, not softened — Sec D-4's benign second reading (that *"the chart recomputes from live inputs and therefore 'back-fills' visually"*, sec-findings D-4) is also out, because the trajectory is not recomputed at all. AC5 minus the trajectory. **AC1 also moves the §2.1.1 headline's read source to the composed reader** (rider 0).
- **SELF-267 AC2a**: the designation is the exclusion hook; cites rider 1.
- **SELF-262 AC12**: the helper's two scalars compose into `051`'s foot at read time. Sec 10.5e's `nav_daily` SELECT-policy obligation attaches to **whichever object reads `nav_daily` under INVOKER**; per the re-derived SELF-262 AC1 the helper does NOT read `nav_daily` (Unrealized reads through `049`), so the obligation sits on the §2.1.5 read-time path at `051`, and a `nav_daily` read inside the helper would be an AC1 change routed back to Sec (Architect close-out item 2, accepted).
- **The trajectory carries no step** at changeover under A′: `nav_daily` freezes `fn_compute_nav(current_date, true)` (`054` at :419/:463; the ETL worker reads the same source), and A′ leaves `fn_compute_nav` untouched, so the checkpoint definition never changes. Sec §9.1 stated its step consequence **unconditionally** ("whenever the A-9 exclusion lands…"); it is **voided** here by the mechanism, not qualified in Sec's text. *(Wording corrected 2026-09-03 on Sec's (a).)*
- Not light-loop eligible ([ADR-066](../../../DECISIONS.md#adr-066) D1 b); Sec joint-review MANDATORY; walk-gated before the Sec spawn.

### R4 — Seam A: bracket-table storage grain + the Decision-3 sub-part · **F/CTO RULING: (C)** · 2026-09-03 · ONE-WAY DOOR (sub-part)

**Ruled.** Two tables as Lock 14 names them — `pfin.tax_bracket_schedule` (parent: `users_id`, jurisdiction, schedule kind, `tax_year smallint`, standard deduction, …) + `pfin.tax_bracket_row` (child: rate, lower bound, …) — with the child carrying **its own `users_id` beside `schedule_id`**. The fence is the `012`-shape local-anchor pattern (P1): two tenant facts exist, can disagree, and the matched-tenant trigger asserts their agreement — a fence that can fail (Sec §9.3: *"C is the only grain whose fence is falsifiable"*). Option (A) (child references parent only) not taken — under it the row is NOT a D3 member and a matched-tenant fence would be a leg that cannot fail (ADR-062 D2's rejected shape). Option (B) (single denormalized table) not taken — the standard-deduction scalar has no home and Lock 14's enumeration would need amending.

**Decision-3 disposition.** `tax_bracket_row` is a genuine [ADR-011](../../../DECISIONS.md#adr-011) Decision 3 family member under (C). **One canonical label is allocated AT the SELF-259 migration** per D18's amendment (*"none may be drafted in advance"*); SELF-259's drafted *"(4th instance)"* ordinal is **STRUCK**. The migration header states which grain it built. D18's locked *"NOT a new instance… settings writes are user-session-bounded"* clause argued from the write path; D3 turns on column shape (Architect + Sec independently). The **tail** of that D18 sentence — the V2+ live-tax-API ingestion trigger, the mandatory Sec re-consult at that adoption, the Lock 12 mod #2-pattern fence going V1-SHIP-BLOCK then — is untouched and live.

**Riders adopted (Decision 18 unamended, carried by citation):** `tax_year smallint` from day one · UPSERT-in-place with `updated_at`, no edit-history rows (settings are not audit-class) · no JSONB blobs in the settings store under any future surface · schedule+rows replace-all under SERIALIZABLE · strict typed-input validation + the numeric-input adversarial battery · `fn_refresh_updated_at()` trigger.

**Riders adopted (this pass):**
1. **Monotonicity trigger re-shaped** to a deferred `CONSTRAINT TRIGGER … AFTER INSERT OR UPDATE … DEFERRABLE INITIALLY DEFERRED` (or a statement-level AFTER check): the drafted BEFORE ROW form cannot see later rows in the same multi-row INSERT and passes a non-monotone batch (Architect Part B AC5; Sec §3 trap 1). *Default-and-notify item, confirmed here.*
2. **SERIALIZABLE does not guarantee monotonicity** (Sec D-5): the two controls are independent; SELF-259 AC6's companion claim struck.
3. **`025` aal2 step-up backstop** on both tables' `authenticated` policies; `025`'s `user_settings` exclusion does not generalize to siblings.
4. **`{schedule_id}` path parameter** is a client-supplied object reference: `users_id` from `auth.uid()`, never from the request; the replace-all is scoped to the caller's own schedule or refuses.
5. `bigint generated always as identity` PKs, not `SERIAL`/`INT` (repo idiom; Architect Part B AC1/2).
6. SELF-259 AC3 raised to the `090` policy standard — USING + WITH CHECK, per verb, grants. *Default-and-notify item, confirmed here.*
7. QA two-tenant pgTAP battery in the same PR, including the adversarial leg that makes the matched-tenant fence go red (a cross-tenant `schedule_id` under a forged `users_id`).
8. **Sec §10.2 items 3–5, elevated here so a builder reading only the log sees them:** two-sided NaN CHECKs on all three numerics (`standard_deduction`, `bracket_floor`, `bracket_rate` — a one-sided `>= 0` admits NaN, per `090`); a unit + domain CHECK on `bracket_rate` with the unit stated in words in its `comment on column` (M-7: `22` vs `0.22`); and a constraint forcing the lowest `bracket_floor` of every schedule to zero — monotonicity cannot catch a schedule starting at 11000, which taxes the first $11,000 at zero silently. ⚠ The zero-floor property is a **set** property like monotonicity: a per-row BEFORE trigger cannot observe it either, so it takes the same deferred CONSTRAINT TRIGGER / statement-level AFTER form as rider 1 (Architect close-out item 4).

**Consuming issues:** SELF-259 (lands Seam A; allocates the label) → SELF-265 (settings editor) · SELF-262 (walks the schedules) · SELF-268 (reads the two top-bracket rows) · SELF-269 (battery). Sec joint-review MANDATORY before locking the DDL.

> **Provenance for R5–R12.** F/CTO, 2026-09-03, after R4: *"go with your recs for the remaining questions."* Each entry below is an **F/CTO RULING BY DELEGATION** — F/CTO adopted the team-lead recommendation presented (R5) or to be presented (R6–R12) rather than choosing among options one at a time. The recommendation's reasoning is team-lead's; the ruling is F/CTO's. Not default-and-notify: no reversal window applies beyond the ordinary one on any ruling.

### R5 — SELF-263 re-scope · **F/CTO RULING BY DELEGATION: (A)** · 2026-09-03

**Ruled.** SELF-263 is re-titled to carry the **BACKLOG §7.28 item 3 tax-value inventory session and its outcome-recording seed-delta migration**, first in the dispatch order. Its drafted migration deliverable already shipped: `pfin.tax_character` registry table at `011` (Option C hybrid over an enum), `tax_relevant`/`tax_character` on `user_taxonomy` at `009`, bootstrap values at `041`, cash-flow vocabulary on `posting_prototype`/`posting_prototype_default` at `084` ([ADR-058](../../../DECISIONS.md#adr-058)), disjointness from `is_tax_payment` at `091` ([ADR-062](../../../DECISIONS.md#adr-062)). Option (B) (close + fresh issue) not taken: the booking would be homeless in the interval Sec F-6b flagged. Option (C) (build as drafted) rejected on the tree: a second competing `tax_character` vocabulary beside `011`.

**Scope of the session — BOTH default tables** (PM §4 AC1): every `pfin.posting_prototype_default` row's `tax_relevant`/`tax_character` (cash-flow side) **and** every `pfin.taxonomy_default` row's (asset side, all `false`/NULL at `041`). Decisions the session must produce, each with its reason (PM §4 AC2): (i) `Equity / Contribution` per account type (ADR-062 D4's notes rider; `true` today is flag-for-review, not a determination); (ii) `Revenue / Bond Premium` = `ordinary` and `Revenue / Dividend` = `qualified_dividend` confirmed or corrected — the two with the largest §2.5.2 routing consequence (Architect Seam H); (iii) the asset-side marking principle stated once; (iv) `long_term_capital_gain_eligible` / `short_term_only` assignments on the asset side. ⚠ **Under R1-A the asset-side outcome has no V1.4 consumer** (the CG half renders UNAVAILABLE); it is decided in the same session because it is the same F/CTO act and the seed delta is cheap, and it is recorded here as **not on V1.4's critical path**.

**Consequences recorded:**
- **SELF-264 gains a hard-gate AC** citing SELF-263 (ADR-062 D3 shape: a sequencing commitment lives in the consumer's ACs, not only in the backlog entry — Architect Seam H). Nothing in the schema prevents §2.5.1 shipping against unaudited values.
- Sec **F-6b** discharged by construction (owner + slot). Sec **M-5** stands as a separate residual (R10 constrains the column, not the reader).
- `BACKLOG.md` §7.28 item 3 widened to the asset-side rows (agenda §4).
- A clarifying comment on SELF-263 records what shipped where, so the history is not lost under the re-title.
- Sec joint-review at the implementing PR if any DDL results; the seed delta is a money-input change and routes to Sec regardless.

### R6 — Seam I + SELF-302/303 placement · **F/CTO RULING BY DELEGATION: (A)** · 2026-09-03

**Ruled.** SELF-302 (`basis_adjust` `wash_sale` P&L) and SELF-303 (substantive `corp_action` GL) **move to Platform / Cross-cutting V1.x**. Neither traces to a §2.5 story; both arrived by the `037` deferral note. Under R2-A, SELF-302's only §2.5 consumer is the recorded V1.x `basis_adjust` path; its return trigger is **"returns to the tax milestone if the V1.x wash-sale path is dispatched."** SELF-303's tax treatment is unspecified in the PRD (its corp-action surface is §2.4.3 / [ADR-033](../../../DECISIONS.md#adr-033)). Option (B) (keep in V1.4 at step 5) not taken.

**Seam I disposition: SELF-262 lands first and carries an explicit named residual**, in the migration header and the issue AC, in `093`'s shape (*"Recorded so a reader does not conclude the case is handled"*): while `wash_sale` `basis_adjust` and substantive `corp_action` remain Suspense-parked at `035`/`037`, `cost_basis` is understated → `049` `unrealized_gl` overstated → §2.5.4 Unrealized overstated; the disallowed loss is unrecognized on §2.5.1. ⚠ Under R1-A the §2.5.1 half has no V1 instance (no sale, no `basis_adjust` writer — PM: the Suspense parking's domain is EMPTY today), so the residual is currently vacuous on the tree and is recorded so it does not become invisible when the writers land. The rejected third state — SELF-262 with no residual — is named so it is seen to have been weighed.

**Rider (Sec D-6):** SELF-303's non-blocking test-durability rider (co-located aal2 pass/block assertion on the `037` battery) survives the move verbatim; if ever dropped, dropped explicitly. Both remain joint-review-mandatory money-flow migrations wherever they run.

### R7 — Platform-lane promotion · **F/CTO RULING BY DELEGATION: (A)** · 2026-09-03

**Ruled.** **SELF-259, SELF-260, SELF-262 promote into V1.4** (the V1.3 SELF-245/246/247 precedent). **SELF-261 stays in Platform and closes** per R2. V1.4's set is now **named, not counted**: SELF-263 · 259 · 267 · 260 · 262 · 265 · 264 · 266 · 268 · 269 (ten; SELF-302/303 out per R6; SELF-261 out per R2). Per-issue grounds (Architect §5a): 259 carries a milestone ruling (Seam A) and a D3 extension, and seven downstream ACs cannot be written until its column names are fixed; 260 is the first exercise of 259's monotonicity trigger — splitting lanes separates a fence from its first test; 262 is the keystone five of seven §2.5 issues call first, where Seams B/C/E/F/I converge, and the ADR home for two undocumented Gate ratifies. Option (B) (keep in Platform) not taken.

**The losing side, named (Architect):** Platform is always in Linear under [ADR-017](../../../DECISIONS.md#adr-017) D2, so promotion buys **ownership clarity and a close-gate that sees its substrate**, not access or throughput. It is a scope change and is F/CTO's — ruled here.

**Consequences:** `MILESTONES.md` Active Feature row names the set and drops the count (also fixes Sec F-7's SELF-264 omission). Linear labels move via the liaison at the close-out.

### R8 — Sec F-4: the prior year's Q4 between Jan 1 and Jan 15 · **F/CTO RULING BY DELEGATION: (B)** · 2026-09-03

**Ruled.** **Extend the §2.5.3 render window**: between Jan 1 and the Federal Q4 due date, the tables also show the prior tax year's Q4 row (obligation, YTD Paid, Funds Due) until it is paid or the date passes; the current year's table is otherwise unaffected (PM A-12 wording, adopted). ONE answer for SELF-266 and SELF-267, same date boundary. Option (A) (accept the gap) not taken: it records a known-wrong `$0` in the two weeks the user most needs the number. Option (C) (tax-year cursor) out of proportion to V1.

**Riders:** YTD Paid is the **account-ledger balance as-of** (Seam B Option A, PRD-verbatim, presupposed by the already-ruled Gate B Option A `tax_jurisdiction` enum — NOT re-opened), so the Jan-15 hazard for YTD Paid dissolves; the F-4 window is about the obligation row only. The date boundary is computed in **one place** — `fn_compute_tax_liability` (SELF-262) — and cited by 266/267 ([ADR-063](../../../DECISIONS.md#adr-063) D2). ⚠ Sec M-4's UTC-pin year boundary (a Pacific user flips year ~7h early) is broader than §2.5 and stays **unowned** — agenda §6 booking.

### R9 — Sec F-3: does Unrealized Tax Liability floor at zero? · **F/CTO RULING BY DELEGATION: (A)** · 2026-09-03

**Ruled.** **Clamp at zero.** §2.5.4 defines Unrealized as *"the estimated tax that would be owed"*; a tax that would be refunded is not that, and the V1 boundary already calls the figure *"an LT-aware floor estimate"* (PM). A negative value would inflate NAV through `051`'s subtraction by an unrealized, capital-loss-capped, possibly-never-realized benefit (Sec). Option (B) (allow negative) not taken; Option (C) (clamp + informational "unrealized loss carry" note) not taken for V1 — bookable at §5 if a user asks.

**Consequence:** SELF-268 AC6 carries the clamp; the battery pins it with a negative-aggregate-G/L fixture (the leg that goes red if the clamp is dropped); **and the `comment on function` states why the clamp exists, so a later reader does not "restore symmetry" by removing it** (Sec M-2, paired requirement — carried on the drift-check).

### R10 — Sec F-5: `tax_relevant DEFAULT false` · **F/CTO RULING BY DELEGATION: (A)+(C)** · 2026-09-03

**Ruled.** **Keep the DEFAULT; fence at the consumer; add a `comment on column` scoping what `false` means** — *"not marked / not yet inventoried"*, never *"examined and found not tax-relevant"* — exactly as ADR-062 did for `is_tax_payment`. PM + Sec agree (Sec §9.2: *"No daylight on the ruling"*). Option (B) (drop the DEFAULT ADR-062-style) not taken: the DEFAULT is load-bearing for the provisioning INSERT and a narrowing change breaks every fixture seeding the barred value.

⚠ **Residual, stated so "Sec agrees with F-5" is not read as clearing M-5 (Sec §9.2):** this constrains the **column**, not the **reader**; the stored values are made right only by R5's inventory session. SELF-263 carries the comment migration alongside the seed delta.

### R11 — Sec F-2: an unmatched sell's ST/LT disposition · **F/CTO RULING BY DELEGATION: (A), ruled for the record** · 2026-09-03

**Ruled.** **Route to ST / ordinary, fail-closed on tax** (overstates rather than understates), with the row footnoted *"holding period unresolved — treated as short-term"* (PM). Sec + PM lean. Option (B) (UNAVAILABLE-with-reason, excluded from totals) not taken; Option (C) (route to LT) is the only one that understates tax silently — not taken.

**Standing:** under R1-A this has **no V1 instance** (no sells, matched or unmatched). Ruled now so the sale-writer milestone cites it rather than re-deriving it; written into SELF-262 AC2 as a dormant clause with this entry as its citation. `lot_match` carries no `users_id` — tenancy inherits through two `account_trans` FKs (Architect Seam G); any future §2.5.1 reader honors that rather than assumes it. **Two mechanics travel with the disposition (Sec M-1 second half + §4 SELF-264 item 1), so the citing milestone gets the rule with what makes it correct:** apportionment is **per `lot_match` row, not per transaction** — one sell can match buys on both sides of the one-year line; and the holding-period `LEFT JOIN` NULL is tested for NULL **before** any membership test (the shipped 099 pattern).

### R12 — Ordering: SELF-268 after the two read surfaces · **F/CTO RULING BY DELEGATION: accept** · 2026-09-03

**Ruled.** SELF-268 (the NAV composition flip) runs **after the two read surfaces** (SELF-264 ∥ SELF-266), not immediately after SELF-262. The agenda numbered this step 9 with SELF-302/303 holding step 5; with those two out per R6 the ruled order below renumbers and 268 is **step 8**, 269 step 9. *(Step number corrected 2026-09-03 on Architect's read-back; the ruled-order block is authoritative.)* Not a dependency; a walk-order judgment shared by Architect and PM: walk the legible tax surfaces before the flip moves the headline, so the walker sees the components before the composed figure changes.

---

## Default-and-notify items — TAKEN by team-lead, reversal window open until the amendment batch merges

Each was listed on the agenda; none was objected to at the sitting. Recorded with provenance **DEFAULT-AND-NOTIFY**, not as rulings.

1. `tax_authority` (PM copy) vs ratified `tax_jurisdiction` (schema): schema wording governs identifiers; the product phrase is kept for user-facing strings.
2. SELF-266 AC7's false-composite citation: SELF-261 → SELF-265.
3. SELF-269: AC8 struck (R2); AC6's *"SERIALIZABLE guarantees integrity"* struck (Sec D-5); AC4's `tax_deferred`/`tax_free` literals → `003`'s underscore forms.
4. SELF-267: `p_users_id` dropped from the INVOKER signature (SELF-211 precedent; Sec D-2 (i); SELF-262's own correct shape); **`p_jurisdiction` typed as `pfin.tax_jurisdiction_enum`, not `TEXT`** — an unknown jurisdiction is a type error at the boundary, not a silent zero-row `$0 YTD Paid` that overstates Funds Due (D-2 (ii), the RT-25 parameter-bypass shape on a new surface); **and the function's `comment on` states what a payment IS** — sign convention and the disposition of a refund, an inbound transfer, and a correction row (D-2 (iii), M-3).
5. SELF-259: monotonicity trigger → deferred CONSTRAINT TRIGGER (confirmed at R4 rider 1); AC3 → the `090` policy standard (R4 rider 6); `bigint … identity` PKs (R4 rider 5).
6. SELF-260 AC5's *"no Sec joint-review"* struck — Architect + Sec both route bracket rates to joint-review as financial-calculation inputs.
7. SELF-262 AC2: *">365 days → LT"* corrected to *"more than one year"*; EXECUTE ACL pair (`revoke … from public; grant … to authenticated`) + `set search_path = ''` + an explicit volatility declaration added.

---

## Ruled dispatch order (agenda §5, with R6/R7/R12 applied)

```
Step 0  the sitting (R1–R12)                                    ✅ 2026-09-03
1       SELF-263 re-scoped: inventory session + seed delta      ∥ 2 and 3
2       SELF-259 bracket tables (Seam A → R4; label allocated)  ∥
3       SELF-267 YTD-Paid overlay + Gate A/B ADR fold-in         ∥
4       SELF-260 seed                                            after 2
5       SELF-262 fn_compute_tax_liability — keystone, named residual (R6)   after 1,2,3,4
6       SELF-265 brackets settings editor                        after 2,4
7       SELF-264 ∥ SELF-266 — the two read surfaces              after 5 (6 for 266's Edit target)
8       SELF-268 NAV composition flip (R3)                       after 5, 7
9       SELF-269 RLS battery — close-gate, LAST                  after all
```

SELF-302/303 → Platform V1.x (R6). SELF-261 → closes (R2). Every issue Sec joint-review MANDATORY; every user-facing one walk-gated before the Sec spawn ([ADR-063](../../../DECISIONS.md#adr-063) D4). Step 1 is F/CTO time: the inventory session is a sitting, not a dispatch.

---

## Post-sitting: Sec brief-drift-catch (2026-09-03, read-only, on 5d59a4a) — verdict RED → resolved in place

Sec ran the brief-drift-catch on this log against its own findings. Verdict **RED on R3** (drift that changed a one-way-door ruling's meaning), flags on R2 / R9 / R11 / DN-4 / X-1, note on R4, CLEAN on R1 / R5–R8 / R10 / R12. Every item is corrected **in place above**, each marked with its correction date, rather than in a corrections appendix — a reader of R3 must not be able to read the uncorrected mechanism. Summary of what moved:

| Entry | Drift | Correction |
|---|---|---|
| R3 | Headline left on `fn_compute_nav` while the foot carried the exclusion — the two "live surfaces sharing one value" would not share it, and the headline would keep the E-2 double-count | Rider 0: one composed reader for both; headline read source moves (SELF-268 AC1). Rider 2 re-aimed to the chart boundary. §9.1 item 1 carried as rider 0b. D-4 quote replaced with Sec's words. (a) wording corrected: the step is voided by `nav_daily` freezing `fn_compute_nav`, not qualified in Sec's text. |
| X-1 | F-1's live caveat (two accounts marked `irs`) absent | Rider 0c: partial unique index in SELF-267, default-and-notify, reversal window open. |
| R2 | A PM phrase attributed to Sec; the placement rider attached to the wrong route | Attribution corrected; rider marked dormant under `basis_adjust`, live at any user-marked-flag surface. |
| R4 | §10.2 items 3–5 not visible from the log | Rider 8. |
| R9 | M-2's comment-on rationale dropped | Carried. |
| R11 | M-1's per-`lot_match`-row apportionment and NULL-before-membership dropped | Carried. |
| DN-4 | D-2 (ii) and (iii) absent | Carried. |

Sec's standing-list verdict, quoted: *"Nothing in R1–R12 crosses my standing veto list… R3 is a flag, not a veto — it needs its wording resolved before SELF-268 dispatches."* Resolved above; Sec re-reads at the SELF-268 pre-ruling.
