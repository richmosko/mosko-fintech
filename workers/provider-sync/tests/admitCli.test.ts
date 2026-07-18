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
	it('parses --owner and optional --public-token', () => {
		expect(parseAdmitArgs(['--owner', 'u1'])).toEqual({ ownerUserId: 'u1', publicToken: undefined });
		expect(parseAdmitArgs(['--owner', 'u1', '--public-token', 'pt'])).toEqual({ ownerUserId: 'u1', publicToken: 'pt' });
	});
});
