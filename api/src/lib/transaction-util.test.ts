// transaction-util.test.ts — SELF-249 Sec NOTE-1: `classifyRefusalCopy`'s exhaustiveness is
// enforced at compile time (CLASSIFY_REFUSAL_COPY is typed `Record<ClassifyFailureCode |
// ClassifiableRefusalReason, string>` — the file fails to build if either union gains a member
// with no matching entry). This file locks in the RUNTIME behavior that type alone can't check:
// every code returns non-generic copy, `unauthenticated` never says "try again", and a genuinely
// unrecognized code still gets a safe non-blank fallback.

import { describe, it, expect } from 'vitest';
import { classifyRefusalCopy } from './transaction-util';
import type { ClassifyFailureCode } from './transactions/classifyFlow';

const GENERIC_FALLBACK = 'Could not save the category. Please try again.';

// Every code either union can produce — mirrors classifyFlow.ts's `ClassifyFailureCode` (a
// superset of transaction-util.ts's own `ClassifiableRefusalReason`).
const ALL_CODES: ClassifyFailureCode[] = [
	'not_standard',
	'has_security',
	'split_parent',
	'is_reversal',
	'journaled',
	'journaled_cat_conflict',
	'invalid_sub_cat_id',
	'not_found',
	'invalid_request',
	'unauthenticated',
	'server_error',
	'network',
	'malformed'
];

describe('classifyRefusalCopy', () => {
	it('every known code returns its own non-generic copy — none silently fall through', () => {
		for (const code of ALL_CODES) {
			expect(classifyRefusalCopy(code)).not.toBe(GENERIC_FALLBACK);
			expect(classifyRefusalCopy(code).length).toBeGreaterThan(0);
		}
	});

	it('Sec NOTE-1: unauthenticated never says "try again" — retrying without re-auth fails identically', () => {
		const copy = classifyRefusalCopy('unauthenticated');
		expect(copy.toLowerCase()).not.toContain('try again');
		expect(copy.toLowerCase()).toContain('sign in');
	});

	it('null/undefined/unrecognized codes fall back to the generic copy, never blank', () => {
		expect(classifyRefusalCopy(null)).toBe(GENERIC_FALLBACK);
		expect(classifyRefusalCopy(undefined)).toBe(GENERIC_FALLBACK);
		expect(classifyRefusalCopy('not_a_real_code')).toBe(GENERIC_FALLBACK);
	});
});
