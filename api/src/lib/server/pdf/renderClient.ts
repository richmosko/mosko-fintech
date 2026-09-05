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
//       with a generous expiry pass). Minted here, checked worker-side
//       (workers/pdf-render/src/auth.js, FRESHNESS_WINDOW_SECONDS = 60 — SAME value; if
//       these ever diverge the freshness check on one side is arguing with the other).
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
//       workers/pdf-render/src/auth.js for the ADR-050 Decision 4 proposal + minimal
//       bounded-counter implementation (a follow-up commit on feature/self-348, not this
//       branch, since that file doesn't exist on `main` yet — A4 hasn't merged). This
//       module's OWN half of (g): a non-2xx response is logged as a STATUS ONLY
//       (`[pdf-render] worker returned <status>`), never the body, the token, or the
//       signing key — see REDACTION below.
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
// ⟨OPEN⟩ — ITEM 6, `users_id` CLAIM vs AN OPAQUE CORRELATION ID (recorded, NOT resolved
// here — routed to Sec per team-lead's instruction, this paragraph IS the proposal, not
// a decision). SD-20 is ratified and already written for a `users_id`-carrying claim, and
// this module keeps it AS RATIFIED. The tension worth Sec's read: R2 (C) states the
// worker holds "no tenant or money knowledge", and a `users_id` claim gives it one bit of
// tenant knowledge it never uses (verified: workers/pdf-render/src/auth.js reads the claim
// only to confirm PRESENCE — `typeof decoded.users_id !== 'string'` — never its VALUE,
// past that check). Two ways to read that: (i) it's already inert in practice, so leaving
// it is the lower-churn choice — SD-20 is ratified, a change is a one-way door on a
// Sec-owned artifact, and "the worker doesn't use it" is not the same claim as "the worker
// couldn't be made to use it by a later, less careful edit" — an opaque correlation id
// (e.g. a per-render UUID minted here, carrying no tenant semantics at all) would remove
// that capability structurally rather than by convention, closing the gap ADR-011
// Decision 1's own reasoning about capability-vs-discipline generally argues for; OR
// (ii) `users_id`'s presence is useful FORENSICALLY (a worker-side rejection log line
// naming the claim, even unverified-and-untrusted per RT-21 letter (g)'s own caveat, is
// more actionable during an incident than an opaque id with no meaning outside this
// module). This module does not adjudicate between (i) and (ii) — it ships (i)'s
// as-ratified shape and states the question so Sec can answer it once rather than have it
// re-litigated per surface.
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
// MUST match workers/pdf-render/src/auth.js's FRESHNESS_WINDOW_SECONDS exactly (RT-21
// letter (c)) — minted here, checked there. A mismatch would not fail loudly; it would
// silently widen or narrow the window on whichever side is stale.
const FRESHNESS_WINDOW_SECONDS = 60;

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

	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
	let res: Response;
	try {
		res = await fetch(`${baseUrl}${RENDER_PATH}`, {
			method: 'POST',
			headers: {
				'content-type': 'text/html',
				[AUTH_HEADER]: `Bearer ${token}`
			},
			body: html,
			signal: controller.signal
		});
	} catch {
		// Network error / DNS / connection refused / timeout-abort → worker unreachable.
		// Never logs `html` or `token` — see REDACTION above.
		console.error('[pdf-render] worker unreachable (transport failure)');
		return { ok: false, status: 502 };
	} finally {
		clearTimeout(timer);
	}

	if (res.status !== 200) {
		// (g)'s app-side half — status ONLY, never the body.
		console.error(`[pdf-render] worker returned ${res.status}`);
		return { ok: false, status: res.status };
	}

	const pdfBytes = new Uint8Array(await res.arrayBuffer());
	return { ok: true, pdfBytes };
}
