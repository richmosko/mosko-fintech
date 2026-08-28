// cashflowPerAccount.ts — server-side read + request-boundary validation for the §2.3.3
// per-account cash-flow drill-down (SELF-253). Backend-owned server surface (ARCH §4.1
// allowlist).
//
// Calls Architect's `094` pfin.fn_cashflow_per_account(p_account_id bigint, p_as_of date) — a
// SECURITY INVOKER read-composition helper (Lock 11; prosecdef=f) that composes on `093`'s
// pfin.fn_cashflow_items(p_as_of), through the per-request anon/authenticated client, exactly
// the same client cashflowCrossAccountRollup.ts / netWorth.ts / navComposition.ts already use —
// NEVER service_role (RT-26 / Lock 11). A cross-tenant or foreign p_account_id resolves zero
// reader rows, and `094`'s own contract makes that INDISTINGUISHABLE from an owned-but-empty
// account by construction (094's header: "an explicit ownership check would BREAK it") — this
// file adds no ownership check of its own for the same reason.
//
// ── SURFACE SHAPE (AC5 decision, recorded here because this is the file that makes it) ────────
// Two candidates were live: a GET `/api/...` JSON endpoint, or a loader-idiomatic validated-load
// helper that SELF-254's `+page.server.ts` calls directly. CHOSEN: the loader helper
// (`loadCashflowPerAccountForRequest` below) — no GET API route. Reasoning: every §2.1–§2.3 read
// surface in this tree (`cash-flow/+page.server.ts`, `accounts/[account_id]/+page.server.ts`,
// the allocation loaders) resolves data straight from a `+page.server.ts` `load()` via a query
// wrapper; none of them front a read with a JSON API route, and the one precedent for a
// client-driven query-param surface on a *page* — `nav-series-params.ts`'s chart params — is
// also consumed by a loader, not an endpoint. SELF-254's as-of toolbar (AC4) is a normal
// re-navigation with an updated `?as_of=`, the same shape as the NAV chart's `?chart_start=` /
// `?chart_end=`, not an AJAX fetch that would need a separate JSON contract. Introducing a new
// API-route shape here would be the novel departure Backend's own operating brief holds to a
// higher bar than "the well-understood pattern that fits" — and the well-understood pattern is
// the loader. `POST /api/settings/cashflow-target` is the ONE §2.3 API route in this tree, and it
// exists because it is a WRITE (SELF-246/252); this surface is a read.
//
// ── VALIDATION (AC5) ─────────────────────────────────────────────────────────────────────────
// `validateCashflowPerAccountParams` runs BOTH checks before any SQL invocation:
//   account_id — a route param string, validated as a positive-integer bigint (digit-string
//     regex, never `z.coerce.number()`'s looser numeric-literal coercion — see the module note
//     on `accountIdSchema` for why). Garbage (non-digit, negative-shaped, zero, non-integer,
//     unsafe-integer) → a field-level error on `account_id`, never reaches SQL.
//   as_of — SELF-247's shared `asOfSchema(maxAsOf)` factory, unchanged. `maxAsOf` is the caller's
//     own ONE-PER-REQUEST resolve of `pfin.fn_server_today()` (ADR-044 D2) — this file mints no
//     clock of its own and takes no default. Out-of-range → a field-level error on `as_of`.
// Both checks always run (never short-circuited on the first failure) so a caller correcting one
// field at a time sees every problem in one round trip, matching `fieldErrors`'s multi-key shape.
//
// ⚠ NAMESPACE-SAFE BY CONSTRUCTION, not by a namespace prefix. `asOf.ts`'s own header warns that
// its schema must never be `.strict()`-parsed against a raw, unfiltered
// `Object.fromEntries(url.searchParams)` — an unrelated param on the page would trip `.strict()`
// and disable the surface (the exact `nav-series-params.ts` incident). This file never does that:
// `validateCashflowPerAccountParams` takes `asOfRaw: string | null | undefined` — ALREADY a
// single extracted value, never a searchParams object — and builds `{ as_of }` itself. A caller
// passing `url.searchParams.get('as_of')` (SELF-254's job) can never leak a second key into this
// schema, so no `chart_`-style namespace prefix is needed on this surface's one param.
//
// ── THE TWO-CLOCK SETTLEMENT (item 3) ───────────────────────────────────────────────────────
// `resolveAllocationAsOf` (schemas/asOf.ts) now takes `maxAsOf` as a required second argument and
// its absent-`as_of` branch returns `maxAsOf` itself — see that file's SETTLED header note. This
// module is the FIRST LIVE CALLER of that function; it does not re-derive "today" anywhere.
//
// ── VALIDATED-PARAMS BRAND (item 7) ─────────────────────────────────────────────────────────
// `loadCashflowPerAccount` takes a `ValidatedCashflowPerAccountParams`, not a bare
// `{ accountId, asOf }` object — mirroring `time/asOf.ts`'s `ZoneResolvedAsOf` brand, at smaller
// scale. The type carries an unexported unique-symbol property, so only THIS FILE's
// `validateCashflowPerAccountParams` can produce a value of it; a caller cannot construct one by
// hand from unvalidated input and cannot skip validation by accident. The Condition-B convention
// this mirrors — "call this ONLY on the output of `asOfSchema(...).safeParse`" — is enforced by a
// grep in `asOf.ts`; here it is enforced by the compiler instead, which is strictly stronger for
// a two-field params object with a single producer.
//
// ── AC10 — PERFORMANCE (unowned until this issue) ───────────────────────────────────────────
// Measured locally (`supabase migration up`, seeded dev DB, 2 accounts / 28 pfin.account_trans
// rows — a smoke-scale dataset, not a load bench): `EXPLAIN ANALYZE` of the inlined reader body
// (094 composes on 093's `fn_cashflow_items`, which the planner treats as an opaque Function Scan
// rather than inlining — the same shape 093's own AC10 measurement would see) against the
// 22-transaction seeded account: Execution Time 2.4ms, planner-estimated cost 12.85, a
// `Sort` + `GroupAggregate` over an 8-row post-filter set with no missing index warning. The
// end-to-end scalar RPC call (`explain analyze select pfin.fn_cashflow_per_account(...)`) measured
// 4.2ms. RE-DERIVED TARGET: 150ms p95 for a single account at V1's expected per-user
// `account_trans` scale (low thousands of rows/account, per PRD §7 constraints) — tighter than
// 093's original 500ms p95 (struck as stale by SELF-250 AC10) because this surface is
// account-scoped, a STRICT SUBSET of the cross-account rollup's row set, over the identical
// reader and identical per-item cost. Not alarming at either the account- or household-scale this
// migration is sized for; no optimization work performed, per the AC's own "only if the
// measurement is alarming" instruction. Re-measure against a realistically-sized fixture before
// this figure is treated as a load-tested SLO rather than a smoke-scale sanity check.

