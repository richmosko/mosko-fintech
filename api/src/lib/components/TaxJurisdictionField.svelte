<!--
	TaxJurisdictionField.svelte — the §2.4.2 tax-authority designation control (SELF-267 AC 2).

	Schema field `tax_jurisdiction` (`pfin.tax_jurisdiction_enum`, NULLABLE — 102's `comment on
	column`: NULL means "not a tax-authority ledger", NOT "unknown"). Product phrase is "tax
	authority"; the two enum values `irs` / `ftb` never appear in user-facing copy — they render
	as "IRS (Federal)" / "FTB (California)" (account-display.ts).

	THREE EXPLICIT STATES, not two-plus-a-blank (rederived-acs.md SELF-267 AC 2b — "the DEFAULT
	state is the bug"). A native <select> with no placeholder and a nullable value reads as
	"nothing chosen yet" — indistinguishable from "deliberately not a tax-authority ledger" on
	sight. So "Not a tax authority ledger" is baked in as OPTIONS[0], a real selectable/selected
	option carrying value `''`, not SelectField's `placeholder` slot (which is instructional —
	"Select…" — the wrong verb for an already-decided default state). This is what makes an
	UNMARKED account legible as unmarked rather than as an unanswered question — the AC 2b/3a walk
	requires seeing BOTH figures move when the designation is set, which needs the unset state to
	be visibly a state.

	HIDDEN for provider-linked accounts (`hidden` prop) — not merely styled off, not rendered at
	all, so a linked account's edit submission carries no `tax_jurisdiction` key. PRD §2.5.3: IRS /
	FTB accounts are V1 instances of §2.4.2 MANUAL non-Plaid accounts; the write path this control
	feeds (AC 139: an ordinary UPDATE under the ordinary attribute-edit action, never a Plaid
	create/land path) has no provider-linked consumer. Frontend judgment call, flagged at
	hand-off: PRD text scopes the designation to manual accounts but does not explicitly rule out a
	linked account someday carrying one; hiding rather than merely defaulting-empty is the
	conservative reading until Backend/PM confirm.

	Consumed by accounts/new/+page.svelte (always visible — that flow creates manual accounts
	only, so `hidden` is never passed there) and accounts/[account_id]/+page.svelte's attribute
	editor (`hidden={isLinked}`).
-->
<script lang="ts">
	import SelectField from './SelectField.svelte';
	import { TAX_JURISDICTIONS } from '$lib/schemas/account-constants';
	import { TAX_JURISDICTION_LABELS } from '$lib/account-display';

	let {
		value = $bindable(''),
		name = 'tax_jurisdiction',
		id,
		errors = [],
		hidden = false
	}: {
		value?: string;
		name?: string;
		id?: string;
		errors?: string[];
		hidden?: boolean;
	} = $props();

	// OPTIONS[0] IS THE DEFAULT, STATED — see the header note. Not a `placeholder` prop.
	const options = [
		{ value: '', label: 'Not a tax authority ledger' },
		...TAX_JURISDICTIONS.map((j) => ({ value: j, label: TAX_JURISDICTION_LABELS[j] }))
	];
</script>

{#if !hidden}
	<SelectField
		label="Tax authority"
		{name}
		{id}
		bind:value
		{errors}
		hint="Marks this as your IRS or FTB ledger — its balance feeds the §2.5.3 YTD Paid column and is excluded from net worth. One account per authority."
		{options}
	/>
{/if}
