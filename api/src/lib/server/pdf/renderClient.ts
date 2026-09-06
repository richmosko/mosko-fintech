// renderClient.ts — SERVER-ONLY PDF-render worker transport (SELF-349 / A5).
//
// SCOPE: the api/src → PDF-render worker (workers/pdf-render/, SELF-348 / A4) INTERNAL
// boundary. Mirrors plaid/admissionClient.ts's shape deliberately (env config + fetch
// transport + typed response schema + redaction discipline) — same problem, same house
// answer, not re-derived from scratch.
//
// DIRECTION — RULED at R2 (C) (docs/records/v15-preflight/sitting-log.md § R2): the APP
// composes the report under the caller's OWN identity, renders it through the SAME
// Svelte template the in-app view uses (escaping every free-text field there — R2
// consequences, proof leg at P6), and PUSHES the FINISHED HTML to the worker; the worker
// runs it through headless Chrome and returns PDF bytes. This module is that push. There
// is NO `/internal/pdf-render` app route — that shape (ARCH §3.2 as originally written,
// worker mints a JWT and pulls rendered HTML from the app) is RETIRED under R2 (C); this
// module is the inverse of it.
//
// CALLER CONTRACT (both P6 and A7 import this — one worker-call implementation, not two):
// `usersId` is a REQUIRED argument the CALLER derives — from the live session
// (`locals.safeGetSession()`) on P6's on-demand path, or from the impersonated tenant
// binding on A7's cron path — mirroring admissionClient.ts's `ownerUserId` argument
// convention (SC3-C1): this module never reads a session itself and never trusts a body
// value for it. `html` must already be the FULLY RENDERED, FULLY ESCAPED document — this
// module constructs no markup and interpolates nothing into it (AC #0/#5's negative
// assertion on the WORKER's side has its app-side mirror here: this file has no template
// either).
//
// AUTH (SD-20 / RT-21, re-derived under R2 (C) — see rederived-acs.md § SELF-349 AC 1-8
// for the full re-derivation; letters below are the CANONICAL RT-21 (a)-(g) labels, kept
// so the battery keeps pointing at the catalog, never renumbered):
//   (a) tier restriction -> key restriction. There is no Supabase-tier JWT on this path at
//       all (this module never touches a Supabase session token) — what survives is (b).
//   (b) DEDICATED SIGNING KEY. HS256, PDF_WORKER_SIGNING_KEY (SD-20) as the ONLY key —
//       never the Supabase JWT secret, never derived from a user's session token.
//   (c) 60-SECOND FRESHNESS WINDOW on `iat` (NOT `exp` — a freshness window asserts when
//       the token was MINTED, and pinning `exp` instead would let a token minted long ago
//       with a generous expiry pass). Minted here (this module sets `iat` only, via
//       `setIssuedAt()`); the 60-second WINDOW is checked and enforced ENTIRELY worker-side
//       (workers/pdf-render/src/auth.js, FRESHNESS_WINDOW_SECONDS) — this module holds no
//       numeral for it and has nothing that could diverge from the worker's, because
//       nothing here reads one (Sec F-4).
//   (d) NONCE REPLAY PROTECTION. A fresh `randomUUID()` (node:crypto) per call — this module never
//       reuses a nonce across calls, and never accepts one as an argument (an argument
//       would be a second, caller-controlled path to a forged single-use guarantee).
//       ⚠ The nonce STORE lives in the WORKER (per-container, in-memory) — RESTART BOUND,
//       stated at the worker (auth.js), not re-stated here.
//   (e) NO service_role ESCALATION. STRUCTURAL under R2 (C): the worker holds no Supabase
//       credential of any kind (workers/pdf-render/.env.example carries exactly ONE
//       variable, PDF_WORKER_SIGNING_KEY; workers/pdf-render/Dockerfile installs no
//       Postgres client — RT-22 + the RT-22-manifest fence audit both on every PR). Cited
//       from A4's fence, not re-implemented or re-asserted here — there is nothing on
//       THIS side of the boundary that could escalate to begin with (this module makes
//       ONE outbound `fetch()` and holds no DB credential of its own).
//   (f) DEDICATED ENDPOINT. The referent MOVED to the worker's own render endpoint
//       (RENDER_PATH below) — verification logic lives there, not on an app route (there
//       is none; see DIRECTION above).
//   (g) REJECTED PAYLOADS DROPPED WITH A DETECTION SIGNAL. This is the WORKER'S obligation
//       (a rejection happens on ITS verification, not this caller's) — see
//       workers/pdf-render/src/auth.js for the ADR-050 Decision 4 bounded-counter
//       implementation (feature/self-348, merged to `main` at `bde35a7`).
//       This module's app-side conduct on a rejection is REDACTION ONLY, and is NOT part
//       of (g)'s discharge: a non-2xx response is logged as a STATUS ONLY
//       (`[pdf-render] worker returned <status>`), never the body, the token, or the
//       signing key — see REDACTION below. Per ADR-050 Decision 6's 2026-09-05 annotation
//       (Sec R-6, E28), an app-side rejection signal measures a DIFFERENT POPULATION than
//       (g) and is not a substitute for it; (g) is discharged wholly at the worker.
//   Labelled ADDITIONS (Sec F-3; kept as SUCH, not folded into the canonical letters):
//     tenant-claim PRESENCE  — `users_id` is a REQUIRED claim (never omitted); this is
//       presence, not trust — see the ⟨OPEN⟩ note below for what the worker does with it
//       (nothing, past verification).
//     AUDIENCE / ISSUER — NOT implemented. Recorded as a considered-and-declined addition,
//       not a silent gap: under R2 (C) there is exactly ONE legitimate caller (this
//       module) and exactly ONE legitimate verifier (the worker's render endpoint) on a
//       private container network with no other party ever presenting a
//       PDF_WORKER_SIGNING_KEY-signed token — an `aud`/`iss` claim would assert a
//       distinction that does not exist on this boundary today. Revisit if a second
//       caller or a second verifier is ever added.
//
// ⟨OPEN⟩ — ITEM 6, `users_id` CLAIM vs AN OPAQUE CORRELATION ID — RULED: ship the
// `users_id`-carrying claim AS RATIFIED, no SD-20/RT-21 edit (Sec, SELF-349 review). SD-20
// is ratified and already written for it, and this module keeps it unchanged. The tension
// this paragraph records for institutional memory, not as an open question: R2 (C) states
// the worker holds "no tenant or money knowledge", and a `users_id` claim gives it one bit
// of tenant knowledge it never uses (verified: workers/pdf-render/src/auth.js reads the
// claim only to confirm PRESENCE — `typeof decoded.users_id !== 'string'` — never its
// VALUE, past that check). The grounds, in the order they carried the ruling. (1) The
// security delta today is ZERO AND IS FENCED, not merely unused: the worker holds no DB
// reach and no Supabase credential of any kind (RT-22 + the RT-22-manifest fence, both
// run-always in CI), so it cannot act on the claim even if a later edit read its value.
// (2) The residual is PROSPECTIVE and has a NAMED SHAPE: a `users_id` claim is the
// affordance that would make a tenant-keyed render cache inside the worker easy to write,
// which is an RT-10 violation; an opaque per-render id would foreclose that structurally
// rather than by convention. Note the opaque-id shape is a DELETION, not a substitution —
// the `nonce` already is a per-render opaque UUID, so correlation can live app-side against
// it without the worker holding any tenant knowledge at all. (3) COST: the swap touches
// five artifacts, two of them already merged (auth.js and its battery), and would land a
// claim-set change mid-rewrite of RT-21. REVISIT TRIGGER — capability, not churn: if the
// worker ever gains outbound reach, a persistence surface, or any per-tenant keying, the
// swap becomes the right shape and should be booked as its own change to SD-20 + the
// worker.
// ⚠ A prior draft of this paragraph also argued the claim's presence is useful
// FORENSICALLY, on the premise that a worker-side rejection log could NAME the claim's
// value. That premise is FALSE, measured: `_rejected()` (workers/pdf-render/src/auth.js,
// ADR-050 Decision 4) logs a fixed, bounded REASON CODE only — it never reads or logs
// `users_id`'s value on any path. That argument is dropped, not carried forward.
//
// RT-25 (as-of-date parameter-bypass) — DOES NOT APPLY TO THIS BOUNDARY, stated rather
// than silently assumed: `html` is ALREADY RENDERED before it reaches this module — no
// `as_of` / `data_as_of` parameter of any kind crosses this call. Whatever as-of the
// report used was resolved and baked into the HTML upstream (P6's own composition step),
// under that surface's own RT-25 discipline if it has one; this module has no as-of
// parameter to bypass because it has no as-of parameter at all.
//
// REDACTION (mirrors admissionClient.ts's C6-5 discipline): NEVER log the signing key,
// the minted token, or the HTML body (a report's rendered content is exactly the
// financial data this whole system exists to protect). Operational logs carry the
// worker's HTTP status ONLY.