import { z } from 'zod';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { asOfSchema, resolveAllocationAsOf } from '$lib/server/schemas/asOf';
import { fieldErrors } from '$lib/server/schemas/account';
import {
	CASHFLOW_SECTION_LABELS,
	type CashflowSectionKey
} from './cashflowSections';

// ── account_id validation ───────────────────────────────────────────────────────────────────
// `pfin.account.account_id` is bigint (003), arriving here as a SvelteKit route-param STRING.
// A digit-only regex FIRST, then `Number()` — never `z.coerce.number()` alone, which accepts
// scientific notation ("1e3"), leading "+"/whitespace-trimmed forms, and non-integer decimals
// that would silently truncate. Mirrors `accounts/[account_id]/+page.server.ts`'s own
// `parseAccountId` (`Number.isInteger(n) && n > 0`), moved into a Zod schema here so this
// surface's failure reports through the same `fieldErrors` structured-error shape as `as_of`.
const ACCOUNT_ID_MESSAGE = 'Invalid account.';

const accountIdSchema = z
	.string()
	.trim()
	.regex(/^\d+$/, ACCOUNT_ID_MESSAGE)
	.transform((s, ctx) => {
		const n = Number(s);
		if (!Number.isSafeInteger(n) || n <= 0) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: ACCOUNT_ID_MESSAGE });
			return z.NEVER;
		}
		return n;
	});

