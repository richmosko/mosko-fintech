// rt26ManualSyncAllowlistFence.qa.test.ts — QA verification battery (SELF-317 "Sync now").
//
// Sec §7 item #6 — RT-26 SUPABASE_SERVICE_ROLE_KEY allowlist stays flat. The manual-sync app
// surface (POST /api/sync route + the syncClient transport) holds ONLY WORKER_ADMISSION_SHARED_
// SECRET; it holds NO service_role key and stays OFF the RT-26 allowlist (design §2 / §7 / §8;
// ADR-016 3-surface allowlist unchanged). This test is the QA-tier mirror of the RT-26 CI grep
// fence, scoped to the exact surfaces SELF-317 added: it fails closed if a service_role literal is
// ever introduced there.
//
// Non-vacuous by construction: the same detector is FIRST proven to fire on a known-bad control
// string (so a green here means "the grep has teeth + the surfaces are clean", never "the grep
// found nothing because it can't match"). It also asserts the surfaces were actually read (guards a
// vacuous pass from an empty file list after a future rename).
//
// DETECTOR = the EXACT token the CI fence greps (scripts/ci/fence-rt26-service-role-allowlist.sh:
// `grep -rEln 'SUPABASE_SERVICE_ROLE_KEY'`). This is deliberately the env-var literal, NOT the prose
// word `service_role` — the +server.ts comment "holds NO service_role key" is a correct annotation,
// not a violation, exactly as the CI fence treats it. Mirroring the CI token keeps this QA mirror
// faithful (no false-positive on documentation of the confinement).
//
// Grounding: docs/SECURITY §RT-26 · ADR-016 (3+1 allowlist) · scripts/ci/rt26-allowlist.txt (the
// SELF-317 sync surfaces are NOT registry entries) · temp/sync-now-design.md §2 / §7 / §8 (api/src
// stays off the allowlist).

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const API_SRC = join(HERE, '..', 'src');

// The SELF-317 app-layer surfaces (the ONLY ones this slice added). Both MUST stay off the allowlist.
const SYNC_ROUTE_DIR = join(API_SRC, 'routes', 'api', 'sync');
const SYNC_CLIENT = join(API_SRC, 'lib', 'server', 'sync', 'syncClient.ts');

// The RT-26 fence token — EXACTLY what the CI grep matches (the env-var literal). Not the prose
// word `service_role` (which legitimately appears in confinement annotations).
const SERVICE_ROLE_KEY = /SUPABASE_SERVICE_ROLE_KEY/;

function collectFiles(path: string): string[] {
	const st = statSync(path);
	if (st.isFile()) return [path];
	return readdirSync(path).flatMap((entry) => collectFiles(join(path, entry)));
}

describe('Sec #6 — RT-26: the SELF-317 app surfaces reference NO SUPABASE_SERVICE_ROLE_KEY', () => {
	it('the detector has TEETH: it matches the known-bad env-var token (non-vacuous guard)', () => {
		expect(SERVICE_ROLE_KEY.test('const k = env.SUPABASE_SERVICE_ROLE_KEY;')).toBe(true);
		// The prose word `service_role` alone is NOT a violation (matches CI fence intent).
		expect(SERVICE_ROLE_KEY.test('// holds NO service_role key → stays OFF the RT-26 allowlist')).toBe(false);
		expect(SERVICE_ROLE_KEY.test('const anon = PUBLIC_SUPABASE_ANON_KEY;')).toBe(false);
	});

	it('src/routes/api/sync/** references no SUPABASE_SERVICE_ROLE_KEY (and the dir was actually scanned)', () => {
		const files = collectFiles(SYNC_ROUTE_DIR).filter((f) => f.endsWith('.ts'));
		expect(files.length).toBeGreaterThan(0); // guard: an empty list must not pass vacuously.
		for (const f of files) {
			const src = readFileSync(f, 'utf8');
			expect(SERVICE_ROLE_KEY.test(src), `${f} must not reference SUPABASE_SERVICE_ROLE_KEY (RT-26)`).toBe(false);
		}
	});

	it('src/lib/server/sync/syncClient.ts references no SUPABASE_SERVICE_ROLE_KEY', () => {
		const src = readFileSync(SYNC_CLIENT, 'utf8');
		expect(src.length).toBeGreaterThan(0); // guard: the file was actually read.
		expect(SERVICE_ROLE_KEY.test(src), 'syncClient.ts must not reference SUPABASE_SERVICE_ROLE_KEY (RT-26)').toBe(false);
	});
});
