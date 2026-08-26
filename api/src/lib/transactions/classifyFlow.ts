// classifyFlow.ts — pure, dependency-injected core for the SELF-249 per-row Sub-Cat picker's
// write path (POST /api/transactions/:trans_id/classify, SELF-248). Mirrors accounts/syncFlow.ts:
// a client-initiated action against a JSON API route (NOT a form action — api/CLAUDE.md forms
// rule: fetch+JSON is correct here because the endpoint IS a `+server.ts` route, not a form
// action), framework-free and unit-testable with an injectable `fetchFn`. The DOM/state parts
// (picker value, saving flag, inline error) live in SubCatPicker.svelte.
//
// The outgoing body runs through classifyTransSchema (the client `.strict()` mirror of
// Backend's server schema) before send — belt-and-braces proof only `sub_cat_id` leaves the
// browser. `users_id`/tenancy is never a field here; RLS resolves it server-side.

import { classifyTransSchema } from '$lib/schemas/transaction';

export type FetchLike = typeof fetch;

/**
 * Actionable failure code. The first block mirrors the server's `ClassifiableRefusalReason` +
 * its two write-time-only codes 1:1 (api/src/lib/server/queries/transactions.ts) — SAME strings,
 * so `classifyRefusalCopy` (transaction-util.ts) can map either a disabled-render reason or a
 * submit failure through ONE copy table. The second block is transport-level, mirroring
 * syncFlow.ts's `SyncFailureKind` shape for an unrecognized/absent code.
 */
export type ClassifyFailureCode =
	| 'not_standard'
	| 'has_security'
	| 'split_parent'
	| 'is_reversal'
	| 'journaled'
	| 'journaled_cat_conflict'
	| 'invalid_sub_cat_id'
	| 'not_found'
	| 'invalid_request'
	| 'unauthenticated'
	| 'server_error'
	| 'network'
	| 'malformed';

const KNOWN_REFUSAL_CODES: ReadonlySet<string> = new Set([
	'not_standard',
	'has_security',
	'split_parent',
	'is_reversal',
	'journaled',
	'journaled_cat_conflict',
	'invalid_sub_cat_id'
]);

export class ClassifyError extends Error {
	readonly code: ClassifyFailureCode;
	readonly status: number | null;
	constructor(code: ClassifyFailureCode, status: number | null = null) {
		super(`Classify failed (${code}${status != null ? ` ${status}` : ''})`);
		this.name = 'ClassifyError';
		this.code = code;
		this.status = status;
	}
}

/** Map a relay HTTP status + the endpoint's own typed `code` (when present and recognized) to
 *  an actionable failure code. The endpoint's `code` wins when it's one we know — it is more
 *  specific than the status alone (e.g. every classifiable() refusal is a 409). */
function classify(status: number, bodyCode?: string): ClassifyFailureCode {
	if (bodyCode && KNOWN_REFUSAL_CODES.has(bodyCode)) return bodyCode as ClassifyFailureCode;
	if (status === 401) return 'unauthenticated';
	if (status === 404) return 'not_found';
	if (status === 400) return 'invalid_request';
	return 'server_error';
}

/**
 * POST { sub_cat_id } to SELF-248's classify endpoint for `transId`. Resolves to the accepted
 * `{ trans_id, sub_cat_id }` on success, or throws `ClassifyError`. Success does NOT itself
 * refresh any local view — the caller (SubCatPicker) re-validates the loader so the row's
 * `category` / `classifiable` / suggestion fields refresh from the server's own re-derivation,
 * the same "accepted, then re-read the real state" shape syncFlow's 202 uses.
 */
export async function classifyTrans(
	transId: number,
	subCatId: number,
	fetchFn: FetchLike = fetch
): Promise<{ trans_id: number; sub_cat_id: number }> {
	const body = classifyTransSchema.parse({ sub_cat_id: subCatId });

	let res: Response;
	try {
		res = await fetchFn(`/api/transactions/${transId}/classify`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		throw new ClassifyError('network');
	}

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new ClassifyError(res.ok ? 'malformed' : classify(res.status), res.status);
	}

	if (!res.ok) {
		const code =
			json && typeof json === 'object' && 'code' in json && typeof (json as { code: unknown }).code === 'string'
				? (json as { code: string }).code
				: undefined;
		throw new ClassifyError(classify(res.status, code), res.status);
	}

	return { trans_id: transId, sub_cat_id: body.sub_cat_id };
}
