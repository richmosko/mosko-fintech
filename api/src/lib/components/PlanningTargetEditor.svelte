<!--
	PlanningTargetEditor.svelte — the `planning-target-editor` primitive (design-system-spec.md
	§4 component inventory; ADR-013 P5's ONLY inline-edit surface for the four planning
	values — this one edits §2.2.2 %Target). SELF-242. Frontend-owned browser surface.

	CONTRACT (props):
	  catalog        : { id, cat, sub_cat, display_order }[] — the caller's full asset-domain
	                   Sub-Cat catalog. Confirmed (+page.server.ts, commit 2e19dfd): the loader
	                   INCLUDES Real Estate — it reuses taxonomy.ts's loadAssetSubCats() verbatim,
	                   the same read the account pickers use, rather than a second, driftable
	                   query — so this component filters Real Estate out independently, client-
	                   side, exactly how SELF-238/240's own read surfaces exclude it independently
	                   of their upstream source rather than relying on the query to have done it.
	                   Grouped/ordered per allocation-taxonomy.ts (CAT_GROUP_ORDER +
	                   US_EQUITY_SUB_CAT_SET — the SAME mirror Issue 5/6 (SELF-238) and Issue 7/8
	                   (SELF-240) consume server-side, so this editor's Cat order and US-Equity
	                   membership can never drift from what those read surfaces show).
	  initialTargets : Record<sub_cat_id, target_percent> — ONLY for Sub-Cats that already carry
	                   a pfin.planning_target row (074). A Sub-Cat absent from this map renders
	                   its field EMPTY (the `empty(bootstrap)` state) — NEVER a seeded 0, per
	                   074's own "unset is row-absent" contract.

	PERSISTENCE (SELF-233 POST + SELF-242 DELETE, both /api/settings/planning-target;
	+server.ts read for contract awareness — Backend-owned, not authored here. Contract
	confirmed by backend-engineer, commit d87a62c on feature/self242-settings-allocation):
	  - A field with a REAL value posts { sub_cat_id, target_percent } — an explicit 0.00 is a
	    valid, storable, DIFFERENT fact from row-absent (ADR-056), so "0" is submitted as-is.
	  - A field CLEARED back to empty, that had an initial value, calls
	    DELETE /api/settings/planning-target with JSON body { sub_cat_id } (no query param —
	    confirmed shape, not this file's earlier guess). Sec's merge-gate binding constraint:
	    "unset must be DELETE, never POST 0.00" — this editor never POSTs an empty field as
	    0.00, by construction (an empty string never reaches the upsert branch below).
	  - DELETE's response is 200 { ok: true, sub_cat_id, deleted: boolean } — ALWAYS 200
	    (idempotent-success whether a row existed or not), so a 2xx status alone does NOT
	    mean the row is gone. `deleted` is a fail-closed team-lead/Sec addition (rationale:
	    a below-aal2 session can't reach this path TODAY only because the loader returns no
	    targets for it — a fact that depends on another table's policy shape, not a fence of
	    this endpoint's own, so the flag exists for when that stops being true). handleSave
	    CONSUMES it: only an explicit `deleted === true` counts as removed; false/missing/
	    unparsable is treated as NOT removed, surfaced per-row ("Not removed —
	    re-verification may be required"), same serverErrors slot a failed POST uses — an
	    added response field nothing reads is a control that decays into decoration.
	  - A field cleared that had NO initial value is a no-op (nothing to delete) — dirty-tracking
	    treats it as "back to baseline", not a pending change.
	  - Per Sec's SELF-233 joint-review ruling (2026-08-17, carried onto SELF-242 by
	    backend-engineer): the editor submits changed rows INDIVIDUALLY against these two
	    endpoints, never as a batched array — Linear AC #3/#7's "keyed array" / single
	    "/api/settings/allocation" route describe a shape neither endpoint implements, and
	    Sec's ruling is the one this file follows.

	WHY FETCH, NOT A FORM ACTION (a departure from the api/CLAUDE.md default, stated rather than
	silently taken): the endpoint above is a raw JSON REST route with a per-Sub-Cat grain, not a
	page form action, and one user-facing "Save" can cover MANY dirty fields at once — a native
	<form method="POST"> cannot express "N discrete POST/DELETE calls, batched, one outcome".
	This is the "genuinely client-initiated op" carve-out in api/CLAUDE.md's Frontend
	conventions, applied to a heavier case than its own examples (chart-axis/sort-order) — flagged
	at hand-off as a judgment call, not asserted unilaterally as obviously right.

	VALIDATION (Lock 14 mod #2): client-side field feedback is sanitizePercent
	($lib/validation/numeric.ts) — the SAME shared battery the server enforces (SELF-233), not a
	re-implementation of it (AC4). The server + DB CHECK remain the actual security boundary;
	this is UX fast-feedback only, and Save is disabled while any dirty field fails it (the
	`disabled(no valid change)` state) so no request is ever sent for a value the server would
	reject anyway.

	States (design-system-spec.md §4): default · editing(dirty) · saving · disabled(no valid
	change) · error(per-field) · empty(bootstrap) · saved. `target-sum-readout` (per-Cat-group +
	grand total, AC6) is informational ONLY — never the attention hue, never blocks Save
	(§5 fence 1 / P5 Consequence).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). No staleness-marker here —
	%Target is user-authored planning data, not a derived aggregation over account balances, so
	ADR-013 D1 does not apply to this surface.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { sanitizePercent } from '$lib/validation/numeric';
	import {
		CAT_GROUP_ORDER,
		US_EQUITY_SUB_CATS,
		US_EQUITY_SUB_CAT_SET,
		US_EQUITY_PARENT_CAT,
		type NonReCat
	} from '$lib/allocation-taxonomy';

	type TaxonomyRow = { id: number; cat: string; sub_cat: string; display_order: number | null };

	let { catalog, initialTargets }: { catalog: TaxonomyRow[]; initialTargets: Record<number, number> } =
		$props();

	// Real Estate is excluded independently here, mirroring nonReAllocation.ts's own belt-and-
	// suspenders filter, rather than trusting the loader alone to have excluded it.
	const nonReCatalog = $derived(catalog.filter((r) => r.cat !== 'Real Estate'));

	const catGroups = $derived(
		CAT_GROUP_ORDER.map((cat) => ({
			cat,
			rows: nonReCatalog
				.filter((r) => r.cat === cat && !US_EQUITY_SUB_CAT_SET.has(r.sub_cat))
				.slice()
				.sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0))
		}))
	);

	const usEquityRows = $derived(
		US_EQUITY_SUB_CATS.map((label) =>
			nonReCatalog.find((r) => r.cat === US_EQUITY_PARENT_CAT && r.sub_cat === label)
		).filter((r): r is TaxonomyRow => r !== undefined)
	);

	function formatInitial(id: number): string {
		const t = initialTargets[id];
		return t === undefined || t === null ? '' : String(t);
	}

	// Frozen baseline for dirty-diffing — built once from the props this component mounted
	// with. The editor's own life cycle ends in a redirect (see handleSave), so a stale
	// baseline across a long-lived session is not a concern here. Deliberately NOT `$derived`:
	// a derived baseline would erase in-progress edits' dirty state the instant `catalog`'s
	// reference ever changed, which is the opposite of what a baseline is for. (svelte-check
	// flags this as `state_referenced_locally` — a correct observation, not a bug: the
	// one-time capture is the intent.)
	const baseline: Record<number, string> = {};
	for (const r of catalog) baseline[r.id] = formatInitial(r.id);

	let values = $state<Record<number, string>>({ ...baseline });
	let serverErrors = $state<Record<number, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let statusMessage = $state('');

	const dirtyIds = $derived(catalog.map((r) => r.id).filter((id) => values[id] !== baseline[id]));
	const hasDirty = $derived(dirtyIds.length > 0);

	function clientErrorFor(id: number): string | null {
		const raw = values[id];
		if (raw === '') return null; // empty = unset, not an error (empty(bootstrap) state)
		const r = sanitizePercent(raw);
		return r.ok ? null : r.reason;
	}

	const anyClientError = $derived(dirtyIds.some((id) => clientErrorFor(id) !== null));
	const saveDisabled = $derived(!hasDirty || anyClientError || saving);

	function errorsFor(id: number): string[] {
		const server = serverErrors[id];
		if (server) return [server];
		const client = dirtyIds.includes(id) ? clientErrorFor(id) : null;
		return client ? [client] : [];
	}

	function parsedOrZero(raw: string): number {
		if (raw === '') return 0;
		const r = sanitizePercent(raw);
		return r.ok ? r.value : 0;
	}

	const catSums = $derived.by(() => {
		const sums: Partial<Record<NonReCat, number>> = {};
		for (const g of catGroups) {
			let sum = g.rows.reduce((s, r) => s + parsedOrZero(values[r.id]), 0);
			if (g.cat === US_EQUITY_PARENT_CAT) {
				sum += usEquityRows.reduce((s, r) => s + parsedOrZero(values[r.id]), 0);
			}
			sums[g.cat] = sum;
		}
		return sums;
	});
	const usEquitySum = $derived.by(() => usEquityRows.reduce((s, r) => s + parsedOrZero(values[r.id]), 0));
	const grandTotal = $derived.by(() =>
		Object.values(catSums).reduce((s: number, v) => s + (v ?? 0), 0)
	);

	function clearField(id: number) {
		values[id] = '';
	}

	async function extractError(settled: PromiseSettledResult<Response>): Promise<string> {
		if (settled.status === 'rejected') return 'Network error — try again.';
		const res = settled.value;
		try {
			const body = await res.json();
			if (body?.fieldErrors?.target_percent?.[0]) return body.fieldErrors.target_percent[0];
			if (body?.fieldErrors?.sub_cat_id?.[0]) return body.fieldErrors.sub_cat_id[0];
			if (body?.error === 'step_up_required') return "Verify it's you and try again.";
			if (body?.error === 'invalid_sub_cat_or_value') return 'This value could not be saved.';
		} catch {
			/* fall through to generic message */
		}
		return 'Could not save this change.';
	}

	async function handleSave(event: SubmitEvent) {
		event.preventDefault();
		if (saveDisabled) return;

		formError = '';
		serverErrors = {};
		saving = true;

		const toUpsert: { id: number; target_percent: number }[] = [];
		const toDelete: number[] = [];
		for (const id of dirtyIds) {
			const raw = values[id];
			if (raw === '') {
				toDelete.push(id);
			} else {
				const r = sanitizePercent(raw);
				if (r.ok) toUpsert.push({ id, target_percent: r.value });
			}
		}

		try {
			const settled = await Promise.allSettled([
				...toUpsert.map(({ id, target_percent }) =>
					fetch('/api/settings/planning-target', {
						method: 'POST',
						headers: { 'content-type': 'application/json' },
						body: JSON.stringify({ sub_cat_id: id, target_percent })
					})
				),
				...toDelete.map((id) =>
					fetch('/api/settings/planning-target', {
						method: 'DELETE',
						headers: { 'content-type': 'application/json' },
						body: JSON.stringify({ sub_cat_id: id })
					})
				)
			]);

			let anyFailed = false;
			for (let i = 0; i < toUpsert.length; i++) {
				const res = settled[i];
				const ok = res.status === 'fulfilled' && res.value.ok;
				if (!ok) {
					anyFailed = true;
					serverErrors[toUpsert[i].id] = await extractError(res);
				}
			}
			for (let j = 0; j < toDelete.length; j++) {
				const res = settled[toUpsert.length + j];
				const id = toDelete[j];
				const ok = res.status === 'fulfilled' && res.value.ok;
				if (!ok) {
					anyFailed = true;
					serverErrors[id] = await extractError(res);
					continue;
				}
				// HTTP 200 no longer means "the row is gone" — the DELETE response now carries its
				// own outcome bit (`deleted`) because the endpoint is deliberately idempotent-success
				// (200 whether a row existed or not) AND can genuinely fail to remove a row it can see
				// (a fail-closed path whose exact trigger is DB-internal — see the PERSISTENCE note
				// above). Fail-closed here too: only an EXPLICIT `deleted === true` counts as removed;
				// anything else (false, missing, or an unparsable body) is treated as NOT removed
				// rather than assumed successful, per Sec's ruling that an unconsumed response field
				// is a control that decays into decoration.
				let deleted = false;
				try {
					const body = await (res as PromiseFulfilledResult<Response>).value.json();
					deleted = body?.deleted === true;
				} catch {
					deleted = false;
				}
				if (!deleted) {
					anyFailed = true;
					serverErrors[id] = 'Not removed — re-verification may be required.';
				}
			}

			if (anyFailed) {
				formError = 'Some changes could not be completed — see the fields below.';
				saving = false;
				return;
			}

			statusMessage = 'Changes saved.';
			await goto('/allocation');
		} catch {
			formError = 'Something went wrong saving your changes. Please try again.';
			saving = false;
		}
	}
