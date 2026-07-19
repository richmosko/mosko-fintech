// api/tests/harness.smoke.test.ts
//
// OQ-3 harness smoke — proves the api/ Vitest runner is wired and green, so
// Frontend's SELF-198 specs, the Option-C relay-leg tests, and QA's api-tier
// tests have a runnable target. Delete or keep as a canary once real specs land.

import { describe, it, expect } from 'vitest';

describe('api/ vitest harness', () => {
	it('runs a trivial assertion (runner is wired)', () => {
		expect(1 + 1).toBe(2);
	});

	it('runs in the node environment (default)', () => {
		// `process` exists in node env; this asserts the config resolved.
		expect(typeof process).toBe('object');
	});
});
