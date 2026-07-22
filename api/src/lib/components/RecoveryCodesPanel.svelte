<!--
	RecoveryCodesPanel.svelte — DISPLAY-ONCE recovery-code panel (SELF-291 / Auth-3b
	Slice 2b). Frontend-owned browser primitive. Renders the plaintext MFA backup codes
	EXACTLY ONCE, from the action-return data the parent passes in — never persists them in
	client state beyond this panel, never refetches. On reload the action data is gone and
	the codes cannot reappear (the display-once security property).

	Contract: `codes` is the 10 grouped strings (`abcd-efgh-ijkl-mnop`) returned by the
	server (?/enrollVerify or ?/regenerateRecoveryCodes). The panel offers:
	  (a) copy-all      → navigator.clipboard (client-initiated; CSP-safe compiled handler)
	  (b) download .txt → a client-generated Blob built from `codes` (no network)
	  (c) confirm       → the user must click "I've saved these codes" before the panel
	                      dismisses; a beforeunload guard warns if they try to leave first.

	INV-1 plain-text only — the codes render as neutral monospace surface text (var(--font-num)
	on var(--c-surface-alt)). NO value-color (--c-pos/--c-neg) and NO attention hue
	(--c-attn-*, reserved for staleness/re-auth) touches the codes. Tokens only (var(--c-*)).
-->
<script lang="ts">
	import Button from './Button.svelte';

	let {
		codes,
		title = 'Save your backup codes',
		confirmLabel = "I've saved these codes"
	}: {
		codes: string[];
		title?: string;
		confirmLabel?: string;
	} = $props();

	// Local, ephemeral only. `dismissed` gates the panel; `copied` is transient UI feedback.
	// Neither the codes nor any derivative is persisted beyond this component instance.
	let dismissed = $state(false);
	let copied = $state(false);

	const plainText = $derived(codes.join('\n'));

	// Warn before a same-page navigation / tab close while the codes are still unsaved —
	// they can never be shown again. Compiled listener (CSP-safe), browser-only via $effect.
	$effect(() => {
		if (dismissed) return;
		const warn = (e: BeforeUnloadEvent) => {
			e.preventDefault();
			// Legacy assignment kept for broad browser support; message text is ignored by
			// modern browsers (they show their own generic "unsaved changes" prompt).
			e.returnValue = '';
		};
		window.addEventListener('beforeunload', warn);
		return () => window.removeEventListener('beforeunload', warn);
	});

	async function copyAll() {
		try {
			await navigator.clipboard.writeText(plainText);
			copied = true;
			setTimeout(() => (copied = false), 2000);
		} catch {
			// Clipboard blocked (permissions / insecure context) — the codes are still visible
			// and downloadable; no destructive fallback needed.
			copied = false;
		}
	}

	function downloadTxt() {
		const body =
			'mosko-fintech — two-factor recovery codes\n' +
			'Keep these somewhere safe. Each code works once.\n\n' +
			plainText +
			'\n';
		const blob = new Blob([body], { type: 'text/plain;charset=utf-8' });
		const url = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = url;
		a.download = 'mosko-fintech-recovery-codes.txt';
		document.body.appendChild(a);
		a.click();
		a.remove();
		URL.revokeObjectURL(url);
	}
</script>

{#if !dismissed}
	<section class="panel" aria-labelledby="rc-title" aria-describedby="rc-intro">
		<h3 id="rc-title" class="panel-title">{title}</h3>
		<p id="rc-intro" class="intro">
			These one-time backup codes let you sign in if you lose your authenticator. Each code
			works once. <strong>They won't be shown again</strong> — copy or download them now and
			store them somewhere safe.
		</p>

		<ol class="codes" aria-label="Your backup codes">
			{#each codes as code (code)}
				<li class="code">{code}</li>
			{/each}
		</ol>

		<div class="actions">
			<Button type="button" onclick={copyAll} aria-live="polite">
				{copied ? 'Copied' : 'Copy all'}
			</Button>
			<Button type="button" onclick={downloadTxt}>Download .txt</Button>
		</div>

		<div class="confirm">
			<Button variant="primary" type="button" onclick={() => (dismissed = true)}>
				{confirmLabel}
			</Button>
		</div>
	</section>
{/if}

<style>
	.panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.panel-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.intro {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.intro strong {
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	/* Neutral monospace block — INV-1 plain text. No value-color, no attention hue. */
	.codes {
		list-style: none;
		margin: 0;
		padding: var(--space-3);
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: var(--space-2) var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
	}
	.code {
		font-family: var(--font-num);
		font-size: var(--fs-body);
		color: var(--c-text-primary);
		letter-spacing: 0.02em;
		user-select: all;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.confirm {
		display: flex;
	}
	@media (max-width: 30rem) {
		.codes {
			grid-template-columns: 1fr;
		}
	}
</style>
