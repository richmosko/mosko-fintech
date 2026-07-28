// classification.test.ts — unit tests for the CLIENT-SIDE classify Zod mirror (SELF-200).
// Pure Zod (no DOM). Proves the client mirror is NOT looser than the server's
// schemas/classification.ts: same .strict() posture, same z.coerce.number().int().positive()
// gate on BOTH ids, and NO nullable "Unsorted" (sub_cat_id is required — user_asset_category
// .sub_cat_id is NOT NULL, 022). Friendlier messages are UX, not a loosening.

import { describe, it, expect } from 'vitest';
import { classifySchema } from './classification';

const PICK_MSG = 'Choose a category.';

describe('classifySchema (client mirror)', () => {
	it('accepts two positive int ids (form strings coerce)', () => {
		const r = classifySchema.safeParse({ asset_id: '42', sub_cat_id: '7' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data).toEqual({ asset_id: 42, sub_cat_id: 7 });
	});

	it('rejects the empty "Select a category…" placeholder on sub_cat_id (required — AC3)', () => {
		// '' coerces to 0 → fails .positive() → the required-category message. There is NO
		// nullable Unsorted option here (unlike account.sub_cat_id).
		const r = classifySchema.safeParse({ asset_id: '42', sub_cat_id: '' });
		expect(r.success).toBe(false);
		if (!r.success) {
			const issue = r.error.issues.find((i) => i.path[0] === 'sub_cat_id');
			expect(issue?.message).toBe(PICK_MSG);
		}
	});

	it.each([
		['zero', '0'],
		['negative', '-3'],
		['fractional', '2.5'],
		['non-numeric', 'abc']
	])('rejects a %s sub_cat_id', (_label, sub_cat_id) => {
		const r = classifySchema.safeParse({ asset_id: '42', sub_cat_id });
		expect(r.success).toBe(false);
	});

	it('rejects a non-positive asset_id', () => {
		const r = classifySchema.safeParse({ asset_id: '0', sub_cat_id: '7' });
		expect(r.success).toBe(false);
	});

	it('is .strict() — rejects extra keys (mass-assignment fence mirror)', () => {
		// users_id is ALWAYS session-derived server-side; the client shape must reject it too so
		// the mirror is never looser than the server's .strict().
		const r = classifySchema.safeParse({ asset_id: '42', sub_cat_id: '7', users_id: 'attacker' });
		expect(r.success).toBe(false);
	});
});
