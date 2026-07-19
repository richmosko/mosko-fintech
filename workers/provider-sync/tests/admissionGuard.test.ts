// admissionGuard.test.ts — CA-1 private-only startup assertion + CA-6 constant-time secret.
// Pure helpers; NO server, NO network.

import { describe, it, expect } from 'vitest';
import {
	assertPrivateOnly,
	detectPublicRouteSignal,
	PUBLIC_ROUTE_ENV_MATCHERS
} from '../src/http/admissionGuard.js';
import { verifySharedSecret } from '../src/http/sharedSecret.js';

describe('CA-1 assertPrivateOnly — fail-closed private-only opt-in', () => {
	it('throws when ADMISSION_PRIVATE_ONLY is unset', () => {
		expect(() => assertPrivateOnly({})).toThrow(/ADMISSION_PRIVATE_ONLY/);
	});

	it('throws when ADMISSION_PRIVATE_ONLY is not exactly "true"', () => {
		expect(() => assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'false' })).toThrow(/ADMISSION_PRIVATE_ONLY/);
		expect(() => assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: '1' })).toThrow(/ADMISSION_PRIVATE_ONLY/);
		expect(() => assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'TRUE' })).toThrow(/ADMISSION_PRIVATE_ONLY/);
	});

	it('passes when opted-in and no public-route signal is present', () => {
		expect(() =>
			assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'true', PFIN_DB_HOST: 'db', WORKER_ADMISSION_SHARED_SECRET: 'x' })
		).not.toThrow();
	});

	it('fails closed on a Coolify Domain FQDN injection even WITH the opt-in (UI-regression case)', () => {
		expect(() =>
			assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'true', SERVICE_FQDN_PROVIDER_SYNC: 'admit.example.com' })
		).toThrow(/public-route signal/);
	});

	it('fails closed on COOLIFY_URL / COOLIFY_FQDN / ADMISSION_PUBLIC_URL', () => {
		for (const name of ['COOLIFY_URL', 'COOLIFY_FQDN', 'ADMISSION_PUBLIC_URL']) {
			expect(() => assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'true', [name]: 'https://x' })).toThrow(
				/public-route signal/
			);
		}
	});

	it('CA-1: catches env-name DRIFT by PATTERN, not an exact-name list', () => {
		// A renamed/added Coolify FQDN var the exact-name list never enumerated is still caught.
		expect(() =>
			assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'true', SERVICE_FQDN_SOME_NEW_SERVICE_8443: 'x' })
		).toThrow(/public-route signal/);
		expect(() => assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'true', COOLIFY_CONTAINER_URL_V2: 'x' })).toThrow(
			/public-route signal/
		);
	});

	it('CA-1: fails closed on the SERVICE_URL_* family even without a co-present SERVICE_FQDN_ (Coolify #8912/#6124)', () => {
		// SERVICE_URL_<ID> is distinct from SERVICE_FQDN_ and can appear alone → must trip.
		expect(() => assertPrivateOnly({ ADMISSION_PRIVATE_ONLY: 'true', SERVICE_URL_ABC123: 'https://admit.example.com' })).toThrow(
			/public-route signal/
		);
	});
});

describe('detectPublicRouteSignal', () => {
	it('returns null when no signal present', () => {
		expect(detectPublicRouteSignal({ FOO: 'bar', PFIN_DB_HOST: 'db' })).toBeNull();
	});

	it('ignores empty-valued vars (not a live route)', () => {
		expect(detectPublicRouteSignal({ SERVICE_FQDN_X: '' })).toBeNull();
		expect(detectPublicRouteSignal({ SERVICE_FQDN_X: undefined })).toBeNull();
	});

	it('is case-insensitive on the name', () => {
		expect(detectPublicRouteSignal({ service_fqdn_x: 'y' })).toBe('service_fqdn_x');
	});

	it('has the documented matcher set', () => {
		expect(PUBLIC_ROUTE_ENV_MATCHERS.map((m) => m.label)).toEqual([
			'SERVICE_FQDN_*',
			'SERVICE_URL_*',
			'COOLIFY_*URL*',
			'COOLIFY_*FQDN*',
			'ADMISSION_PUBLIC_URL'
		]);
	});
});

describe('CA-6 verifySharedSecret — constant-time, fail-closed', () => {
	const SECRET = 'a'.repeat(64);

	it('true only on an exact match', () => {
		expect(verifySharedSecret(SECRET, SECRET)).toBe(true);
		expect(verifySharedSecret(SECRET.slice(0, 63) + 'b', SECRET)).toBe(false);
	});

	it('fails closed on absent/empty presented secret', () => {
		expect(verifySharedSecret(undefined, SECRET)).toBe(false);
		expect(verifySharedSecret(null, SECRET)).toBe(false);
		expect(verifySharedSecret('', SECRET)).toBe(false);
	});

	it('fails closed on empty expected secret', () => {
		expect(verifySharedSecret(SECRET, '')).toBe(false);
	});

	it('is length-independent (different lengths → false, never throws)', () => {
		expect(() => verifySharedSecret('short', SECRET)).not.toThrow();
		expect(verifySharedSecret('short', SECRET)).toBe(false);
		expect(verifySharedSecret(SECRET + 'extra', SECRET)).toBe(false);
	});
});
