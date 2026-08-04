# MOVED → `supabase/tests/rls/DESIGN.md`

The per-Wave RLS battery design doc now lives beside the batteries it governs, at
`supabase/tests/rls/DESIGN.md`.

It was here while `tests/rls/` was the scaffolding-era home. That left **two directories with
the same tail** — `tests/rls/` holding one file, `supabase/tests/rls/` holding all 52
batteries — which produced a silent instrument failure: `git show <ref>:tests/rls/<battery>`
returns **empty and exits clean**, because the short path is a real tree that simply does not
hold the batteries. No error, no signal.

This pointer exists so anything already citing the old path resolves rather than 404s.
History is preserved: `git log --follow supabase/tests/rls/DESIGN.md`.
