// syncClient.ts — SERVER-ONLY worker-admission transport for the SELF-317 manual "Sync now" leg.
//
// SCOPE: the api/src → provider-sync worker INTERNAL boundary, manual-sync half. Mirrors the shipped
// reauth admissionClient transport (callWorker / mapUpstreamStatus / admissionConfig). Lives in
// src/lib/server/** (ARCH §4.1 allowlist) — never ships to the browser. Calls the NEW dedicated
// worker route POST /admission/manual-sync (NOT /admission/sync — the 045 webhook route).
//
// SECURITY POSTURE
//  • Holds NO provider credential and NO service_role key — only WORKER_ADMISSION_SHARED_SECRET
//    (keeps api/src OFF the RT-26 allowlist). All ingest/credential work lives worker-side.
//  • SC3-C1: `ownerUserId` is a REQUIRED function argument the caller derives from the validated
//    session — NEVER read from a request body. The worker re-validates it (RLS-scoped enumeration).
//  • C6-5/C4 redaction: never logs bodies/tokens/secret — route + upstream status only.
//  • Transport is the internal Docker network only (http://provider-sync:8081).

import { env } from '$env/dynamic/private';
import { z } from 'zod';

const ADMISSION_HEADER = 'x-worker-admission-secret';
const MANUAL_SYNC_PATH = '/admission/manual-sync';
const DEFAULT_BASE_URL = 'http://provider-sync:8081';
const TIMEOUT_MS = 10_000;
/** The worker returns 202 (A2 return-fast) on success — validated + debounced, sync(s) backgrounded. */
const ACCEPTED = 202;

let cfg: { baseUrl: string; secret: string } | null = null;
function admissionConfig(): { baseUrl: string; secret: string } {
	if (cfg) return cfg;
	const secret = env.WORKER_ADMISSION_SHARED_SECRET;
	if (!secret) {
		throw new Error(
			'Missing WORKER_ADMISSION_SHARED_SECRET — set it in the container runtime env (see .env.example, server tier).'
		);
	}
	const baseUrl = (env.WORKER_ADMISSION_URL || DEFAULT_BASE_URL).replace(/\/+$/, '');
	cfg = { baseUrl, secret };
	return cfg;
}

/** Test-only: clears the memoized env config so a spec can vary process.env per case. */
export function __resetConfigForTests(): void {
	cfg = null;
}

// ── Upstream (worker) response schema — strip unknown keys (NOT user input). ─────────────────────
const manualSyncResponseSchema = z.object({
	accepted: z.literal(true),
	sources: z.array(
		z.object({
			source_id: z.string(),
			disposition: z.enum(['triggered', 'debounced'])
		})
	)
});

export type ManualSyncResponse = z.infer<typeof manualSyncResponseSchema>;
export type LegOutcome<T> = { ok: true; data: T } | { ok: false; status: number };

/** worker 4xx (bad request) → 400 client-correctable; worker 5xx / unexpected → 502 (design §1a:
 *  "worker unreachable / worker 5xx" → 502). */
export function mapUpstreamStatus(status: number): number {
	if (status === 400 || status === 413) return 400;
	return 502;
}

type WorkerCall = { transportOk: true; status: number; json: unknown } | { transportOk: false };

async function callWorker(path: string, payload: unknown): Promise<WorkerCall> {
	const { baseUrl, secret } = admissionConfig();
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
	try {
		const res = await fetch(`${baseUrl}${path}`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', [ADMISSION_HEADER]: secret },
			body: JSON.stringify(payload),
			signal: controller.signal
		});
		let json: unknown = null;
		try {
			json = await res.json();
		} catch {
			json = null;
		}
		if (res.status !== ACCEPTED) {
			console.error(`[manual-sync-admission] worker ${path} returned ${res.status}`); // C4: status + path only.
		}
		return { transportOk: true, status: res.status, json };
	} catch {
		console.error(`[manual-sync-admission] worker ${path} unreachable (transport failure)`);
		return { transportOk: false };
	} finally {
		clearTimeout(timer);
	}
}

/**
 * Trigger a manual "Sync now". `ownerUserId` is session-derived (SC3-C1 — never body-sourced);
 * `sourceId` is optional (absent ⇒ sync-all the caller's active sources). Returns the per-source
 * dispositions on 202, or a mapped failure status (502 transport/5xx; 400 bad request).
 */
export async function requestManualSync(
	ownerUserId: string,
	sourceId?: string
): Promise<LegOutcome<ManualSyncResponse>> {
	const call = await callWorker(MANUAL_SYNC_PATH, {
		ownerUserId,
		...(sourceId ? { source_id: sourceId } : {})
	});
	if (!call.transportOk) return { ok: false, status: 502 };
	if (call.status === ACCEPTED) {
		const parsed = manualSyncResponseSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 };
		return { ok: true, data: parsed.data };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}
