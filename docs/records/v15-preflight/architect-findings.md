# V1.5 pre-flight recalibration — Architect findings (round 1)

**Baseline.** `origin/main` @ `b90b846bdfc243d7235df59083d98708e6ce1eb4` (2026-09-04, post V1.4→V1.5 rotation). Every identifier, signature, route, file path and workflow cited below was grepped or read at this sha in this session. `origin/main` had not moved at authoring (`git rev-parse HEAD` == `git rev-parse origin/main`).

**Issue text.** `temp/v15-preflight/issue-dump.md`, md5 `b6f9e76c3420534d10378f2426298409` (verified before use). Spot-checked against `BACKLOG.md` §7.1 (A-item titles) and §7.2 (P2/P3 bodies): **the dump and the promotion source agree**; no divergence found on the entries checked.

**§10 three-axis cross-check.** ADR-011 Decision 4 read verbatim at this sha before drafting. This file **touches the ledger by reference only — Path B, linked not restated**; it carries **no ledger count and no ledger enumeration**. One finding below (F-6) concerns an *instance-numbering* drift in a drafted AC and is stated as "the AC's claim is falsified by Decision 4 read live", not by restating the ledger. ⚠ The **catalogued** set and the **CI-fenced** set are different sets and are not reconciled anywhere in this file.

**ADR-011 Decision 3.** Read live at this sha. No family tally is stated here. The two `monthly_report`-family labels are **already allocated** and are named below by their canonical labels, because the drafted ACs allocate *different* ones — that is the finding, not a count.

**Scoping of "buildable as drafted."** An issue is buildable as drafted when (i) every schema identifier, function signature, route, worker and workflow its AC names either exists at this sha or is legitimately new; (ii) the AC contradicts no ratified Lock or ADR ruling; and (iii) no unresolved seam sits between the AC and a Backend/Frontend engineer starting work. Failing any one is *not* a judgement that the issue is wrong — most fail on (ii) or (iii) and are repaired by the replacement text in `rederived-acs.md`.

**Verdict: 4 of 18 buildable as drafted** — A8 (SELF-352), A9 (SELF-353), P7 (SELF-359), P9 (SELF-361). **1 more (A6 / SELF-350) should close rather than build — its deliverable is already on the tree and wired into CI.** The remaining 13 need AC amendment; **6 of those are blocked behind a ruling** (S-1 or S-2).

---

## 1. Seams — schema-level decisions the drafts assume and the tree does not settle

### S-1 ⚠ ONE-WAY DOOR — the monthly report is specified as a *frozen rendered artifact* and architected as a *read-time recomposition*. These are not the same thing and on this schema they cannot be made the same thing.

**The claim about the tree (measured).**

PRD §2.6.4 φ-1, verbatim at this sha: *"later views of the 'April 2026 report' show the values that rendered the day April 2026 was generated, not current-state values that would re-compute today"*; and its Snapshot shape commitment: *"Each per-report snapshot persists the rendered values for all six §2.6.1 sections … The snapshot is **rendered-value level**, not source-data-level."*

ADR-011 Decision 15 / Lock 11 locked **Option B — minimal report-identity table + composition at read time**, in 2026-05, naming a join set (`holdings_checkpoint` + `eod_price` + `account_trans` + `tax_character` + `pfin.nav`) of which **`pfin.nav` does not exist at this sha** (the tree carries `pfin.nav_daily` plus `fn_compute_nav` / `fn_nav_composition`). Lock 12 locked the snapshot child at **three columns** — `(monthly_report_id, account_id, acct_name_at_generation)`.

Read-time recomposition **cannot reproduce four of the six §2.6.1 sections** for a past month on this schema, and each reason is structural, not a preference:

