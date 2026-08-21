// admissionServer.ts — SELF-212 Option C inbound admission endpoint (the app→worker relay).
//
// A THIN authenticated HTTP wrapper over (leg-1) mintLinkToken + (leg-2) PlaidAdapter.connect()
// — it does NOT re-implement the admission; it authenticates the internal caller, validates the
// inbound body, and delegates. Every security property is enforced by a dedicated, unit-tested
// helper: CA-1 private-only boot (admissionGuard) / CA-6 constant-time secret (sharedSecret) /
// (u) atomic exchange + C6-4 recovery (PlaidAdapter.connect).
//
// SERVER CHOICE: Node's built-in `node:http`. Rationale (flagged for Sec/team-lead): the worker
// stack today is pure Node/TS with only `plaid` / `postgres` / `zod` as deps and NO web
// framework. This is a two-route internal RPC surface, not a web app — Express/Fastify would add
// a dependency + transitive supply-chain surface for routing we can hand-write in a few lines.
// The lightest thing that fits the existing stack + Dockerfile (no new dep, no build change) is
// the stdlib http server. If the surface later grows, revisit.
//
// TENANT BINDING (C6-3): `ownerUserId` is accepted ONLY from the request body of the
// shared-secret-authed internal call (api/src derives it from the validated session). The worker
// exposes NO browser-reachable field, and is unreachable by the browser by construction (CA-1
// private bind). The in-code binding is the SOLE primary tenant-correctness control per ADR-027
// (t); fn_account_matched_linked_source (Decision-3 #6) is the downstream backstop, not a
// substitute.
//
// REDACTION (C6-5): request/response bodies are NEVER logged; error responses to api/src carry a
// stable machine code only — no token fragments, no secret, no stack, no tenant-PII. The
// server-side log lines carry only route + a coarse outcome (+ scrubbed adapter message).

import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { z } from 'zod';
import type {
	ProviderAccountRef,
	ReauthHandoff,
	ReauthInput,
	ReauthResult
} from '../adapters/ProviderAdapter.js';
import { PublicTokenInvalidError } from '../adapters/PlaidAdapter.js';
import { SetupTokenInvalidError } from '../adapters/SimpleFINAdapter.js';
import { ADMISSION_SECRET_HEADER, verifySharedSecret } from './sharedSecret.js';
import type { PublicJwk } from './webhookVerificationKey.js';
import type { SyncSourceInput, SyncSourceResult } from './triggerSync.js';
import type { ManualSyncInput, ManualSyncResult } from './manualSync.js';
import type { AssetResolveInput, AssetResolveResult } from './assetResolve.js';

/** Max inbound body. A link_token request / public_token handoff is tiny; anything larger is
 *  abuse → reject (fail-closed) rather than buffer. */
const MAX_BODY_BYTES = 64 * 1024;

// ── Inbound body schemas — Zod `.strict()` at the boundary (mass-assignment prevention,
//    Lock 14 mod #1). `ownerUserId` is a uuid; connect() re-validates independently. ──────────
const linkTokenBodySchema = z.object({ ownerUserId: z.string().uuid() }).strict();

const exchangeBodySchema = z
	.object({
		public_token: z.string().min(1),
		ownerUserId: z.string().uuid(),
		institutionId: z.string().min(1).optional(),
		institutionName: z.string().min(1).optional()
	})
	.strict();

export interface ExchangeInput {
	publicToken: string;
	ownerUserId: string;
	institutionId?: string;
	institutionName?: string;
}

// ── SimpleFIN claim leg (leg-S) — ONE leg, no link-token analogue, no /item/remove recovery.
//    A new ROUTE on the RT-27 admission surface (NOT a new §10 instance): same private-bind, same
//    shared-secret gate, same session-derived tenant. `ownerUserId` is a uuid; connect()
//    re-validates independently. `.strict()` — mass-assignment fence (Lock 14 mod #1). The token
//    field is `setup_token` (snake) to mirror the shipped Plaid `public_token` convention. ──────
const simplefinClaimBodySchema = z
	.object({
		setup_token: z.string().min(1),
		ownerUserId: z.string().uuid(),
		institutionName: z.string().min(1).optional()
	})
	.strict();