import { env } from '$env/dynamic/private';
import { SignJWT } from 'jose';
import { randomUUID } from 'node:crypto';

const AUTH_HEADER = 'authorization';
const RENDER_PATH = '/render';
// Coolify internal service name — DevOps's compose manifest (SELF-348 AC #4c) is the
// canonical source once it lands; overridable via PDF_RENDER_WORKER_URL for local/CI
// targeting, same convention as admissionClient.ts's WORKER_ADMISSION_URL.
const DEFAULT_BASE_URL = 'http://pdf-render:8080';
// Longer than admissionClient's 10s — this call does a real headless-Chrome render on
// the far side, not a lightweight admission RPC.
const TIMEOUT_MS = 30_000;
// Sec F-8: under R2 (C) this single shared secret is the ENTIRE admission perimeter for
// "make headless Chrome render arbitrary bytes" — there is no second factor. A floor, not
// a real entropy check (length is not entropy), but cheap and catches a placeholder/typo
// value before it ever reaches a signing call.
const MIN_SIGNING_KEY_LENGTH = 32;

// ── Env config (memoized, fail-loud at first use — mirrors admissionClient.ts) ─────────
let cfg: { baseUrl: string; secret: Uint8Array } | null = null;
function renderConfig(): { baseUrl: string; secret: Uint8Array } {
	if (cfg) return cfg;
	const secret = env.PDF_WORKER_SIGNING_KEY;
	if (!secret) {
		throw new Error(
			'Missing PDF_WORKER_SIGNING_KEY — set it in the container runtime env (production_only per secrets-manifest.yml; SD-20).'
		);
	}
	if (secret.length < MIN_SIGNING_KEY_LENGTH) {
		// Sec F-8: fail loud on an obviously-too-short secret rather than sign with one —
		// this key is the whole perimeter (see the constant's own comment above).
		throw new Error(
			`PDF_WORKER_SIGNING_KEY is shorter than ${MIN_SIGNING_KEY_LENGTH} characters — refusing to sign with a secret this short (SD-20; it is the entire admission perimeter under R2 (C)).`
		);
	}
	const baseUrl = (env.PDF_RENDER_WORKER_URL || DEFAULT_BASE_URL).replace(/\/+$/, '');
	cfg = { baseUrl, secret: new TextEncoder().encode(secret) };
	return cfg;
}

