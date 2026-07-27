<!--
	SyncHistoryTable.svelte — per-account provider sync-history view (SELF-204 / ADR-034 D3;
	AC #4/#5). READ-ONLY: renders the rows Backend exposes from pfin.linked_source_sync_history
	(the owner-semantics view over the service_role-only sync-audit — only provider / source /
	created_at / transactions_inserted / transactions_skipped ever reach the browser).

	NO edit / delete / re-run affordance — read-only is an AC requirement (RBAC-tested). The
	parent only renders this for provider-linked accounts (a manual account has no sync history);
	empty-state here covers a linked account with no history rows yet.

	Self-contained table styles (own .sync-tbl class — not coupled to the page-owned .tbl :global
	rules). Tokens only (var(--c-*)). Counts are neutral (--font-num), never --c-pos/--c-neg
	(those are ACTUAL-performance only; a sync count is not performance — design §5 fence 1).
-->
<script lang="ts">
	import { formatTimestamp, syncSourceLabel, type SyncHistoryRow } from '$lib/transaction-util';

	let { rows }: { rows: SyncHistoryRow[] } = $props();
</script>

{#if rows.length === 0}
	<p class="empty">No sync history yet.</p>
{:else}
	<div class="table-scroll">
		<table class="sync-tbl">
			<thead>
				<tr>
					<th scope="col">When (UTC)</th>
					<th scope="col">Provider</th>
					<th scope="col">Trigger</th>
					<th scope="col" class="num">Added</th>
					<th scope="col" class="num">Skipped</th>
				</tr>
			</thead>
			<tbody>
				{#each rows as r, i (`${r.created_at}-${i}`)}
					<tr>
						<td>{formatTimestamp(r.created_at)}</td>
						<td>{r.provider}</td>
						<td>{syncSourceLabel(r.source)}</td>
						<td class="num num-cell">{r.transactions_inserted ?? '—'}</td>
						<td class="num num-cell">{r.transactions_skipped ?? '—'}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
{/if}

<style>
	.table-scroll {
		overflow-x: auto;
	}
	.sync-tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.sync-tbl th,
	.sync-tbl td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
		white-space: nowrap;
	}
	.sync-tbl th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.sync-tbl td.num,
	.sync-tbl th.num {
		text-align: right;
	}
	.sync-tbl .num-cell {
		font-family: var(--font-num);
	}
	.sync-tbl tbody tr:hover td {
		background: var(--c-surface-alt);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
	}
</style>
