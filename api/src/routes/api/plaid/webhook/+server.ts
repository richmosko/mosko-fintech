// POST /api/plaid/webhook — SELF-206 (§2.4.4.a) Plaid webhook handler. V1-SHIP-BLOCK,
// Sec-joint-review-mandatory (external-API webhook + RT-05 + privileged-context-write).
//
// ROUTE Z-INVOKER (F/CTO-ratified) — the atomic DB write body lives in two SECURITY INVOKER
// RPCs (migration 045: fn_plaid_webhook_resolve read-only + fn_plaid_webhook_commit atomic),
// because supabase-js/PostgREST cannot hold a client-side BEGIN SERIALIZABLE across calls.
// The handler orchestrates them around the EXTERNAL worker sync (Option A — PLAID_SECRET is
// worker-only; api/src never fetches Plaid).
//
// C-X2 CLOSURE (sync-FIRST / gate-at-COMPLETION): the idempotency gate (the sync_audit row) is
// claimed by commit ONLY AFTER the external sync is confirmed dispatched. A crash before commit
// leaves NO gate row → Plaid's at-least-once retry re-drives (resolve is read-only/idempotent; the
// sync is idempotent via the 045 sync_cursor + fn_ingest ON CONFLICT). No poll backstop needed
// (SELF-213 is Backlog). C-X1: return 2xx ONLY on full completion (incl. sync dispatch) OR a
// confirmed duplicate; ANY partial failure → 5xx so Plaid retries.
//
// THREE capability-verify reconciliations (Sec joint-review headline items):
//   R1 signature = asymmetric ES256 JWT (not HMAC PLAID_WEBHOOK_SECRET) — worker fetches the PUBLIC
//      JWK; we verify locally with jose (webhookVerify.ts).
//   R2 atomicity = Route Z-INVOKER RPC pair (PostgREST has no interactive tx) — migration 045.
//   R3 `.strict()` on the external Plaid body would 400 legit webhooks (type-specific top-level
//      fields) → strip-unknowns z.object() + extract ONLY named fields + never spread the body.
//
// DISCIPLINES: tenant resolved IN CODE from the Item id INSIDE the RPCs (never a session/caller key;
// the webhook is external → NO safeGetSession). service_role confined to supabaseAdmin() (the sole
// RT-26 surface). C6-5/M8: machine-code-only error envelopes; NO raw body / token / secret in logs.

import { json, type RequestHandler } from '@sveltejs/kit';
import { z } from 'zod';
import { supabaseAdmin } from '$lib/server/supabase-admin';
import { fetchWebhookVerificationKey, triggerSourceSync } from '$lib/server/plaid/admissionClient';
import {
	JwkCache,
	verifyPlaidWebhook,
	deriveProviderEventId
} from '$lib/server/plaid/webhookVerify';
import { plaidStatusTransition, isTransactionsEvent } from '$lib/server/plaid/webhookStatus';

const MAX_BODY_BYTES = 64 * 1024; // mirror the worker admission 64KB cap (fail-closed on oversize).
const PLAID_VERIFICATION_HEADER = 'plaid-verification';

// Module-singleton bounded JWK cache; the credentialed fetch is the worker admission route (the
// ONLY place the Plaid creds live). Values come solely from this fetch, never from the JWT (M7).
const jwkCache = new JwkCache(fetchWebhookVerificationKey);

// R3: strip-unknowns (default z.object) over the CONSUMED fields only. Extra top-level keys are
// dropped, never passed through. `error` is Plaid's nested error object on ITEM errors.
const plaidWebhookSchema = z.object({
	webhook_type: z.string().min(1),
	webhook_code: z.string().min(1),
	item_id: z.string().min(1),
	error: z.object({ error_code: z.string().nullish() }).nullish()
});

/** service_role PostgREST accessor scoped to the pfin schema (RPCs live in pfin). */
const pfin = () => supabaseAdmin().schema('pfin');

interface ResolveRow {
	resolved: boolean;
	already_processed: boolean;
	should_trigger_sync: boolean;
	source_id: number | string | null;
	users_id: string | null;
}