export interface SimplefinClaimInput {
	setupToken: string;
	ownerUserId: string;
	institutionName?: string;
}

// ── Re-auth legs (SELF-207 §2.4.4.b) — provider-agnostic routes on the SAME RT-27 admission
//    surface (same private-bind, same shared-secret gate, same session-derived tenant). The
//    server delegates to a provider dispatch wired in serve-admission.ts. `.strict()` bodies
//    (mass-assignment fence). `linked_source_id` is a digit-string (bigint); `ownerUserId` is a
//    uuid the adapter re-validates. NEVER carries a credential in the START body; COMPLETE
//    carries only the SimpleFIN fresh setup_token (Plaid update mode has no token). ────────────
const reauthStartBodySchema = z
	.object({
		provider: z.enum(['plaid', 'simplefin']),
		linked_source_id: z.string().regex(/^\d+$/),
		ownerUserId: z.string().uuid()
	})
	.strict();

const reauthCompleteBodySchema = z
	.object({
		provider: z.enum(['plaid', 'simplefin']),
		linked_source_id: z.string().regex(/^\d+$/),
		ownerUserId: z.string().uuid(),
		// Plaid: { kind:'link_update_success' } (no token). SimpleFIN: the fresh Bridge token.
		input: z.discriminatedUnion('kind', [
			z.object({ kind: z.literal('link_update_success') }).strict(),
			z.object({ kind: z.literal('setup_token'), setup_token: z.string().min(1) }).strict()
		])
	})
	.strict();

// ── SELF-206 Plaid-webhook support legs (Option 1) — NEW ROUTES on this SAME admission server
//    (same private-bind listener + same C6-6 constant-time shared-secret gate). Keeping them on
//    the existing server is load-bearing: a separate listener/port would be a NEW §10 instance.
//    On the existing server they are ROUTES on the RT-27 surface (Sec-verified; mirrors the
//    /admission/simplefin/claim + reauth-leg precedent). Both bodies `.strict()` (mass-assignment
//    fence, Lock 14 mod #1).
//  • webhook-verification-key: fetch the PUBLIC JWK by kid (credentialed Plaid call — the creds
//    that api/src does NOT hold). `kid` is the JWT header key id (opaque string).
//  • sync: AC5 on-demand incremental Plaid sync for a VERIFIED webhook. `ownerUserId` is the
//    tenant api/src resolved FROM the Plaid Item id (never browser-sourced); `linked_source_id` is
//    a digit-string (bigint). resolveCredential double-binds source+tenant downstream (fail-closed).
const webhookVerificationKeyBodySchema = z.object({ kid: z.string().min(1) }).strict();

const syncSourceBodySchema = z
	.object({
		ownerUserId: z.string().uuid(),
		linked_source_id: z.string().regex(/^\d+$/)
	})
	.strict();

// ── SELF-317 manual "Sync now" leg — a NEW dedicated route on this SAME admission server (NOT an
//    overload of /admission/sync, which carries the 045 webhook's C-X2 gate-at-completion contract).
//    Same private-bind listener + same C6-6 constant-time shared-secret gate → a route on the RT-27
//    surface (no new §10 instance). `ownerUserId` is the session-derived tenant api/src forwards
//    (C6-3; never browser-sourced); `source_id` (OPTIONAL — absent ⇒ sync-all) is a digit-string
//    bigint the worker intersects with the RLS-scoped enumerated set (Sec C2). `.strict()` —
//    mass-assignment fence (Lock 14 mod #1).
const manualSyncBodySchema = z
	.object({
		ownerUserId: z.string().uuid(),
		source_id: z.string().regex(/^\d+$/).optional()
	})
	.strict();

// ── SELF-325 asset-resolve leg — a NEW route on this SAME admission server (private-bind +
//    shared-secret gate + session-derived tenant, identical to every other leg here). NOT a new
//    §10 instance (Architect design temp/architect-purchase-path-addendum.md §2.1/§4): reuses the
//    existing withServiceRole() identity + the existing 020 grant, no new privileged surface.
//    NAMESPACE-POLLUTION boundary validation (addendum §2.3 — a design condition, not polish):
//    symbol/cusip constrained by pattern+length, asset_type restricted to 016's CHECK vocabulary
//    (the full 14-value enum — narrowing to a "market-priced" subset is a Frontend picker/UX
//    call, not a server-validation one), name length-bounded. At least one of symbol/cusip is
//    required — a blank/blank resolve has no identity to bind a purchase to. `.strict()` —
//    mass-assignment fence (Lock 14 mod #1).
const ASSET_TYPES = [
	'equity',
	'etf',
	'fund',
	'money_market',
	'bond',
	'future',
	'option',
	'crypto',
	'real_estate',
	'vehicle',
	'metal',
	'collectible',
	'currency',
	'private'
] as const;