</script>

<form class="editor" onsubmit={handleSave}>
	{#if formError}
		<p class="banner" role="alert">{formError}</p>
	{/if}
	{#if statusMessage}
		<p class="sr-only" role="status">{statusMessage}</p>
	{/if}

	<section class="section" aria-labelledby="nonre-heading">
		<h2 id="nonre-heading" class="section-title">Non-RE</h2>

		{#each catGroups as group (group.cat)}
			<div class="cat-group">
				<div class="cat-head">
					<h3 class="cat-title">{group.cat}</h3>
					<span class="cat-sum">{(catSums[group.cat] ?? 0).toFixed(2)}%</span>
				</div>
				<div class="rows">
					{#each group.rows as row (row.id)}
						<div class="row">
							<TextField
								label={row.sub_cat}
								name={`target-${row.id}`}
								bind:value={values[row.id]}
								inputmode="decimal"
								numeric
								placeholder="—"
								hint="% of total Non-RE"
								errors={errorsFor(row.id)}
							/>
							<Button
								variant="link"
								type="button"
								disabled={values[row.id] === ''}
								onclick={() => clearField(row.id)}
								aria-label={`Clear target for ${row.sub_cat}`}
							>
								Clear
							</Button>
						</div>
					{/each}
				</div>

				{#if group.cat === US_EQUITY_PARENT_CAT}
					<div class="sub-section" aria-labelledby="us-equity-heading">
						<div class="cat-head">
							<h4 id="us-equity-heading" class="sub-title">US Equity</h4>
							<span class="cat-sum">{usEquitySum.toFixed(2)}%</span>
						</div>
						<div class="rows">
							{#each usEquityRows as row (row.id)}
								<div class="row">
									<TextField
										label={row.sub_cat}
										name={`target-${row.id}`}
										bind:value={values[row.id]}
										inputmode="decimal"
										numeric
										placeholder="—"
										hint="% of total Non-RE"
										errors={errorsFor(row.id)}
									/>
									<Button
										variant="link"
										type="button"
										disabled={values[row.id] === ''}
										onclick={() => clearField(row.id)}
										aria-label={`Clear target for ${row.sub_cat}`}
									>
										Clear
									</Button>
								</div>
							{/each}
						</div>
					</div>
				{/if}
			</div>
		{/each}

		<!-- target-sum-readout — informational ONLY (P5 Consequence): never the attention hue,
		     never blocks Save, regardless of how far from 100% this reads. -->
		<div class="grand-total">
			<span class="grand-total-label">Total (all Non-RE Sub-Cats)</span>
			<span class="grand-total-value">{grandTotal.toFixed(2)}%</span>
		</div>
		{#if Math.abs(grandTotal - 100) > 0.005}
			<p class="soft-warning" role="status">
				This doesn't total 100% yet — that's fine. V1 surfaces the gap rather than requiring a
				balanced target (PRD §2.2.2).
			</p>
		{/if}
	</section>

	<div class="actions">
		<Button variant="primary" type="submit" loading={saving} disabled={saveDisabled}>
			Save changes
		</Button>
	</div>
</form>

<style>
	.editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}
	.section {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
	}
	.section-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.cat-group {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.cat-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.cat-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / 1.2 var(--font-ui);
		color: var(--c-text-primary);
	}
	.sub-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.02em;
	}
	/* Cat/section subtotal — font-num per §2.3 numeric convention, secondary ink (never
	   --c-pos/--c-neg — that fence is scoped to actual performance, not %Target). */
	.cat-sum {
		font-family: var(--font-num);
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.rows {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-2);
	}
	.row :global(.field) {
		flex: 1;
	}
	/* Nested US Equity sub-section (AC2 "under sub-section") — indented + a left rule so it
	   reads as a drill-down of the Marketable Securities Cat group, not a sibling. */
	.sub-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		margin-left: var(--space-4);
		padding-left: var(--space-4);
		border-left: 2px solid var(--c-border);
	}
	.grand-total {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		padding: var(--space-4) var(--space-5);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
	}
	.grand-total-label {
		font: var(--weight-semi) var(--fs-body) / 1.2 var(--font-ui);
		color: var(--c-text-primary);
	}
	.grand-total-value {
		font-family: var(--font-num);
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	/* Informational only — neutral ink, no attention hue (P5 Consequence / §5 fence 1). */
	.soft-warning {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
	}
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-neg);
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