/** Test-only: clears the memoized env config so a spec can vary process.env per case. */
export function __resetConfigForTests(): void {
	cfg = null;
}

/**
 * Mint the short-lived render-auth token (RT-21 (b)/(c)/(d)). Exported separately from
 * `renderReportHtml` so the RT-21 battery can assert on the MINTED TOKEN'S SHAPE directly
 * (claims present, `iat` fresh, a fresh nonce per call) without needing a live worker.
 */
export async function mintRenderToken(usersId: string): Promise<string> {
	const { secret } = renderConfig();
	return new SignJWT({ users_id: usersId, nonce: randomUUID() })
		.setProtectedHeader({ alg: 'HS256' })
		.setIssuedAt()
		.sign(secret);
}

export type RenderOutcome = { ok: true; pdfBytes: Uint8Array } | { ok: false; status: number };

/**
 * Render `html` (a COMPLETE, already-escaped document — see module header) via the
 * PDF-render worker under `usersId`'s short-lived token. `usersId` is ALWAYS the
 * caller-derived identity (SC3-C1) — this function never resolves one itself.
 *
 * Returns `{ ok:false, status }` on ANY non-200 (auth rejection, transport failure
 * mapped to 502, malformed/oversize payload) rather than throwing — mirrors
 * admissionClient.ts's `LegOutcome<T>` discriminated-result convention so callers
 * (P6's route, A7's cron path) branch on the SAME shape every other worker-call surface
 * in this tree already uses.
 */
export async function renderReportHtml(usersId: string, html: string): Promise<RenderOutcome> {
	const { baseUrl } = renderConfig();
	const token = await mintRenderToken(usersId);

	// Sec F-1: the body read (`res.arrayBuffer()` — the whole PDF download) MUST stay
	// inside this same try/finally, guarded by the SAME abort timer, exactly like
	// admissionClient.ts's `callWorker()` does for its own body read. `fetch()` resolves
	// once RESPONSE HEADERS arrive — a version that clears the timer and exits the try
	// right after `fetch()` returns leaves the body download unbounded (a worker that
	// dribbles the body holds this call open indefinitely) and lets a mid-body network
	// error THROW OUT of this function, contradicting its own discriminated-result
	// contract below.
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
	try {
		const res = await fetch(`${baseUrl}${RENDER_PATH}`, {
			method: 'POST',
			headers: {
				'content-type': 'text/html',
				[AUTH_HEADER]: `Bearer ${token}`
			},
			body: html,
			signal: controller.signal,
			// Sec N-2: a compromised/misconfigured worker could otherwise 307/308 this
			// POST (with the finished report HTML) to a redirect target, and a
			// subsequent 200 from THAT target would read as a successful render. The
			// worker never legitimately redirects; refuse the class outright rather
			// than following it.
			redirect: 'error'
		});

		if (res.status !== 200) {
			// Redaction only — NOT part of (g)'s discharge (see header): status ONLY, never the body.
			console.error(`[pdf-render] worker returned ${res.status}`);
			return { ok: false, status: res.status };
		}

		const pdfBytes = new Uint8Array(await res.arrayBuffer());
		return { ok: true, pdfBytes };
	} catch {
		// Network error / DNS / connection refused / timeout-abort / a mid-body read
		// failure / a refused redirect → worker unreachable or misbehaving. Never logs
		// `html` or `token` — see REDACTION above.
		console.error('[pdf-render] worker unreachable (transport failure)');
		return { ok: false, status: 502 };
	} finally {
		clearTimeout(timer);
	}
}