const nullableTrimmed = (max: number) =>
	z.preprocess(
		(v) => (v === '' || v === undefined ? null : v),
		z.string().trim().max(max).nullable()
	);

const assetResolveBodySchema = z
	.object({
		ownerUserId: z.string().uuid(),
		symbol: z.preprocess(
			(v) => (v === '' || v === undefined ? null : v),
			z
				.string()
				.trim()
				.max(20)
				.regex(/^[A-Za-z0-9.\-]+$/, 'symbol must be alphanumeric (with . or -).')
				.nullable()
		),
		cusip: z.preprocess(
			(v) => (v === '' || v === undefined ? null : v),
			z
				.string()
				.trim()
				.length(9, 'cusip must be exactly 9 characters.')
				.regex(/^[A-Za-z0-9]{9}$/, 'cusip must be alphanumeric.')
				.nullable()
		),
		assetType: z.enum(ASSET_TYPES),
		name: nullableTrimmed(200),
		currency: z
			.string()
			.trim()
			.regex(/^[A-Za-z]{3}$/, 'currency must be a 3-letter ISO code.')
	})
	.strict()
	.refine((v) => v.symbol !== null || v.cusip !== null, {
		message: 'At least one of symbol or cusip is required.',
		path: ['symbol']
	});

export interface ReauthStartInput {
	provider: 'plaid' | 'simplefin';
	linkedSourceId: bigint;
	ownerUserId: string;
}

export interface ReauthCompleteInput {
	provider: 'plaid' | 'simplefin';
	linkedSourceId: bigint;
	ownerUserId: string;
	input: ReauthInput;
}

/** The account routing key api/src forwards to the browser. `account_id` is the stable
 *  provider account id (ProviderAccountRef.providerAccountId). */
export interface AdmissionAccountRef {
	account_id: string;
	name: string;
	type: string;
	subtype: string | null;
	currency: string;
}

/**
 * The admission server's collaborators, injected so the server unit-tests with NO Plaid client
 * and NO Postgres. The entrypoint (cli/serve-admission.ts) wires these to the real Plaid client
 * + PlaidAdapter.connect().
 */
export interface AdmissionServerDeps {
	/** The shared secret both legs authenticate against (constant-time). */
	readonly sharedSecret: string;
	/** Leg-1: mint a link_token for the session-derived tenant. */
	mintLinkToken(ownerUserId: string): Promise<{ link_token: string; expiration: string }>;
	/** Leg-2: drive the atomic exchange+vault+INSERT admission (PlaidAdapter.connect). */
	admit(input: ExchangeInput): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }>;
	/** Leg-S: drive the SimpleFIN claim+vault+INSERT admission (SimpleFINAdapter.connect). */
	admitSimplefin(input: SimplefinClaimInput): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }>;
	/** Re-auth Phase 1: dispatch to the provider's reauthStart (SELF-207). */
	reauthStart(input: ReauthStartInput): Promise<ReauthHandoff>;
	/** Re-auth Phase 2: dispatch to the provider's reauthComplete (SELF-207). */
	reauthComplete(input: ReauthCompleteInput): Promise<ReauthResult>;
	/** SELF-206: fetch the PUBLIC JWK by kid (credentialed Plaid call — worker-side only). */
	fetchWebhookVerificationKey(kid: string): Promise<PublicJwk>;
	/** SELF-206 AC5: on-demand incremental Plaid sync for a verified webhook (resolved tenant). */
	syncSource(input: SyncSourceInput): Promise<SyncSourceResult>;
	/** SELF-317: user-initiated "Sync now" — validates + debounces synchronously, returns per-source
	 *  dispositions, and runs the actual sync(s) fire-and-forget (A2). Resolves fast (before the 202). */
	manualSync(input: ManualSyncInput): Promise<ManualSyncResult>;
	/** SELF-325: resolve-or-mint a GLOBAL pfin.asset row for the manual purchase-path (thin wrapper
	 *  over resolveSecurityId — see assetResolve.ts). */
	resolveAsset(input: AssetResolveInput): Promise<AssetResolveResult>;
	/** Token-free diagnostic logger (never receives a body/secret/token). */
	logger?: (message: string) => void;
}

