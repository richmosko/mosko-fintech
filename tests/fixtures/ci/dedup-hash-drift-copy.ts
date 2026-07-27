// GENERATED — DO NOT EDIT.
// Source of truth: workers/provider-sync/src/shared/importHash.ts
// Regenerate: node scripts/generate-import-hash-copy.mjs
// This byte-identical copy lets the SvelteKit tier import the SAME canonical import_hash as
// the provider-sync worker (SELF-204 / ADR-034 D4, Location B). A CI byte-equality fence
// fails on any drift. Edit the source, then regenerate — never hand-edit this file.

// FIXTURE — golden canonical source for the dedup-hash-identical inversion test.
// NOT the real import_hash module. This stand-in exists only so the inversion-mode step
// can drive the generator (`--stdout --source <this>`) and diff its output against the
// deliberately-diverged golden copy (dedup-hash-drift-copy.ts), proving the fence goes RED.
// A fence without a failing golden is theater (Sec, 2026-07-27).
export function fixtureImportHash(x: string): string {
	// DELIBERATE DRIFT: a hand-edit that diverged the canonicalization from the source
	// (toLowerCase → toUpperCase). This is the invisible-dedup-break class ADR-034 D4 fears;
	// the generator's output from dedup-hash-drift-source.ts does NOT match this file, so the
	// inversion step's diff is nonzero and the fence goes RED. If this ever matches, the fence
	// is broken.
	return x.trim().toUpperCase();
}
