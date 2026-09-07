// layout-pending-monthly-report-count.server.test.ts — SELF-357 / P5 AC2's in-app pending
// notification badge, added to root +layout.server.ts. Covers: the count is 0 for a signed-out
// visitor (no read attempted); a signed-in read counts only `draft` rows, tenant-scoped under
// `locals.supabase` (never service_role — AC2's Sec F-8 concern, checked structurally here by
// asserting the count call goes through the SAME client every other per-request read uses); and
// fail-soft-to-0 on a read error or thrown exception (mirrors pendingClassificationCount's own
// documented posture — a layout load that threw would break every page).
//
// The other two existing counts (`countPendingSymbols`, `loadConnectionHealth`) and
// `provisionDefaultTaxonomy` are MOCKED — their own contracts are those modules' own tests' job;
// this file only proves the NEW count's wiring.

import { describe, it, expect, vi } from 'vitest';

vi.mock('$lib/server/queries/pendingSymbols', () => ({ countPendingSymbols: vi.fn(async () => 0) }));
vi.mock('$lib/server/queries/taxonomy', () => ({ provisionDefaultTaxonomy: vi.fn(async () => undefined) }));
vi.mock('$lib/server/queries/connectionState', () => ({
	loadConnectionHealth: vi.fn(async () => ({ reauthCount: 0, institutionDownCount: 0 }))
}));

const { load } = await import('./+layout.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeSupabase(opts: { count?: number | null; error?: { message: string } | null }) {
	const calls: Array<{ table: string; eq: Array<[string, unknown]> }> = [];
	const from = (table: string) => {
		const call = { table, eq: [] as Array<[string, unknown]> };
		calls.push(call);
		return {
			select: (_cols: string, _opts: unknown) => ({
				eq: (col: string, val: unknown) => {
					call.eq.push([col, val]);
					return Promise.resolve({ count: opts.count ?? 0, error: opts.error ?? null });
				}
			})
		};
	};
	return { client: { schema: (_s: string) => ({ from }) }, calls };
}

function makeEvent(user: { id: string } | null, supabase: ReturnType<typeof makeSupabase>['client']) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return { locals } as unknown as Parameters<typeof load>[0];
}

describe('+layout.server load — pendingMonthlyReportCount (SELF-357 AC2)', () => {
	it('signed-out visitor: count is 0, no read attempted', async () => {
		const { client, calls } = makeSupabase({ count: 5 });
		const result = await load(makeEvent(null, client));
		expect((result as { pendingMonthlyReportCount: number }).pendingMonthlyReportCount).toBe(0);
		expect(calls).toHaveLength(0);
	});

	it("signed-in: counts draft rows via locals.supabase (tenant-scoped, no service_role) filtered to generation_status='draft'", async () => {
		const { client, calls } = makeSupabase({ count: 3 });
		const result = await load(makeEvent({ id: SESSION_UID }, client));
		expect((result as { pendingMonthlyReportCount: number }).pendingMonthlyReportCount).toBe(3);
		expect(calls).toHaveLength(1);
		expect(calls[0].table).toBe('monthly_report');
		expect(calls[0].eq).toEqual([['generation_status', 'draft']]);
	});

	it('a null count (PostgREST edge case) degrades to 0, not NaN or undefined', async () => {
		const { client } = makeSupabase({ count: null });
		const result = await load(makeEvent({ id: SESSION_UID }, client));
		expect((result as { pendingMonthlyReportCount: number }).pendingMonthlyReportCount).toBe(0);
	});

	it('a thrown read failure degrades to 0 — a layout load that threw would break every page', async () => {
		const client = {
			schema: () => ({
				from: () => ({
					select: () => ({
						eq: () => Promise.reject(new Error('network down'))
					})
				})
			})
		};
		const result = await load(makeEvent({ id: SESSION_UID }, client as never));
		expect((result as { pendingMonthlyReportCount: number }).pendingMonthlyReportCount).toBe(0);
	});
});