const OK = 200;
const ACCEPTED = 202;
const BAD_REQUEST = 400;
const UNAUTHORIZED = 401;
const NOT_FOUND = 404;
const METHOD_NOT_ALLOWED = 405;
const PAYLOAD_TOO_LARGE = 413;
const BAD_GATEWAY = 502;

function sendJson(res: ServerResponse, status: number, body: unknown): void {
	const payload = JSON.stringify(body);
	res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
	res.end(payload);
}

/** Generic error envelope — a stable machine `error` code ONLY (C6-5: no internal detail). */
function sendError(res: ServerResponse, status: number, code: string): void {
	sendJson(res, status, { error: code });
}

/** Read + size-cap the request body, then JSON.parse. Rejects (throws a tagged reason) on
 *  oversize or malformed JSON so the handler can map to a generic 4xx. */
async function readJsonBody(req: IncomingMessage): Promise<unknown> {
	return new Promise((resolve, reject) => {
		let size = 0;
		const chunks: Buffer[] = [];
		req.on('data', (chunk: Buffer) => {
			size += chunk.length;
			if (size > MAX_BODY_BYTES) {
				reject(new Error('BODY_TOO_LARGE'));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on('end', () => {
			if (chunks.length === 0) {
				resolve(undefined);
				return;
			}
			try {
				resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
			} catch {
				reject(new Error('BODY_NOT_JSON'));
			}
		});
		req.on('error', () => reject(new Error('BODY_READ_ERROR')));
	});
}

function toAdmissionAccounts(accounts: ProviderAccountRef[]): AdmissionAccountRef[] {
	return accounts.map((a) => ({
		account_id: a.providerAccountId,
		name: a.name,
		type: a.type,
		subtype: a.subtype,
		currency: a.currency
	}));
}

/**
 * Build (but do not start) the admission HTTP server. Call `.listen(port, host)` on the result.
 * Routes:
 *   GET  /healthz                → { status: 'ok' }           (UNAUTHENTICATED liveness; no secrets)
 *   POST /admission/link-token       → { link_token, expiration } (leg-1, shared-secret authed)
 *   POST /admission/exchange         → { sourceId, accounts }     (leg-2, shared-secret authed)
 *   POST /admission/simplefin/claim  → { sourceId, accounts }     (leg-S, shared-secret authed)
 *   POST /asset/resolve              → { assetId }                (SELF-325, shared-secret authed)
 * Every non-health route requires the constant-time shared-secret header; absent/mismatch → 401.
 */
/** N-1 (Sec SELF-212): explicit inbound timeouts — do NOT rely on Node defaults for a
 *  credential-admission server (Slowloris / hung-request hardening). Values are conservative
 *  for a two-route internal RPC over the private Docker network (fast local calls, tiny bodies):
 *    - headers must arrive within 5s (a stalled header stream is dropped),
 *    - the ENTIRE request (headers+body) must arrive within 15s.
 *  These bound REQUEST RECEIPT from the caller, not downstream Plaid handler time. Constraint:
 *  requestTimeout > headersTimeout (Node). */
const HEADERS_TIMEOUT_MS = 5_000;
const REQUEST_TIMEOUT_MS = 15_000;

export function createAdmissionServer(deps: AdmissionServerDeps): Server {
	const log = (m: string): void => deps.logger?.(m);

	const server = createServer((req, res) => {
		void handle(req, res).catch(() => {
			// Last-resort catch — never leak an internal error to the caller (C6-5).
			if (!res.headersSent) sendError(res, 502, 'internal_error');
			else res.end();
		});
	});
	server.headersTimeout = HEADERS_TIMEOUT_MS;
	server.requestTimeout = REQUEST_TIMEOUT_MS;
	return server;

	async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
		const method = req.method ?? 'GET';
		// Strip query string — no route consumes it, and we never want tenant ids in a query
		// (C6-5). Anything after '?' is discarded.
		const path = (req.url ?? '/').split('?')[0];

		// (0) Liveness — unauthenticated, reveals nothing (Coolify healthcheck).
		if (path === '/healthz') {
			if (method !== 'GET') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return sendJson(res, OK, { status: 'ok' });
		}

		// (1) Auth gate (BOTH legs, C6-6): constant-time shared-secret compare, fail-closed.
		const presented = req.headers[ADMISSION_SECRET_HEADER];
		const headerValue = Array.isArray(presented) ? presented[0] : presented;
		if (!verifySharedSecret(headerValue, deps.sharedSecret)) {
			log(`admission: 401 unauthorized (${method} ${path})`);
			return sendError(res, UNAUTHORIZED, 'unauthorized');
		}

		// (2) Route.
		if (path === '/admission/link-token') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleLinkToken(req, res);
		}
		if (path === '/admission/exchange') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleExchange(req, res);
		}
		if (path === '/admission/simplefin/claim') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleSimplefinClaim(req, res);
		}
		if (path === '/admission/reauth/start') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleReauthStart(req, res);
		}
		if (path === '/admission/reauth/complete') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleReauthComplete(req, res);
		}
		if (path === '/admission/webhook-verification-key') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleWebhookVerificationKey(req, res);
		}
		if (path === '/admission/sync') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleSyncSource(req, res);
		}
		if (path === '/admission/manual-sync') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleManualSync(req, res);
		}
		if (path === '/asset/resolve') {
			if (method !== 'POST') return sendError(res, METHOD_NOT_ALLOWED, 'method_not_allowed');
			return handleAssetResolve(req, res);
		}
		return sendError(res, NOT_FOUND, 'not_found');
	}

	async function handleLinkToken(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = linkTokenBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		try {
			const result = await deps.mintLinkToken(parsed.data.ownerUserId);
			log('admission: 200 link-token minted');
			return sendJson(res, OK, { link_token: result.link_token, expiration: result.expiration });
		} catch (err) {
			// scrubbedPlaidError already stripped secrets; keep it server-side only (C6-5).
			log(`admission: 502 link-token mint failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'link_token_failed');
		}
	}

	async function handleExchange(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = exchangeBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		const input: ExchangeInput = {
			publicToken: parsed.data.public_token,
			ownerUserId: parsed.data.ownerUserId,
			...(parsed.data.institutionId ? { institutionId: parsed.data.institutionId } : {}),
			...(parsed.data.institutionName ? { institutionName: parsed.data.institutionName } : {})
		};

		try {
			const { sourceId, accounts } = await deps.admit(input);
			log(`admission: 200 admitted source_id=${sourceId} (accounts=${accounts.length})`);
			// bigint → string (JSON has no bigint). Never echo the public_token (C6-5).
			return sendJson(res, OK, { sourceId: String(sourceId), accounts: toAdmissionAccounts(accounts) });
		} catch (err) {
			// Item-2: ONLY a recognized public_token-invalidity at the exchange leg is client-
			// correctable → worker-400 `public_token_invalid` (one uniform code; api/src maps it to
			// browser-400 "re-run Link"). EVERY other failure — DB / vault / network / unknown /
			// post-exchange — stays 5xx (guardrail #2, fail-safe): a server failure must never be
			// dressed up as client-correctable. Envelope stays scrubbed (guardrail #3).
			if (err instanceof PublicTokenInvalidError) {
				log('admission: 400 public_token_invalid (client-correctable)');
				return sendError(res, BAD_REQUEST, 'public_token_invalid');
			}
			// connect() already scrubbed Plaid errors + ran the C6-4 /item/remove recovery.
			log(`admission: 502 admit failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'admission_failed');
		}
	}

	// leg-S — SimpleFIN setup-token claim + admit. Mirrors handleExchange exactly, minus the
	// leg-1 mint (SimpleFIN has none) and minus /item/remove recovery (a read-only Access URL
	// needs none). The ONE divergence: the client-correctable typed error is
	// SetupTokenInvalidError → worker-400 `setup_token_invalid`.
	async function handleSimplefinClaim(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = simplefinClaimBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		const input: SimplefinClaimInput = {
			setupToken: parsed.data.setup_token,
			ownerUserId: parsed.data.ownerUserId,
			...(parsed.data.institutionName ? { institutionName: parsed.data.institutionName } : {})
		};

		try {
			const { sourceId, accounts } = await deps.admitSimplefin(input);
			log(`admission: 200 simplefin admitted source_id=${sourceId} (accounts=${accounts.length})`);
			// bigint → string (JSON has no bigint). Never echo the setup token / Access URL (C6-5).
			return sendJson(res, OK, { sourceId: String(sourceId), accounts: toAdmissionAccounts(accounts) });
		} catch (err) {
			// ONLY a recognized setup-token-invalidity is client-correctable → worker-400
			// `setup_token_invalid` (one uniform code; api/src maps it to browser-400 "obtain a fresh
			// setup token"). EVERY other failure — DB / vault / network / a 5xx Bridge error / unknown
			// — stays 5xx (guardrail #2, fail-safe). Envelope stays scrubbed (guardrail #3).
			if (err instanceof SetupTokenInvalidError) {
				log('admission: 400 setup_token_invalid (client-correctable)');
				return sendError(res, BAD_REQUEST, 'setup_token_invalid');
			}
			// connect() already scrubbed every SimpleFIN/DB error (whole error object discarded).
			log(`admission: 502 simplefin admit failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'admission_failed');
		}
	}

	// reauth Phase 1 — provider-agnostic. Delegates to deps.reauthStart (dispatched by provider
	// in serve-admission.ts). Returns the ReauthHandoff verbatim (Plaid link_token / recollect
	// signal — no credential). ownerUserId is session-derived (C6-3), re-validated by the adapter.
	async function handleReauthStart(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = reauthStartBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		try {
			const handoff = await deps.reauthStart({
				provider: parsed.data.provider,
				linkedSourceId: BigInt(parsed.data.linked_source_id),
				ownerUserId: parsed.data.ownerUserId
			});
			log(`admission: 200 reauth-start (${parsed.data.provider})`);
			return sendJson(res, OK, handoff);
		} catch (err) {
			log(`admission: 502 reauth-start failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'reauth_failed');
		}
	}

	// reauth Phase 2 — provider-agnostic. Plaid: no token (link update-mode success). SimpleFIN:
	// the fresh setup token (the ②-gated rotation currently throws → 5xx until wired). A recognized
	// SimpleFIN setup-token-invalidity is client-correctable → 400; every other failure stays 5xx.
	async function handleReauthComplete(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = reauthCompleteBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		// Map the wire input (snake `setup_token`) → the adapter ReauthInput (camel `setupToken`).
		const wire = parsed.data.input;
		const reauthInput: ReauthInput =
			wire.kind === 'setup_token'
				? { kind: 'setup_token', setupToken: wire.setup_token }
				: { kind: 'link_update_success' };

		try {
			const result = await deps.reauthComplete({
				provider: parsed.data.provider,
				linkedSourceId: BigInt(parsed.data.linked_source_id),
				ownerUserId: parsed.data.ownerUserId,
				input: reauthInput
			});
			log(`admission: 200 reauth-complete (${parsed.data.provider}, rotated=${result.rotated})`);
			return sendJson(res, OK, result);
		} catch (err) {
			if (err instanceof SetupTokenInvalidError) {
				log('admission: 400 setup_token_invalid (reauth; client-correctable)');
				return sendError(res, BAD_REQUEST, 'setup_token_invalid');
			}
			log(`admission: 502 reauth-complete failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'reauth_failed');
		}
	}

	// SELF-206 — fetch the PUBLIC JWK for a kid (credentialed Plaid call). Returns { key } (public
	// EC point + routing metadata; no secret). On any Plaid/transport failure → generic 502 so
	// api/src fails the webhook CLOSED (never 200s an unverifiable webhook). C6-5: route+status only.
	async function handleWebhookVerificationKey(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = webhookVerificationKeyBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		try {
			const key = await deps.fetchWebhookVerificationKey(parsed.data.kid);
			log('admission: 200 webhook-verification-key');
			return sendJson(res, OK, { key });
		} catch (err) {
			log(`admission: 502 webhook-verification-key failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'verification_key_failed');
		}
	}

	// SELF-206 AC5 — on-demand incremental Plaid sync for a VERIFIED webhook. ownerUserId is the
	// tenant api/src resolved from the Item id (C6-3: never browser-sourced — the webhook has no
	// session). resolveCredential double-binds source+tenant downstream (fail-closed). Returns
	// non-sensitive landed counts. On failure → 502 (api/src logs + relies on the next poll as the
	// self-healing backstop; it does NOT un-ack the already-committed webhook). C6-5: no token/body.
	async function handleSyncSource(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = syncSourceBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		try {
			const result = await deps.syncSource({
				ownerUserId: parsed.data.ownerUserId,
				linkedSourceId: BigInt(parsed.data.linked_source_id)
			});
			log(`admission: 200 sync source_id=${result.sourceId} (inserted=${result.inserted})`);
			return sendJson(res, OK, { ok: true, ...result });
		} catch (err) {
			log(`admission: 502 sync failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'sync_failed');
		}
	}

	// SELF-317 — user-initiated "Sync now". ownerUserId is the session-derived tenant api/src forwards
	// (C6-3; never browser-sourced). deps.manualSync validates + debounces SYNCHRONOUSLY and runs the
	// actual sync(s) fire-and-forget (A2) → this handler resolves FAST and returns 202 + per-source
	// dispositions (triggered|debounced). resolveCredential double-binds source+tenant downstream, and
	// the enumeration is RLS-scoped (Sec C1/C2) — a foreign source_id is a no-op, never a cross-tenant
	// fetch. C4: route + status + a coarse source count only — never body/credential/token.
	async function handleManualSync(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = manualSyncBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		try {
			const result = await deps.manualSync({
				ownerUserId: parsed.data.ownerUserId,
				...(parsed.data.source_id ? { sourceId: parsed.data.source_id } : {})
			});
			log(`admission: 202 manual-sync accepted (sources=${result.sources.length})`);
			return sendJson(res, ACCEPTED, { accepted: true, sources: result.sources });
		} catch (err) {
			// Phase-1 (enumeration/debounce) failure only — the background sync(s) never reject here
			// (A2 fire-and-forget is guarded worker-side). Envelope stays scrubbed (C6-5/C4).
			log(`admission: 502 manual-sync failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'manual_sync_failed');
		}
	}

	// SELF-325 — resolve-or-mint a GLOBAL pfin.asset row for the manual purchase-path (Case 3 /
	// public tickers). A thin wrapper (deps.resolveAsset → resolveSecurityId; see assetResolve.ts
	// module header) — this handler re-implements nothing. ownerUserId is session-derived (C6-3;
	// never browser-sourced) and doubles as the audit subject + future rate-limit key (no
	// rate-limit control exists yet — flagged to Sec, not built here). Every failure stays 5xx: a
	// resolve/mint failure here is a DB/infra condition, never a client-correctable input (the
	// Zod schema already rejected malformed identity inputs before this runs). C6-5: route+status
	// only — never the body.
	async function handleAssetResolve(req: IncomingMessage, res: ServerResponse): Promise<void> {
		let body: unknown;
		try {
			body = await readJsonBody(req);
		} catch (err) {
			const reason = err instanceof Error ? err.message : '';
			return sendError(res, reason === 'BODY_TOO_LARGE' ? PAYLOAD_TOO_LARGE : BAD_REQUEST, 'invalid_request');
		}
		const parsed = assetResolveBodySchema.safeParse(body);
		if (!parsed.success) return sendError(res, BAD_REQUEST, 'invalid_request');

		try {
			const result = await deps.resolveAsset({
				ownerUserId: parsed.data.ownerUserId,
				symbol: parsed.data.symbol,
				cusip: parsed.data.cusip,
				assetType: parsed.data.assetType,
				name: parsed.data.name,
				currency: parsed.data.currency
			});
			log(`admission: 200 asset-resolve asset_id=${result.assetId ?? 'null'}`);
			return sendJson(res, OK, { assetId: result.assetId });
		} catch (err) {
			log(`admission: 502 asset-resolve failed (${err instanceof Error ? err.message : 'error'})`);
			return sendError(res, BAD_GATEWAY, 'asset_resolve_failed');
		}
	}
}
