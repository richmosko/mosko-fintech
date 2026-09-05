<!--
	MonthlyCommentaryEditor.svelte — the §2.6.2.b Rebalancing Targets free-text commentary editor
	(SELF-355 / P3). Frontend-owned browser surface, posting to
	reports/monthly/[target_month]/commentary/+page.server.ts's `?/save` form action (Backend-
	surface file, flagged there for its own re-read).

	SUB-SECTIONS (PRD §2.6.2 "Sub-section structure" clause, F/CTO-ratified 2026-08-19): Cash /
	Bonds / Marketable Securities / Alternatives, VERBATIM and in THIS order — the same order and
	labels as `NONRE_TABLE_CAT_ORDER` ($lib/nonre-allocation.ts), reused directly rather than
	re-declared, because the PRD's own ratification ties this editor's sub-sections to "the same
	top-level Cat-group rows" the $ReAlloc reference panel renders (Cat-alignment wins over the
	Finance_Report's literal old label per ADR-058 Decision 7). `SECTION_KEY` below is the one
	place that maps a Cat-group label to its commentary column name (`cash` / `bonds` /
	`marketable_securities` / `alternatives`, matching +page.server.ts's `CommentaryValues` shape
	and migration 108's four column names) — no independent ordering or label list is declared
	here.

	BLANK BY DEFAULT / COPY-FROM-PRIOR (PRD §2.6.2 "Pre-population behavior" clause): a new month's
	editor opens blank under every sub-section (never auto-pre-populated) with an explicit
	per-sub-section AND a global "Copy from {prior month}" affordance that pulls the PRIOR month's
	content in as a starting point, which the user then edits. JUDGMENT CALL (PRD is silent on the
	exact enablement predicate): each per-section copy button is disabled when that section's prior
	value is blank (`.trim() === ''`) — nothing to copy — OR the report is not a draft; the global
	button is disabled only when EVERY prior section is blank, or the report is not a draft. "Copy"
	is a plain overwrite of the CURRENT draft (not a merge) — the PRD's own framing ("pulls the
	prior month's commentary content into the current editor as a starting point") reads as a
	replacement, and there is no ratified merge/append behavior to invent one of.

	REPLACE-ALL SUBMIT (migration 112's own contract): all four sections are ALWAYS submitted
	together on Save — there is no "leave this one alone" partial-save semantics, matching 112's
	own "the editor submits the whole form" posture. An emptied section saves as an actual empty
	value (a legitimate authored state per 112's header), never silently reverted.

	LENGTH / NEWLINE MIRROR (E15 items 10-12, Sec N-5): each section's live "{n} / 4000" counter and
	the Save-disabled gate both run on the NORMALIZED value (`\r\n` -> `\n`, `Array.from(s).length`
	code points — see $lib/validation/monthlyCommentary.ts's own header for the falsifying
	astral-character case this mirror rule exists to catch). The VISIBLE <textarea> stays bound to
	whatever the browser hands back via its own `bind:value`; a HIDDEN input per section, named to
	match +page.server.ts's own `form.get(...)` reads (`cash` / `bonds` / `marketable_securities` /
	`alternatives`), carries the normalized value that actually gets submitted. ⚠ VERIFIED
	(MonthlyCommentaryEditor.dom.test.ts), not merely assumed: a `<textarea>`'s own API `.value`
	getter already normalizes CRLF -> LF on every read per the HTML living standard, in every real
	browser and in jsdom — so a real `<textarea>` submission never hands this component a literal
	`\r\n` to begin with, and `normalizeLineEndings()` is IDEMPOTENT on that path. It is kept
	anyway because it is a one-line defensive mirror of migration 112's own stated concern ("any
	OTHER caller reaches this function ... without doing it"), not because this component's own
	typed-input path can ever exercise it. The visible
	textarea is deliberately given a DIFFERENT `name` (`${key}_editor`) so the two never collide in
	the posted FormData — the action reads only the hidden field's name.

	FINAL / READ-ONLY STATE (loader's own header: this route must still RENDER for a `final` month
	reached directly or via a stale bookmark, even though it can never WRITE one — 112's own lock
	predicate excludes anything but a `draft`). `!isDraft` renders every textarea `disabled`
	(TextAreaField.svelte's SELF-355 addition), hides Save and both copy-from-prior affordances,
	and shows a "this report is final" banner — showing the row's own frozen commentary values,
	never blank.

	FINALIZE STUB: "Finalize {Month YYYY}" renders as a PERMANENTLY DISABLED control (P4's own
	transition is not built — dispatch is explicit not to build it here). It is not gated on
	`isDraft` the way Save is; it is unconditionally inert in this ticket regardless of state.

	$ ReAlloc REFERENCE PANEL (AC3): `<NonReAllocationTable>` — the SAME shipped table SELF-239's
	`/allocation` page renders — fed from the loader's OWN live read (loadStaleness +
	loadNonReAllocation at serverTodayAsOf(), not a frozen/report-scoped read; see
	+page.server.ts's header for why this is not a P8 staleness slot). `allocation === null`
	(the live read failed) renders the SAME "temporarily unavailable" copy `/allocation`'s own page
	uses verbatim, rather than a fabricated empty table.

	EDITOR NOTE COPY — FLAGGED, not a UX-routed decision: the short instructional line under the
	sub-sections ("Plain text. Line breaks are kept — no markdown or rich-text formatting.")
	restates PRD §2.6.2's own locked "Editor format" clause fact (plain text, line breaks
	preserved, no markdown/rich-text) rather than inventing new product behavior — same class of
	self-authored micro-hint as CashflowTargetEditor's "Leave blank for no target." /
	TaxBracketScheduleEditor's fixed-deduction note. Bubbled up per role charter regardless, since
	user-facing copy is nominally UX's call.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). RT-11 canonical test label.
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TextAreaField from '$lib/components/TextAreaField.svelte';
	import Button from '$lib/components/Button.svelte';
	import NonReAllocationTable from '$lib/components/NonReAllocationTable.svelte';
	import { NONRE_TABLE_CAT_ORDER } from '$lib/nonre-allocation';
	import type { NonReAllocation } from '$lib/nonre-allocation';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import {
		MONTHLY_COMMENTARY_MAX_CODE_POINTS,
		codePointLength,
		normalizeLineEndings
	} from '$lib/validation/monthlyCommentary';

	// Local, self-contained shape — this branch is stacked on the DB unit, not on P2/SELF-354's
	// own branch (see +page.server.ts's CROSS-BRANCH NOTE), so there is no shared
	// `$lib/monthly-report.ts` to import a `CommentaryValues` type from. Structurally identical to
	// +page.server.ts's own exported `CommentaryValues` — duplicated, not re-declared differently.
	type CommentarySection = 'cash' | 'bonds' | 'marketable_securities' | 'alternatives';
	interface CommentaryValues {
		cash: string;
		bonds: string;
		marketable_securities: string;
		alternatives: string;
	}

	const SECTION_KEY: Record<(typeof NONRE_TABLE_CAT_ORDER)[number], CommentarySection> = {
		Cash: 'cash',
		Bonds: 'bonds',
		'Marketable Securities': 'marketable_securities',
		Alternatives: 'alternatives'
	};

	const SECTIONS = NONRE_TABLE_CAT_ORDER.map((label) => ({ label, key: SECTION_KEY[label] }));

	let {
		targetMonthLabel,
		isDraft,
		commentary,
		priorMonthLabel,
		priorCommentary,
		allocation,
		staleness
	}: {
		targetMonthLabel: string;
		isDraft: boolean;
		commentary: CommentaryValues;
		priorMonthLabel: string;
		priorCommentary: CommentaryValues;
		allocation: NonReAllocation | null;
		staleness: StalenessData;
	} = $props();

	// Raw, un-normalized draft state -- one $state string per section, bound directly to each
	// visible <textarea>. ONE-TIME capture from props at mount, same "correct by construction"
	// posture TaxBracketScheduleEditor.svelte documents: this component has no `{#key}`-driven
	// remount concern (one instance per page, `targetMonth` never changes under a mounted
	// instance -- the whole page remounts on navigation to a different month).
	let values = $state<CommentaryValues>({ ...commentary });

	let serverFieldErrors = $state<Record<string, string[]>>({});
	let formError = $state('');
	let statusMessage = $state('');
	let saving = $state(false);

	function normalized(key: CommentarySection): string {
		return normalizeLineEndings(values[key]);
	}

	function codePoints(key: CommentarySection): number {
		return codePointLength(normalized(key));
	}

	function overBound(key: CommentarySection): boolean {
		return codePoints(key) > MONTHLY_COMMENTARY_MAX_CODE_POINTS;
	}

	const anyOverBound = $derived(SECTIONS.some((s) => overBound(s.key)));
	const saveDisabled = $derived(!isDraft || anyOverBound || saving);

	function errorsFor(key: CommentarySection): string[] {
		const server = serverFieldErrors[key];
		const client = overBound(key)
			? [`Over the ${MONTHLY_COMMENTARY_MAX_CODE_POINTS}-character limit.`]
			: [];
		return [...(server ?? []), ...client];
	}

	function priorBlank(key: CommentarySection): boolean {
		return priorCommentary[key].trim() === '';
	}

	const allPriorBlank = $derived(SECTIONS.every((s) => priorBlank(s.key)));

	function copyFromPrior(key: CommentarySection) {
		values[key] = priorCommentary[key];
	}

	function copyAllFromPrior() {
		for (const s of SECTIONS) values[s.key] = priorCommentary[s.key];
	}

	type ActionSuccess = { ok: true; commentary: CommentaryValues };
	type ActionFailure = { errors: Record<string, string[]> };

	// This component reads its OWN enhance callback's `result`, mirroring
	// TaxBracketScheduleEditor.svelte's convention -- one form on this page today, but the
	// convention is kept for consistency and because the page's shared `form` prop carries the
	// same ambiguity risk if a second form is ever added alongside this one.
	const handleSubmit: SubmitFunction = ({ formData, cancel }) => {
		if (saveDisabled) {
			cancel();
			return;
		}
		// Overwrite each hidden field with its normalized value at submit time -- the bind:value
		// on the hidden inputs below already tracks `normalized(key)` reactively, but this guards
		// against any staleness between the last keystroke and the submit event.
		for (const s of SECTIONS) formData.set(s.key, normalized(s.key));

		formError = '';
		serverFieldErrors = {};
		statusMessage = '';
		saving = true;

		return async ({ result, update }) => {
			saving = false;
			if (result.type === 'success') {
				const data = result.data as ActionSuccess | undefined;
				if (data?.ok) {
					statusMessage = 'Draft saved.';
					await update({ reset: false });
					return;
				}
			}
			if (result.type === 'failure') {
				const data = result.data as ActionFailure | undefined;
				serverFieldErrors = data?.errors ?? {};
				formError =
					serverFieldErrors._form?.join(' ') ?? 'Could not save — see the sections below.';
				await update({ reset: false });
				return;
			}
			formError = 'Something went wrong saving your changes. Please try again.';
			await update({ reset: false });
		};
	};
</script>

<div class="commentary-page">
	<div class="editor-col">
		{#if !isDraft}
			<p class="banner final-banner" role="status">
				This report is final. Commentary is read-only.
			</p>
		{/if}

		<form class="editor" method="POST" action="?/save" use:enhance={handleSubmit}>
			{#if formError}
				<p class="banner error-banner" role="alert">{formError}</p>
			{/if}
			{#if statusMessage}
				<p class="sr-only" role="status">{statusMessage}</p>
			{/if}

			<p class="editor-note">
				Plain text. Line breaks are kept — no markdown or rich-text formatting.
			</p>

			{#if isDraft}
				<div class="global-actions">
					<Button
						variant="link"
						type="button"
						disabled={allPriorBlank}
						onclick={copyAllFromPrior}
					>
						Copy all from {priorMonthLabel}
					</Button>
				</div>
			{/if}

			{#each SECTIONS as s (s.key)}
				<section class="sub-section" aria-labelledby={`heading-${s.key}`}>
					<div class="sub-section-head">
						<h3 id={`heading-${s.key}`}>{s.label}</h3>
						{#if isDraft}
							<Button
								variant="link"
								type="button"
								disabled={priorBlank(s.key)}
								onclick={() => copyFromPrior(s.key)}
							>
								Copy from {priorMonthLabel}
							</Button>
						{/if}
					</div>
					<TextAreaField
						label={`${s.label} commentary`}
						name={`${s.key}_editor`}
						id={`f-commentary-${s.key}`}
						bind:value={values[s.key]}
						disabled={!isDraft}
						rows={5}
						errors={errorsFor(s.key)}
					/>
					<p class="counter" class:over={overBound(s.key)} aria-live="polite">
						{codePoints(s.key)} / {MONTHLY_COMMENTARY_MAX_CODE_POINTS}
					</p>
					<input type="hidden" name={s.key} value={normalized(s.key)} />
				</section>
			{/each}

			<div class="actions">
				{#if isDraft}
					<Button variant="primary" type="submit" loading={saving} disabled={saveDisabled}>
						Save draft
					</Button>
				{/if}
				<Button variant="secondary" type="button" disabled title={`Not yet available (P4)`}>
					Finalize {targetMonthLabel}
				</Button>
			</div>
		</form>
	</div>

	<aside class="reference-col" aria-label="$ ReAlloc reference">
		{#if allocation === null}
			<p class="banner error-banner" role="status">
				Allocation is temporarily unavailable. Please try again shortly.
			</p>
		{:else}
			<NonReAllocationTable {allocation} {staleness} />
		{/if}
	</aside>
</div>

<style>
	.commentary-page {
		display: grid;
		grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
		gap: var(--space-6);
		align-items: start;
	}
	@media (max-width: 900px) {
		.commentary-page {
			grid-template-columns: 1fr;
		}
	}
	.editor-col,
	.reference-col {
		min-width: 0;
	}
	.editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.editor-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.global-actions {
		display: flex;
		justify-content: flex-end;
	}
	.sub-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding-top: var(--space-4);
		border-top: 1px solid var(--c-border);
	}
	.sub-section:first-of-type {
		padding-top: 0;
		border-top: none;
	}
	.sub-section-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-2);
	}
	.sub-section-head h3 {
		margin: 0;
		font-size: var(--fs-body);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.counter {
		margin: 0;
		align-self: flex-end;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.counter.over {
		color: var(--c-neg);
		font-weight: var(--weight-semi);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-3);
	}
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
	.final-banner {
		background: color-mix(in srgb, var(--c-text-muted) 12%, transparent);
		border: 1px solid var(--c-border-strong);
		color: var(--c-text-secondary);
	}
	.error-banner {
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
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
