<!--
	OwnerIdentificationEditor.svelte — the §2.6.4.b owner-identification header editor (SELF-359
	AC1/AC2/AC3/AC4). Frontend-owned browser surface. Posts against
	settings/owner-id/+page.server.ts's `?/save` form action — a real SvelteKit form action, per
	api/CLAUDE.md's Frontend convention, not a fetch+JSON carve-out.

	CONTRACT (props):
	  initialHeaderText : the loader's `data.ownerIdHeaderText` — `string | null`. `null` covers
	                      BOTH of 106's unset representations (row-absent, column NULL) — the
	                      loader already collapsed them, so this component never distinguishes the
	                      two (106's own reader obligation).

	COPY (PM, folded verbatim, SELF-359 AC2):
	  - field label            "Owner identification"
	  - helper                 "Appears at the top of every monthly report generated after you
	                            save. Plain text, one line, up to 120 characters. Example: THE
	                            ⟨NAME⟩ 2023 TRUST."
	  - empty state             "No header set — reports show no owner line until you add one."
	  - forward-only statement  "Reports already generated keep the header they were generated
	                            with." (also true a second time under R1 (A): the header is BOTH
	                            snapshotted onto A1 and frozen inside A1's payload — this editor
	                            states the product fact once, the mechanism doubling it up is P2/A1's
	                            concern, not this editor's.)
	  Page title "Report header" lives on +page.svelte, not here (this component is the field,
	  not the page).

	CLIENT MIRROR: $lib/validation/ownerIdHeader.ts's `sanitizeOwnerIdHeader` — mirrors
	$lib/server/schemas/owner-identification.ts's two rules (<=120 UTF-16 code units on the
	TRIMMED value, no Unicode line-boundary code point) for live per-keystroke feedback. Blank
	(empty or whitespace-only) is a valid CLEAR, never an error — 106's TEXT FENCE (3): an
	emptied field is written as NULL, never ''.

	SUBMIT-RESULT HANDLING: reads this form's OWN `use:enhance` SubmitFunction callback, never a
	page-level `form` prop — this page has exactly one form, but the pattern is kept consistent
	with every other settings editor on this tree (TaxBracketScheduleEditor.svelte /
	PurchaseEntryForm.svelte) so a future second form on this page is not a silent footgun.
	⚠ TEST-HARNESS LIMIT, same as those siblings: `tests/stubs/app-forms.ts`'s `enhance` stub
	invokes this SubmitFunction synchronously on a real submit (so the pre-submit `cancel()` gate
	IS exercised by a DOM test) but never its returned async callback — server-error rendering
	after a real submit is out of this harness's reach, same documented gap those files accept.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). No staleness marker here —
	the owner header is user-authored settings data, not a derived account aggregation (SELF-360
	AC6's own exclusion names this surface explicitly: "the §2.6.4 owner header [is] not marked —
	not account-derived").
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { sanitizeOwnerIdHeader } from '$lib/validation/ownerIdHeader';

	let { initialHeaderText }: { initialHeaderText: string | null } = $props();

	let headerText = $state(initialHeaderText ?? '');
	let serverFieldErrors = $state<Record<string, string[]>>({});
	let formError = $state('');
	let statusMessage = $state('');
	let saving = $state(false);

	function headerError(): string | null {
		const r = sanitizeOwnerIdHeader(headerText);
		return r.ok ? null : r.reason;
	}

	// Empty-state copy tracks the CURRENT draft, not only the server-known initial value — the
	// AC2 empty state describes what is true right now ("reports show no owner line until you
	// add one"), which stays true while the field is blank whether that is the initial load or a
	// value the user just cleared.
	const isBlank = $derived(headerText.trim().length === 0);
	const saveDisabled = $derived(headerError() !== null || saving);

	type ActionSuccess = { ok: true; ownerIdHeaderText: string | null };
	type ActionFailure = { errors: Record<string, string[]> };

	const handleSubmit: SubmitFunction = ({ cancel }) => {
		if (saveDisabled) {
			cancel();
			return;
		}
		formError = '';
		serverFieldErrors = {};
		statusMessage = '';
		saving = true;

		return async ({ result, update }) => {
			saving = false;
			if (result.type === 'success') {
				const data = result.data as ActionSuccess | undefined;
				if (data?.ok) {
					statusMessage = 'Header saved.';
					// Mirrors TaxBracketScheduleEditor.submit-update.dom.test.ts's regression: the
					// default `update()` resets the native <form> on success, which would blank the
					// field and show it as empty immediately after a save that actually persisted a
					// value — never desired here.
					await update({ reset: false });
					return;
				}
			}
			if (result.type === 'failure') {
				const data = result.data as ActionFailure | undefined;
				serverFieldErrors = data?.errors ?? {};
				formError = serverFieldErrors._form?.join(' ') ?? 'Could not save the header — see below.';
				await update({ reset: false });
				return;
			}
			// result.type === 'error' (thrown exception) or an unrecognized shape.
			formError = 'Something went wrong saving the header. Please try again.';
			await update({ reset: false });
		};
	};
</script>

<form class="editor" method="POST" action="?/save" use:enhance={handleSubmit}>
	{#if formError}
		<p class="banner" role="alert">{formError}</p>
	{/if}
	{#if statusMessage}
		<p class="sr-only" role="status">{statusMessage}</p>
	{/if}

	<TextField
		label="Owner identification"
		name="owner_id_header_text"
		id="f-owner-id-header"
		bind:value={headerText}
		maxlength={120}
		placeholder="THE ⟨NAME⟩ 2023 TRUST"
		hint="Appears at the top of every monthly report generated after you save. Plain text, one line, up to 120 characters. Example: THE ⟨NAME⟩ 2023 TRUST."
		errors={[
			...(serverFieldErrors.owner_id_header_text ?? []),
			...(headerError() ? [headerError() as string] : [])
		]}
	/>

	{#if isBlank}
		<p class="empty-state">No header set — reports show no owner line until you add one.</p>
	{/if}

	<p class="forward-only">Reports already generated keep the header they were generated with.</p>

	<div class="actions">
		<Button variant="primary" type="submit" loading={saving} disabled={saveDisabled}>Save</Button>
	</div>
</form>

<style>
	.editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.empty-state {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.forward-only {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.actions {
		display: flex;
		align-items: center;
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
