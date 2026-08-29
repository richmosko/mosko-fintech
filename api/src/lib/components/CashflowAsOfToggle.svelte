<!--
	CashflowAsOfToggle.svelte — the §2.3.3 as-of toolbar toggle (SELF-254 AC4). Frontend-owned
	browser surface. The FIRST as-of-toggle rendering surface in this tree: `?as_of=` re-navigation,
	the same idiom NavHistoryChart.svelte's `?chart_start=` / `?chart_end=` toggle already
	established (`goto(url.toString(), { keepFocus: true, noScroll: true })`, preserving every
	OTHER existing query param — including `from`, AC5's back-nav marker).

	BOUNDS ARE INJECTED, NEVER EMBEDDED (mirrors asOf.ts's own discipline, extended to the floor):
	`floor` / `max` are REQUIRED props, sourced from `+page.server.ts`'s page data — which itself
	imports the real `AS_OF_FLOOR` and resolves `maxAsOf` from `pfin.fn_server_today()` ONCE per
	request. This component mints no date of its own anywhere, including as a fallback.

	CLIENT MIRROR (frontend-engineer discipline #2): `cashflowPerAccountAsOfSchema` re-validates on
	`onchange`, BEFORE any navigation fires — a malformed or out-of-range value degrades to an
	inline message and no request is sent. This is UX only; the server's own `asOfSchema` re-checks
	unconditionally regardless (cashflowPerAccount.ts's `validateCashflowPerAccountParams`).

	`serverError` renders the AUTHORITATIVE case: a request that already reached the server with an
	invalid `as_of` (a hand-edited URL, or a value that slipped past this same client check under a
	stale `max`/`floor`) — cashflowPerAccount.ts's own module header states BOTH checks always run
	server-side, never short-circuited. `localError` (this component's own pre-flight check) takes
	precedence once the user starts editing, since it is the more current signal about the
	in-progress draft; `serverError` reasserts itself once `value` (the server-confirmed as-of)
	resyncs a `localError`-free draft.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). Native `<input type="date">`
	via TextField, so keyboard + AT date-picker semantics come for free.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import TextField from './TextField.svelte';
	import { cashflowPerAccountAsOfSchema } from '$lib/schemas/cashflow-per-account-as-of';

	let {
		value,
		floor,
		max,
		serverError = null
	}: {
		/** The as-of ACTUALLY APPLIED to the current render (`drilldown.as_of` when available,
		 *  else the raw `?as_of=` the URL carried into a failed validation). */
		value: string;
		floor: string;
		max: string;
		serverError?: string | null;
	} = $props();

	let draft = $state(value);
	let localError = $state<string | null>(null);

	// Resync the draft whenever the server-confirmed value changes (a fresh navigation landed) —
	// clears any stale localError from the PRIOR draft along with it.
	$effect(() => {
		draft = value;
		localError = null;
	});

	const displayedError = $derived(localError ?? serverError);

	function apply(event: Event) {
		// Read the committed value straight off the native event rather than trusting `draft`
		// (the bind:value-updated state) to have already settled — `bind:value` and this
		// `onchange` passthrough both attach to the SAME native `change` event, and their
		// relative ordering is a compiler/runtime detail this component must not depend on.
		const inputValue = (event.currentTarget as HTMLInputElement).value;
		draft = inputValue;
		const schema = cashflowPerAccountAsOfSchema(floor, max);
		const parsed = schema.safeParse({ as_of: inputValue === '' ? undefined : inputValue });
		if (!parsed.success) {
			localError = parsed.error.issues[0]?.message ?? 'Enter a valid date.';
			return;
		}
		localError = null;
		const url = new URL(page.url);
		if (parsed.data.as_of) {
			url.searchParams.set('as_of', parsed.data.as_of);
		} else {
			url.searchParams.delete('as_of');
		}
		goto(url.toString(), { keepFocus: true, noScroll: true });
	}
</script>

<div class="as-of-toggle">
	<TextField
		label="As of"
		name="as_of"
		type="date"
		bind:value={draft}
		min={floor}
		{max}
		onchange={apply}
		errors={displayedError ? [displayedError] : []}
		hint={`Between ${floor} and ${max}.`}
	/>
</div>

<style>
	.as-of-toggle {
		max-width: 12rem;
	}
</style>
