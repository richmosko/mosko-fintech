<!--
	CashflowAccountPicker.svelte — the §2.3.3 account selector (SELF-254 AC3). Frontend-owned
	browser surface.

	AC3 — CLOSED accounts are INCLUDED, grouped separately with their closure date folded into the
	option label (a native `<option>` cannot carry a separate badge element, so the date rides the
	text itself — `closedAtLabel` renders it UTC per ADR-043, the same rule the account-detail
	page's own closure copy follows). `pfin.account.is_active` was DROPPED at `059` (ADR-042); this
	component reads `closed_at` only and never references a boolean that no longer exists.

	NO CLIENT-SIDE VALIDATION MIRROR ON `account_id` (frontend-engineer discipline #2 note, not an
	omission): this is a STRUCTURAL PICKER, not a free-text field — every `<option value>` is one of
	the caller's OWN accounts, from the SAME server-loaded list `+page.server.ts` used to resolve
	the currently-viewed account. A wrong/foreign id is unreachable through this control by
	construction, so there is no input boundary here for a mirror to duplicate; the server's own
	`accountIdSchema` (cashflowPerAccount.ts) remains the fence against a hand-edited URL, which
	this component cannot and does not attempt to narrow.

	Re-navigates on selection (mirrors CashflowAsOfToggle's `goto()` idiom) rather than a
	`<form method="POST">`: this is a pure client-side ROUTE change (SvelteKit re-runs load() on
	navigation), not a server mutation, the same distinction NavHistoryChart.svelte's
	granularity/zoom controls already draw. Every OTHER existing query param (`as_of`, `from`) is
	preserved — only the path segment changes.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). Native `<select>` via
	SelectField, so keyboard + AT semantics come for free.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import SelectField from './SelectField.svelte';
	import { closedAtLabel } from '$lib/account-display';

	export type CashflowAccountOption = {
		account_id: number;
		name: string;
		closed_at: string | null;
	};

	let {
		accounts,
		currentAccountId
	}: {
		accounts: CashflowAccountOption[];
		currentAccountId: number;
	} = $props();

	const openGroup = $derived({
		label: 'Open',
		options: accounts
			.filter((a) => a.closed_at === null)
			.map((a) => ({ value: String(a.account_id), label: a.name }))
	});
	const closedGroup = $derived({
		label: 'Closed',
		options: accounts
			.filter((a) => a.closed_at !== null)
			.map((a) => ({
				value: String(a.account_id),
				label: `${a.name} — Closed ${closedAtLabel(a.closed_at)}`
			}))
	});
	const groups = $derived([openGroup, closedGroup].filter((g) => g.options.length > 0));

	let selected = $state(String(currentAccountId));
	$effect(() => {
		selected = String(currentAccountId);
	});

	function apply(event: Event) {
		// Read the committed value straight off the native event — same race note as
		// CashflowAsOfToggle's own `apply`: `bind:value` and this `onchange` passthrough both
		// attach to the same native `change` event, ordering unspecified.
		const chosen = (event.currentTarget as HTMLSelectElement).value;
		selected = chosen;
		if (chosen === String(currentAccountId)) return;
		const url = new URL(page.url);
		url.pathname = `/cash-flow/${chosen}`;
		goto(url.toString(), { keepFocus: true, noScroll: true });
	}
</script>

<div class="account-picker">
	<SelectField
		label="Account"
		name="account_id"
		bind:value={selected}
		{groups}
		onchange={apply}
	/>
</div>

<style>
	.account-picker {
		max-width: 18rem;
	}
</style>