1. **Asset Allocation (§2.2.2).** Its `% Target / $ Target / $ ReAlloc` columns derive from `pfin.planning_target` (`074`). ADR-011 Decision 18 / Lock 14 locks the settings store as *"UPSERT-in-place + `updated_at`; **no edit-history rows** (settings NOT audit-class)"* — reaffirmed unchanged by the 2026-08-16 family-size amendment. **A `%Target` edited today silently rewrites every historical report's Asset Allocation section.** There is no as-of read of a settings row because there is no history to read.
2. **Estimated Taxes (§2.5.1/§2.5.3).** `fn_compute_tax_liability` (`104`) resolves a schedule to *the current-year schedule if present, else the latest prior-year one*, off `tax_bracket_schedule` / `tax_bracket_row` (`101`) — also Lock 14 UPSERT-in-place, also no history. Same failure, plus `basis_year` shifts underneath the reader.
3. **Account Holdings (§2.1.5), tax lines.** `fn_nav_composition` (`105`) subtracts two tax envelopes carried verbatim from `fn_compute_tax_liability(p_as_of)`. **The ruling:** [ADR-067](DECISIONS.md#adr-067) Decision 3, verbatim — *"**Option C** (backfill the series) carries a recorded **Sec VETO**, reached independently by Architect, Sec and PM."* **The rationale, in its own home:** migration `105`'s `comment on function` — *"the tax state for a past date is not recoverable, so a back-fill would be a fabrication with the shape of a measurement (Sec veto, recorded at ruling R3)."* Recomposing a past month's §2.1.5 tax lines from today's ledger designations and today's schedules **produces exactly the artifact that veto covers**, arrived at by a different route.
   - ⚠ **Citation-form correction, and the error was mine** (Sec **N-1**; verified independently here — `grep -c 'fabrication with the shape of a measurement' DECISIONS.md` returns **0** at `b90b846`, and the string lives in `105` plus `docs/records/v14-*`). Round 1 presented that sentence as **ADR-067 Decision 3's own words**. It is not: the *ruling* is the ADR's and was correctly attributed; the *rationale wording* is `105`'s comment and the V1.4 records, which are not canon. **Right ruling, wrong pointer** — the ADR-011 Decision 4 PR #476 class, committed by me. Corrected above and in the Architect memory entry that had inherited it. ⚠ **This sentence must not enter a V1.5 migration header or the §9 consolidated ADR as a quotation *of ADR-067*.** If the wording is wanted in canon, promote it into the ADR deliberately.
4. **Category labels across every section.** Migration `082` renamed the asset-domain Cat `Equity` → `Marketable Securities` (ADR-058 Decision 7, F/CTO 2026-08-18). A pre-`082` month recomposed today renders the new label on a report the user archived under the old one. That is benign this once and is the general shape of the problem.

Lock 15's dual-column filter (`transaction_date <= D and created_at < (D+1)`) genuinely reproduces `account_trans` as-of, so **Cash Flow and the gross half of Account Holdings do recompose faithfully**. The failure is not total — which is precisely why it will not announce itself.

**Where it surfaces in the drafts.** A3 (SELF-347) is a pure read-composition helper with a `p_data_as_of` parameter and no persistence. A2 (SELF-346) stores per-account rows, not rendered values. P2 (SELF-354) asserts *"historical reports immutable post-final per Lock 11 mod #2"* — but Lock 11 mod #2's immutability is a property of the **row**, and **no component in the arc freezes the rendered values the row's immutability is being invoked to guarantee.** P2 asserts a property nothing in A1–A3 delivers.

**Why it is a one-way door.** Once reports ship and users archive them, the answer cannot be changed without either (a) admitting archived reports were never frozen, or (b) a migration that manufactures the rendered values for months whose settings history was never recorded — unrecoverable by construction, and the same fabrication ADR-067 D3 vetoed.

**Options.**

- **Option A — freeze the rendered payload.** A3 composes as drafted; its JSONB return is written **once, at finalization**, onto the header (a `rendered_payload JSONB NOT NULL` column, or a payload child) and every subsequent read of a `final` report reads the stored payload. A2 keeps Lock 12's per-account rows as the queryable index over the frozen artifact. *Buys:* φ-1 satisfied literally; ADR-067 D3 honored (a stored past value is a measurement, not a fabrication); the PDF and the in-app view provably agree because they read one artifact; §2.6.5's live-staleness carve-out still works, because staleness is read live by design. *Costs:* a JSONB payload column on a `pfin` table, and the header table's row size grows with report count. *What it makes harder later:* the payload's internal shape becomes a compatibility surface — a §2.1.5 rendering change must keep reading old payloads. Mitigable with a `payload_schema_version SMALLINT`, which `nav_daily` conspicuously lacks and pays for (ADR-040 / ADR-067 D3).
  - ⚠ **This does not touch Lock 14's no-JSONB-blobs forward-compat fence.** That fence governs the **settings store**; `monthly_report` is not a settings table. The `101` amendment already draws this exact line for `p_rows jsonb`. Recording it because a reader meeting JSONB near a Lock 14 sentence will otherwise re-litigate it.
- **Option B — narrow the PRD commitment to live-recompute-as-of.** Keep A1–A3 as drafted; amend §2.6.4 φ-1 to promise *"the report as-of that date, recomputed"* rather than *"the artifact as it shipped."* *Buys:* no new storage, no payload-compat surface, smallest diff. *Costs:* it discards the parity anchor §2.6.4 rests on (*"parity-exact with existing-system Finance_Report PDF behavior"*), and it does not actually work — §2.2.2 and §2.5 have **no as-of read at all**, so the promise would be false the day a user edits a target. *What it makes harder later:* nothing recoverable; the observations are simply never taken.
- **Option C — hybrid: freeze what cannot recompute, recompose the rest.** Store the four unrecoverable sections' rendered values; recompute Cash Flow and the gross §2.1.5. *Buys:* smaller stored payload. *Costs:* two render paths that must foot to each other, and a per-section boundary that has to be defended in every future change to any of the six sections. *What it makes harder later:* every new §2.x surface must be classified into one of the two halves, forever, by someone who may not know the classification exists.

**Lean: Option A.** It is the only one that makes the PRD's own words true, and freezing a payload is a well-understood pattern rather than a novel one. **The losing side, named:** Option A pays a real and permanent cost — the payload shape becomes a versioned compatibility surface, and a future §2.1.5 change will have to keep rendering payloads written under an older shape. Option C avoids that for two of six sections. If F/CTO weights payload-compat above render-path unity, C is defensible; B is not, because its central promise is unsatisfiable on this schema.

> **⟳ Round-2 update — PM CONCEDES to Option A** (`pm-findings.md` @ `77425b3` §12.3, PM's own id **A-5**). PM's earlier (B) — freeze the history-less *inputs* and re-run composition — is, in PM's words, *"Architect's Option C with inputs where he has outputs"*, and inherits C's cost. **PM also names a case (B) cannot catch at all: the `082` Cat rename** — labels are not settings, so an input-freeze does not stop an archived report re-labelling. PM's product ground is that PRD §2.6.4 says *"rendered-value level"* verbatim and the parity anchor is a PDF. **A-5's proposed φ-1 exception wording is withdrawn; under Option A the PRD amendment is a pointer, not a rewrite — φ-1 becomes true as written.**
>
> **PM's rider, carried into the ruling and into A3's AC:** the frozen payload includes **every `{status, reason}` envelope, `basis_year`, the exclusion line's state, and the unclassified count as rendered** — and **staleness stays OUTSIDE it** (PRD §2.6.4's live-read carve-out; P8 item 2). *Freeze what was computed; never freeze what is observed.* A3 item 4 and P8 item 2 already state both halves; the rider makes the boundary explicit at the ruling rather than leaving it distributed across two blocks.
>
> **PM's half of the losing side, which is not mine and is worth the sitting's attention:** *"a frozen payload freezes its defects"* — a report generated against a bad target, or against an undesignated tax-authority ledger, is **wrong forever**, and the only remedy is the PRD's regeneration affordance, which the user must know to use. That is why PM §8's "Regenerate" copy and the pre-finalize *"No IRS/FTB ledger designated"* prompt (P4 item 4) are load-bearing under Option A rather than nice-to-have. ⚠ **Option A converts a class of silent drift into a class of permanent, visible error.** That is the better trade, and it is a trade.
>
> **⟳ Round-2b — Sec backs Option A and VETOES Option B** (`sec-findings.md` @ `04bec6e` **R2.1**). Sec's ground for A is one this role does not supply: under A there is **one stored artifact and one read path**, so the P10 tenant-isolation battery's job is finite; under the hybrid the battery must prove tenancy on two render paths forever, *"including for every §2.x surface added later."*
>
> ⚠ **Sec scopes the veto's ground precisely, and the scoping is the load-bearing part.** ADR-067 D3's recorded Sec VETO on backfill has two grounds, and **only one transfers**: ground **(i)** (a backfill rewrites an append-only audit surface) does **NOT** transfer — Option B writes nothing, so there is no rewrite. Ground **(ii)** (the past state is not recoverable, so the values are fabricated) **does** transfer intact: *"Stored or not stored is immaterial to ground (ii); presented as a measurement is the whole of it."* **The veto rests on (ii) alone and Sec says so rather than leaning on both.**
>
> ⚠ **What is NOT vetoed:** PM's round-1 A-5 option (A) — *amend φ-1 to name the exceptions, loudly labelled* — is a **different proposal from S-1 Option B**, because *"it changes the promise instead of breaking it."* Sec's only requirement there is that the label render **on the historical report**, not merely in the PRD. PM has since withdrawn it in favour of Option A, so nothing turns on it; it is recorded so a later reader does not treat the veto as covering more than it does.
>
> **Sec's conditional acceptance of the hybrid,** if F/CTO weights payload-compat above render-path unity: Sec will not block it, but would then **require the per-section frozen/recomposed classification to live in the SCHEMA** (a marker column on the child), not in prose — *"so a misclassification is a visible column value rather than an absence."* ⚠ That condition is worth carrying whichever way this rules; it is the mitigation my Option C lacked.
>
> **All three roles now back Option A.** Sec's stake (F-2 / the SD-12 derivative class) is unchanged and the joint review still governs.

**`⟨RULING⟩` S-1.** Sec joint-review mandatory either way (Lock 11/12 surfaces, ADR-011 D2 + D3, financial values).

**Which half of ADR-011 D2 applies (asked in the brief, answered).** **Both, and to different tables.** D2's *immutable* half governs `monthly_report_account_snapshot` and (under Option A) the frozen payload: read-only post-write. D2's *INSERT-new-version* half governs the **header's regeneration path** — Lock 11 mod #2 verbatim, *"hard-overwrite UPDATE would lose `included_reconciliation_event_ids` + `owner_header_at_generation` history."* A regeneration inserts a new row and supersedes the old; it never updates in place. The two halves are not alternatives here; the header is INSERT-new-version and each individual row is immutable once `final`.

### S-2 ⚠ The PDF render direction is INVERTED in A4, A5 and P6 relative to ARCH §3.2 and RT-21.

**The claim about the tree (measured).** `docs/ARCH/index.html` §3.2 *"PDF render cross-container handoff"* carries a sequence diagram whose steps are, verbatim in order: PDF worker mints JWT → **`PW->>V1: "GET /internal/pdf-render + signed JWT"`** → V1 verifies JWT (RT-21) → V1 calls the SECURITY INVOKER helper → DB returns rendered data → **`V1-->>PW: Rendered HTML`** → worker loads that HTML in Puppeteer → PDF artifact. SECURITY §4.5 **RT-21** agrees: *"V1 app `/internal/pdf-render` endpoint verifies inbound JWT **from PDF worker**."* ADR-011 Decision 17 / Lock 13 agrees: *"Puppeteer browser-context-per-render hitting V1 app render URL with short-lived signed JWT."*

**The drafts say the opposite.** A4: the worker *"composes HTML from JSON payload at `/internal/pdf-render`"* — the worker is the endpoint and the worker composes HTML. A5: the app route *"accepts … JSON payload (composed report) … invokes A4 PDF worker; returns PDF bytes"* — app pushes to worker. P6: the browser button *"invokes A5 endpoint with composed JSON payload + JWT-bearer; receives PDF bytes."*

**Why the direction is load-bearing and not a wording nit.** Under the ARCH/Lock-13 pull direction the app's own Svelte template is the single render path, so P6's *"layout matches in-app render via shared HTML template"* is free rather than a second implementation, and **§7.32 item 6's `schedule_label` escaping hazard is discharged by Svelte's default escaping** — no user-controlled prose is ever composed into HTML inside the worker. Under the drafted push direction the worker receives free-text financial data as JSON and builds HTML itself, in a container with no DB, no test harness and no escaping framework — which is exactly the control §7.32 item 6 says must then exist and be tested with a stored `<script>`. **The drafted direction creates the hazard that a V1.4 Sec finding already booked against V1.5.**

Likely provenance, offered so the drafts are not read as careless: the **provider-sync** worker genuinely does use an app→worker admission hop (ADR-027 amendment (hh) / RT-27 / SELF-212, `:8081`). RT-21's own body warns about precisely this: *"Two clauses that read as siblings have different attacker models and therefore different right answers — reasoning from the resemblance produces a confident wrong answer for one of them."*

**Options.**
- **Option A — conform the drafts to ARCH §3.2 (worker pulls HTML).** *Buys:* one render template; escaping discharged structurally; matches three ratified artifacts. *Costs:* the worker needs network reach to the app and the app must serve a render endpoint that returns HTML for an arbitrary user identity — which is S-3. *Harder later:* the worker cannot render anything the app cannot serve as a page.
- **Option B — ratify the inversion (app pushes JSON; worker renders).** *Buys:* the app never needs to impersonate — it composes under the user's own live session, which dissolves S-3 entirely. *Costs:* a second HTML template in the PDF worker; §7.32 item 6's escaping control becomes mandatory and must be built and tested; ARCH §3.2, Lock 13's mod inventory and RT-21 all need amending — Lock 13 is an ADR-011 Decision, so this is an ADR amendment plus Sec joint-review, not a doc edit.
- **Option C — app pushes *rendered HTML* (not JSON) to the worker.** The app composes and escapes under the user's live session, hands the worker finished HTML, worker returns PDF bytes. *Buys:* one template; escaping in Svelte; no impersonation (S-3 dissolves); worker stays zero-DB and zero-logic. *Costs:* still inverts the direction versus ARCH §3.2/RT-21, so it still needs the Lock 13 amendment; the JWT's purpose changes from "prove who is asking" to "prove the caller is our app," which is an RT-21 rewrite.

**Lean: Option C.** It keeps every property Option A buys (one template, structural escaping) while removing the hardest unsolved problem in the arc (S-3), and it makes the worker as close to a pure function as this design can get. **The losing side, named:** C requires amending a ratified ADR-011 Lock and rewriting RT-21's battery, which A costs nothing. If F/CTO prefers not to reopen Lock 13, Option A is correct and S-3 must then be ruled. **Option B is dominated by C** — it pays A's costs *and* C's costs and buys nothing C does not.

> **⟳ Round-2b — Sec backs Option C, and names a losing side I did not** (`sec-findings.md` @ `04bec6e` **R2.2**). Sec re-measured ARCH §3.2 itself (`:325`, `:330`, `:332`) and confirms the inversion. Sec's ground for C is the same as mine stated more sharply: *"Trading a silent tenant-confusion class for a loud network class is the right trade on a fintech surface."*
>
> ⚠ **The losing side of C that my §1 missed, and it is concrete.** C makes the HTML body an **inbound network input to a browser engine**. Under Option A the worker only ever loads what it fetched from a known app URL; under C anyone reaching the worker's port hands arbitrary HTML to Puppeteer, and `<iframe src="file:///proc/self/environ">` rendered into a PDF returned to the caller **exfiltrates `PDF_WORKER_SIGNING_KEY` — that container's only secret and therefore its entire compromise.** **C is not safe without both of Sec's conditions:**
> 1. **All outbound and local resource loading denied at render:** `page.setContent()` plus request interception aborting every request whose scheme is not `data:` — no `file:`, no `http`, no `https`. ⚠ Lock 13 mod #7's shipped hardening list does **not** contain this, so it is an **addition, not an inheritance**. **Catch criterion:** POST HTML containing `<iframe src="file:///proc/self/environ">` and `<img src="http://169.254.169.254/">`; assert the PDF contains neither the key nor any fetched content **and that the interception handler recorded two aborts** — *"a failed fetch and a blocked fetch render identically"*, so asserting only that the PDF looks fine is vacuous.
> 2. **Sec N-4 — C creates a second inbound admission channel and the RT-27 fence does not reach it.** `scripts/ci/fence-admission-private-bind.sh` locates its target by an in-file sentinel in a **Coolify Compose manifest**, and `workers/pdf-render/` has **no compose manifest at all**, so the admission endpoint would come up unfenced. **Requirement (DevOps):** pdf-render ships a manifest carrying the sentinel and the RT-27 job invokes the script against it — *"a wiring change, not a new fence"*, since the script is already generic over its target.
>    - ⚠ **INTRA-instance coverage expansion of RT-27; NOTHING changes on the §10 catalogued ledger.** Sec cites the direct precedent rather than re-arguing it: SECURITY §4.5's RT-30 entry records an *"INTRA-instance allowlist expansion (RT-26 3→4)"* with *"§10 ledger UNCHANGED"*. **No new catalogued instance may be drafted for this channel and no ledger edit is owed** — Sec states this because the opposite failure, catalogueing it, *"would look like diligence."*
>    - ⚠ It **is** a CI **fence-boundary** change, which is a standing escalation trigger and joint-review-mandatory; it ships with a golden fixture that fails closed.
>
> **Sec on the alternatives:** Option **A** *"remains correct and I will not block it"* — its network posture is strictly better because the worker holds no listener at all — but choosing A makes **S-3 live and it must then be ruled.** Option **B** is not supported; Sec agrees it is dominated.
>
> ⚠ **Sec also retracts its own round-1 position on §7.32 item 6** (R2.2 close): under A or C the worker composes no HTML, so *"both of those are wrong under the ratified direction."* That converges with PM's §12.3 R-5 point and with §9.5 below — **the control's home tracks S-2, but the proof leg is owed under every outcome.**

**`⟨RULING⟩` S-2.** Sec joint-review mandatory (RT-21 HIGH, SD-20, Lock 13).

### S-3 — How a non-JWT caller binds a tenant identity for a SECURITY INVOKER helper. (Live only if S-2 resolves to Option A.)

**Measured.** ARCH §3.2 states the binding mechanism is **open**: *"Concrete binding mechanism (Supabase JWT claim injection via `SET LOCAL request.jwt.claims` vs parametric `WHERE users_id = $1` at helper level vs other) **is Phase 5 detail design** per Lock 13 mod #1 contract."* A5's AC asserts it as settled — *"tenant binding via `SET LOCAL request.jwt.claims` (Arch-locked binding mechanism per RT-21(e) no-service_role-escalation)"*. **RT-21(e) contains no binding mechanism**; it is the no-escalation clause. This is a real label paired with content it does not hold (F-4 below).

**The mechanism already exists on the tree for the cron half.** `workers/etl/src/pfin_back_etl/connection.py` implements `TenantBoundConnection`: READ as `authenticated` via `SET LOCAL ROLE` + `set_config('request.jwt.claims', …, true)`; WRITE as `service_role` via `SET LOCAL ROLE`. `workers/etl/src/pfin_back_etl/nav_backfill.py` runs the per-tenant loop A7 describes, including the `set_config('app.nav_computed_for', auth.uid()::text, true)` fence `054` requires and the `request.jwt.claim.sub` singular-GUC hazard (N7) already handled. **A7's "cron tenant-binding pattern" is therefore not novel — it is the shipped W-1 pattern, and A7 should name and reuse that module rather than re-specify it.**

**The app half is genuinely unsolved.** The V1 app reaches Postgres through PostgREST/supabase-js, not a raw pg client, so it has no place to issue `SET LOCAL`. The three candidates: (a) mint a Supabase `authenticated` JWT for the user — needs an admin path, which strains RT-21(e); (b) add a raw pg client to the app and port `TenantBoundConnection` to Node — a new server surface inside RT-26's audit scope, and the CI fence for TBC is Python-side only (Wave 1 E2); (c) parametric `WHERE users_id = $1` under `service_role` — **excluded**: ARCH §3.2 states the endpoint *"does not use `service_role` in V1"*, and RT-21(e) forbids the escalation.

⚠ **A parametric `p_users_id` on an INVOKER helper is a trap regardless.** Under INVOKER, RLS already scopes to `auth.uid()`; a `p_users_id` argument either does nothing (misleading) or is ANDed into the predicate, in which case passing another tenant's id returns **empty rather than an error** — a wrong question answered as "no data". The tree has already ruled this twice: `105` records *"p_users_id DROPPED (INVOKER + RLS scope by auth.uid())"*, and `101`'s replace-all *"takes NO tenant parameter (`users_id` from `auth.uid()`, R4 rider 4 / Sec D-2)."* **A3's drafted `p_users_id UUID` parameter contradicts both.**

**`⟨RULING⟩` S-3**, and it is moot under S-2 Option C. Sec joint-review mandatory.

### S-4 — The staleness primitive is whole-tenant; P8 and P9 ask it for per-section attribution.

**Measured.** `pfin.fn_aggregation_has_stale_constituent()` (`046`, re-commented at `059`) takes **zero arguments** and *"Returns ONE aggregate row (`is_stale`, `stale_items`) for the calling user."* It answers "does this tenant have any unhealthy `linked_source`", not "is *this section* stale."

PRD §2.6.5 requires **both** *"per-section inline + report-level banner; both required"*, and names two exclusions (§2.6.2 commentary, §2.6.4 header) as *not account-derived*. The report-level banner is served directly by the shipped primitive. **The per-section half is not**, and P8's AC (*"badge adjacent to affected section headers"*) needs a mapping from a stale `linked_source` to the §2.6.1 sections its accounts feed.

Per-row attribution already exists for one surface — `api/src/lib/cashflow-row-staleness.ts` plus `CashflowRowStaleTag.svelte` (V1.3, SELF-258) — so the V1.5 question is whether §2.6 reuses that shape or needs a section-scoped primitive. Three options: (a) reuse the V1.3 per-row derivation, deriving section-affectedness in the app from the accounts each section consumed; (b) extend the DB primitive with a scope argument — ⚠ note `pfin.scope` **is not a type**; `pfin.account.scope` is `text not null`, a free-text ADR-004 Decision B label, so a scope-typed argument is not available; (c) ship report-level banner only at V1.5 and book per-section — **rejected: PRD §2.6.5 explicitly names α′-3 banner-only as a rejected alternative.**

**Lean: (a)**, reusing the shipped V1.3 shape. **Losing side:** (a) puts the section↔account mapping in the app layer where nothing fences it, while (b) would make it a DB-side, testable property. If S-1 lands on Option A, (a) gets easier — the frozen payload knows exactly which accounts fed each section.

### S-5 — `included_reconciliation_event_ids` has no reachable writer, and it is the reason ADR-011 D3 label #3 exists.

**Measured.** `pfin.reconciliation_event` exists (created in the `015`–`023` batch). **`insert into pfin.reconciliation_event` appears nowhere** in `supabase/migrations/`, `api/src/` or `workers/` at this sha. ADR-035 records that SELF-205's reconciliation mechanism is **superseded**, with the successor a **V1.6** statement control tie-out.

So Lock 11 mod #9's `included_reconciliation_event_ids INTEGER[]` — which is the *entire subject* of ADR-011 Decision 3's label **#3** — would ship as a column that is structurally always `{}` in V1.5, and its mandatory matched-tenant array-element trigger would be **DORMANT: correct, mandatory, and unreachable until a `reconciliation_event` writer lands at V1.6.**

**Options.** (a) Ship the column and the fence now, labelled dormant with the revival condition named in the migration header — the D3 label is realized and V1.6 inherits a fenced surface. (b) Defer the column to V1.6 — A1 ships without it; label #3 stays DDL-deferred as Decision 3 already records it. **Lean: (a).** It costs one trigger nobody trips and it means the V1.6 writer arrives into a fenced surface rather than having to remember to build one. **Losing side:** (a) ships a fence with no test that can meaningfully fail, and a fence that cannot fire is a known way to make a future regression invisible — the QA leg would have to be a construction assertion, not a behavioural one. If F/CTO prefers no unreachable fences, (b) is clean and Decision 3 needs no edit at all.

⚠ Whichever wins, **the label is #3.** It is already allocated. See F-6.

---

## 2. Findings

**F-1 — A1's UNIQUE constraint contradicts Lock 11 and breaks the regeneration model it is drafted to support.** Lock 11 verbatim: *"partial UNIQUE `(users_id, target_month)` WHERE `generation_status = 'final'`."* A1's AC: *"UNIQUE(users_id, target_month, generation_status) for `final`."* The drafted triple-column constraint additionally forbids **two `superseded` rows for the same (user, month)** — which is exactly what INSERT-new-version regeneration produces on the second regeneration. The drafted constraint makes the mechanism the same AC mandates fail on its second use. Use Lock 11's partial index.

**F-2 — A1's column list omits both columns Lock 11 mod #2 names as the reason for INSERT-new-version.** Lock 11 verbatim: *"hard-overwrite UPDATE would lose `included_reconciliation_event_ids` + `owner_header_at_generation` history."* Neither appears in A1's drafted column list. `owner_header_at_generation` is independently required by PRD §2.6.4: *"when a historical report renders … the owner-identification header reads from the snapshot, not live from the settings store."* Without it, renaming the trust retroactively re-labels every archived report — the exact failure §2.6.4 rules against.

**F-3 — the commentary columns carry a retired label.** A1 names `commentary_equity`; P3 names the text area "Equity". PRD §2.6.2 verbatim names the four sub-sections **Cash / Bonds / Marketable Securities / Alternatives**, *"F/CTO-ratified 2026-08-19: the sub-section label follows the §2.2.1 Cat rename per ADR-058 Decision 7 — Cat-alignment wins over literal label parity."* Migration `082` performed that rename. A column name on a Lock 11 header table is effectively permanent; this is cheap to fix now and a migration later. Recommend `commentary_marketable_securities` (or `commentary_msec` if the length is objectionable — a naming call I will take as trivial if F/CTO does not care).

**F-4 — A5's RT-21 battery (a)–(g) is a false composite: real labels, wrong clauses.** SECURITY §4.5 RT-21 verbatim enumerates (a) authenticated-tier JWT only; (b) dedicated signing key; (c) **60-second freshness window**; (d) nonce replay; (e) no `service_role` escalation; (f) dedicated endpoint; (g) rejected-JWT detection signal. A5's AC enumerates (a) JWT signature; (b) nonce replay; (c) tenant claim presence; (d) expiry; (e) no service_role escalation; (f) **audience check**; (g) **issuer check**. Only (e) matches. The drafted list **drops the 60s freshness window** — the anti-replay half that sits beside the nonce — and invents two clauses RT-21 does not contain. A battery built to A5's letters would pass while leaving RT-21(c) and (g) unbuilt.
  - ⚠ **RT-21(g) is known-defective and must not be built by inheritance.** ADR-050 F3 records that RT-21(g) inherits RT-05's defect **unbuilt**, and RT-21's own body says its answer *"may legitimately differ from RT-05's."* It also notes the superseded text named `pfin.plaid_sync_audit` as the storage surface for rejections — a table dropped at `015`. RT-21(g) needs its own design call at build time, routed to Sec.
  - ⚠ RT-21's body also already records, independently of this pass, that **the whole A4/A5 surface is unbuilt**: *"`workers/pdf-render/` holds a Dockerfile and a `.env.example` and nothing else, there is no `/internal/pdf-render` route, and `PDF_WORKER_SIGNING_KEY` has no consumer in source."* Measured independently at this sha and confirmed.

**F-5 — A6's deliverable is already on the tree and wired into CI. This issue should close, not build.** `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` exists and implements both catch criteria. `.github/workflows/security-scan.yml` runs it **twice** — production mode against `workers/pdf-render/Dockerfile`, and **inversion mode** against `tests/fixtures/ci/rt22-violation.Dockerfile` with an explicit fail-closed check that the fence *caught* the fixture (*"FATAL: RT-22 fence reported clean against violation fixture — fence is broken; failing closed"*). It landed at commit `eada4b2`, *"ci(meta): Phase 5 Step 4 W1 — CI fences (RT-22 + RT-26 + TBC)"*. `scripts/ci/README.md` documents it. This is the V1.4 SELF-263 pattern repeating: **a Backlog item whose deliverable shipped under another workstream's name.**
  - Two AC clauses are wrong on their own terms and should not be "fixed" into the shipped fence. (i) A6 says grep for *"`SUPABASE_*` env vars (**other than `SUPABASE_URL`**)"*. Lock 13 mod #2, ARCH §3.2, RT-22, the Dockerfile's own header and the shipped fence all say **no `SUPABASE_*` at all**, with `PDF_WORKER_SIGNING_KEY` as the single permitted var. The drafted carve-out would **weaken** the fence. (ii) A6 says *"both catalogued instances now have V1 CI automation"* — "both" is an instance-count claim falsified by ADR-011 Decision 4 read live. See F-6.
  - **What closing A6 means for the ledger: nothing.** Decision 4's catalogued list is a list of *instances*, not of automation states; RT-22 was catalogued in 2026-05 and building its fence neither adds, removes, reorders nor renumbers anything. **Path B — reference, do not restate.** No ledger edit is owed by A6, and the residual work is a wording correction on the issue, not on the ADR.

**F-6 — A1 and A2 allocate NEW Decision 3 labels for instances that are ALREADY LABELLED.** A1's AC says *"Decision 3 family — 6th instance"*; A2's says *"7th instance"*. ADR-011 Decision 3, read live at this sha, carries `pfin.monthly_report.included_reconciliation_event_ids INTEGER[]` and `pfin.monthly_report_account_snapshot.account_id` as **already-allocated labels, currently DDL-deferred** — and Locks 11 and 12 name them by those labels in their own text (*"Decision 3 third instance"*, *"Decision 3 fourth instance"*). Building these two tables **realizes existing labels; it allocates none.** Migrations `012`, `017`, `019`, `022`, `023`, `029`, `033` and `054` all carry header annotations naming this family by those labels — a drafted renumber would falsify all of them.
  - ⚠ **A1 also attaches the label to the wrong column.** Its AC says *"matched-tenant trigger on `users_id` FK per Decision 3."* A direct `users_id = auth.uid()` anchor is **not** a Decision 3 instance — `007` and `015` both state this explicitly (*"users_id = auth.uid() is the SOLE tenant anchor (direct-owner RLS; NOT a Decision-3 instance)"*). The instance on `monthly_report` is the **`INTEGER[]` array column** (Lock 11 mod #9), which A1's column list does not include at all (F-2). The AC mislabels a non-instance and omits the instance.
  - This is the reason S-5 must be ruled before A1's DDL is written: which column carries the fence depends on whether the array column ships.

**F-7 — A2's column set is far wider than Lock 12's locked shape, and one named column is not a thing.** Lock 12 locks `(monthly_report_id, account_id, acct_name_at_generation)`. A2's AC says *"NAV components + balances + `tax_treatment` + **scope** at snapshot time."* `pfin.account.tax_treatment` is real (`003`, `text not null`). **`pfin.scope` is not a type** — `pfin.account.scope` is `text not null`, a free-text ADR-004 Decision B label (`105` records the same finding: *"p_scope DROPPED (pfin.scope type does not exist)"*), and PRD §2.6.1 states the owner header is *"not a tenant-isolation boundary or a scope filter"* with multi-scope reports V2+. The widening is not wrong in principle — under S-1 Option A the snapshot child is exactly where per-account frozen values belong — but it is a **Lock 12 amendment**, not an implementation detail, and it must be drafted as one.

**F-8 — P4 omits the PRD's explicit-skip path and routes the user notification to the wrong channel.** PRD §2.6.3 verbatim: the flow blocks finalization *"until the user completes **(or explicitly skips)** authoring"*, and cron-fired authoring is surfaced *"via an **in-app notification + pending-monthly-report queue** affordance."* PRD §2.6.2 adds that *"empty sub-sections render with the label and an empty body region."* P4's AC instead makes empty commentary an unconditional block (*"skips report generation"*) and sends the notice to **Coolify→Discord**. Discord is an operator channel; the PRD's affordance is the in-app queue P5 owns. Two consequences: the user has no way to say "no commentary this month, generate anyway", and the notification lands where the user is not looking.
  - Corollary for A1: because cron produces a report that is **not yet final**, Lock 11's `draft`/`final`/`superseded` vocabulary maps cleanly — cron writes `draft`, completing-or-skipping authoring promotes to `final`, regeneration supersedes. A1's presentation mapping (`not-yet-triggered`/`pending`/`generated`) should be stated against that transition, not against the raw enum.

**F-9 — P3 omits the copy-from-prior-month affordance, which PRD §2.6.2 makes an explicit V1 commitment.** Verbatim: the editor opens blank, V1 does **not** auto-pre-populate, and *"the editor surfaces an **explicit 'copy from prior month' affordance** the F/CTO invokes per-sub-section or globally."* Not in P3's AC. Flagged to PM for round 2 — it is a scope item, not an architecture one, but it changes P3's read surface (the editor must read the prior month's row).

**F-10 — P2 cites ADR-013 P5 for a rule that decision does not make.** ADR-013 Decision 7 (P5) governs *"all four user-authored **planning values**: §2.2 allocation `%Target`, §2.3.2 income/expense targets, §2.5.2 tax brackets, §2.6 owner-id header"* — no inline editing for those four. **Commentary is not one of the four.** Whether commentary edits inline on the report is genuinely open, and PRD §2.6.3 leans the other way (the generation flow *"opens the §2.6.2 commentary editor"*). Right ADR, right decision, wrong subject. Route to PM/UX; no architectural stake.

**F-11 — A7 should name the shipped module rather than re-specify the pattern.** A7's AC describes `TenantBoundConnection`'s behaviour without naming it. See S-3. Two additional binding details A7 must inherit and does not mention: `054`'s `app.nav_computed_for` GUC discipline is specific to `nav_daily` writes, but the **singular-vs-plural claims-GUC hazard** it documents (`auth.uid()` prefers `request.jwt.claim.sub` over the plural blob, so a stale singular GUC serves one tenant's data for every tenant with no code bug) applies to **any** per-tenant loop, and `connection.py` already nulls it. A7's AC should require the loop to reuse that module rather than re-derive it.

**F-12 — A9 is well-drafted; only its provenance wording is stale.** A9's Source and AC(3) describe ADR-054 as *"Architect-authored, ratifies with the same doc PR"* / *"ratifies with the ADR."* **ADR-054 is Accepted (2026-08-12) and on the tree at this sha**, including Decision 5's two closures. The AC's substance is correct and unusually careful — it declines to draft a D3 label, cites Decision 4 as unchanged without restating it, names the aal2 backstop obligation explicitly, and carries the Σ(leaves)↔scalar reconciliation leg as required. Only the tense needs fixing.
  - One substantive check: A9 is coherent post-V1.4. ADR-067 D3 keeps `nav_daily` the **gross pre-tax** series permanently, and `051`/`105` emit leaf values at read time. A9 captures leaves in the same cron transaction as the scalar checkpoint, so *"capture-only"* against `105` means: the component rows and the scalar row derive from the same computation in the same transaction and reconcile by construction; A9 introduces **no** read helper and therefore cannot drift from `105`'s tax-adjusted definition, because it never renders. That orthogonality is what makes A9 safe to ship before S-1 is ruled.

**F-13 — A8 is buildable as drafted, and the ADR it half-contradicts has already recorded the contradiction.** A8's Source quotes Lock 14's *"four per-domain tables"* while its AC builds against five. ADR-011 Decision 18's family-size amendment (2026-08-16) names **this exact A8 entry** as the measurement that made the divergence visible, and ratifies **FIVE**. So the AC is right and the Source line is quoting superseded text. Measured at this sha: `planning_target` (`074`), `cashflow_target` (`090`), `tax_bracket_schedule` + `tax_bracket_row` (`101`) all exist; **`owner_identification` is the only unbuilt member.** `pfin.fn_refresh_updated_at` exists and is widely reused. Settings editors on the tree: `api/src/routes/settings/{allocation,cash-flow-targets,tax-brackets}` — so P7 genuinely closes the ramp at 4/4 (the tax pair is one editor, which is why the table family is 5 and the editor ramp is 4; A8's AC states both correctly).
  - **Is A8 a Decision 3 instance? No.** Its only reference column is `users_id`, a direct owner anchor — explicitly not a family member per `007`/`015`. It carries no FK-shaped reference. Decision 3 is unchanged by A8, and **no label may be drafted for it** — Decision 18's own amendment warns that pre-recording an expectation of membership *"is how a draft label gets invented and then reasoned out of existence."*
  - ⚠ A8 must still clause the **aal2 step-up backstop** on its `authenticated` policies (ADR-029 / `025`), and it is **not** eligible for the `user_settings` exclusion — that exclusion exists solely because `user_settings` is the clause's own subquery target. A8's AC does not mention aal2; add it.

**F-14 — one dated catalog comment reads as live state (observation, not V1.5 work).** `059`'s `comment on function fn_aggregation_has_stale_constituent` asserts *"Decision-3 unchanged 15/13"*, and `054`'s trigger comment asserts *"Decision-3 family unchanged at 15 labeled / 12 DDL-realized."* Both were true when written and are falsified by Decision 3 read live at this sha. `104` and `105` state the correct posture — *"no count is stated here … read ADR-011 Decision 4/3 live"* — so the convention has already been fixed going forward. Recording the two residuals so they are not discovered as a surprise; **not** proposing a comment-only migration for them in V1.5. Routed to team-lead for booking.

---

## 3. Already on the tree that an issue treats as unbuilt

1. **A6 / SELF-350 — the RT-22 fence.** Fully shipped: script, production leg, inversion leg with a golden violation fixture, README. See F-5. **Close, do not build.**
2. **A4 / SELF-348 — partially.** `workers/pdf-render/Dockerfile` and `.env.example` exist, deliberately, as a *placeholder shipped so the RT-22 fence has a real target to audit* (its own header says so). A4 is not greenfield: it **extends** a file that is already the subject of a fail-closed CI fence, so every A4 commit is fence-gated from the first line. A4's AC should say "extend", not "scaffold", and must not restructure the ENV/ARG block the fence keys on.
3. **A7 / SELF-351 — the tenant-binding mechanism.** `TenantBoundConnection` (`workers/etl/src/pfin_back_etl/connection.py`) plus the per-tenant loop in `nav_backfill.py`. See F-11.
4. **P8 / P9 — the staleness framework.** `fn_aggregation_has_stale_constituent()` (`046`/`059`), `StaleConstituentBadge.svelte`, `CashflowRowStaleTag.svelte`, `cashflow-row-staleness.ts`, `api/src/lib/server/queries/staleness.ts` and a per-surface test set including `staleness-cross-surface-consistency.server.test.ts`. **P9 is a genuine ramp onto shipped surfaces and is the cleanest P-item in the wave.** P8 needs S-4.

---

## 4. Dispatch order

Three tracks. **Tracks 2 and 3 do not touch S-1 and can start immediately.**

**Track 1 — blocked on rulings.** S-1 → then A1 → A2 → A3 → (P2, P5) → P4 → P10. A1/A2/A3 are one design unit under S-1 and should be one Sec joint-review, not three.

**Track 2 — the PDF path, blocked on S-2 only.** S-2 → A4 (extend) → A5 → P6. Independent of S-1 until P6 needs a report to render.

**Track 3 — unblocked today.**
- **A8 → P7.** Smallest complete vertical slice in the wave; closes Lock 14 at 5/5 and the Settings ramp at 4/4. **Recommended first dispatch.**
- **A9.** Fully independent of everything else in V1.5 (ADR-054 Decision 6 makes the orthogonality structural). Its clock argument is real — every day it does not exist is an unrecoverable observation gap — so it should not queue behind the report arc.
- **P9.** Ramps the shipped framework onto shipped §2.5 surfaces (SELF-264/266/268). No new substrate.
- **A6.** Close with a verification note.
- **P3** can start once A1's commentary columns land, but its four column names depend on F-3.

**P10** is the close-gate and must be last; its battery extends in the same PR as each RLS surface it covers, per standing QA pairing.

---

## 5. Promotion / re-scope recommendations

1. **A6 / SELF-350 → close as already-delivered**, with the two AC corrections (F-5) recorded in the closing comment so the weakened `SUPABASE_URL` carve-out is never inherited by a future edit of the fence.
2. **A1+A2+A3 → re-scope as one design unit** under a single S-1 ruling and a single Sec joint-review. They are currently three issues that cannot be independently specified.
3. **The Linear milestone asymmetry — it matters, and the V1.4 R7 precedent says so.** The nine A-items (SELF-345–353) carry **no milestone** while P2–P10 carry *"V1.5 — Monthly report full (§2.6)"*. For **A1–A7** this is wrong on the facts: they are labelled V1-SHIP-BLOCK, they are named as upstream dependencies of the V1.5 P-items, and P10 is the V1.5 close-gate that covers them — a V1.5 close-gate cannot pass while its own substrate sits outside the milestone it gates. They are "Platform / Cross-cutting" by **project**, which is a different axis from milestone, and the V1.4 pass ruled at R7 that project-placement does not carry milestone-placement. **Recommend A1–A7 be assigned the V1.5 milestone.**
  - **A8 and A9 are the genuine exceptions and should stay unmilestoned or be placed deliberately.** A8 closes a Lock 14 family that spans V1.2–V1.5 and is only incidentally in this wave; A9 is explicitly V1.x capture-only with its V2 consumer named, and ADR-054 Decision 6 makes it orthogonal by construction. Placing them in V1.5 would make the close-gate depend on work that has nothing to do with §2.6. **A9's clock is the reason to dispatch it early regardless of milestone.**
  - This is a scope/label change and therefore **F/CTO's call, not mine** — recorded as a recommendation only.
4. **P8's per-section attribution** may warrant splitting the report-level banner (deliverable today) from the per-section markers (needs S-4). PM's call.

---

## 6. Ruling-owed index

| id | Ruling owed | Blocks | Sec |
|---|---|---|---|
| **S-1** | ⚠ **ONE-WAY DOOR.** Frozen rendered payload (A) vs live recompute (B) vs hybrid (C). Lean **A**. | A1, A2, A3, P2, P5, P10 | mandatory |
| **S-2** | PDF render direction: conform to ARCH §3.2 (A) vs ratify inversion w/ JSON (B) vs app-pushes-HTML (C). Lean **C**; B dominated. | A4, A5, P6 | mandatory |
| **S-3** | Tenant-binding mechanism for a non-JWT caller of an INVOKER helper. Moot under S-2 (C). | A5, A7 | mandatory |
| **S-4** | Per-section staleness attribution: app-layer reuse (a) vs DB primitive extension (b). Lean **(a)**. | P8 | advisory |
| **S-5** | Ship `included_reconciliation_event_ids` + dormant fence now (a) vs defer to V1.6 (b). Lean **(a)**. | A1 | mandatory (D3) |
| **F-3** | Commentary column naming — `commentary_marketable_securities` per PRD §2.6.2 / ADR-058 D7. | A1, P3 | — |
| **F-7** | Lock 12 amendment for the widened snapshot child; drop `scope` (no such type). | A2 | mandatory |
| **F-8** | Explicit-skip path + in-app queue vs Discord. | P4, A7, P5 | — |
| **§7.32 #6** | Escaping control ownership — **discharged structurally under S-2 (A) or (C); mandatory and testable under (B).** | A4, P6 | mandatory |

**Ledger effects of this file: none.** No catalogued §10 instance is added, removed, reordered or renumbered; no layer attribution moves; no Decision 3 label is drafted or reallocated. F-6 reports that two drafted ACs allocate labels that already exist — the repair is to the ACs, not to Decision 3.

---

## 7. Instruments

Migration tree `supabase/migrations/001–105` (105 files). `git rev-parse`, `git log -- workers/pdf-render/`. `grep -rn` over `supabase/migrations/`, `api/src/`, `workers/`, `.github/workflows/`, `scripts/`. `create table` enumeration over the migration tree. Python HTML-to-text extraction over `docs/PRD/index.html`, `docs/ARCH/index.html`, `docs/SECURITY/index.html` (anchors and `<tr>` spans, cited by anchor/heading/label). `DECISIONS.md` read by bracketing `## ADR-` heading, never by line number.

---

## 8. Round 2 — sibling cross-reference (2026-09-04)

**Refs read.** PM: `origin/meta/v15-preflight-pm` @ `4c9f628`, `docs/records/v15-preflight/pm-findings.md`, md5 `06db14a407c89cf5dedc4ecfffb39c5d`. Sec: `origin/meta/v15-preflight-sec` @ `374ba8e`, `docs/records/v15-preflight/sec-findings.md`, md5 `a8e7090d1066bf70d5bf14e982774e75`. Both re-read from `origin` in this session, not from the round-2 brief. `origin/main` re-checked: still `b90b846` — baseline unmoved, so nothing in §1–§7 needs re-measuring.

⚠ **All three files use `F-n` and `D-n` independently.** Every citation below names its owner. Sibling items are cited, never restated.

### 8.1 Seam ↔ sibling map

| Arch | PM | Sec | Note |
|---|---|---|---|
| **S-1** frozen vs recomposed | **A-5** (lean **B**: freeze only the history-less inputs into the Lock 12 child) | M-5 adjacent; F-2 downstream | Same one-way door, reached by three routes. PM measured it from φ-1's text and named the exact unrecoverable inputs; I measured it from the settings tables' absence of history. **Neither of us found a fourth failure the other missed** — the convergence is the useful part. |
| **S-2** PDF direction | **D-7** | **F-5** | Three independent confirmations of the inversion. Sec adds the half I did not state: as drafted the *content* is caller-supplied, so a valid render JWT renders arbitrary content under any owner header. That is a stronger objection than the escaping one. |
| **S-3** tenant binding | D-11 (signature half) | **F-4** / **R-3** (lean α) | Sec supplies the mechanism I asked for and the failure mode I did not name: `request.jwt.claims` **without** `SET LOCAL ROLE authenticated` leaves `rolbypassrls` in force — `auth.uid()` returns the intended tenant, RLS is skipped, every tenant's rows compose, nothing raises. ADR-011 D4's 2026-09-03 amendment is the citation. **I adopt Sec's α and withdraw S-3's option (b)** as under-specified. |
| **S-4** per-section staleness | §4 (*"generation time is the load-bearing defect"*) | **M-4** | Both siblings hit the freeze-vs-live axis; **neither hit the attribution axis** (the primitive is whole-tenant and cannot say *which section*). S-4 stands as mine alone. |
| **S-5** the array column | §2 (A1) | **F-2** (lean **B** retire-by-amendment) | I leaned A (ship with a dormant fence); Sec leans B. See §8.6. |
| **F-6** D3 ordinals | **D-4** | **F-1** | Three-way agreement. Sec adds defect 3, which is sharper than mine: a matched-tenant fence on `users_id` is *the leg that cannot fail* — not merely the wrong column. |
| **F-1** UNIQUE constraint | — | **D-5** | Agreement. Sec's catch criterion is better than mine: **three** regenerations, not two. |
| **F-4** RT-21 letters | — | **F-3** | Agreement. Sec keeps A5's inventions as *labelled additions* rather than striking them; folded. |
| **F-5** A6 already built | §2 (A6) | **D-2** / **D-1** (**veto**) / **F-6** | See §8.7 — Sec found live successor work I concluded away. |
| **F-13** A8 aal2 | §2 (A8, riders) | **F-7** / **F-9** / **D-3** | Agreement on aal2; Sec escalates the review classification (**R-6**). I concur with Sec. |
| — | **A-1/A-2/A-3/A-6/A-8** PRD amendments | M-5 | Product-text territory; no Architect position owed. Folded into the AC blocks where they change a schema-visible fact. |
| — | — | **D-3** five missing RT labels | Neither PM nor I found this. Folded into six blocks. |

### 8.2 Three buildable counts, over three different predicates

**They are not competing estimates of one quantity.** Stated so the agenda can present three definitions rather than one disputed number.

| | Count | Predicate | Named |
|---|---|---|---|
| **Architect** | **4 / 18** | Identifiers resolve · no ratified Lock/ADR contradicted · **no unresolved seam between the AC and an engineer starting** | A8, A9, P7, P9 |
| **PM** | **2 / 18** | Identifiers resolve · **no AC sentence contradicts a PRD V1 lock or an ADR-011 Lock** (product only; mechanism explicitly deferred to Architect) | A8, P7 — *"both with riders"* |
| **Sec** | **3 / 18** | A competent implementer following the AC verbatim produces a surface **Sec would pass at joint review** without a correction changing schema / fence shape / test label / tenant-binding / review classification | A9, P4, P9 |

⚠ **The intersection of the three sets is EMPTY, and the union is five (A8, A9, P4, P7, P9).** No issue is called buildable by all three, and every issue named is named by at most two. That is a fact about the predicates, not a contradiction:

- **A9** — mine and Sec's; PM classes it out-of-§2.6-scope and therefore does not count it. Sec calls it *"the best-drafted issue in the wave."* All three would ship it.
- **A8, P7** — mine and PM's; **Sec's D-3 (missing RT-11/RT-12) and F-9 (aal2) are corrections of exactly the grade Sec's predicate counts**, so they fall out of Sec's set without anyone disagreeing about the tree.
- **P4** — Sec's alone, and Sec §5 says why: *"P4's author-before-generate gating is not a security control and I do not treat it as one."* It is clean on a security predicate and contradicts the PRD twice on the other two.
- **P9** — mine and Sec's; PM finds one of its three legs already shipped, which is an amendment on PM's predicate and not a correction on Sec's.

**Honesty note on my own 4.** My round-1 block for A8 attached an aal2 rider (F-13) while still counting A8 as buildable-as-drafted. That is inconsistent with my own predicate: an added policy clause changes the DDL, so it sits between the AC and the engineer. **On a strict reading my count is 3 (A9, P7, P9)**; I am not restating it as 3 because the agenda wants the three predicates as authored, but the inconsistency is mine and is recorded rather than quietly corrected.

### 8.3 Position on Sec ⟨RULING R-1⟩ — supersession, derive vs store

**Architect's position: option B (a narrow, column-scoped UPDATE exemption). I disagree with Sec's lean of A, and the disagreement rests on a mechanical claim, not a preference.**

Sec's A says supersession is derived, so *"no UPDATE, no DEFINER, no allowlist change, Decision 2 untouched"*, and calls it *"the only option where nothing is added and nothing is weakened."*

⚠ **Two mechanical facts falsify the "nothing is weakened" half.**

1. **The locked partial UNIQUE forbids A.** Lock 11's index is `UNIQUE (users_id, target_month) WHERE generation_status = 'final'`. Under A no row is ever demoted out of `final`, so **the second regeneration's row cannot become `final`** — the index rejects it. A therefore requires **retiring or narrowing the locked partial index**, which is an amendment to Decision 15's locked text. A's advantage over B was that B needs an amendment and A does not; **both need one**, to different Decisions.
2. **The locked vocabulary already requires an UPDATE, independent of supersession.** PRD §2.6.3 and Lock 11's `draft`/`final`/`superseded` mean a report is written `draft`, authored against while `draft`, and **promoted to `final`** — and that promotion is an UPDATE of `generation_status`, as is every commentary save before it. So Decision 2's blanket *"UPDATE blocked"* was never literally true of this table under its own locked vocabulary. **The real question is not how to avoid an UPDATE; it is where the mutability window closes and what fences it** — which is exactly what PM **D-6** identified from the product side.

**Restated shape, which is what I would draft:** the immutability trigger permits (i) any column while `generation_status = 'draft'`, (ii) `generation_status` on the single monotone `final → superseded` transition, (iii) nothing else, ever — and `users_id` / `target_month` are fenced in every state (Lock 12's Sec catch). **No DEFINER, no allowlist change, the locked partial index kept working exactly as written, and the full locked vocabulary preserved as stored state.**

**Losing side of B, named:** Decision 2's blanket append-only claim stops being true of this table and the ADR must say so — Sec's own stated cost, and it is real. Sec's second point stands too: *"an exemption on one column is an exemption a future column joins."* The mitigation is that the exemption is expressed as a **monotone transition on one column**, which is mechanically checkable in the trigger and in a battery leg, rather than as a column allowlist.

**What would change my position:** if F/CTO prefers to retire the partial index and make "current final" a read-path concept, A is coherent — but it must be ruled *as* retiring a locked constraint, not as the no-change option.

### 8.4 Position on the escaping control's home — PM and Sec home it differently

**PM §10** attaches BACKLOG §7.32 item 6 to **A4** as a `+AC`. **Sec ⟨RULING R-5⟩** leans folding it into **P6**, *"the control and its only consumer then share a review."* **They disagree, and I think neither is unconditionally right, because the home follows S-2.**

- **S-2 Option B** (app pushes JSON; worker composes HTML) → the worker owns escaping. **PM's home is correct**: it is a property of the container, asserted on rendered output, and it must exist before any payload reaches it. P6 is downstream of the hazard, not co-located with it.
- **S-2 Option A or C** (worker never composes HTML) → **no escaping control is needed in the worker at all**, and building one would be a control with nothing to catch. The obligation converts into a **negative assertion** — that the worker composes no HTML and receives no unescaped free text — which belongs on A4 as a property and in P10 as a leg.

**So: rule S-2 first; the home falls out.** ⚠ The one thing that must not happen either way is the §7.32 booking dissolving: Sec's named losing side for folding — *"folding hides a Sec-raised item inside a product issue, and the §7.32 booking is the only record that it was raised independently"* — applies to my answer too. Whichever block receives it cites §7.32 item 6 by name, and Sec **M-2**'s scope note travels with it: the booking was drafted against `schedule_label` before the commentary columns and `owner_id_header_text` existed, and reaches them only through its *"every other free-text field"* clause.

### 8.5 Position on PM §7 item 2 — the five V1 surfaces no issue carries

PM's five: (i) the report listing surface · (ii) the on-demand generation **write path** · (iii) the in-app pending notification + queue · (iv) copy-from-prior-month and the `$ ReAlloc` side-by-side reference · (v) the report-level staleness banner. **PM leans fold; losing side named as P5 and P3 growing past one-session granularity.**

**Architect's position: fold four, open one — (ii) is a new A-item.** I disagree with PM on exactly one of the five.

- **Option 1 — fold all five (PM's lean).** *Buys:* no new Linear seats; the milestone set is unchanged; each surface sits with the issue that already owns its territory. *Costs:* (ii) is not a UI gap. A3 is a **read** helper and A7 is cron-only, so **nothing on the tree or in the wave writes a `monthly_report` row on the on-demand path.** Folding it into P5 puts a Lock 11 write with a server-derived `data_as_of` and an **RT-25** obligation inside a SvelteKit issue whose reviewer is Frontend and whose gate is not `sec-joint-review`. *Harder later:* the write path has no independent record — if P5 slips, it slips invisibly, and its Sec obligations slip with it.
- **Option 2 — fold (i)+(iii)→P5, (iv)→P3, (v)→P8; open one new A-item for (ii). Lean.** *Buys:* the write path gets the right owner, the right label and its RT-25 named; the other four sit where their territory already is, and none of them is a DB surface. *Costs:* one new issue in a wave already at eighteen, and a new blocking edge into P5.
- **Option 3 — two new issues (PM's alternative: listing+queue as one; on-demand write as another).** *Buys:* P5 stays small. *Costs:* two seats, and the listing/queue **is** P5's own subject matter — splitting it invents a seam the PRD does not have.

**Losing side of Option 2, named:** it grows the wave to nineteen and lengthens the critical path — if the new A-item is not dispatched early, P5 has nothing to call. It also concedes PM's general point (folding is right) while carving out an exception, and a carve-out is exactly the shape that gets forgotten at promotion; the mitigation is that it carries a `sec-joint-review` label, which a fold would not.

A sketch block for it is drafted in `rederived-acs.md` as **A10**, marked proposed-not-promoted.

### 8.6 Disagreements left standing for the sitting

Not reconciled, deliberately.

1. **Sec R-1 supersession** — Sec leans **A** (derive); Architect **B** (narrow exemption). §8.3 carries the mechanical objection to A. **This one has a right answer and the sitting can reach it**; it is not a preference split.
2. **Sec F-2 / Arch S-5, the array column** — Sec leans **B** (retire the instance by ADR-011 D3 amendment, citing ADR-035); Architect leaned **A** (ship it with a dormant fence, revival condition named). ⚠ **I now find Sec's B stronger on one point I had not weighed:** my A ships a fence that cannot fire, and a fence that cannot fire is a known way to make a future regression invisible — my own round-1 losing-side note said so. I am **not** switching my lean, because B's cost is real too (retiring a label needs the same care as allocating one) and because A leaves the V1.6 writer arriving into a fenced surface. **Both leans stand; the choice is F/CTO's.**
3. **Escaping-control home** — PM says A4, Sec says P6, Architect says it follows S-2 (§8.4).
4. **PM §7 item 2** — PM says fold all five, Architect says fold four and open one (§8.5).
5. **A6's disposition** — Architect round-1 said *close*; Sec **R-2** leans *re-scope in place*. **Resolved in Sec's favour, and the concession is recorded at §8.7 rather than silently absorbed.**

### 8.7 What round 2 changed in my own findings

- **F-5 was right that the fence is built and wrong that nothing remains.** I measured the fence's *implementation* and concluded A6 should close. Sec **F-6** measured the fence's *reach against what A4 will actually do* and found the live gap: the RT-22 script matches `RUN` install verbs and is documented not to inspect manifests, so the moment A4 lands `COPY package*.json .` + `RUN npm ci`, **`pg` can enter through a path the fence cannot see while the fence reports clean** — Lock 13 mod #2 false with its watcher green. That is a better answer than mine, and it is the shape my own memory warns about: I verified a control existed without asking what it could not observe. A6's block is re-scoped in place accordingly, and A4 gains a sequencing constraint (its `package.json` may not land before the manifest fence does).
- **S-3 option (b) is withdrawn.** Sec **F-4** supplies the fail-open mechanism, and it is not merely "the app has no place to issue `SET LOCAL`" — it is that the plausible partial implementation (claims without role) reads every tenant silently. Sec's α is adopted as the option to rule on, with Sec's own losing side (it puts a role-assumable identity on the cron host, which `055`'s deliberately non-owner identity exists to keep small) carried unedited.
- **My buildable count is internally inconsistent by one** (§8.2, A8). Recorded, not restated.
- **Nothing in §1–§7 is retracted.** The baseline did not move; every measurement in those sections stands as taken.

### 8.8 Ledger — unchanged, again

No catalogued §10 instance is added, removed, reordered or renumbered by round 2; no layer attribution moves; no Decision 3 label is drafted or reallocated. ADR-011 Decision 4 was read verbatim before round-1 drafting and nothing in round 2 touches it. **Path B throughout — referenced, not restated, no count carried.** ⚠ Sec **D-2** independently records the same discipline note the round-1 file carries: the **CI-fenced** set and the **§10 catalogued** set are different sets, RT-22's membership in both is coincidence rather than identity, and they must not be reconciled.

### 8.9 Round-2 instruments

`git fetch origin` + `git rev-parse` on both sibling refs and on `main`; `git show <ref>:<path>` piped to `md5` (both hashes matched the round-2 brief before any content was read); sibling files extracted to the session scratchpad and read whole. No tree re-measurement was performed, because `origin/main` is unmoved at `b90b846` — the round-1 measurements in §1–§7 remain current by that fact rather than by assumption.

---

## 9. Round 2, second pass — PM's round 2 (2026-09-04)

**Ref read.** `origin/meta/v15-preflight-pm` @ `77425b3`, `docs/records/v15-preflight/pm-findings.md`, md5 `eb7bcb2cc0bec0a737dad1708e79e45d` — fetched and hashed from `origin` in this session before any content was read. `origin/main` re-checked: still `b90b846`. No tree measurement is re-taken.

⚠ **PM's §12 was written against Architect's ROUND-1 file** (`architect-findings.md` md5 `d43968e7…`, `rederived-acs.md` md5 `f3335c48…`), which PM names. Several §12.5 items were therefore already applied in Architect's round 2. **Those are ref-skew, not disagreement**, and are marked as such in their blocks rather than silently absorbed — the distinction matters because a skew corrected quietly reads as a sibling having been wrong.

### 9.1 S-1 is settled among the three roles

PM concedes A-5 to **Option A** (freeze the rendered payload). The concession, PM's rider (envelopes / `basis_year` / exclusion state / unclassified count frozen **in**; staleness **out**) and PM's half of the losing side are carried into the **S-1 block at §1**, not restated here. **This was the wave's one one-way door and it now has no standing disagreement** — it still needs F/CTO's ruling and Sec's joint review, but it is no longer a contested seam.

### 9.2 §12.5 applied, by block

Applied and credited `(PM)` in `rederived-acs.md`:

| PM §12.5 item | Disposition |
|---|---|
| A2 item 7 — RT-20 vs RT-21 false composite | **Already applied** in round 2 (ref-skew) |
| RT-11 / RT-12 / RT-19 / RT-25 placements | **Already applied** in round 2 (ref-skew) |
| A8 item 7 — *"advisory, not joint-review"* | **Already applied** in round 2; block now records the skew explicitly and that **all three roles concur** on mandatory |
| P2 item 3 — *"California on the 2025 schedule"* | **Already removed** in round 2; A3 item 4 now names `basis_year` as a payload field and coins no user-facing sentence |
| P2 item 5 — inline editing | **Newly applied.** Answer unchanged (no inline edit) but **re-grounded on PRD §2.6.2's V2+ late-edit boundary**, ADR-013 P5 citation struck, and PM's routing rule added: "Edit commentary" → P3 for a `draft`, → "Regenerate" for a `final` |
| P3 item 6 — *"the F/CTO"* → *"the user"* | **Already applied** in round 2. ⚠ One *"the F/CTO"* survives at A9 item 7 and is **deliberate**: it names the ratifier of an ADR-054 rider, not the actor of a user action — PM **A-11** scopes the sweep to actor-framing |
| P5 — state names + tenant-scoped read as an AC line | **Already applied** in round 2 (ref-skew) |
| P6 — no PDF of a pending report | **Already applied** in round 2 (ref-skew) |
| P6 — filename convention | **Newly applied.** `mosko-monthly-{YYYY-MM}-{generated_at}.pdf`; ⚠ **never the owner string** — *"a PDF name travels further than its contents"* (PM). This was the file's last `⟨PM⟩` |
| P9 — copy already shipped | **Newly applied.** The round-1 *"`⟨PM⟩` copy for both"* is withdrawn; the AC points at `reasonCopy()` and `<StaleConstituentBadge>` instead of asking for strings |
| A1 item 9 → item 8 — presentation labels | **Newly applied**, and PM's rewording is the better one for a reason worth keeping: *"superseded is a storage state only"* **presumes `superseded` exists as a stored value**, which is true under Sec R-1 options B and C and **false under option A**. PM's *"a superseded version is never rendered in V1"* holds under all three, so the AC no longer waits on R-1 |

Two further PM items applied outside the §12.5 list: **A8's 120-character bound** moves from *proposal* to *decided* (PM §12.4, as a dispatch prerequisite), and **P7's forward-only editor notice** gets PM's string, resolving the last placeholder in that block.

### 9.3 New from PM's round 2 — the rename's vehicle

PM **§12.3 F-3**: PM does not object to renaming `commentary_equity` → `commentary_marketable_securities`, but the four column names are a **Gate B ratify record** carried in CHANGELOG, so the rename **rides the §9 consolidated ADR as a stated correction to Gate B's text and must not arrive by migration alone.**

**Architect concurs, and this is a genuinely better disposition than round 1's.** Round 1 treated the rename as a naming call cheap to make now; PM correctly identifies that it edits a ratified enumeration. A migration that silently renames one is the same failure ADR-011 Decision 18's own amendment names — *"a Gate ratify that changes a LOCKED ENUMERATION must amend the ADR holding it, not only the log that records the Gate"* — running in the opposite direction. Folded into A1 item 8.

### 9.4 Standing disagreements with PM, named and NOT reconciled

1. **A8's milestone.** Architect: A1–A7 in V1.5, **A8 out**. PM **D-1 / §12.4**: A1–**A8** in. ⚠ **PM's argument is stronger than my round-1 ground and I am recording that rather than burying it:** P7 is in the milestone and V1-SHIP-BLOCK and cannot ship without A8, and A1's `owner_header_at_generation` is written from A8's row — so A8 is §2.6 substrate **on product trace**, not incidental family closure. My ground was that the Lock 14 *family* spans V1.2–V1.5, which is a fact about the family and not about this issue's trace. **I am not switching, per the sitting's instruction to leave this standing; F/CTO should know the argument runs PM's way.** Both roles agree A9 stays out.
2. **A6's disposition.** PM **§12.3 R-2** records Architect as *close-and-note* and leans Sec's re-scope. ⚠ **Ref-skew: Architect's round 2 already moved to re-scope-in-place** (§8.7). **Not a live disagreement — all three now agree**, and the concession's reason is recorded at §8.7.
3. **A8's review classification.** PM records Architect as keeping *advisory*. ⚠ **Ref-skew: Architect's round 2 concurs with Sec R-6 (mandatory).** **All three agree.**
4. **F-3, the rename.** No disagreement on the rename; PM adds a **vehicle constraint** which Architect adopts (§9.3). Not standing.
5. **S-5, the array column.** Architect (a) ship-dormant · Sec **F-2** (B) retire-by-amendment · **PM has no product stake and leaves it standing** (*"no §2.6 story names a reconciliation event"*; PRD text untouched either way). **Genuinely standing, and now a two-role split with PM abstaining.**

**So of the five PM names, two are live (A8's milestone; S-5), one is an adopted refinement (F-3's vehicle), and two are ref-skew already resolved in Architect's favour-of-the-sibling.** Stated this way so the agenda does not spend time on three settled items.

### 9.5 Where PM answered something I had left open

- **F-10 / P2 inline editing.** I called it *"a UX call with no architectural stake"* and left it. **PM answered it** (§12.3 F-10) on PRD §2.6.2's V2+ late-edit boundary, with a routing rule. Adopted; the block no longer defers.
- **S-4.** PM concurs with my lean (a) and supplies the argument I did not make: the section↔account mapping **is PRD §2.6.1's composition map**, which already lives in the app layer, so a DB-side primitive would be a second copy of a product definition. PM accepts my named losing side (nothing fences it) with *"markers are not money"*.
- **Sec R-5 / the escaping control.** PM concurs with Sec (fold into P6) and adds the point that resolves my §8.4 conditional: **under S-2 options A/C the *control* is discharged structurally, but the *proof leg* is still owed** — INV-2 spans both engines regardless of who escapes. ⚠ **That makes P6 the right home under every S-2 outcome**, which my §8.4 did not see: I had the control's home tracking S-2 and missed that the obligation survives as a test even when the hazard does not. **§8.4's conditional is superseded on that point; the home is P6, and A4 carries the property only under S-2 Option B.**

### 9.6 Ledger — unchanged

No §10 catalogued instance added, removed, reordered or renumbered by this pass; no layer attribution moves; no Decision 3 label drafted or reallocated. PM **§12.6** records the same for PM's round 2. Path B throughout.

---

## 10. Round 2b — Sec's round 2 (2026-09-04)

**Ref read.** `origin/meta/v15-preflight-sec` @ `04bec6e`, `docs/records/v15-preflight/sec-findings.md`, md5 `e3cdafb95f7ae2fcd8d73ab8ba5851fd` — fetched and hashed from `origin` in this session before any content was read. `origin/main` re-checked: still `b90b846`.

⚠ **Sec's R2.6 pre-verdicts grade Architect's ROUND-1 blocks (`66288e0`)**, which Sec names. Of the five AMBER, **three were already fixed in round 2** (A2's RT-21→RT-20, A8's review classification, P10's unconditional tri-axis) — **ref-skew, not disagreement**, marked as such in their blocks. **Two AMBER and the one RED are genuinely new and are applied.** Sec's own verdict summary against the round-1 blocks: **GREEN 12 · AMBER 5 · RED 1.**

### 10.1 Applied from Sec's round 2

| Sec item | Grade | Disposition |
|---|---|---|
| **R2.6 A7 item 5** | **RED** | **Applied, and it becomes a ruling.** Sec **N-2** measured past PM's D-8: the successor `pfin.linked_source_sync_audit` (`015:441`) **exists and rejects a report-generation row on two CHECKs** (`source in ('webhook','scheduled_poll')`; a provider list with no internal/report member), and the general helper is unauthored. So the AC could only be built by silently dropping D1(d) or by widening CHECKs on a shipped append-only table. **New `⟨RULING⟩` A7-AUDIT** with three options; **Architect lean (b), author the reserved general helper**; losing side named. ⚠ Sec **withdrew its own round-1 catch criterion** here — it is untestable until the home exists. |
| **R2.6 A1 item 6** | **AMBER** | **Applied.** Round 1 *asserted* final-row immutability and named no mechanism, and **nothing addressed `service_role` on A1 at all** while A2 carries a bypass trigger. Decision 2 requires append-only across **both** roles. A1 now specifies a whole-row-on-final trigger plus the `service_role` fence, with the note that `rolbypassrls` leaves the trigger as that writer's **only** applicable layer. |
| **R2.6 A4 item 3** | **AMBER** | **Applied as two new AC items.** The resource-loading fence (`setContent` + scheme interception, two-abort catch criterion) is an **addition to Lock 13 mod #7, not an inheritance**; and Sec **N-4**'s compose-manifest wiring so RT-27's private-bind fence has a target under `workers/pdf-render/`. Both scoped to S-2 B or C. |
| **N-5** | flag | **Applied.** CHECK-enforced length bounds on the four commentary columns, mirrored in Zod, with the two-layer catch criterion. Without them P3's *"length bounds"* battery is a single-layer app control on a Lock 14 write path. `⟨PM⟩` owns the figure, not the mechanism. |
| **N-3** | note | **Applied as a stated reading.** See §10.3. |
| **N-1** | note | **Applied, and it was my error.** See §1 item 3 and §10.2. |
| **D-4 / N-6** | conflict | **Applied as `⟨RULING D-4⟩`** on both affected blocks; not decided. See §10.4. |
| **R2.5 item 3** | new trigger | **Applied to the A10 sketch:** the on-demand generation write path is a new user-reachable write onto a Decision 2 audit-class table, so **D2 is the governing trigger** — a second, independent reason it is not a fold into P5. |
| **R2.5 (A3 EXECUTE leg)** | — | **Applied to P10:** the no-`rolbypassrls`-EXECUTE assertion is restated as **standing**, with Sec's verification of the mechanism (`104:913-914`, `105:434-435`, and no function-level grant in `008`) and the reason — the failure mode is a future migration adding a grant to make something work. |

### 10.2 N-1 — a false-composite citation of my own

Sec found that my S-1 presented *"a fabrication with the shape of a measurement"* as **ADR-067 Decision 3's own words**. **Verified independently here rather than taken on report:** `grep -c 'fabrication with the shape of a measurement' DECISIONS.md` returns **0** at `b90b846`; the string lives in migration `105`'s `comment on function` and in `docs/records/v14-*`. **The ruling was correctly attributed; the rationale wording was not.** Right ruling, wrong pointer — the ADR-011 Decision 4 PR #476 class, and I committed it while citing that class elsewhere in the same file.

Corrected in §1 and **in the Architect memory entry that had already inherited it**, which is the part that would have propagated. ⚠ **The sentence must not enter a V1.5 migration header or the §9 consolidated ADR as a quotation of ADR-067.** If the wording is wanted in canon, promote it deliberately.

**The reusable half:** a quotable sentence in a migration comment reads exactly like an ADR quotation once it has been repeated twice. `105`'s comment is unusually well-written, which is precisely why its sentences travel.

### 10.3 N-3 — ARCH `:208` and the cron, with the intended reading stated

Sec found a third ratified artifact bearing on S-3 and raised it *"as a genuine ambiguity, not as a confirmed defect"*. Re-measured here: ARCH `:208` reads *"All **reads** flow through a single `SECURITY INVOKER` read-composition helper (**user-session only — never invoked from a worker**) …"*, and A7 has the cron invoking A3.

**Architect's intended reading, stated in full in the A3 block and summarized here: the clause constrains the SESSION CONTEXT, not the process identity, and it is PDF-scoped.** The cron satisfies it by impersonating — at the database layer that caller *is* a user session, with RLS applying and `auth.uid()` resolving. What the sentence forbids is its own second clause's subject: a worker reaching the database **directly**, outside any user session.

**Why the general reading cannot be right: under it A7 could not exist**, and ADR-011 Decision 15 / Lock 11 **mod #4 locks a V1-SHIP-BLOCK cron tenant-binding discipline** — meaningless if the cron may never invoke the helper it binds a tenant for. A reading that voids a ratified V1-SHIP-BLOCK mod is the wrong reading.

⚠ **This makes Sec F-4 sharper, not softer.** If *"user-session only"* is a session-context constraint, **claims-without-role does not satisfy it** — `rolbypassrls` remains in force and it is not a user session in the sense that matters. ARCH `:208` and Sec's α are the **same requirement stated twice**. **Owed:** ARCH `:208` is narrowed on the §9 ADR's doc PR so the next reader does not hit this.

### 10.4 Standing disagreements — the register after Sec's round 2

**Two close, one opens, two remain.**

1. **S-5, the array column — CLOSED in Architect's favour.** Sec **R2.8 retracts its round-1 lean B** and backs Architect's **(a)**, ship the dormant fence, *"reason given"*. PM abstains. ⚠ §8.6 item 2 and §9.4 item 5 recorded this as live; **it is no longer**, and I record the change rather than editing the earlier entries, because they are the account of what was true when written.
2. **Sec F-6 vs A6's residual — CLOSED, ref-skew.** Sec's named disagreement is with round 1's *"human-PR-review second line"* disposition for the manifest. **Round 2 already re-scoped A6 to the manifest extension and added the A4 sequencing constraint**, which is Sec's requirement. What remains under human PR-review is the **base-image transitive** residual only, which Sec does not contest. **We agree.**
3. **`⟨RULING D-4⟩` (sitting agenda item R11), the commentary IDENTIFIER — OPENS as a live cross-sibling conflict.** Sec **N-6** records it as needing a decision *"and neither sibling's file records that the other disagrees"* — a fair catch: my round 2 folded PM's *vehicle* constraint and read PM as not objecting, while PM's §3/D-3 says the identifier `commentary_equity` **stands**. **Not reconciled.** Both blocks now carry `⟨RULING D-4⟩`. **Settled under every outcome:** the heading is `Marketable Securities`, and the decision is stated in the §9 consolidated ADR rather than arriving by migration.
4. **A8's milestone — STILL LIVE** (Architect A1–A7 · PM A1–A8). Unchanged; Sec takes no position. My §9.4 note stands: PM's product-trace argument is the stronger one.
5. **Sec R-1 supersession — STILL LIVE** (Sec A derive · Architect B narrow exemption). Sec's round 2 does not revisit it; my §8.3 mechanical objection stands unanswered and should be put to the sitting.

### 10.5 Where Sec's round 2 changed my own conclusions

- **S-2's losing side was incomplete and Sec completed it.** My §1 named C's cost as *"a Lock 13 amendment plus an RT-21 rewrite"*. **Sec named the one that matters: C turns the HTML body into an inbound network input to a browser engine**, and `<iframe src="file:///proc/self/environ">` returned inside the PDF exfiltrates the container's only secret. **C is not safe without both of Sec's conditions**, and I had proposed it without either. My lean is unchanged; the option is now correctly costed.
- **Sec independently reached my §9.5 conclusion on §7.32 item 6 and retracted its round-1 position** (M-2 / R-5): under S-2 A or C the worker composes no HTML, so asking for the control *in the worker* is wrong under the ratified direction. Three roles now agree the control's home tracks S-2 while the **proof leg is owed under every outcome**.
- **Sec confirms it missed S-1's cause in round 1** (*"I found the two symptoms and did not find the cause"*) and confirms it did not read ARCH §3.2 in round 1. Recorded because the corresponding fact about my own pass — that I verified the RT-22 fence existed without asking what it could not observe (§8.7) — is the same failure shape, and neither is a reason to weight either file's round-1 measurements differently now.

### 10.6 Counts — a fourth number exists and must not be merged

Sec **R2.7** states its **3** was over *the original drafted AC text in the issue dump*, and adds that **against Architect's re-derived blocks the same predicate gives 12 GREEN / 5 AMBER / 1 RED at `66288e0`.** ⚠ **That is a fourth number over a fourth object** (re-derived blocks, not drafted ACs) and it is not comparable to the three at §8.2. **A9 and P9 are in all three drafted-text counts.** Sec's framing is the one to carry to the sitting: *"Stated this way so nobody reconciles three correct numbers into one wrong one."*

### 10.7 Ledger — unchanged

No §10 catalogued instance is added, removed, reordered or renumbered by this pass. ⚠ **Sec N-4's RT-27 wiring is explicitly an INTRA-instance coverage expansion with no ledger effect**, and both files now say so with the RT-30 precedent cited rather than re-argued — recorded because catalogueing it *"would look like diligence."* No Decision 3 label drafted or reallocated. Path B throughout.

---

## 11. Round 2d — Sec's round 2b (2026-09-04). Sec concedes R-1; the register closes to two.

**Ref read.** `origin/meta/v15-preflight-sec` @ `fe757d1`, md5 `888f637f820bb4139413535a5ec0e591`, §**R2.9** — fetched and hashed from `origin` before reading. `origin/main` still `b90b846`.

### 11.1 Sec R-1 — CONCEDED to Architect's Option B, and Sec's self-correction is sharper than my objection

Sec withdraws lean A *"not softened, not conditioned"*, and finds a defect **worse than the one I raised**. My §8.3 said the locked partial index **forbids** A. Sec's own text is **internally incoherent**: it read *"the locked partial-UNIQUE already makes 'the current final' unambiguous; `superseded` becomes a presentation label computed from `(target_month, generated_at)` ordering"* — but the index makes it unambiguous **by permitting exactly one such row**, so there is never a set of `final` rows to order and never anything to label `superseded`. Sec: *"I asserted the constraint as A's support while proposing a mechanism the constraint's own semantics exclude."*

Sec also confirms my claim (ii) and adopts the reframing: *"the question is not how to avoid an UPDATE, it is where the mutability window closes and what fences it."* And it names the second escape route as worse than an amendment — inserting every row as `draft` and deriving `final` leaves **the locked partial index never firing on any row**, *"a constraint that cannot fail … strictly worse than a recorded amendment because a dead index looks identical to a working one."*

**Four conditions folded into A1's block** (Sec: additions to a sound shape, not objections; with them **A1 moves AMBER → GREEN**): **(a)** DELETE blocked on any non-`draft` row — Decision 2 is a two-verb rule and B's clauses covered one verb; **(b)** the trigger is not role-conditional, proven under `authenticated` **and** `service_role`, because the cron does the `final → superseded` UPDATE and the realistic defect is a later `service_role` early-return; **(c)** legal INSERT **states** constrained, not only transitions, or a row POSTed straight in as `final` takes the month's slot without passing the authoring gate; **(d)** `superseded` is terminal, plus the runbook line that this trigger is an RLS-exempt writer's only layer and goes inert under `session_replication_role = replica`.

⚠ **(a) is the one I would have missed.** I restated a two-verb rule with one verb and did not notice; the whole shape was about UPDATE because the *question* was about UPDATE.

### 11.2 The standing-disagreement register — now TWO

1. **Sec R-1 — CLOSED, converged on B.** §8.6 item 1 and §10.4 item 5 recorded it live; **they are now stale and are superseded here rather than edited**, since each is the account of what was true when written.
2. **S-5 — CLOSED, converged on (a)**, recorded at §10.4 item 1; Sec's **R2.9(4)** adds its condition: the paired QA leg is **labelled construction-only in its own text**, which is the answer to the fence-cannot-fire objection I had recorded against my own lean. Folded into A1 item 2.
3. **Sec F-6 / A4 sequencing — CLOSED, and Sec WITHDREW the disagreement** (*"holding a disagreement past a concession would be bad faith"*), replacing it with a better mechanism — see §11.3.
4. **A8's milestone — LIVE.** Architect A1–A7 · PM A1–A8. Unchanged; Sec takes no position; my §9.4 note stands that PM's product-trace argument is the stronger one.
5. **`⟨RULING D-4⟩` (agenda R11), the commentary identifier — LIVE.** Architect rename · PM identifier stands · Sec neutral. Marked in both blocks, not picked.

**Two live items into the sitting, and neither is a security question.**

### 11.3 A4/A6 — a fence SHAPE replaces the sequencing constraint

Sec **R2.9(3)** withdrew its F-6 disagreement and asked for something better than what I had written: *"a sequencing constraint stated in an AC is a convention with no mechanism, and conventions with no mechanism rot silently."* **The re-scoped RT-22 fence audits `workers/pdf-render/package.json` if it exists and passes if it does not** — so it can land at any time, no-ops until A4 creates the file, and bites on A4's first commit. **The ordering requirement disappears rather than being remembered.** ⚠ Deliberately unlike the shipped Dockerfile fence, which exits 2 on a missing target — correct there because its target exists, and *"copying it here would red CI from the day it lands."* Fallback if the shape is not adopted: a **blocking Linear dependency edge**, never an AC sentence. Two further conditions folded: the catch criterion and its golden fixture go to Sec **before merge**, and the successor AC **cites the shipped fence's own header**, which names manifest inspection as a deliberate non-catch — *"or a future reader finds a fence that already says it does not do this and concludes the successor is redundant."*

**This is the better disposition and it is Sec's, not mine.** My AC sentence was the convention; Sec's fence shape is the mechanism.

### 11.4 A10 — Sec backs it, on the attachment point

Sec **R2.9(2)** backs opening A10 with `sec-joint-review`, citing ADR-064 Decision 5 **as a precedent for the reasoning and expressly not as jurisdiction** over `monthly_report` (D5 is scoped to `pfin.account_trans`; conflating them would be the false-composite class). D5 verbatim: *"The trigger is the surface, not the layer, and not the author's assessment of risk."*

⚠ **Sec's fallback is stated so this is not binary, and it concedes my own losing side:** if F/CTO prefers PM's fold-all-five, the fold is acceptable **provided P5 carries `joint-review:sec` and its AC names the Decision 2 and RT-25 obligations explicitly** — *"I would rather have the label on P5 than a nineteenth issue that gets dropped at promotion."* That is the exact risk I named at §8.5. **Both roles now back A10 with the same fallback; PM leans fold. F/CTO's call, and the fallback makes either outcome safe.**

### 11.5 N-3 — ref-skew, one last time

Sec **R2.9(5)** records N-3 as *"open, no action taken … pending Architect's 2b statement of intent."* ⚠ **That statement landed at `b26b1c8`** (§10.3 and the A3/A7 blocks), which post-dates the `d87c9dc` tip Sec answered against and names its own skew. **Not an open item from this side.** Sec's one substantive rider is adopted and already recorded: whichever reading is ratified, **ARCH `:208` ends up unambiguous on the tree rather than resolved in a records file** — owed on the §9 consolidated ADR's doc PR.

### 11.6 Ledger — unchanged

No §10 catalogued instance added, removed, reordered or renumbered; no layer attribution moves; no Decision 3 label drafted or reallocated — S-5's closure **realizes** an already-allocated label and allocates none. Path B throughout.
