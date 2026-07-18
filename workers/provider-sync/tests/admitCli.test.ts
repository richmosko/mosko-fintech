// admitCli.test.ts — SC3-C2: the dev admit CLI is sandbox-gated. It MUST refuse to run
// outside PLAID_ENV=sandbox (production admission goes through the api/src server-session
// relay, never this CLI). Pure-function tests — no Plaid client, no DB.

import { describe, it, expect } from 'vitest';
import { assertSandboxGate, parseAdmitArgs, runAdmit } from '../src/cli/admit.js';
import type { WorkerConfig } from '../src/config/env.js';

function cfg(env: 'sandbox' | 'production'): WorkerConfig {
	return {
		db: { host: 'h', port: 5432, database: 'pfin', user: 'authenticator', password: 'x' },
		plaid: { clientId: 'cid', secret: 'sec', env },
		simplefinToken: undefined,
		discordWebhookUrl: undefined
	};
}

describe('assertSandboxGate (SC3-C2)', () => {
	it('permits sandbox', () => {
		expect(() => assertSandboxGate('sandbox')).not.toThrow();
	});
	it('refuses production', () => {
		expect(() => assertSandboxGate('production')).toThrow(/sandbox/i);
	});
	it('refuses any other value', () => {
		expect(() => assertSandboxGate('development')).toThrow(/sandbox/i);
	});
});

describe('runAdmit (SC3-C2 gate is checked first)', () => {
	it('refuses to run under a production config before touching Plaid or the DB', async () => {
		// No Plaid client / no dbFor are constructed because the gate throws first.
		await expect(runAdmit(cfg('production'), ['--owner', '11111111-1111-4111-8111-111111111111'])).rejects.toThrow(
			/sandbox/i
		);
	});
});

describe('parseAdmitArgs', () => {
	it('requires --owner', () => {
		expect(() => parseAdmitArgs([])).toThrow(/--owner/);
	});
	it('parses --owner and optional --public-token; map defaults off with provisional defaults', () => {
		expect(parseAdmitArgs(['--owner', 'u1'])).toEqual({
			ownerUserId: 'u1',
			publicToken: undefined,
			map: false,
			scope: 'personal',
			taxTreatment: 'taxable'
		});
		expect(parseAdmitArgs(['--owner', 'u1', '--public-token', 'pt'])).toMatchObject({ ownerUserId: 'u1', publicToken: 'pt' });
	});
	it('parses --map with --scope / --tax-treatment overrides', () => {
		expect(parseAdmitArgs(['--owner', 'u1', '--map', '--scope', 'joint', '--tax-treatment', 'tax_deferred'])).toEqual({
			ownerUserId: 'u1',
			publicToken: undefined,
			map: true,
			scope: 'joint',
			taxTreatment: 'tax_deferred'
		});
	});
	it('rejects a --tax-treatment outside the 003 CHECK domain (fail-fast, before any DB touch)', () => {
		expect(() => parseAdmitArgs(['--owner', 'u1', '--map', '--tax-treatment', 'bogus'])).toThrow(/tax-treatment/i);
	});
	it('accepts all three valid tax_treatment values', () => {
		for (const t of ['taxable', 'tax_deferred', 'tax_free']) {
			expect(parseAdmitArgs(['--owner', 'u1', '--tax-treatment', t]).taxTreatment).toBe(t);
		}
	});
});
