<!--
	NoLedgerDesignatedPrompt.svelte — the P4 (SELF-356 AC4) pre-finalize nudge: "No IRS/FTB ledger
	designated — NAV on this report will exclude tax liabilities." R1 rider 6: a frozen payload
	freezes its defects, so this is the ONE moment (before finalize) to catch a tax-authority
	designation gap while it is still correctable. A PROMPT, NOT A BLOCK (team-lead's own framing,
	AC4) — this renders informationally beside the finalize affordances; it never disables them.

	Copy is PM-authored, folded verbatim (AC4). The CTA link text/href reuses
	TaxQuarterlyTables.svelte's own shipped `designateAccountHref` precedent ("Designate an
	account" -> `/accounts`, its own AC 6(ii) empty-state banner) rather than inventing new
	copy/target for what is the SAME underlying signal (a tax_jurisdiction designation gap) —
	flagged at hand-off since user-facing copy is nominally UX/PM's call, even when reused rather
	than invented.

	Shared by TWO call sites (JUDGMENT CALL, flagged): P5's pending-list item (AC4's own literal
	"the pending view") AND P3's commentary-editor finalize action — R1 rider 6's rationale ("catch
	it before it's permanent") applies equally to the authored-finalize exit door, not only the
	skip-finalize one named in AC4's text, so this renders on both rather than leaving the authored
	path uncovered. One shared component so the copy has exactly one source.

	Visual treatment mirrors TaxQuarterlyTables.svelte's own `.no-authority-banner` (informational
	register — `--c-surface-alt` / `--c-border-strong` — deliberately NOT the `--c-attn-*` canary
	hue, which this codebase reserves for staleness/re-auth only, a different signal class).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<div class="no-ledger-prompt" role="status">
	<span class="prompt-text">
		No IRS/FTB ledger designated — NAV on this report will exclude tax liabilities.
	</span>
	<a class="prompt-cta" href="/accounts">Designate an account</a>
</div>

<style>
	.no-ledger-prompt {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-3);
		padding: var(--space-3);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
	}
	.prompt-text {
		font: var(--weight-semi) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-primary);
	}
	.prompt-cta {
		color: var(--c-accent);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		text-decoration: underline;
	}
	.prompt-cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
</style>
