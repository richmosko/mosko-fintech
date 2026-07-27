// FIXTURE — golden canonical source for the dedup-hash-identical inversion test.
// NOT the real import_hash module. This stand-in exists only so the inversion-mode step
// can drive the generator (`--stdout --source <this>`) and diff its output against the
// deliberately-diverged golden copy (dedup-hash-drift-copy.ts), proving the fence goes RED.
// A fence without a failing golden is theater (Sec, 2026-07-27).
export function fixtureImportHash(x: string): string {
	return x.trim().toLowerCase();
}
