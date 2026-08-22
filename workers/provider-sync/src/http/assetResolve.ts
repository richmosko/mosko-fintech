// assetResolve.ts — SELF-325 asset-resolve leg (manual purchase-path, Case 3 / public tickers).
//
// A NEW route on the EXISTING RT-27 admission surface (POST /asset/resolve) — NOT a new §10
// instance, per the in-tree precedent admissionServer.ts already documents for the SimpleFIN
// leg-S route: same private-bind listener, same CA-6 constant-time shared-secret gate, same
// session-derived tenant convention. Clean on the §10/DEFINER axes because this reuses the
// existing service_role identity + the existing 020 grant; no new privileged surface is created.
// The D1 assessment is its own section below (ADR-011 DECISION 1).
//
// THIN WRAPPER (load-bearing, not a style choice): this module does NOT re-implement asset
// resolution. It opens a withServiceRole() transaction on a tenant-bound client and delegates
// to the EXISTING resolveSecurityId (../ingest/resolution.ts) — a second copy of the cusip-
// first/symbol-fallback/ON CONFLICT key order is a known drift surface (the repo has already
// paid for one instance of this at 078). pricingSourceForAssetType
// is reused UNCHANGED so a user-minted asset and a Plaid-minted asset are indistinguishable
// downstream — introducing a distinguishing value here would re-fork what global-first
// resolution exists to unify.
//
// TENANT BINDING (C6-3 convention, mirrors every other leg on this server): `ownerUserId` is
// accepted ONLY from the shared-secret-authed internal call's body; the worker exposes no
// browser-reachable field. Per ADR-011 Decision 1 clause (c) (see the full assessment below): a
// GLOBAL asset row (users_id IS NULL) has no tenant to bind incorrectly — the strongest security
// property of this route — but `ownerUserId` is still required and still forwarded, because it is
// the audit subject (clause (d)) and the natural future rate-limit key (no rate-limit control
// exists today; flagged to Sec at SELF-325 joint review, not built here).
//
// ADR-011 DECISION 1 — THE FOUR CLAUSES, READ LIVE HERE (⚠ this is the surface the clauses
// apply to — NOT `pfin.fn_create_manual_purchase` / 088, which is a JWT-bearing INVOKER call D1
// does not reach; Architect's correction, SELF-325 handoff 2026-08-21). This route IS a non-JWT
// `service_role` write, so D1 governs it directly:
//   (a) Ingress under no JWT — SATISFIED. The internal call is shared-secret authed (CA-6); the
//       worker holds no user session, same as every other admission leg.
//   (b) Writes under service_role — SATISFIED by the existing withServiceRole() + the existing
//       020 grant. No new grant, no new privileged identity.
//   (c) Tenant correctness derives from code, not RLS — VACUOUS BY CONSTRUCTION, and that is a
//       property of this route, not a gap: a GLOBAL asset row (users_id IS NULL) has no tenant a
//       code path could bind incorrectly, because it belongs to none. There is no tenant-binding
//       claim for `ownerUserId` to get wrong here — its job is (d)/audit-subject and the future
//       rate-limit key, stated above, never tenant correctness.
//   (d) Explicit audit log capturing the tenant-resolution chain — ⚠ THE GAP, NOT FREE. The
//       same-transaction audit-log infra this would write into does not exist yet (the A2
//       deferral shared with 087/088 — SELF-201 Task #7). DOCUMENTED DEFERRAL (Architect's
//       recommendation (i), A2-style, mirroring 088's own "AUDIT FORWARD-HOOK" shape): when that
//       infra lands, the audit row belongs HERE — this resolve-or-mint call, keyed by
//       `ownerUserId` as the tenant-resolution subject and `assetId` as the resulting row. Until
//       then this deferral is NOT discharged by worker log lines: C6-5's route+status logging is
//       operational diagnostics, not a forensic audit trail, and ADR-011 Decision 1 clause (d)
//       requires an EXPLICIT audit log — a diagnostic log line is not that, whatever its content.
//       Sec accepts-or-overrides this at joint-review.
//
// REDACTION (C6-5): request/response bodies are never logged; the route layer (admissionServer.ts)
// logs route + coarse outcome only.

import { TenantBoundClient } from '../db/TenantBoundClient.js';
import type { WorkerConfig } from '../config/env.js';
import { resolveSecurityId, type ResolvableAsset } from '../ingest/resolution.js';

export interface AssetResolveInput {
	ownerUserId: string;
	symbol: string | null;
	cusip: string | null;
	/** pfin.asset.asset_type — already validated against 016's CHECK vocabulary at the route. */
	assetType: string;
	name: string | null;
	currency: string;
}

export interface AssetResolveResult {
	/**
	 * pfin.asset.asset_id, serialized as a DECIMAL STRING — not a number — or null for a
	 * blank/blank sweep (unreachable via the route's Zod schema, which requires at least one of
	 * symbol/cusip — preserved for parity with resolveSecurityId's own contract).
	 *
	 * ⚠ WIRE-FORMAT BUG, FIXED (freeze-break, found by QA): `resolveSecurityId` is typed
	 * `Promise<number | null>`, but `asset_id` is `bigint` (016) and postgres.js returns bigint
	 * columns as JS STRINGS at runtime by default (TenantBoundClient sets no `bigint` type
	 * override) — the TS type was aspirational, not a runtime guarantee. Every OTHER bigint this
	 * admission server puts on the wire already follows the established convention this one
	 * should have from the start: `sourceId: String(sourceId)` at both the exchange and
	 * simplefin-claim legs in admissionServer.ts, mirrored by `linkedSourceIdField()` in
	 * api/CLAUDE.md's schemas/account.ts ("bigint... serialized by the connect relay as a
	 * decimal STRING (JSON-safe)"). `productionAssetResolveDeps` below now `String()`-coerces
	 * explicitly, so this type finally states what was already true of the OTHER ids and was
	 * never true of this one.
	 */
	assetId: string | null;
}

/** The seam admissionServer.ts depends on — injectable so the route unit-tests with no live DB. */
export interface AssetResolveDeps {
	resolve(input: AssetResolveInput): Promise<AssetResolveResult>;
}

/**
 * Production wiring: opens a withServiceRole() transaction on a tenant-bound client and
 * delegates to the EXISTING resolveSecurityId (see module header — do not re-implement). The
 * tenant-bound client is constructed per-call and closed in a `finally`, mirroring every other
 * production dep factory on this server (writeManualAudit / enumerateSourcesForTenant).
 */
export function productionAssetResolveDeps(config: WorkerConfig): AssetResolveDeps {
	return {
		resolve: async (input) => {
			const client = TenantBoundClient.forTenant(config, input.ownerUserId);
			try {
				const asset: ResolvableAsset = {
					symbol: input.symbol,
					cusip: input.cusip,
					assetType: input.assetType,
					name: input.name,
					currency: input.currency
				};
				const assetId = await client.withServiceRole((tx) => resolveSecurityId(tx, asset));
				// String() is the fix, not a formatting nicety — see AssetResolveResult's own
				// comment. Do NOT trust resolveSecurityId's `number` type; postgres.js hands back a
				// bigint column as a string at runtime, and this coerces to a definite one either
				// way (idempotent if a future postgres.js config ever changed the default).
				return { assetId: assetId === null ? null : String(assetId) };
			} finally {
				await client.end();
			}
		}
	};
}
