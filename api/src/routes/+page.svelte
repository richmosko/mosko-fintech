<!--
	SELF-185 scaffold hello-world. Proves the locked design-system tokens
	(docs/DESIGN/tokens.css) are globally available and consumed via var(--c-*).
	Token-consumption-only — no hardcoded hex/px/font values (ADR-013 P5).
-->
<main class="scaffold">
	<h1>mosko-fintech</h1>
	<p>SvelteKit (Svelte 5) web-app scaffold — SELF-185.</p>
	<p class="note">Design-system tokens wired: this surface renders from <code>var(--c-*)</code>.</p>
</main>

<style>
	.scaffold {
		max-width: 40rem;
		margin: 0 auto;
		padding: var(--space-7) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	h1 {
		margin: 0;
		font-size: var(--fs-hero);
		font-weight: var(--weight-bold);
		line-height: var(--lh-tight);
		color: var(--c-accent);
	}

	p {
		margin: 0;
		color: var(--c-text-secondary);
	}

	.note {
		padding: var(--space-3) var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		color: var(--c-text-primary);
	}

	code {
		font-family: var(--font-num);
		font-size: var(--fs-num);
		color: var(--c-accent-active);
	}
</style>
