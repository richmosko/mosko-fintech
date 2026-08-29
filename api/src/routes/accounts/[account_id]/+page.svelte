<!--
	accounts/[account_id]/+page.svelte — account detail + the CLOSE / REOPEN control.
	SELF-201 §2.4.2 AC #3/#4, re-pointed at `059` per ADR-042. Renders the account attributes +
	its transaction history (the AcctSetup opening-balance row appears here).

	CLOSURE IS A DATED EVENT, NOT A FLAG (ADR-042 Decision 1 + 2). `pfin.account.is_active` was
	dropped at `059`; the account carries `closed_at timestamptz` (NULL = open) and the page
	branches on `closed_at !== null`. Two named actions, NOT a toggle: `?/closeAccount` (posts a
	required `reason_code`) and `?/reopenAccount` (posts NOTHING — its server schema is
	`z.object({}).strict()`, so any stray field is a 400 rather than an ignored value).

	WHAT THIS PAGE MUST NOT IMPLY. The old copy here read "marking inactive = is_active=false …
	the account is excluded from current-value surfaces (other issues' backend concern)". Both
	halves are now false. There is no flag; and the exclusion is not delegated — Decision 3 makes
	ZERO VALUE A PRECONDITION `058` ENFORCES, so a close is REFUSED while the account still holds
	securities or cash as of the closing date, or has activity dated after it. The user must learn
	that BEFORE they press the button, which is why the help text names the gate rather than
	describing a label change. History is still RETAINED (AC #4) — and a closed account is
	additionally FROZEN: corrections go reopen → correct → re-close.

	COPY IS SETTLED as of the PM review 2026-08-04 — no longer provisional. Closure help text
	(open state rewritten, closed state shipped as authored), status pill and reason labels all
	ruled; the reasoning sits at each string. The pill stays SHORT ("Open" / "Closed") on the same
	logic that made the connections marker long: it renders beside the account name with no
	competing referent in view, whereas that marker renders inside a connection card where a closed
	CONNECTION is a real state. Same vocabulary, disambiguated only where there is something to
	disambiguate from.

	FENCES: no --c-pos/--c-neg on values (those are ACTUAL-performance only; ledger amounts
	are neutral). No staleness banner — a manual account has no Plaid re-auth. INV-1: name +
	scope are free-text → plain text. acct_number is not exposed (SD-15; masked-only posture).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { PageData, ActionData } from './$types';
	import { CLOSURE_REASONS, CLOSURE_REASON_LABELS } from '$lib/schemas/account-constants';
	import { accountTypeLabel, taxTreatmentLabel, closedAtLabel } from '$lib/account-display';
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import TransactionEntryForm from '$lib/components/TransactionEntryForm.svelte';
	import PurchaseEntryForm from '$lib/components/PurchaseEntryForm.svelte';
	import StockSplitEntryForm from '$lib/components/StockSplitEntryForm.svelte';
	import DuplicateCandidateList from '$lib/components/DuplicateCandidateList.svelte';
	import SyncHistoryTable from '$lib/components/SyncHistoryTable.svelte';
	import SyncNowControl from '$lib/components/SyncNowControl.svelte';
	import TransactionRow from '$lib/components/TransactionRow.svelte';
	import UnpricedMarker from '$lib/components/UnpricedMarker.svelte';
	import { subCatGroupsOf, securityLabel } from '$lib/transaction-util';
	import { ACCOUNT_TYPES, TAX_TREATMENTS } from '$lib/schemas/account-constants';
	import { updateAttributesSchema, closeAccountSchema, fieldErrors } from '$lib/schemas/account';
	import { providerLabel } from '$lib/accounts/connection-display';

	// SELF-325: Backend's load() extension (round 5, `8a7719b`) now returns `selectableAssets` /
	// `defaultSubCatId` / `defaultSubCatLabel` directly — the generated `PageData` carries them
	// with the right shapes, no widening needed (verified: regenerated types with `svelte-kit
	// sync`, removed the temporary `PageDataWithPurchase` cast this line used to carry, `npm run
	// check` clean). PurchaseEntryForm.svelte still declares its own `SelectableAssetOption`
	// prop type (purchase-util.ts) — that one stays; it types the component's OWN prop
	// contract, independent of whatever shape `PageData` happens to infer.
	let { data, form }: { data: PageData; form: ActionData } = $props();

	const account = $derived(data.account);
	const transactions = $derived(data.transactions);

	// ADR-042 / `059`: closure is a DATE, not a flag. This is a RENDER surface — it asks "is this
	// account closed right now?" — so `closed_at !== null` is the correct AND COMPLETE answer
	// (api/CLAUDE.md closure contract, render-vs-valuation split).
	//
	// The as-of form (`closed_at is null or closed_at > <as_of>`) is not merely heavier here, it
	// is WRONG: it needs an `as_of` this page has no business choosing, to answer a question
	// nobody asked. That form is mandatory on VALUATION surfaces (NAV, aggregation, any
	// presence-check paired with a NAV read) BECAUSE THAT IS WHERE THE SILENT-FLIP RISK LIVES —
	// there the two forms are behaviourally identical until a closed account exists, so no test
	// on today's data separates them. No such trap here: the current-state answer is the one
	// being asked for, and it is verifiable by looking at the screen.
	const isClosed = $derived(account.closed_at !== null);

	// Connections-redesign Aggregation section: THIS account's connection state (provider + health +
	// last-sync), resolved server-side from its linked_source_id. null = manual / non-linked account.
	const connection = $derived(data.connection);
	const isLinked = $derived(account.linked_source_id != null);

	// Select options for the attribute-edit form — labels via account-display, values from the
	// shared account-constants (anti-drift with the DB CHECK; same value-sets the server enforces).
	const accountTypeOptions = ACCOUNT_TYPES.map((v) => ({ value: v, label: accountTypeLabel(v) }));
	const taxTreatmentOptions = TAX_TREATMENTS.map((v) => ({ value: v, label: taxTreatmentLabel(v) }));

	function formatSyncTime(iso: string | null): string {
		if (!iso) return 'Never synced';
		const d = new Date(iso);
		if (Number.isNaN(d.getTime())) return '—';
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(d);
	}

	// ── Attribute edit (updateAttributes) ────────────────────────────────────────────────────
	// The Edit affordance swaps the read-only attribute display for an inline form. Client-side
	// `.strict()` mirror (updateAttributesSchema) gives fast field-level feedback before the POST;
	// the SERVER schema is the security boundary (Lock 14). Values live in local $state seeded from
	// the account on open, so a cancel discards cleanly and a save closes on the success result.
	let editing = $state(false);
	let saving = $state(false);
	let editErrors = $state<Record<string, string[]>>({});
	let editName = $state('');
	let editType = $state('');
	let editScope = $state('');
	let editTax = $state('');

	function openEditor() {
		editName = account.name;
		editType = account.account_type;
		editScope = account.scope;
		editTax = account.tax_treatment;
		editErrors = {};
		editing = true;
	}
	function cancelEditor() {
		editing = false;
		editErrors = {};
	}

	const editHandler: SubmitFunction = ({ formData, cancel }) => {
		// Client mirror of the server .strict() schema — reject an obviously-bad submit before the
		// round-trip. Same value-sets + posture as the server; never looser (api/CLAUDE.md).
		const parsed = updateAttributesSchema.safeParse(Object.fromEntries(formData));
		if (!parsed.success) {
			editErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		editErrors = {};
		saving = true;
		return async ({ update, result }) => {
			await update({ reset: false }); // success → load reruns → name/attrs refresh
			saving = false;
			if (result.type === 'success') {
				editing = false;
			} else if (result.type === 'failure' && result.data && 'errors' in result.data) {
				editErrors = (result.data.errors as Record<string, string[]>) ?? {};
			}
		};
	};

	// SELF-203 stock split — held-security picker options (Backend derives via fn_holdings_as_of).
	// The affordance is source-of-truth gated (OWD-2 / ADR-033): rendered ONLY when the account is
	// NOT provider-linked (linked_source_id IS NULL). A provider-linked account's splits arrive via
	// reconciliation (SELF-204); the fn_create_stock_split RPC is the DB-level backstop.
	const heldSecurities = $derived(data.heldSecurities ?? []);
	const isSourceOfTruth = $derived(account.linked_source_id == null);

	// SELF-204 read-only surfaces (Backend exposes both view row-sets from load()):
	//  - dupCandidates: manual↔provider candidate-duplicate pairs for THIS account
	//    (pfin.manual_provider_dup_candidate). DETECTION-ONLY — no action affordance.
	//  - syncHistory: per-account provider sync history (pfin.linked_source_sync_history),
	//    rendered only for provider-linked accounts (a manual account has no sync history).
	const dupCandidates = $derived(data.dupCandidates ?? []);
	const syncHistory = $derived(data.syncHistory ?? []);

	// Cashflow-domain Sub-Cat picker groups for the transaction entry/edit/split/categorize
	// surfaces (per-transaction annotation category — the cashflow domain, not asset taxonomy).
	const cashflowGroups = $derived(subCatGroupsOf(data.cashflowSubCats));

	// SELF-325 purchase-path (088): selectableAssets (own + global pfin.asset, the BIND-mode
	// "pick an existing asset" affordance) + the BTO-default category readout, from Backend's
	// load() extension (round 5, `8a7719b`). Local aliases only, matching this file's existing
	// `const account = $derived(data.account)` convention — no fallback needed, load() always
	// supplies these three (its own fail-soft-to-[] on a read error lives server-side).
	const selectableAssets = $derived(data.selectableAssets);
	const defaultSubCatId = $derived(data.defaultSubCatId);
	const defaultSubCatLabel = $derived(data.defaultSubCatLabel);

	// Cash / Purchase fork on "Add a transaction" — the two manual-entry write paths
	// (fn_create_manual_trans vs fn_create_manual_purchase, 040 vs 088). A segmented toggle,
	// not a dropdown, mirroring TransactionFactFields' own Direction toggle visual idiom
	// (consistency within this page rather than inventing a second toggle shape).
	let entryMode = $state<'cash' | 'purchase'>('cash');

	// The ledger table column count — shared with each row so its full-width editor rows
	// (<td colspan>) span correctly: Date | Category | Vendor | Description | Amount | Actions.
	const TABLE_COLUMNS = 6;

	// ── Close / reopen (ADR-042 Decision 1) ──────────────────────────────────────────────────
	// One `submitting` flag, because the two forms are mutually exclusive by `isClosed` — only
	// ever one of them is on the page.
	let submitting = $state(false);
	let closeErrors = $state<Record<string, string[]>>({});
	// Seeded EMPTY, not to the first reason — see the placeholder note on the form below.
	let reasonCode = $state('');

	const closureReasonOptions = CLOSURE_REASONS.map((r) => ({
		value: r,
		label: CLOSURE_REASON_LABELS[r]
	}));

	// CLOSE — the client `.strict()` mirror runs before the POST (fast field feedback). It is
	// NOT the boundary: `058`'s gate is, and it is the only thing that can answer "does this
	// account still hold value?", which no client check can. All the mirror does is refuse a
	// missing/out-of-set reason_code before a round trip.
	const closeHandler: SubmitFunction = ({ formData, cancel }) => {
		const parsed = closeAccountSchema.safeParse(Object.fromEntries(formData));
		if (!parsed.success) {
			closeErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		closeErrors = {};
		submitting = true;
		return async ({ update }) => {
			// `{ reset: false }` MIRRORS editHandler, and it matters MORE here: on this form a
			// refusal is the EXPECTED outcome — `058`'s gate refuses a close on an account that
			// still holds value — so the reset path is the common path, not the edge case.
			//
			// A reset blanks the reason the user picked while the bound `$state` KEEPS it:
			// `form.reset()` fires neither `input` nor `change`, so `bind:value` never observes
			// it and nothing re-renders the DOM back from state. Re-submitting then produces a
			// SECOND error — a client-side "Choose a reason" — that looks unrelated to anything
			// the user did, on top of the legitimate gate refusal they were already reading.
			// Spelled out because a bare `update()` looks correct to the next reader, and the
			// sibling handler carrying the same flag is not something you notice from here.
			await update({ reset: false }); // success → load reruns → closed_at refreshes
			submitting = false;
		};
	};

	// REOPEN — posts nothing at all, so there is nothing to validate client-side. See
	// `reopenAccountSchema` in $lib/schemas/account for why the empty mirror is deliberately NOT
	// wired here (a client cancel() on a stray field would be silent; the server 400 is visible).
	const reopenHandler: SubmitFunction = () => {
		submitting = true;
		return async ({ update }) => {
			// Bare `update()` is CORRECT here and is not an oversight: this form has no inputs,
			// so `reset: true` has nothing to reset. Do not "fix" it for symmetry with
			// closeHandler above — the flag there is load-bearing for a reason that does not
			// exist on this form.
			await update();
			submitting = false;
		};
	};
</script>

<svelte:head>
	<title>{account.name} — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">{account.name}</span>
	</nav>

	<header class="head">
		<div class="title">
			<h1>{account.name}</h1>
			<!-- The pill carries the STATE only; the DATE lives in the Account status section
			     below. Splitting them keeps the pill short next to a free-text account name that
			     can be 200 characters, and puts the date next to the copy that explains it. -->
			<span class="status" class:closed={isClosed}>
				{isClosed ? 'Closed' : 'Open'}
			</span>
		</div>
		<!-- SELF-254 entry point: this account's own §2.3.3 drill-down. `from=cross-account-rollup`
		     is carried unconditionally — SELF-251's cross-account rollup is this feature's one
		     logical "parent" cash-flow surface regardless of the literal click path that landed
		     here, so the drill-down page's back-link always has a real target (judgment call,
		     flagged at hand-off). -->
		<a class="cashflow-link" href="/cash-flow/{account.account_id}?from=cross-account-rollup">
			View cash flow →
		</a>
	</header>

	<section class="region" aria-label="Account details">
		<div class="section-head">
			<h2 class="section-title">Account details</h2>
			{#if !editing}
				<Button variant="secondary" onclick={openEditor}>Edit</Button>
			{/if}
		</div>

		{#if editing}
			<!-- Inline attribute editor (updateAttributes) — replaces the read-only display while open.
			     name / account_type / scope / tax_treatment. Client `.strict()` mirror guards submit. -->
			<form method="POST" action="?/updateAttributes" use:enhance={editHandler} class="edit-form">
				{#if editErrors._form}
					<p class="form-error" role="alert">{editErrors._form.join(' ')}</p>
				{/if}
				<TextField
					label="Name"
					name="name"
					bind:value={editName}
					required
					maxlength={200}
					errors={editErrors.name ?? []}
				/>
				<SelectField
					label="Type"
					name="account_type"
					bind:value={editType}
					required
					options={accountTypeOptions}
					hint="How this account is grouped — cash, investment, retirement, crypto, real estate, or liability."
					errors={editErrors.account_type ?? []}
				/>
				<TextField
					label="Scope"
					name="scope"
					bind:value={editScope}
					required
					maxlength={200}
					hint="Your own ownership label (e.g. personal, joint, trust) — used to group accounts across views."
					errors={editErrors.scope ?? []}
				/>
				<SelectField
					label="Tax treatment"
					name="tax_treatment"
					bind:value={editTax}
					required
					options={taxTreatmentOptions}
					hint="How the account is taxed: taxable, tax-deferred, or tax-free. Feeds the estimated-tax view."
					errors={editErrors.tax_treatment ?? []}
				/>
				<div class="edit-actions">
					<Button type="submit" variant="primary" loading={saving}>Save changes</Button>
					<Button type="button" variant="secondary" onclick={cancelEditor}>Cancel</Button>
				</div>
			</form>
		{:else}
			<dl class="attrs">
				<div class="attr">
					<dt>Type</dt>
					<dd>{accountTypeLabel(account.account_type)}</dd>
					<p class="attr-hint">How this account is grouped — depository (cash), investment, retirement, crypto, real estate, or liability.</p>
				</div>
				<div class="attr">
					<dt>Scope</dt>
					<dd>{account.scope}</dd>
					<p class="attr-hint">Your own ownership label (e.g. personal, joint, trust) — used to group accounts across views.</p>
				</div>
				<div class="attr">
					<dt>Tax treatment</dt>
					<dd>{taxTreatmentLabel(account.tax_treatment)}</dd>
					<p class="attr-hint">How the account is taxed: taxable, tax-deferred, or tax-free. Feeds the estimated-tax view.</p>
				</div>
			</dl>
		{/if}
	</section>

	<!--
		Holdings (SELF-325 P-b, UX ruling 2026-08-21). Minimal — exists to make the LOUD unpriced
		state observable at any later time, not only at the purchase confirmation that produced
		it, and NEVER as a portfolio view. NO valuation/cost-basis/market-price column: no
		per-holding valued read exists (Architect, measured) and building one is explicitly out
		of scope — NAV/allocation aggregates are a separate follow-up (team-lead).

		PLACEMENT (UX ruling): here, immediately after "Account details" and before "Account
		linking & aggregation" — grouped with the page's other current-STATE sections, ahead of
		the activity/action sections below. Deliberately NOT positioned beside "Record a stock
		split": that section is source-of-truth-gated (hidden for provider-linked accounts via
		`isSourceOfTruth`), but Holdings must render for EVERY account — coupling their position
		would leave a provider-linked account with an orphaned gap where Holdings should be.

		EMPTY STATE DOUBLES AS THE CLOSED-ACCOUNT STATE (UX ruling): `058`'s gate leg 1 refuses a
		close while the account still holds positions, so `heldSecurities` is guaranteed empty
		once `closed_at` is set — no separate "closed" branch needed here, unlike the sections
		below that carry their own `isClosed` copy.

		Status column ALWAYS renders (header included) — "empty cell, never a missing one", the
		same rule the Transactions table's Actions column already follows when frozen. A priced
		row's Status cell is genuinely BLANK (UnpricedMarker's own zero-footprint discipline) —
		that blankness IS the "priced" signal; UX ruled explicitly against a redundant "priced"
		chip for the all-priced case. Table shell reuses the page's `.table-scroll` / `.tbl`
		classes and `<th scope="col">` pattern (same as the Transactions table below) — no new
		table styling.
	-->
	<section class="region" aria-label="Holdings">
		<h2 class="section-title">Holdings</h2>
		{#if heldSecurities.length === 0}
			<p class="empty">No holdings in this account.</p>
		{:else}
			<div class="table-scroll">
				<table class="tbl">
					<thead>
						<tr>
							<th scope="col">Security</th>
							<th scope="col" class="num">Quantity</th>
							<th scope="col">Status</th>
						</tr>
					</thead>
					<tbody>
						{#each heldSecurities as h (h.security_id)}
							<tr>
								<td>{securityLabel(h)}</td>
								<td class="num num-cell">{h.quantity}</td>
								<td><UnpricedMarker priced={h.priced} context="inline" /></td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>

	<!--
		Account linking & aggregation (connections-redesign). Shows how this account is fed:
		aggregator service (provider or manual), connection health, last sync, the descriptive
		daily-sync line + per-account "Sync now" for linked accounts, and a discoverable (grayed)
		"Change aggregator" placeholder — the affordance is present now; the backend lands later.
	-->
	<section class="region" aria-label="Account linking &amp; aggregation">
		<h2 class="section-title">Account linking &amp; aggregation</h2>
		<dl class="attrs">
			<div class="attr">
				<dt>Aggregator service</dt>
				<dd>{connection ? providerLabel(connection.provider) : 'None (manual)'}</dd>
				<p class="attr-hint">
					The data aggregator that syncs this account. Manual accounts have no aggregator — you
					update them by hand.
				</p>
			</div>
			{#if connection}
				<div class="attr">
					<dt>Connection status</dt>
					<dd>
						<ConnectionStatusChip
							connection_status={connection.connection_status}
							provider={connection.provider}
						/>
					</dd>
				</div>
				<div class="attr">
					<dt>Last synced</dt>
					<dd>{formatSyncTime(connection.last_successful_sync_at)}</dd>
				</div>
			{/if}
		</dl>

		{#if isLinked}
			<p class="sync-note">Syncs automatically (daily).</p>
			<div class="agg-actions">
				<SyncNowControl source_id={String(account.linked_source_id)} />
			</div>
		{/if}

		<div class="agg-change">
			<Button variant="secondary" disabled aria-describedby="change-agg-note">
				Change aggregator
			</Button>
			<p id="change-agg-note" class="agg-note">
				Coming soon — switching an account's aggregator isn't available yet.
			</p>
		</div>
	</section>

	<section class="region" aria-label="Account status">
		<h2 class="section-title">Account status</h2>

		{#if isClosed}
			<!--
				PM COPY RULING (2026-08-04): SHIP AS IS. Every clause earns its place, and the last
				one earns it most. "Reopen it, make the correction, and close it again" is the right
				level of detail for help text and does NOT belong behind a disclosure, because the
				affordance it explains — the "Reopen account" button — is already on screen and
				MISREADS WITHOUT IT: unlabelled, reopening looks like an admission that the closure
				was a mistake, so a user with a genuine correction to make will not press it and will
				conclude the history is frozen. Naming reopen as the correction MECHANISM (Decision
				3's reopen → edit → re-close) is what makes the visible control legible.

				The sync sentence is the second-most valuable and is easy to under-rate: a user
				closing a still-connected account otherwise has no way to know provider writes will
				be refused (Decision 6 surfaces those only as a quarantine counter — the user sees
				nothing). Keep it.

				NOT copy, flagged onward: `closedAtLabel` formats in UTC, so a close at 18:00 PDT
				renders tomorrow's date next to copy that then says "on or after that day".
			-->
			<p class="help">
				Closed {closedAtLabel(account.closed_at)}. Its transaction history is kept, and it no
				longer counts toward balances or totals dated on or after that day. While it's closed
				it can't take new entries — including automatic ones from a connected institution. To
				correct something, reopen it, make the correction, and close it again.
			</p>
		{:else}
			<!--
				This copy NAMES THE GATE rather than describing a label change, because `058` refuses
				a close that the user has every reason to expect will succeed.

				PM COPY RULING (2026-08-04) — the instinct is right, the dose was too high, and ONE
				CLAUSE OF IT WAS NOT TRUE OF THIS FORM.

				(1) REQUIRED FIX, not taste: "on the closing date" named a control that does not
				    exist. This form posts `reason_code` and nothing else; `p_closed_at` defaults to
				    server `now()` (see `closeAccountSchema`). Copy must not name a variable the UI
				    does not expose.

				    ⚠ REFINED, because the paragraph now says "from its closing date onward" and a
				    flat reading of the rule above would forbid exactly that. The rule is about a
				    date the user must CHOOSE, not a date the account HAS. "Close it as of a later
				    date" is forbidden — it demands an input this form has no control for. "From its
				    closing date onward" is fine and is now REQUIRED, because the account genuinely
				    has one and the page renders it. **The test is whether the phrase implies an
				    input, not whether it contains the word "date".** Stated because the two readings
				    are one word apart and the narrow one would delete a correction.

				(2) ⚠ THE TRIM WAS REVERSED, AND THE NOTE IS KEPT BECAUSE ITS DEPENDENCY IS WHAT
				    REVERSED IT. This paragraph used to enumerate only the two legs a user can be
				    holding TODAY, on the reasoning that the third — activity dated after closure,
				    which with `closed_at = now()` is exactly "a future-dated transaction" — was
				    covered by the refusal. That trim was recorded WITH its dependency: it assumed
				    the post-closure refusal was fixed, and said in as many words that if the
				    refusal was not corrected, the leg must come back here.

				    IT WAS CORRECTED, AND THAT DOES NOT REOPEN THE TRIM. `c06c984`, on this
				    branch, rewrote `GATE_LEG_MESSAGE['post-closure']` off "Close it as of a
				    later date" — which named a date control this form does not have
				    (`closeAccount` posts `reason_code` only; `p_closed_at` is always server
				    `now()`) — to "This account has entries dated in the future. Remove or
				    re-date them, or wait until those dates have passed, then close it." That
				    string implies no input and is correct as it stands. The six words are back
				    (PM ruling) and they STAY — unconditionally, on UX's finding below. Nothing
				    in this note licenses removing them.

				    Two things worth keeping from how this played out. First: **the dependency
				    fired as written, which is the whole reason it was written down** — the trim
				    was revisited rather than rediscovered, and a stated assumption is what made
				    that a one-line check instead of an archaeology problem. Second, UX's finding,
				    which outranks the trim argument entirely: leg 3 is the LEAST SELF-DERIVABLE
				    of the three. A user can guess that "emptied" covers securities and cash.
				    **Nobody guesses that a future-dated transaction blocks closing.** So even a
				    perfect refusal would not make this leg safe to omit — the refusal teaches it
				    only to someone who has already hit it. THAT is why the leg stays, and it is
				    conditional on nothing.

				    And the warning this episode is actually worth, which is sharper than the
				    first lesson: the version of this note written in `99dede8` asserted the
				    refusal "was not corrected" — ONE COMMIT AFTER `c06c984` corrected it. Its
				    condition was already met the moment it was written, so a correctly-shaped
				    conditional ("keep this until X") had silently become a removal-license
				    aimed at the copy it existed to protect. A conditional in a comment is a
				    live claim about the tree: check it against the tree as you write it, and
				    prefer the unconditional reason whenever one exists.

				(3) Why trimming is safe, and the correction to the argument that produced the long
				    form: ADR-042 Decision 1 does NOT fence "learning a precondition from a
				    refusal". Verbatim, it fences a DEAD END — *"the refusal message must name it so
				    the gate is not a dead end"* — and it places that burden on the refusal, which
				    it treats as the teaching surface. That burden is largely discharged:
				    `GATE_LEG_MESSAGE` in `+page.server.ts` names the failing leg AND its remedy for
				    each CLASSIFIED leg (its `other` fallback names neither, and `cash-contract` is
				    byte-identical to `cash` by Sec's ruling — so four visible strings over six
				    keys; do not restate that as a leg count anywhere).

				(4) BUT THE TRIM IS NOT THE WHOLE JOB, and UX corrected the ordering — on my
				    replacement, not only on the original. Both the brief's framings assume this
				    paragraph's job is to PREVENT a refusal. It isn't. Its job is to say what
				    closing MEANS: a bookkeeping event with a zero precondition, not a way to get a
				    row out of sight. Someone holding the second model closes an account that still
				    holds value and is confused by the refusal EVEN IF THE REFUSAL IS PERFECT,
				    because it contradicts their reading of the verb. So the precondition is not an
				    edge case being front-loaded — it is the definition. What was actually wrong was
				    ORDER: leading with the constraint makes the common case (empty account, just
				    close it) read a restriction first. Now the verb is defined by what it DOES,
				    reversibility lands early where it defuses hesitation, and the precondition
				    follows as a CONSEQUENCE ("because of that") rather than as an arbitrary rule —
				    still landing before the button.

				(5) NOT changed, deliberately: "holds securities or cash" stays a QUANTITY claim.
				    Decision 3 measures holdings quantity-based via `fn_holdings_as_of` precisely
				    because an unpriced asset fails a market-value test OPEN. So "empty" here must
				    never become "worth nothing" or "zero balance" — those are the wrong test, and
				    an account that reads as worth nothing can still be refused.

				(6) "Stops accepting new entries" is load-bearing and is NOT redundant with the
				    closed-state copy, which the user only reads AFTER closing. Said here, it is
				    the one warning that reaches a user who is about to close an account they are
				    still posting to.

				(7) ⚠ THIS PARAGRAPH MAKES NO DAY-CLAIM, AND THAT IS THE POINT. It said "marks it
				    finished as of today"; it now says "from its closing date onward". PM's
				    correction of their own line, found by UX.

				    "Today" was a promise this page can CONTRADICT SECONDS LATER. `closedAtLabel`
				    renders in UTC by deliberate design (see `account-display.ts`, and `059`'s
				    column comment at the DDL layer), so a close at 18:00 Pacific prints
				    "Closed 5 Aug" to a user whose today is the 4th. The copy would have said
				    "today" and the very next render would have named a different day.

				    "From its closing date onward" is true of WHATEVER date the render prints, so
				    the two cannot disagree — the fix is the absence of a day-claim, not a better
				    one. It also matches the closed-state copy's "dated on or after that day".

				    ⛔ DO NOT "FIX" THE UTC RENDERING TO LOCAL to make "today" work again. The UTC
				    choice is deliberate and load-bearing: the ledger renders UTC and `058`'s gate
				    evaluates as of the same instant, so a local render would show the account
				    closed the day BEFORE the entries the gate checked. **The three surfaces
				    agreeing is the property protecting them — it is not the same defect copied
				    three times.** Ruled by UX for V1 (UTC stays, unlabelled).
			-->
			<p class="help">
				Closing an account marks it finished: from its closing date onward it stops
				counting toward your balances and totals, and stops accepting new entries. Its
				transaction history is kept, and you can reopen it at any time. Because of that, an
				account can only be closed once it's empty and has no transactions dated in the
				future — if it still holds securities or cash, record the sale or transfer out
				first.
			</p>
		{/if}

		{#if form && 'errors' in form && form.errors?._form}
			<p class="form-error" role="alert">{form.errors._form.join(' ')}</p>
		{/if}

		<!--
			TWO FORMS, NOT A TOGGLE — mirroring Backend's two named actions, which mirror the two
			INVOKER RPCs (`fn_close_account` / `fn_reopen_account`). One form posting a direction
			boolean is what `059` retired; the directions carry different payloads.
		-->
		{#if isClosed}
			<!--
				REOPEN posts NOTHING. `reopenAccountSchema` is `z.object({}).strict()` server-side, so
				a stray field is a 400, not an ignored value. Keep it that way: no hidden inputs, and
				`Button` must stay `name`-less (a named submit button posts its own name/value).
				Reopening is deliberately UNGATED (Decision 3) — a closed account is already at zero
				by the gate that admitted it, so gating the exit would be incoherent.
			-->
			<form method="POST" action="?/reopenAccount" use:enhance={reopenHandler}>
				<Button type="submit" variant="primary" loading={submitting}>Reopen account</Button>
			</form>
		{:else}
			<form method="POST" action="?/closeAccount" use:enhance={closeHandler} class="close-form">
				<!--
					reason_code is MANDATORY on the into-closed transition (`057`'s CHECK; `058`'s audit
					writer refuses without it and will not invent one). Values come from the shared
					account-constants, copied verbatim from the CHECK — the LABELS are placeholders
					pending PM + UX copy. Reopening carries no reason vocabulary at all, which is why
					this control lives only on the close branch.

					THE EMPTY PLACEHOLDER IS DELIBERATE and is a change from the hand-rolled <select>
					that stood here, which auto-selected the first reason. That reason is written into
					`pfin.account_event`, which is IMMUTABLE audit-class (ADR-011 Decision 2) — so a
					defaulted reason records a fact the user never asserted, in the one table that
					cannot later be corrected. "Sold" and "no longer used" are not interchangeable to
					anyone reading that history back. The empty value fails the client mirror's
					`z.enum` and renders inline, so the cost of requiring a choice is one visible
					error rather than a silent falsehood.

					Rendered through the design-system SelectField rather than a raw <select>: the
					hand-rolled one carried no token styling, no aria-invalid/describedby wiring and
					no error slot at all.
				-->
				<SelectField
					label="Reason for closing"
					name="reason_code"
					bind:value={reasonCode}
					required
					placeholder={{ value: '', label: 'Select a reason…' }}
					options={closureReasonOptions}
					errors={closeErrors.reason_code ?? []}
				/>
				<div class="close-actions">
					<Button type="submit" variant="secondary" loading={submitting}>Close account</Button>
				</div>
			</form>
		{/if}
	</section>

	<!--
		FROZEN-ACCOUNT WRITE CONTROLS (F1a). ADR-042 Decision 3: every write into a closed account
		is REJECTED by `058`'s fence. These controls used to render live and enabled on a closed
		account, so the user got "Could not save the transaction. Please try again." — retry advice
		for something that can never succeed.

		REPLACED, not hidden and not `disabled`. F/CTO ruled the mechanism as "disable + named
		reason"; the refinement to replacement was escalated by UX and CONFIRMED by F/CTO — the
		reason stands untouched, only the carrier moves.
		  · not HIDDEN — an absence cannot name its own cause. A vanished section reads as "this
		    feature doesn't apply to this account", and the remedy is then discoverable only by
		    connecting an absence to a section further up the page. (Contrast `isSourceOfTruth`
		    below, which correctly hides: that condition is permanent and the user cannot lift it.
		    Closed is a condition the user CAN lift, which is why it must state itself.)
		  · not `disabled` — right for `Change aggregator`, which is ONE button. Wrong for a
		    multi-field form and N per-row action pairs, where it leaves a large amount of dead
		    tabbable UI and noise proportional to the user's transaction history.
		The section and its heading stay, so the page's shape is stable across open→closed and the
		remedy is stated where the intent was formed.

		⚠ THIS IS NOT A FENCE. The write stays reachable from a stale tab, a second window, or a
		provider sync landing on a freshly-closed account. `058` is the enforcement. This reduces
		how often the refusal is seen; it does not make it unreachable, and Backend's classification
		of that raise is the other half — neither alone is sufficient.

		NO reopen control here (Decision 1b): closure has one home, and a second control elsewhere
		spends the cost D1b deliberately accepted. The path is named in words.
	-->
	<section class="region" aria-label="Add a transaction">
		<h2 class="section-title">Add a transaction</h2>
		{#if isClosed}
			<p class="frozen-note">
				This account is closed, so it can't take new entries. To add one, reopen it under
				Account status above, add the transaction, then close it again.
			</p>
		{:else}
			<!--
				SELF-325: Cash (040) vs Purchase (088) are TWO DIFFERENT RPCs with different shapes —
				not a variant of the same form — so the toggle switches components entirely rather
				than branching fields within one. Each form keeps its own local state; switching away
				and back discards an unsubmitted purchase in progress (mirrors TransactionRow's
				activeMode reset — an abandoned entry is not persisted state).
			-->
			<fieldset class="entry-mode">
				<legend>Entry type</legend>
				<div class="seg" role="radiogroup" aria-label="Cash or purchase">
					<label class="seg-opt" class:active={entryMode === 'cash'}>
						<input
							type="radio"
							name="entry-mode"
							value="cash"
							checked={entryMode === 'cash'}
							onchange={() => (entryMode = 'cash')}
						/>
						<span>Cash</span>
					</label>
					<label class="seg-opt" class:active={entryMode === 'purchase'}>
						<input
							type="radio"
							name="entry-mode"
							value="purchase"
							checked={entryMode === 'purchase'}
							onchange={() => (entryMode = 'purchase')}
						/>
						<span>Purchase</span>
					</label>
				</div>
			</fieldset>
			{#if entryMode === 'cash'}
				<TransactionEntryForm subCatGroups={cashflowGroups} />
			{:else}
				<PurchaseEntryForm {selectableAssets} {defaultSubCatId} {defaultSubCatLabel} />
			{/if}
		{/if}
	</section>

	<!--
		Stock-split entry (SELF-203). Source-of-truth gate (OWD-2 / ADR-033): only rendered for
		non-provider-linked accounts. A provider-linked account's splits come via reconciliation
		(SELF-204) — showing manual entry there would be a conflicting write path.
	-->
	{#if isSourceOfTruth}
		<section class="region" aria-label="Record a stock split">
			<h2 class="section-title">Record a stock split</h2>
			<!--
				THREE NESTED CONDITIONS, DELIBERATELY NOT COLLAPSED. `isSourceOfTruth`, `isClosed`
				and "no securities held" are three DIFFERENT facts with three different remedies —
				permanent / user-liftable / data-dependent — and folding any two into one condition
				is this ADR's own failure mode one layer up. (UX caught the temptation; the shorter
				expression is the wrong one.) Order matters too: source-of-truth is the outermost
				because it is the only one that means "this control does not belong here at all".
			-->
			{#if isClosed}
				<p class="frozen-note">
					This account is closed, so it can't take new entries. Reopen it under Account status
					above to record a split, then close it again.
				</p>
			{:else if heldSecurities.length === 0}
				<p class="empty">No securities held in this account to split.</p>
			{:else}
				<StockSplitEntryForm securities={heldSecurities} />
			{/if}
		</section>
	{/if}

	<!--
		Candidate-duplicate DETECTION surface (SELF-204). Read-only — surfaces manual entries that
		look like a synced provider transaction so the user can reconcile them through existing
		mechanisms. NO action affordance here (resolution is SELF-205). Empty-state when none.
	-->
	<section class="region" aria-label="Possible duplicates">
		<h2 class="section-title">Possible duplicates</h2>
		<DuplicateCandidateList candidates={dupCandidates} />
	</section>

	<section class="region" aria-label="Transactions">
		<h2 class="section-title">Transactions</h2>
		{#if transactions.length === 0}
			<p class="empty">No transactions yet.</p>
		{:else}
			<!--
				ONE note above the table, not N disabled button pairs in it. The rows keep their data
				in full (SELF-201 AC #4 — a closed account retains its history); only the per-row
				write controls go, via TransactionRow's `frozen` prop.

				⚠ The Actions column header STAYS when frozen. Dropping it would change TABLE_COLUMNS,
				and that constant is what TransactionRow's full-width editor rows span via `colspan`.
				An empty cell, never a missing one — the coupling runs through this constant and is
				not visible from either file alone.
			-->
			{#if isClosed}
				<p class="frozen-note">
					This account is closed, so its transactions can't be edited. Reopen it under Account
					status above to make a correction, then close it again.
				</p>
			{/if}
			<div class="table-scroll">
				<table class="tbl">
					<thead>
						<tr>
							<th scope="col">Date</th>
							<th scope="col">Category</th>
							<th scope="col">Vendor</th>
							<th scope="col">Description</th>
							<th scope="col" class="num">Amount</th>
							<th scope="col">Actions</th>
						</tr>
					</thead>
					<tbody>
						{#each transactions as t (t.trans_id)}
							<TransactionRow
								transaction={t}
								subCatGroups={cashflowGroups}
								columns={TABLE_COLUMNS}
								frozen={isClosed}
							/>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>

	<!--
		Per-account sync history (SELF-204). Rendered ONLY for provider-linked accounts (a manual
		account has no sync history); the component's empty-state covers a linked account with no
		history rows yet. Read-only — no edit/delete affordance (AC requirement, RBAC-tested).
	-->
	{#if !isSourceOfTruth}
		<section class="region" aria-label="Sync history">
			<h2 class="section-title">Sync history</h2>
			<!--
				The per-account "Sync now" (SELF-317) control now lives in the "Account linking &
				aggregation" section above (its canonical connections-redesign home) — deduped so a
				linked account shows a single Sync-now affordance. This panel keeps the history table.
			-->
			<SyncHistoryTable rows={syncHistory} />
		</section>
	{/if}
</main>

<style>
	.page {
		max-width: 52rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.breadcrumb {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.breadcrumb a {
		color: var(--c-link);
		text-decoration: none;
	}
	.breadcrumb a:hover {
		text-decoration: underline;
	}
	.breadcrumb .sep {
		color: var(--c-text-muted);
	}
	.breadcrumb .crumb-current {
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.title {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.cashflow-link {
		align-self: flex-start;
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
	}
	.cashflow-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	.cashflow-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	h1 {
		margin: 0;
		font-size: var(--fs-h1);
		font-weight: var(--weight-bold);
		line-height: var(--lh-tight);
		color: var(--c-text-primary);
	}
	.status {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-pill);
		padding: 1px var(--space-2);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
		background: var(--c-surface);
	}
	/* Closed = muted + dashed. Deliberately NOT --c-neg: a closed account is a bookkeeping
	   state, not an error or a negative value, and --c-neg is reserved for ACTUAL-performance
	   amounts (the page's standing fence). Tone is carried by weight + border style. */
	.status.closed {
		color: var(--c-text-muted);
		border-style: dashed;
	}
	.region {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		box-shadow: var(--shadow-1);
	}
	.section-title {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.attrs {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-4);
		margin: 0;
	}
	@media (max-width: 560px) {
		.attrs {
			grid-template-columns: 1fr;
		}
	}
	.attr {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		min-width: 0;
	}
	.attr dt {
		font-size: var(--fs-small);
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--c-text-muted);
		font-weight: var(--weight-semi);
	}
	.attr dd {
		margin: 0;
		color: var(--c-text-primary);
		overflow-wrap: anywhere;
	}
	.attr-hint {
		margin: var(--space-1) 0 0;
		font-size: var(--fs-small);
		line-height: var(--lh-body);
		color: var(--c-text-muted);
	}
	.help {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		max-width: 44rem;
	}
	.form-error {
		margin: 0 0 var(--space-3);
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.section-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		margin-bottom: var(--space-3);
	}
	.section-head .section-title {
		margin: 0;
	}
	.edit-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.edit-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-1);
	}
	/* Close form — same column rhythm as .edit-form so the two forms on this page match. */
	.close-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		max-width: 24rem;
	}
	.close-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.sync-note {
		margin: var(--space-3) 0 var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.agg-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.agg-change {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		margin-top: var(--space-4);
		padding-top: var(--space-3);
		border-top: 1px solid var(--c-border);
	}
	.agg-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.table-scroll {
		overflow-x: auto;
	}
	.tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	/* Header cells live in this component; body cells (<td>) are rendered by TransactionRow,
	   so the td-level rules are :global-scoped to this page-owned .tbl to reach them. */
	.tbl th,
	.tbl :global(td) {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
		white-space: nowrap;
	}
	.tbl th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.tbl :global(td.num),
	.tbl th.num {
		text-align: right;
	}
	.tbl :global(.num-cell) {
		font-family: var(--font-num);
	}
	.tbl :global(tbody tr:hover td) {
		background: var(--c-surface-alt);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
	}
	/* Sibling of .empty and DELIBERATELY NOT italic, because it is a different fact: .empty means
	   "nothing here yet"; this means "the action is unavailable and here is how to make it
	   available". Collapsing the two would be the third conflation in this family. Matches .help
	   visually; kept as its own class so pm-copy can find these strings by class name. */
	.frozen-note {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		max-width: 44rem;
	}
	/* SELF-325 Cash/Purchase entry-mode toggle — same segmented-control visual idiom as
	   TransactionFactFields' Direction toggle (component-scoped there, so reproduced here
	   rather than shared, same as every other page-local .seg on this page family). */
	.entry-mode {
		border: 0;
		margin: 0 0 var(--space-3);
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.entry-mode legend {
		padding: 0;
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.entry-mode .seg {
		display: inline-flex;
		gap: 0;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		overflow: hidden;
		width: fit-content;
	}
	.entry-mode .seg-opt {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2) var(--space-3);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
		cursor: pointer;
	}
	.entry-mode .seg-opt + .seg-opt {
		border-left: 1px solid var(--c-border-strong);
	}
	.entry-mode .seg-opt.active {
		background: var(--c-accent-soft);
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
	}
	.entry-mode .seg-opt input {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}
	.entry-mode .seg-opt:focus-within {
		box-shadow: inset 0 0 0 2px var(--c-accent);
	}
</style>
