// POST /api/asset/resolve — SELF-325 asset-resolve leg (manual purchase-path, Case 3 / public
// tickers). Browser-facing (fetch+JSON, NOT a form action — a security lookup step the purchase
// form calls BEFORE it can submit, the same shape as an autocomplete/picker read; the purchase
// itself goes through the createPurchase FORM ACTION in accounts/[account_id]/+page.server.ts).
//
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1) — never trusts a
//      client-supplied tenant.
//   2. Rate-limits on user.id (Sec C2, SELF-325 round 10 joint review) — see RESOLVE_RULE.
//   3. Validates the body with assetResolveSchema (`.strict()`, RESOLVABLE_ASSET_TYPES-narrowed —
//      the namespace-pollution boundary; see that schema's header for the full reasoning).
//   4. Relays { ownerUserId=session, symbol, cusip, asset_type, name=NULL, currency='USD' } to
//      the worker's internal /asset/resolve leg and returns { assetId }.
//
// ⚠ Sec C1 (SELF-325 round 10 joint review): `name` is HARD-CODED null to the worker regardless
// of the request body — never the client-supplied value. Measured vector: any signup can POST a
// free-text `name` (≤200 chars) that, on a resolve MISS, becomes a GLOBAL row's permanent display
// name — 020 grants the worker no UPDATE, so a bad name is unrepairable first-write squatting.
// `name` stays a CLIENT-SIDE match-confirmation field only (what the user sees after resolving),
// never mint content. This mirrors the existing `currency='USD'` treatment below (already never
// threaded from the body) — a second field the browser boundary must not author.
//
// Holds NO service_role key → stays OFF the RT-26 allowlist (mirrors every other admissionClient
// consumer in this directory).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { assetResolveSchema, fieldErrors } from '$lib/server/schemas/asset';
import { resolveAsset } from '$lib/server/asset/admissionClient';
import { consumeRateLimit } from '$lib/server/auth/rateLimit';

// Sec C2: a coarse abuse gate on user.id, using the SAME sliding-window primitive
// forgot-password/+page.server.ts already uses (Sec-reviewed there). SINGLE-INSTANCE CAVEAT
// (rateLimit.ts's own documented limit, restated here because it governs this call site too):
// the window state is per-process — V1 deploys ONE api container (ADR-011 Lock 13), so this is
// the whole picture today; it becomes per-instance if api/ ever scales horizontally, and GoTrue-
// style distributed enforcement is NOT what this is. Not a hard security boundary — a shed for
// obvious scripted abuse against the namespace-pollution surface (Sec C1), layered alongside it.
// 30 requests / 5 min / user — generous for interactive ticker lookups, coarse enough to block a
// scripted mint-loop.
const RESOLVE_RULE = { max: 30, windowMs: 5 * 60 * 1000 };

export const POST: RequestHandler = async ({ request, locals }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	const hit = consumeRateLimit('asset-resolve', user.id, RESOLVE_RULE);
	if (hit.limited) {
		return json(
			{ error: 'rate_limited' },
			{ status: 429, headers: { 'retry-after': String(Math.ceil(hit.retryAfterMs / 1000)) } }
		);
	}

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	const parsed = assetResolveSchema.safeParse(raw);
	if (!parsed.success) return json({ error: 'invalid_request', errors: fieldErrors(parsed.error) }, { status: 400 });

	// Sec C1 + currency: neither is threaded from the body. `name` is HARD-CODED null (see module
	// header) regardless of what parsed.data.name holds; `currency` is the literal 'USD', mirroring
	// schemas/account.ts's manualAccountCreateSchema precedent.
	const outcome = await resolveAsset(user.id, {
		symbol: parsed.data.symbol,
		cusip: parsed.data.cusip,
		assetType: parsed.data.asset_type,
		name: null,
		currency: 'USD'
	});
	if (!outcome.ok) return json({ error: 'resolve_failed' }, { status: outcome.status });

	return json({ assetId: outcome.data.assetId });
};
