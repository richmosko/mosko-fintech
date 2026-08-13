<!--
	InformationalMarkerBadge.svelte — the `informational-marker-badge` (design-
	system-spec.md §4, SELF-220 — first UI instantiation of §2.4.4's informational
	tier). §12.4 of flows/phase-2-flows-2.1-net-worth.md (merged dba7bf1) is the
	authoritative interaction spec; CSS is Visual Designer's deliverable
	(temp/visual-designer-self220-tokens.md §1), reproduced here verbatim.

	Series-level (ONE static badge for the whole visible window, never per-point —
	§2.4.4: "one series-level mark, not one per point"), anchored beside the
	"Net Worth (Inflation-Adjusted)" legend entry. Present/absent only — no loading,
	hover, or error states (§2.4.4: a static fact-render or nothing).

	Deliberately NOT `--c-attn-*` (Visual's explicit call): this is the
	INFORMATIONAL tier, not the actionable one — a different visual register
	entirely (quiet neutral chip), never a recolor of the canary stale-tag. Where an
	actionable marker (account re-auth / a real post-boundary cron gap) is also live
	in the same view, that marker takes visual precedence in ordering (rendered
	first in the legend-adjacent stack) but this badge stays fully readable beside
	it — "takes precedence" never means suppression here (§12.4 / §12.1 both state
	this explicitly for the basis-line family; the same rule governs this badge).

	Copy is UX's (Part 2 §2.4), threaded through as props — this component renders
	whatever it is given, never composes the cause-clause logic itself.
-->
<script lang="ts">
	let {
		carriedCount,
		cpiPeriod,
		carriedFrom,
		nonpublicationOnRecord
	}: {
		/** Count of distinct carried CPI-U months in the current visible window.
		 * Zero-footprint when 0 (§2.4.4: renders nothing, not an empty badge). */
		carriedCount: number;
		/** The (most recent, if multiple) carried period — first-of-month ISO date. */
		cpiPeriod: string | null;
		/** The period it was carried from — first-of-month ISO date. */
		carriedFrom: string | null;
		/** §2.4.4 "cause asserted only when on record" — same tier/weight either
		 * way, only the sentence differs. */
		nonpublicationOnRecord: boolean;
	} = $props();

	const monthYear = (iso: string) =>
		new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
			month: 'long',
			year: 'numeric',
			timeZone: 'UTC'
		});

	// §12.4: multiple distinct carried spans collapse into one count-naming badge;
	// a single span names the period + source. Per-month hover attribution is V2+.
	const message = $derived.by(() => {
		if (carriedCount > 1) {
			return `Includes ${carriedCount} carried CPI-U months in this range.`;
		}
		if (cpiPeriod && carriedFrom) {
			const cause = nonpublicationOnRecord
				? ` — CPI-U for ${monthYear(cpiPeriod)} was not published; carried forward. No action needed.`
				: '';
			return `Includes a carried CPI-U value for ${monthYear(cpiPeriod)} (from ${monthYear(carriedFrom)}).${cause}`;
		}
		return '';
	});
</script>

{#if carriedCount > 0 && message}
	<span class="info-marker-badge">
		<span class="info-marker-icon" aria-hidden="true"></span>
		<span class="info-marker-value">{message}</span>
	</span>
{/if}

<style>
	/* Series-level, static, non-hover-legible. NEVER canary — that hue is reserved
	   for the actionable tier (stale-tag / stale-row / P4 banner). Zero-footprint
	   when no CPI-carry is in the visible window (the #if above). */
	.info-marker-badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-sm);
		padding: 2px var(--space-2);
		line-height: var(--lh-body);
	}
	.info-marker-icon {
		flex: 0 0 auto;
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--c-text-muted); /* quiet dot, NOT attn-solid — informational identity */
	}
	.info-marker-value {
		font-family: var(--font-num);
		color: var(--c-text-primary);
		font-weight: var(--weight-med);
	}
</style>
