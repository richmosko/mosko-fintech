<!--
	PurchaseEntryForm.svelte — the manual INSTRUMENT-PURCHASE entry surface (SELF-325 / 088,
	§2.4.3 manual-entry extension). Sibling of TransactionEntryForm.svelte (cash); the two are
	toggled on accounts/[account_id]'s "Add a transaction" section by a Cash/Purchase fork.

	F/CTO REQUIREMENT (verbatim, relayed 2026-08-21): "the purchase picker must make the fork
	explicit — 'market security' (enter ticker → global resolve) vs 'personal asset' (name it →
	mints owned, like the create flow). Validation should nudge a ticker-looking string typed
	into the personal-asset path toward resolve." That fork is `fork` below; the nudge is
	`looksLikeTicker` (schemas/purchase.ts), applied only to the MINT `asset_name` field.

	TWO-STEP FLOW for the market-security fork, mirroring 088's own BIND/MINT split:
	  (1) IDENTIFY the security — either pick one already in `selectableAssets` (own + global;
	      no network round trip needed, the RPC's own asset read does the rest), OR — for a
	      ticker/CUSIP not yet in that list — `doResolve()` POSTs JSON to `/api/asset/resolve`
	      (a plain fetch endpoint, NOT a SvelteKit form action — Backend, SendMessage
	      2026-08-21: "a security lookup step the purchase form calls BEFORE it can submit,
	      the same shape as an autocomplete/picker read"), which forwards to the provider-sync
	      worker's /asset/resolve route and resolves-or-mints a GLOBAL pfin.asset row. Its
	      result sets `boundAssetId`.
	  (2) Once an asset is bound (existing pick OR resolve success), the PURCHASE form itself
	      appears: quantity / total cost (with a derived per-unit price preview) / trade date /
	      description / note, POSTing `mode: 'bind'` + `security_id` to the EXISTING
	      `accounts/[account_id]` route's `?/createPurchase` action (no new route).
	The personal-asset (MINT) fork skips step (1) entirely — asset_type + asset_name (+ optional
	symbol) are inline fields on the SAME purchase form, `mode: 'mint'`.

	⚠ ASSET-TYPE VOCABULARY SPLIT (F/CTO + Architect ruling, 2026-08-21, relayed by team-lead —
	held until landed, now CONFIRMED at commit a9ba25e): `resolveAssetTypeOptions` (the identify
	step's picker) offers ONLY `RESOLVABLE_ASSET_TYPES` — the 9 feed-priceable types.
	`mintAssetTypeOptions` (the MINT fork's picker) offers `MINT_ASSET_TYPES` — the full 13,
	including the 4 personal types (real_estate/vehicle/collectible/private). This makes the
	house/car boundary STRUCTURAL, not merely labeled: a personal type is not a selectable
	<option> in the resolve dropdown at all, so it cannot reach the resolve call through this
	UI — see schemas/purchase.ts's header for why (routing a house through resolve would mint a
	permanently unpriceable, unrepairable global row).

	CONTRACT CONFIRMED (Backend, SendMessage 2026-08-21, superseding this file's earlier
	EXPECTED-CONTRACT draft): action name `?/createPurchase` (guessed correctly), field names
	un-prefixed (also guessed correctly), success payload `{ success, transId, securityId,
	priced, price }` (also guessed correctly) — the ONE real correction was the resolve step's
	transport (fetch+JSON, not a form action) and the vocabulary narrowing above.

	BTO CATEGORY DEFAULT: 088's header names this an APP-LAYER decision, not the RPC's — "this
	function does NOT default the category... the RECOMMENDATION is that the manual-purchase form
	defaults the category to the user's BTO row where one exists". Per the team-lead brief,
	Backend's load() computes and supplies it; this component RENDERS `defaultSubCatLabel`
	read-only and posts `defaultSubCatId` as a hidden field — it does not compute the match itself
	(single-authority discipline, same reason 088's body doesn't guess at a per-user taxonomy).

	THE LOUD UNPRICED STATE (UnpricedMarker, context="confirmation") is a HARD CONDITION of this
	surface, not polish — see UnpricedMarker.svelte's header for the full ruling. It renders off
	the RPC's own `priced` composite-return flag once a purchase is recorded.

	Client `.strict()`-posture Zod mirror (schemas/purchase.ts) runs before either POST for fast
	field-level feedback; the RPC's own raises (088) are the security boundary. Tokens only
	(var(--c-*)) — no hardcoded color/spacing/type.
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import UnpricedMarker from '$lib/components/UnpricedMarker.svelte';
	import {
		assetResolveSchema,
		createPurchaseSchema,
		looksLikeTicker,
		fieldErrors
	} from '$lib/schemas/purchase';
	import { RESOLVABLE_ASSET_TYPES, MINT_ASSET_TYPES } from '$lib/schemas/asset-constants';
	import {
		selectableAssetLabel,
		assetTypeLabel,
		derivedPerUnitPrice,
		formatPrice,
		type SelectableAssetOption
	} from '$lib/purchase-util';

	let {
		selectableAssets,
		defaultSubCatId = null,
		defaultSubCatLabel = null
	}: {
		/** Own + global pfin.asset rows the caller can bind to (Backend's selectableAssets.ts). */
		selectableAssets: SelectableAssetOption[];
		/** The caller's BTO Sub-Cat id, Backend-resolved — render only, never computed here. */
		defaultSubCatId?: number | null;
		defaultSubCatLabel?: string | null;
	} = $props();

	// THE STRUCTURAL FORK (see file header): two DIFFERENT vocabularies, not one filtered two
	// ways. `resolveAssetTypeOptions` drives the identify step's picker — a personal type is
	// simply not an <option> there, so it cannot reach the resolve call through this UI.
	// `mintAssetTypeOptions` drives the MINT fork's picker — the superset (13 = all 14 minus
	// currency, which is structurally excluded from MINT_ASSET_TYPES itself, not filtered here).
	const resolveAssetTypeOptions = RESOLVABLE_ASSET_TYPES.map((t) => ({
		value: t,
		label: assetTypeLabel(t)
	}));
	const mintAssetTypeOptions = MINT_ASSET_TYPES.map((t) => ({
		value: t,
		label: assetTypeLabel(t)
	}));

	const existingAssetOptions = $derived(
		selectableAssets.map((a) => ({ value: String(a.asset_id), label: selectableAssetLabel(a) }))
	);

	// ── Fork (F/CTO-ratified explicit choice) ────────────────────────────────────────────────
	let fork = $state<'market' | 'personal'>('market');

	function switchFork(next: 'market' | 'personal') {
		fork = next;
		// Crossing forks invalidates any half-completed identity step from the other side.
		boundAssetId = null;
		boundAssetLabel = '';
		pickedAssetId = '';
		showResolve = false;
		errors = {};
	}

	// ── Market-security identify step ────────────────────────────────────────────────────────
	let pickedAssetId = $state('');
	let boundAssetId = $state<number | null>(null);
	let boundAssetLabel = $state('');

	function useExistingPick() {
		const id = Number(pickedAssetId);
		const found = selectableAssets.find((a) => a.asset_id === id);
		if (!found) return;
		boundAssetId = id;
		boundAssetLabel = selectableAssetLabel(found);
	}

	function changeBoundAsset() {
		boundAssetId = null;
		boundAssetLabel = '';
		pickedAssetId = '';
	}

	let showResolve = $state(false);
	let resolveSymbol = $state('');
	let resolveCusip = $state('');
	let resolveAssetType = $state('');
	let resolveName = $state('');
	let resolveErrors = $state<Record<string, string[]>>({});
	let resolving = $state(false);

	// `/api/asset/resolve` is a plain fetch+JSON endpoint, NOT a SvelteKit form action (Backend,
	// confirmed) — so this is a bare async function, not a `SubmitFunction` for `use:enhance`.
	// The surrounding markup stays a real `<form>` (native Enter-key submit, a11y) but its
	// `onsubmit` calls this directly rather than posting anywhere.
	async function doResolve() {
		const parsed = assetResolveSchema.safeParse({
			symbol: resolveSymbol,
			cusip: resolveCusip,
			asset_type: resolveAssetType,
			name: resolveName
		});
		if (!parsed.success) {
			resolveErrors = fieldErrors(parsed.error);
			return;
		}
		resolveErrors = {};
		resolving = true;
		try {
			const res = await fetch('/api/asset/resolve', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					symbol: parsed.data.symbol,
					cusip: parsed.data.cusip,
					asset_type: parsed.data.asset_type,
					name: parsed.data.name
				})
			});
			let json: unknown = null;
			try {
				json = await res.json();
			} catch {
				json = null;
			}
			const body = (json ?? {}) as { assetId?: number | null; errors?: Record<string, string[]> };
			if (res.ok && typeof body.assetId === 'number') {
				boundAssetId = body.assetId;
				boundAssetLabel = resolveSymbol.trim() || resolveName.trim() || `Asset #${body.assetId}`;
				showResolve = false;
			} else if (res.ok) {
				// 200 with assetId: null — the endpoint ran but found/created nothing to bind to.
				resolveErrors = {
					_form: ["Couldn't find or create a match for that symbol or CUSIP. Check the details and try again."]
				};
			} else {
				resolveErrors = body.errors ?? { _form: ["Couldn't resolve that security. Please try again."] };
			}
		} catch {
			resolveErrors = { _form: ["Couldn't reach the server. Please try again."] };
		} finally {
			resolving = false;
		}
	}

	// ── Personal-asset (MINT) fork ────────────────────────────────────────────────────────────
	let mintAssetType = $state('');
	let mintAssetName = $state('');
	let mintSymbol = $state('');

	// F/CTO ruling: nudge, never block — see schemas/purchase.ts `looksLikeTicker`.
	const nameLooksLikeTicker = $derived(mintAssetName.trim().length > 0 && looksLikeTicker(mintAssetName));

	// ── The purchase itself (common to both forks once identity is settled) ─────────────────
	let tradeDate = $state('');
	let quantity = $state('');
	let costBasis = $state('');
	let description = $state('');
	let note = $state('');
	let errors = $state<Record<string, string[]>>({});
	let submitting = $state(false);
	let confirmation = $state<{
		transId: number;
		securityId: number;
		priced: boolean;
		price: number;
	} | null>(null);

	// Live per-unit preview — same derivation the schema's own fence uses (purchase-util.ts),
	// so the number shown here and the number that gates submit can never disagree.
	const previewPerUnit = $derived.by(() => {
		const q = Number(quantity);
		const c = Number(costBasis);
		if (!quantity || !costBasis || !Number.isFinite(q) || !Number.isFinite(c)) return null;
		return derivedPerUnitPrice(q, c);
	});

	// The purchase form only renders once identity is resolved: MINT is always ready (inline
	// fields); BIND needs `boundAssetId` from either the picker or a successful resolve.
	const identityReady = $derived(fork === 'personal' || boundAssetId !== null);

	function resetPurchaseFields() {
		tradeDate = '';
		quantity = '';
		costBasis = '';
		description = '';
		note = '';
	}

	const purchaseHandler: SubmitFunction = ({ formData, cancel }) => {
		const shape =
			fork === 'market'
				? { mode: 'bind' as const, security_id: String(boundAssetId ?? '') }
				: {
						mode: 'mint' as const,
						asset_type: mintAssetType,
						asset_name: mintAssetName,
						symbol: mintSymbol
					};
		const parsed = createPurchaseSchema.safeParse({
			...shape,
			trade_date: tradeDate,
			quantity,
			cost_basis: costBasis,
			sub_cat_id: defaultSubCatId ?? '',
			description,
			note
		});
		if (!parsed.success) {
			errors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		errors = {};
		// POST exactly the mode's own keys — drop whichever identity fields belong to the
		// OTHER mode so the server sees an unambiguous shape (mirrors TransactionEntryForm's
		// "delete the helper field" discipline).
		if (parsed.data.mode === 'bind') {
			formData.set('mode', 'bind');
			formData.set('security_id', String(parsed.data.security_id));
			formData.delete('asset_type');
			formData.delete('asset_name');
			formData.delete('symbol');
		} else {
			formData.set('mode', 'mint');
			formData.set('asset_type', parsed.data.asset_type);
			formData.set('asset_name', parsed.data.asset_name);
			formData.set('symbol', parsed.data.symbol ?? '');
			formData.delete('security_id');
		}
		formData.set('trade_date', parsed.data.trade_date);
		formData.set('quantity', String(parsed.data.quantity));
		formData.set('cost_basis', String(parsed.data.cost_basis));
		formData.set('sub_cat_id', parsed.data.sub_cat_id === null ? '' : String(parsed.data.sub_cat_id));
		formData.set('description', parsed.data.description ?? '');
		formData.set('note', parsed.data.note ?? '');

		submitting = true;
		confirmation = null;
		return async ({ result, update }) => {
			submitting = false;
			// EXPECTED CONTRACT — see file header: `{ success: true, transId, securityId, priced,
			// price }` on the happy path (088's own composite return, forwarded verbatim).
			if (result.type === 'success' && result.data && 'transId' in result.data) {
				const d = result.data as {
					transId: number;
					securityId: number;
					priced: boolean;
					price: number;
				};
				confirmation = d;
				resetPurchaseFields();
				boundAssetId = null;
				boundAssetLabel = '';
				pickedAssetId = '';
				mintAssetType = '';
				mintAssetName = '';
				mintSymbol = '';
				await update({ reset: false }); // re-invalidate load(); state already cleared above
			} else if (result.type === 'failure') {
				errors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not record the purchase. Please try again.'] };
			} else {
				await update();
			}
		};
	};
</script>

<div class="purchase-entry">
	<fieldset class="fork">
		<legend>What are you buying?</legend>
		<div class="seg" role="radiogroup" aria-label="Market security or personal asset">
			<label class="seg-opt" class:active={fork === 'market'}>
				<input
					type="radio"
					name="purchase-fork"
					value="market"
					checked={fork === 'market'}
					onchange={() => switchFork('market')}
				/>
				<span>Market security</span>
			</label>
			<label class="seg-opt" class:active={fork === 'personal'}>
				<input
					type="radio"
					name="purchase-fork"
					value="personal"
					checked={fork === 'personal'}
					onchange={() => switchFork('personal')}
				/>
				<span>Personal asset</span>
			</label>
		</div>
		<p class="fork-hint">
			{#if fork === 'market'}
				A publicly traded ticker — enter it and we'll resolve it against the shared security
				list.
			{:else}
				Something only you hold — a property, a vehicle, a private holding. Name it and we'll
				create it as yours.
			{/if}
		</p>
	</fieldset>

	{#if fork === 'market'}
		{#if boundAssetId === null}
			<div class="identify">
				<SelectField
					label="Security"
					name="picked_asset_id"
					bind:value={pickedAssetId}
					placeholder={{ value: '', label: '— choose —' }}
					options={existingAssetOptions}
					hint="Your own holdings and the shared security list."
				/>
				{#if pickedAssetId}
					<Button type="button" variant="primary" onclick={useExistingPick}>Use this security</Button>
				{/if}
				{#if !showResolve}
					<Button type="button" variant="link" onclick={() => (showResolve = true)}>
						Don't see it? Look up a ticker or CUSIP
					</Button>
				{/if}

				{#if showResolve}
					<!-- NOT a SvelteKit form action — `/api/asset/resolve` is a plain fetch+JSON
					     endpoint (Backend, confirmed). No `method`/`action`/`use:enhance`; `onsubmit`
					     prevents the native (non-JS) navigation and calls `doResolve()` directly. Kept
					     as a real `<form>` (not a bare `<div>`) so Enter-key submit + the existing
					     field-grouping semantics stay free. -->
					<form
						onsubmit={(e) => {
							e.preventDefault();
							doResolve();
						}}
						class="resolve-form"
						novalidate
					>
						{#if resolveErrors._form}
							<p class="form-error" role="alert">{resolveErrors._form.join(' ')}</p>
						{/if}
						<TextField
							label="Ticker symbol"
							name="symbol"
							bind:value={resolveSymbol}
							errors={resolveErrors.symbol}
							hint="e.g. AAPL, BRK.B — or leave blank and enter a CUSIP instead."
							autocomplete="off"
						/>
						<TextField
							label="CUSIP"
							name="cusip"
							bind:value={resolveCusip}
							errors={resolveErrors.cusip}
							hint="Optional — 9 characters, only needed if you don't have a ticker."
							autocomplete="off"
						/>
						<!-- RESOLVABLE_ASSET_TYPES only (the 9 feed-priceable types) — see file header. A
						     personal type is not a selectable option here at all. -->
						<SelectField
							label="Asset type"
							name="asset_type"
							bind:value={resolveAssetType}
							required
							placeholder={{ value: '', label: 'Select…' }}
							options={resolveAssetTypeOptions}
							errors={resolveErrors.asset_type}
						/>
						<TextField
							label="Name"
							name="name"
							bind:value={resolveName}
							errors={resolveErrors.name}
							hint="Optional — helps confirm we found the right one."
							autocomplete="off"
						/>
						<div class="actions">
							<Button type="submit" variant="primary" loading={resolving}>Look up</Button>
							<Button type="button" variant="secondary" onclick={() => (showResolve = false)}>
								Cancel
							</Button>
						</div>
					</form>
				{/if}
			</div>
		{:else}
			<p class="bound-asset">
				Buying <strong>{boundAssetLabel}</strong>.
				<Button type="button" variant="link" onclick={changeBoundAsset}>Change</Button>
			</p>
		{/if}
	{/if}

	{#if identityReady}
		<form method="POST" action="?/createPurchase" use:enhance={purchaseHandler} class="purchase-form" novalidate>
			{#if errors._form}
				<p class="form-error" role="alert">{errors._form.join(' ')}</p>
			{/if}

			<!--
				HIDDEN mode/security_id carriers — NOT just JS-set. `mode` and (for the market fork)
				`security_id` come from component STATE (the fork toggle, the identify step), not
				from a user-editable control, so they need a real named field in the DOM for the
				browser's own "constructing the form data set" algorithm to include them at all — the
				enhance handler's `formData.set(...)` calls below only MUTATE what already exists once
				JS runs; without a real control here a no-JS submit (or a `new FormData(form)` read
				of the raw DOM, as this component's own dom test does) would post `security_id`
				as entirely ABSENT rather than merely stale. (SymbolClassifyRow.svelte's opposite
				discipline — an intentionally NAME-LESS control — doesn't apply here: that pattern
				excludes a field; this one must ensure a field is present.)
			-->
			<input type="hidden" name="mode" value={fork === 'market' ? 'bind' : 'mint'} />
			{#if fork === 'market'}
				<input type="hidden" name="security_id" value={boundAssetId ?? ''} />
			{/if}

			{#if fork === 'personal'}
				<!-- MINT_ASSET_TYPES (the 13-type superset, incl. the 4 personal types) — see file
				     header. This is the ONLY picker in the component that offers them. -->
				<SelectField
					label="Asset type"
					name="asset_type"
					bind:value={mintAssetType}
					required
					placeholder={{ value: '', label: 'Select…' }}
					options={mintAssetTypeOptions}
					errors={errors.asset_type}
				/>
				<TextField
					label="Name"
					name="asset_name"
					bind:value={mintAssetName}
					required
					maxlength={200}
					errors={errors.asset_name}
					hint="What this is — e.g. '123 Main St' or 'Acme Holdings LLC'."
					autocomplete="off"
				/>
				{#if nameLooksLikeTicker}
					<p class="nudge" role="note">
						"{mintAssetName.trim()}" looks like a ticker symbol. If this is a publicly traded
						security, switch to <Button type="button" variant="link" onclick={() => switchFork('market')}>
							Market security
						</Button> and we'll resolve it against the shared security list instead of creating a
						private one.
					</p>
				{/if}
				<TextField
					label="Symbol"
					name="symbol"
					bind:value={mintSymbol}
					errors={errors.symbol}
					hint="Optional."
					autocomplete="off"
				/>
			{/if}

			<TextField
				label="Quantity"
				name="quantity"
				bind:value={quantity}
				required
				numeric
				inputmode="decimal"
				errors={errors.quantity}
				placeholder="0"
				autocomplete="off"
			/>
			<TextField
				label="Total cost"
				name="cost_basis"
				bind:value={costBasis}
				required
				numeric
				inputmode="decimal"
				errors={errors.cost_basis}
				hint="What you paid in total — the per-unit price is derived below."
				placeholder="0.00"
				autocomplete="off"
			/>
			{#if previewPerUnit !== null}
				<p class="preview" aria-live="polite">Per-unit price: {formatPrice(previewPerUnit)}</p>
			{/if}
			<TextField
				label="Trade date"
				name="trade_date"
				type="date"
				bind:value={tradeDate}
				required
				errors={errors.trade_date}
			/>

			{#if defaultSubCatLabel}
				<p class="category-note">Categorized as: <strong>{defaultSubCatLabel}</strong></p>
			{/if}

			<TextField
				label="Description"
				name="description"
				bind:value={description}
				errors={errors.description}
				hint="Optional."
				autocomplete="off"
			/>
			<TextField
				label="Note"
				name="note"
				bind:value={note}
				errors={errors.note}
				hint="Optional."
				autocomplete="off"
			/>

			<div class="actions">
				<Button type="submit" variant="primary" loading={submitting}>Record purchase</Button>
			</div>
		</form>
	{/if}

	{#if confirmation}
		<div class="confirmation" role="status">
			<p>Purchase recorded.</p>
			<UnpricedMarker priced={confirmation.priced} context="confirmation" />
		</div>
	{/if}
</div>

<style>
	.purchase-entry {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		max-width: 30rem;
	}
	.fork {
		border: 0;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.fork legend {
		padding: 0;
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.fork-hint {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.seg {
		display: inline-flex;
		gap: 0;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		overflow: hidden;
		width: fit-content;
	}
	.seg-opt {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2) var(--space-3);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
		cursor: pointer;
	}
	.seg-opt + .seg-opt {
		border-left: 1px solid var(--c-border-strong);
	}
	.seg-opt.active {
		background: var(--c-accent-soft);
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
	}
	.seg-opt input {
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
	.seg-opt:focus-within {
		box-shadow: inset 0 0 0 2px var(--c-accent);
	}
	.identify {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		align-items: flex-start;
	}
	.bound-asset {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.resolve-form,
	.purchase-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		width: 100%;
	}
	.form-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.nudge {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
		color: var(--c-text-secondary);
		font-size: var(--fs-small);
	}
	.preview {
		margin: 0;
		font-family: var(--font-num);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.category-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		justify-content: flex-end;
	}
	.confirmation {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
	}
	.confirmation p {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-primary);
	}
</style>
