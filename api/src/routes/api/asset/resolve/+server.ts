// POST /api/asset/resolve — SELF-325 asset-resolve leg (manual purchase-path, Case 3 / public
// tickers). Browser-facing (fetch+JSON, NOT a form action — a security lookup step the purchase
// form calls BEFORE it can submit, the same shape as an autocomplete/picker read; the purchase
// itself goes through the createPurchase FORM ACTION in accounts/[account_id]/+page.server.ts).
//
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1) — never trusts a
//      client-supplied tenant.
//   2. Validates the body with assetResolveSchema (`.strict()`, RESOLVABLE_ASSET_TYPES-narrowed —
//      the namespace-pollution boundary; see that schema's header for the full reasoning).
//   3. Relays { ownerUserId=session, symbol, cusip, asset_type, name, currency='USD' } to the
//      worker's internal /asset/resolve leg and returns { assetId }.
//
// Holds NO service_role key → stays OFF the RT-26 allowlist (mirrors every other admissionClient
// consumer in this directory).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { assetResolveSchema, fieldErrors } from '$lib/server/schemas/asset';
import { resolveAsset } from '$lib/server/asset/admissionClient';

export const POST: RequestHandler = async ({ request, locals }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	const parsed = assetResolveSchema.safeParse(raw);
	if (!parsed.success) return json({ error: 'invalid_request', errors: fieldErrors(parsed.error) }, { status: 400 });

	// Currency is deliberately not a form field (see assetResolveSchema's header) — 'USD' is the
	// literal supplied here, mirroring schemas/account.ts's manualAccountCreateSchema precedent.
	const outcome = await resolveAsset(user.id, {
		symbol: parsed.data.symbol,
		cusip: parsed.data.cusip,
		assetType: parsed.data.asset_type,
		name: parsed.data.name,
		currency: 'USD'
	});
	if (!outcome.ok) return json({ error: 'resolve_failed' }, { status: outcome.status });

	return json({ assetId: outcome.data.assetId });
};