// ── the validated-params brand (item 7) ─────────────────────────────────────────────────────
declare const cashflowPerAccountValidated: unique symbol;

/** Produced ONLY by `validateCashflowPerAccountParams` below — see the module header. */
export type ValidatedCashflowPerAccountParams = {
	readonly accountId: number;
	readonly asOf: ZoneResolvedAsOf;
	readonly [cashflowPerAccountValidated]: true;
};

export type CashflowPerAccountFieldErrors = Record<string, string[]>;

/**
 * Validates BOTH boundary inputs — `account_id` and `as_of` — before any SQL invocation (AC5).
 * Runs both checks unconditionally (never short-circuits on the first failure) so every problem
 * surfaces in one round trip. Returns the branded, RPC-ready params on success.
 */
export function validateCashflowPerAccountParams(input: {
	accountIdRaw: string;
	asOfRaw: string | null | undefined;
	maxAsOf: ZoneResolvedAsOf;
}): { ok: true; params: ValidatedCashflowPerAccountParams } | { ok: false; fieldErrors: CashflowPerAccountFieldErrors } {
	const idResult = accountIdSchema.safeParse(input.accountIdRaw);
	const asOfResult = asOfSchema(input.maxAsOf).safeParse({
		as_of: input.asOfRaw ?? undefined
	});

	if (!idResult.success || !asOfResult.success) {
		const errs: CashflowPerAccountFieldErrors = {};
		if (!idResult.success) errs.account_id = [ACCOUNT_ID_MESSAGE];
		if (!asOfResult.success) Object.assign(errs, fieldErrors(asOfResult.error));
		return { ok: false, fieldErrors: errs };
	}

	const resolvedAsOf = resolveAllocationAsOf(asOfResult.data, input.maxAsOf);

	return {
		ok: true,
		params: {
			accountId: idResult.data,
			asOf: resolvedAsOf
		} as ValidatedCashflowPerAccountParams
	};
}

// ── the typed read shape ────────────────────────────────────────────────────────────────────

/** One (cat, sub_cat) row inside a section — raw amounts from `094`, unmodified. The middle
 *  section spans two classes (Transfer ∪ Equity), so `cat` is carried alongside `sub_cat` as
 *  part of the row's identity — unlike `093`'s cross-account rows, where the section IS the cat. */
