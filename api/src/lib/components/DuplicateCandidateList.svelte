<!--
	DuplicateCandidateList.svelte — manual↔provider candidate-duplicate DETECTION surface
	(SELF-204 / §ADR-034 Decision 2). READ-ONLY: renders the pairs Backend exposes from
	pfin.manual_provider_dup_candidate (a manual transaction that shares an import-hash with a
	synced provider transaction in the same account). Each pair shows enough to identify both
	legs so the user can reconcile them THROUGH EXISTING MECHANISMS.

	DETECTION-ONLY (hard scope): NO auto-action, NO skip button, NO link button. This surface
	writes nothing and decides nothing — whether a pair is already reconciled is SELF-205's
	interpretation, not shown here. Empty-state when there are no candidates.

	Tokens only (var(--c-*)). The "Manual" / "Synced" leg tags are NEUTRAL chrome (surface-alt /
	border) — NOT the canary attention hue (--c-attn-*, reserved for staleness/re-auth) and NOT
	--c-pos/--c-neg (amounts are neutral ledger values, not ACTUAL performance; design §5 fences).
-->
<script lang="ts">
	import { money, type DupCandidate } from '$lib/transaction-util';

	let { candidates }: { candidates: DupCandidate[] } = $props();
</script>

{#if candidates.length === 0}
	<p class="empty">No possible duplicates detected.</p>
{:else}
	<p class="lead">
		These manual transactions look like transactions a linked provider also synced. Review each
		pair and reconcile them yourself — nothing here changes your data.
	</p>
	<ul class="cand-list">
		{#each candidates as c (`${c.manual_trans_id}-${c.provider_trans_id}`)}
			<li class="cand">
				<div class="leg">
					<span class="leg-tag">Manual entry</span>
					<dl class="leg-facts">
						<div class="fact"><dt>Date</dt><dd>{c.manual_date}</dd></div>
						<div class="fact"><dt>Amount</dt><dd class="num">{money(c.manual_amount)}</dd></div>
						<div class="fact"><dt>Vendor</dt><dd>{c.manual_vendor ?? '—'}</dd></div>
						<div class="fact"><dt>Description</dt><dd>{c.manual_description ?? '—'}</dd></div>
					</dl>
				</div>
				<div class="leg">
					<span class="leg-tag">Synced from provider</span>
					<dl class="leg-facts">
						<div class="fact"><dt>Date</dt><dd>{c.provider_date}</dd></div>
						<div class="fact"><dt>Amount</dt><dd class="num">{money(c.provider_amount)}</dd></div>
						<div class="fact"><dt>Provider</dt><dd>{c.provider}</dd></div>
					</dl>
				</div>
			</li>
		{/each}
	</ul>
{/if}

<style>
	.lead {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		max-width: 44rem;
	}
	.cand-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.cand {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-4);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-3);
		background: var(--c-surface-alt);
	}
	@media (max-width: 560px) {
		.cand {
			grid-template-columns: 1fr;
		}
	}
	.leg {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		min-width: 0;
	}
	.leg-tag {
		align-self: flex-start;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-pill);
		padding: 1px var(--space-2);
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
		background: var(--c-surface);
	}
	.leg-facts {
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.fact {
		display: grid;
		grid-template-columns: 7rem minmax(0, 1fr);
		gap: var(--space-2);
	}
	.fact dt {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
		font-weight: var(--weight-semi);
	}
	.fact dd {
		margin: 0;
		color: var(--c-text-primary);
		overflow-wrap: anywhere;
	}
	.fact dd.num {
		font-family: var(--font-num);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
	}
</style>
