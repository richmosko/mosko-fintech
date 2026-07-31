// connection-display.ts — presentation strings + tone for the connection-status chip states.
//
// The VALUE-SET + chip-state derivation are canonical (connection-status-constants.ts, tracked
// to the `015` DB CHECK). These are only the human-readable DISPLAY strings + the visual TONE
// each chip state maps to. Copy is PROVISIONAL — final user-facing wording is UX Designer's
// call (flagged at authoring). Kept exhaustive-by-state (Record<ConnectionChipState,…>) so a
// value-set change is a compile error here, not a silent gap.
//
// TONE is the design-system fence made explicit: only the re-auth / staleness states carry the
// ATTENTION hue (`--c-attn-*`, canary — reserved for staleness/re-auth per §5 fence 8). 'fresh'
// gets the positive dot; 'manual'/'inactive' are neutral/muted (NOT attention — they are not
// staleness). The component maps tone → tokens; the copy here never picks a hex.

import type { ConnectionChipState } from '$lib/schemas/connection-status-constants';

/** Visual tone a chip state maps to. `pos` = healthy dot; `attn` = canary staleness/re-auth;
 *  `muted` = neutral (manual/inactive — not an attention signal). */
export type ChipTone = 'pos' | 'attn' | 'muted';

export type ChipPresentation = {
	/** Short chip label. */
	label: string;
	/** Visual tone (→ token mapping in the component). */
	tone: ChipTone;
	/** One-line explanation for the connection-state view row (not shown in the compact chip). */
	description: string;
};

export const CONNECTION_CHIP_PRESENTATION: Record<ConnectionChipState, ChipPresentation> = {
	fresh: {
		label: 'Connected',
		tone: 'pos',
		description: 'Syncing normally.'
	},
	login_required: {
		label: 'Action needed',
		tone: 'attn',
		description: 'Your institution needs you to sign in again to keep this account syncing.'
	},
	institution_down: {
		label: 'Institution unavailable',
		tone: 'attn',
		description: "Your institution is temporarily unreachable. We'll keep retrying — no action needed."
	},
	revoked: {
		label: 'Access revoked',
		tone: 'attn',
		description: 'Access to this account was revoked. Re-authenticate to resume syncing.'
	},
	disconnected: {
		label: 'Disconnected',
		tone: 'attn',
		description: 'This connection was disconnected. Re-authenticate to resume syncing.'
	},
	manual: {
		label: 'Manual',
		tone: 'muted',
		description: 'You update this account by hand — no automatic connection.'
	},
	inactive: {
		label: 'Sync paused',
		tone: 'muted',
		description: 'This account is inactive, so syncing is paused. Its history is kept.'
	}
};

/** How each provider is labelled on connection surfaces — the connection's identity is its
 *  provider (Plaid / SimpleFIN), a system value, NOT a user-editable nickname (F/CTO). */
const PROVIDER_LABEL: Record<string, string> = {
	plaid: 'Plaid',
	simplefin: 'SimpleFIN',
	manual: 'Manual',
	import: 'Import'
};

/** Human label for a provider value; unknown providers fall back to the raw value. */
export function providerLabel(provider: string): string {
	return PROVIDER_LABEL[provider] ?? provider;
}

/** Safe lookup that falls back to a neutral presentation if an unknown state ever appears. */
export function chipPresentation(state: ConnectionChipState): ChipPresentation {
	return (
		CONNECTION_CHIP_PRESENTATION[state] ?? {
			label: 'Unknown',
			tone: 'muted',
			description: ''
		}
	);
}
