// admissionClient.ts — SERVER-ONLY worker-admission transport for the SELF-207 reauth legs.
//
// SCOPE: the api/src → provider-sync worker INTERNAL boundary, reauth half. Provider-agnostic:
// the worker dispatches by the `provider` this relay resolves server-side (never client-supplied).
// Mirrors the shipped plaid/simplefin admissionClient transport (callWorker / mapUpstreamStatus /
// admissionConfig) — deferred shared-transport lift is a known cleanup (§3b). Lives in
// src/lib/server/** (ARCH §4.1 allowlist) — never ships to the browser.
//
// SECURITY POSTURE
//  • Holds NO provider credential and NO service_role key — only WORKER_ADMISSION_SHARED_SECRET
//    (keeps api/src OFF the RT-26 allowlist). The reauth credential work (Plaid update-mode mint,
//    SimpleFIN claim + Vault rotation) lives worker-side.
//  • SC3-C1: `ownerUserId` is a REQUIRED function argument the caller derives from the validated
//    session — NEVER read from a request body. The worker re-validates it.
//  • C6-5 redaction: never logs bodies/tokens/secret — route + upstream status only.
//  • Transport is the internal Docker network only (http://provider-sync:8081).

import { env } from '$env/dynamic/private';
import { z } from 'zod';

const ADMISSION_HEADER = 'x-worker-admission-secret';
const START_PATH = '/admission/reauth/start';
const COMPLETE_PATH = '/admission/reauth/complete';
const DEFAULT_BASE_URL = 'http://provider-sync:8081';
const TIMEOUT_MS = 10_000;

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

// ── Upstream (worker) response schemas — strip unknown keys (NOT user input). ────────────
const handoffSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('link_update'), linkToken: z.string().min(1) }),
	z.object({ kind: z.literal('recollect_credential') })
]);
const completeSchema = z.object({ connectionStatus: z.literal('healthy'), rotated: z.boolean() });

export type ReauthHandoff = z.infer<typeof handoffSchema>;
export type ReauthCompleteResult = z.infer<typeof completeSchema>;
export type Provider = 'plaid' | 'simplefin';

/** The Phase-2 wire input (provider-derived by the relay): Plaid = no token; SimpleFIN = token. */
export type ReauthWireInput = { kind: 'link_update_success' } | { kind: 'setup_token'; setup_token: string };

export type LegOutcome<T> = { ok: true; data: T } | { ok: false; status: number };

// worker 4xx (bad/burned request) → 400 client-correctable; else → 500 generic.
export function mapUpstreamStatus(status: number): number {
	if (status === 400 || status === 413) return 400;
	return 500;
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
		if (res.status !== 200) {
			console.error(`[reauth-admission] worker ${path} returned ${res.status}`); // C6-5: status + path only.
		}
		return { transportOk: true, status: res.status, json };
	} catch {
		console.error(`[reauth-admission] worker ${path} unreachable (transport failure)`);
		return { transportOk: false };
	} finally {
		clearTimeout(timer);
	}
}

/** Phase 1: begin re-auth. `provider` is relay-resolved (authoritative), `ownerUserId` session-derived. */
export async function reauthStart(
	ownerUserId: string,
	provider: Provider,
	linkedSourceId: string
): Promise<LegOutcome<ReauthHandoff>> {
	const call = await callWorker(START_PATH, { provider, linked_source_id: linkedSourceId, ownerUserId });
	if (!call.transportOk) return { ok: false, status: 502 };
	if (call.status === 200) {
		const parsed = handoffSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 };
		return { ok: true, data: parsed.data };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}

/** Phase 2: complete re-auth. `input` is built by the relay from the resolved provider. */
export async function reauthComplete(
	ownerUserId: string,
	provider: Provider,
	linkedSourceId: string,
	input: ReauthWireInput
): Promise<LegOutcome<ReauthCompleteResult>> {
	const call = await callWorker(COMPLETE_PATH, { provider, linked_source_id: linkedSourceId, ownerUserId, input });
	if (!call.transportOk) return { ok: false, status: 502 };
	if (call.status === 200) {
		const parsed = completeSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 };
		return { ok: true, data: parsed.data };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}
