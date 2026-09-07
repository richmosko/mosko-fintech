<!--
	settings/+layout.svelte — the /settings shell (SELF-242 AC1). Frontend-owned browser
	surface; authors NO server logic.

	Left-rail navigation over the Settings sections. V1.2 shipped two ENABLED sections —
	Security (pre-existing, SELF-291) and Allocation (SELF-242) — SELF-252 enabled a third,
	Cash-flow Targets (§2.3.2), SELF-265 enabled a fourth, Tax Brackets (§2.5.2), and SELF-359
	(this issue) enables the fifth, Owner Identification (§2.6.4.b, pfin.owner_identification)
	— closing the Settings ramp at 4/4 planning-value editors (AC6: SELF-242 + SELF-252 +
	SELF-265 + this). Sections and Lock 14 members do not count one-to-one (Tax Brackets is one
	section over two tables; Owner Identification is the fifth and last table but the fourth
	editor), so no tally is carried here — read ADR-011 Decision 18 live for the family's
	amended size. Security sits outside the V1.2/V1.3 versioning scheme named in the AC (it's
	an existing MFA surface, not one of the planning-value settings) but belongs in this shell
	as a real, live section.

	LEFT-RAIL vs TOP-TAB (AC1 offers either shape): left-rail chosen here — a Just-Decide
	call, not routed to Visual Designer, since the design system does not lock either shape
	for Settings specifically and a 5-section list reads better as a rail than as tabs that
	will keep growing. Flagged at hand-off as a judgment call rather than asserted as the
	only good answer.

	Disabled sections render as non-interactive <span> (not <a> — no dead links to a route
	that doesn't exist), aria-disabled, with a visible "Coming in V1.x" caption rather than a
	title-only cue (screen-reader + visual parity).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { page } from '$app/state';

	let { children }: { children: import('svelte').Snippet } = $props();

	type Section = { label: string; href: string } | { label: string; href: null };

	const sections: Section[] = [
		{ label: 'Security', href: '/settings/security' },
		{ label: 'Allocation', href: '/settings/allocation' },
		{ label: 'Cash-flow Targets', href: '/settings/cash-flow-targets' },
		{ label: 'Tax Brackets', href: '/settings/tax-brackets' },
		{ label: 'Owner Identification', href: '/settings/owner-id' }
	];

	const path = $derived(page.url.pathname);
	function isActive(href: string): boolean {
		return path === href || path.startsWith(`${href}/`);
	}
</script>

<div class="settings-shell">
	<nav class="settings-rail" aria-label="Settings">
		<ul>
			{#each sections as section (section.label)}
				<li>
					{#if section.href}
						<a
							class="rail-link"
							href={section.href}
							aria-current={isActive(section.href) ? 'page' : undefined}
						>
							{section.label}
						</a>
					{:else}
						<span class="rail-link is-disabled" aria-disabled="true">
							{section.label}
							<span class="coming-soon">Coming in V1.x</span>
						</span>
					{/if}
				</li>
			{/each}
		</ul>
	</nav>
	<div class="settings-content">
		{@render children()}
	</div>
</div>

<style>
	.settings-shell {
		display: flex;
		align-items: flex-start;
		gap: var(--space-6);
		max-width: 64rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		box-sizing: border-box;
	}
	.settings-rail {
		flex: 0 0 12rem;
		position: sticky;
		top: var(--space-6);
	}
	.settings-rail ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.rail-link {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-body) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		text-decoration: none;
	}
	.rail-link:hover {
		background: var(--c-surface-alt);
		color: var(--c-text-primary);
	}
	.rail-link[aria-current='page'] {
		background: var(--c-accent-soft);
		color: var(--c-accent);
		font-weight: var(--weight-semi);
	}
	.rail-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.rail-link.is-disabled {
		color: var(--c-disabled-text);
		cursor: default;
	}
	.coming-soon {
		font: var(--weight-reg) var(--fs-micro) / 1.2 var(--font-ui);
		color: var(--c-disabled-text);
	}
	.settings-content {
		flex: 1 1 auto;
		min-width: 0;
	}
</style>