export const POST: RequestHandler = async ({ request }) => {
	// ── Body-size cap (fail-closed) ─────────────────────────────────────────────────────
	const declaredLen = Number(request.headers.get('content-length') ?? '');
	if (Number.isFinite(declaredLen) && declaredLen > MAX_BODY_BYTES) {
		return json({ error: 'payload_too_large' }, { status: 413 });
	}

	// M2: read the RAW body BEFORE any JSON parse — the signature is over these exact bytes.
	let rawBody: string;
	try {
		rawBody = await request.text();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	if (rawBody.length > MAX_BODY_BYTES) {
		return json({ error: 'payload_too_large' }, { status: 413 });
	}

	// ── AC1 / RT-05: signature verification (M1 ES256-pin, M2 body-hash, M3 iat freshness) ──
	// Invalid → 401, NO writes. Fails CLOSED on every error mode.
	const verification = await verifyPlaidWebhook(
		rawBody,
		request.headers.get(PLAID_VERIFICATION_HEADER),
		{ cache: jwkCache }
	);
	if (!verification.ok) {
		console.error(`[plaid-webhook] 401 verification failed (${verification.reason})`);
		return json({ error: 'unauthorized' }, { status: 401 });
	}

	// ── R3: parse the AUTHENTIC body; extract ONLY named fields (strip-unknowns) ────────────
	let parsedBody: unknown;
	try {
		parsedBody = JSON.parse(rawBody);
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	const parsed = plaidWebhookSchema.safeParse(parsedBody);
	if (!parsed.success) {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	const { webhook_type, webhook_code, item_id } = parsed.data;
	const errorCode = parsed.data.error?.error_code ?? null;

	// Normalize provider → provider-blind status_class (AC4) + AC5 gate. Provider mapping stays
	// app-side (webhookStatus.ts); the RPCs receive already-normalized inputs.
	const transition = plaidStatusTransition(webhook_type, webhook_code, errorCode);
	const isTxn = isTransactionsEvent(webhook_type);

	// PER-PATH IDEMPOTENCY (045): the provider_event_id gate is event-class-split.
	//  • STATE / ITEM events → a per-delivery id (plaid:<iat>:<body_sha256>) so RPC-1
	//    already_processed suppresses an exact-JWT replay (short-circuit 200); RPC-2 RAISEs on NULL.
	//  • TRANSACTIONS events → NULL id. The money path is deduped by the /transactions/sync A3
	//    cursor + fn_ingest ON CONFLICT — a content-hash id would FALSE-COLLIDE on two same-second
	//    byte-identical SYNC_UPDATES_AVAILABLE bodies (iat is integer seconds) → a dropped legit
	//    sync = money-flow data loss. RPC-2 does NOT RAISE on NULL for transactions; NULLs are
	//    distinct in the UNIQUE index → no collision. Replay bound = RT-05 iat-freshness + cursor.
	const pEvent: Record<string, unknown> = {
		item_id,
		provider_event_id: isTxn ? null : deriveProviderEventId(verification.claims),
		is_transactions_event: isTxn,
		status_class: transition?.statusClass ?? null,
		provider_error_code: transition?.providerErrorCode ?? null,
		event_type: `${webhook_type}.${webhook_code}`
	};

	try {
		// ── Phase 1: read-only resolve (tenant-from-Item + idempotency pre-check) ───────────
		const { data: resolveData, error: resolveErr } = await pfin().rpc('fn_plaid_webhook_resolve', {
			p_event: pEvent
		});
		if (resolveErr) throw new Error('resolve_failed');
		const r = (Array.isArray(resolveData) ? resolveData[0] : resolveData) as ResolveRow | undefined;
		if (!r) throw new Error('resolve_empty');

		// Verified webhook for an unknown/foreign/removed Item → ack-and-drop (no writes). 200 so
		// Plaid does not retry forever for an Item we will never have (M4 reject = no tenant write).
		if (!r.resolved) {
			// MOD 2 (Sec): a VALID-SIGNATURE webhook for an unknown/foreign Item can signal an
			// ORPHANED LIVE Plaid Item (deleted locally but never revoked at Plaid) — security-
			// operationally relevant, so the ack-drop must be detectable. item_id is an opaque Plaid
			// identifier for an unlinked item (non-secret; no tenant/PII → keeps M8). No writes.
			console.warn(
				`[plaid-webhook] ack-drop: valid-signature webhook for unknown/foreign Item id=${item_id} — possible orphaned live Plaid Item or stale local removal`
			);
			return json({ received: true }, { status: 200 });
		}
		// Confirmed duplicate — a prior delivery already COMMITTED the gate (⟺ fully processed).
		if (r.already_processed) {
			return json({ received: true }, { status: 200 });
		}

		// ── AC5: on a fresh transactions event, dispatch the external worker sync BEFORE commit ──
		if (r.should_trigger_sync) {
			const kick = await triggerSourceSync(String(r.users_id), String(r.source_id));
			if (!kick.ok) {
				// C-X1: sync did not confirm → partial → 5xx so Plaid retries (gate not yet claimed;
				// the retry re-drives the idempotent sync). NEVER 200 without the sync dispatched.
				console.error(`[plaid-webhook] 5xx sync did not confirm (source_id=${r.source_id})`);
				return json({ error: 'sync_unconfirmed' }, { status: 502 });
			}
			pEvent.sync_outcome = { ok: true };
		}

		// ── Phase 2: atomic commit — state flip (only-on-change) + gate/audit row at COMPLETION ──
		const { error: commitErr } = await pfin().rpc('fn_plaid_webhook_commit', { p_event: pEvent });
		if (commitErr) throw new Error('commit_failed');

		return json({ received: true }, { status: 200 });
	} catch (err) {
		// C-X1 / C6-5 / M8: any partial failure → 5xx (Plaid retries; the two-phase ordering makes
		// the retry safe). Never leak internals.
		console.error(`[plaid-webhook] 500 apply failed (${err instanceof Error ? err.message : 'error'})`);
		return json({ error: 'internal_error' }, { status: 500 });
	}
};