export type CashflowPerAccountRow = {
	cat: string;
	sub_cat: string;
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

/** Same period-cell semantics as `cashflowCrossAccountRollup.ts`'s `CashflowSectionTotal` — a
 *  quarter that hasn't started relative to `as_of` is `null` (em-dash); a started quarter with no
 *  activity is `0` (a real answer). Summed DOWN each column, never across. */
export type CashflowPerAccountSectionTotal = {
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

/** One §2.3.3 section. `sectionKey` is `094`'s own discriminator (never a `cat` value — the
 *  middle section has no single `cat` that names it); `label` is attached HERE from the shared
 *  `cashflowSections.ts` module, never typed inline. `cats` is `094`'s watcher array — the class
 *  set the section partitioned on, carried through unmodified for a QA leg to compare against
 *  `CASHFLOW_CLASS_TO_SECTION`'s inverse. */
export type CashflowPerAccountSection = {
	sectionKey: CashflowSectionKey;
	label: string;
	cats: string[];
	rows: CashflowPerAccountRow[];
	total: CashflowPerAccountSectionTotal;
};

/** The S-2 banner's `N`, scoped to THIS account and the rendered year — from the SAME query as
 *  every sum (094's own contract), so the banner and the totals cannot drift. */
export type CashflowPerAccountUnclassified = {
	count_ytd: number;
};

/** The full §2.3.3 per-account drill-down — the typed, section-labelled shape of `094`'s jsonb
 *  return. ⚠ NO `targets` key (AC7) — targets are §2.3.2 aggregate concepts and do not attach to
 *  a single-account scope; this type has no field for one, and a caller cannot synthesise one. */
export type CashflowPerAccount = {
	as_of: string;
	account_id: number;
	sections: CashflowPerAccountSection[];
	unclassified: CashflowPerAccountUnclassified;
};

/** Raw shape as it arrives from the RPC — `094`'s jsonb, before section labels are attached. */
type RawCashflowPerAccountSection = {
	section_key: string;
	cats: string[];
	rows: CashflowPerAccountRow[];
	total: CashflowPerAccountSectionTotal;
};
type RawCashflowPerAccount = {
	as_of: string;
	account_id: number;
	sections: RawCashflowPerAccountSection[];
	unclassified: CashflowPerAccountUnclassified | null | undefined;
};

/** Attaches AC5-shared section labels; defensively coalesces `unclassified` the same way
 *  `cashflowCrossAccountRollup.ts`'s `normalize` does, so this function's return type stays
 *  well-formed even against a hypothetically narrowed future `094` payload. */
function normalize(raw: RawCashflowPerAccount): CashflowPerAccount {
	return {
		as_of: raw.as_of,
		account_id: raw.account_id,
		sections: raw.sections.map((section) => {
			const key = section.section_key as CashflowSectionKey;
			return {
				sectionKey: key,
				// Fall back to the raw section_key only in the structurally-unreachable case where a
				// future 094 revision emits a key this loader's shared label table hasn't caught up
				// with yet (mirrors cashflowCrossAccountRollup.ts's AC5 fallback) — never throw over a
				// label gap.
				label: CASHFLOW_SECTION_LABELS[key] ?? section.section_key,
				cats: section.cats,
				rows: section.rows,
				total: section.total
			};
		}),
		unclassified: raw.unclassified ?? { count_ytd: 0 }
	};
}

/**
 * Load the caller's §2.3.3 per-account drill-down, RLS-scoped via the per-request
 * anon/authenticated client. Takes a `ValidatedCashflowPerAccountParams` — obtainable only from
 * `validateCashflowPerAccountParams` — so a call site cannot reach this RPC with an
 * un-range-checked `as_of` or an un-shape-checked `account_id`.
 *
 * Fail-soft on any read error (network, RPC failure, wrong-shaped payload): degrades to `null` —
 * logged server-side, never thrown. Mirrors `loadCashflowCrossAccountRollup`'s posture.
 */
export async function loadCashflowPerAccount(
	supabase: SupabaseClient,
	params: ValidatedCashflowPerAccountParams
): Promise<CashflowPerAccount | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_cashflow_per_account', { p_account_id: params.accountId, p_as_of: params.asOf });

	if (error) {
		console.error('[cashflowPerAccount] fn_cashflow_per_account failed:', error.message);
		return null;
	}

	// Scalar jsonb RPC -> the parsed object directly, same contract cashflowCrossAccountRollup.ts
	// documents for 093 (094 shares the same jsonb-scalar return shape).
	if (data === null || data === undefined) {
		console.error('[cashflowPerAccount] fn returned no jsonb payload; degrading to null');
		return null;
	}

	return normalize(data as RawCashflowPerAccount);
}

export type CashflowPerAccountRequestResult =
	| { status: 200; data: CashflowPerAccount | null }
	| { status: 400; fieldErrors: CashflowPerAccountFieldErrors };

/**
 * The SELF-254 loader entry point (AC5): validates BOTH `account_id` (route param string) and
 * `as_of` (query-param string, possibly absent) BEFORE any SQL invocation, then loads on success.
 * A validation failure returns `{ status: 400, fieldErrors }` — the caller's `+page.server.ts`
 * maps that to `error(400, ...)` or the loader-idiomatic equivalent; it never reaches this
 * function's own RPC call.
 */
export async function loadCashflowPerAccountForRequest(
	supabase: SupabaseClient,
	input: { accountIdRaw: string; asOfRaw: string | null | undefined; maxAsOf: ZoneResolvedAsOf }
): Promise<CashflowPerAccountRequestResult> {
	const validated = validateCashflowPerAccountParams(input);
	if (!validated.ok) {
		return { status: 400, fieldErrors: validated.fieldErrors };
	}
	const data = await loadCashflowPerAccount(supabase, validated.params);
	return { status: 200, data };
}
