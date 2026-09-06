---
name: postgres-are-backslash-b-is-backspace-not-boundary
description: In Postgres's ARE regex flavor, \b is a literal backspace char escape, not a word boundary — \y is the boundary. A prosrc/structural regex leg using \b silently fails closed (0 matches) with no error.
metadata:
  type: feedback
---

Wrote a comment-stripped structural leg (SELF-345/110, FLAG-4 version-pin) matching
`'''payload_schema_version''\s*,\s*1\b'` against `pg_proc.prosrc` — modeled on 111's own
leg-7g convention. It matched 0 rows even though the literal text `'payload_schema_version',
1,` was unambiguously present, byte-for-byte, in the target string.

**Why:** Postgres's regex engine (ARE — Advanced Regular Expressions) reserves `\b` as an
ordinary character-escape meaning BACKSPACE (0x08), the same family as `\n`/`\t`, NOT a
zero-width word-boundary assertion like in PCRE/Perl/most other engines. The boundary
assertion in Postgres is spelled `\y` (word boundary), with `\B` for not-a-word-boundary and
`\m`/`\M` for beginning/end-of-word. `select 'test1,' ~ '1\b'` is FALSE; `select 'test1,' ~
'1\y'` is TRUE. There is no error — the pattern just never matches, so a `count(*) = 1` /
`count(*) != 1` structural leg fails CLOSED silently, reading as "the body doesn't have this"
when the real cause is a wrong escape in the TEST, not a defect in the body.

**How to apply:** any time a battery leg builds a regex against `prosrc` (or any installed-
definition text) with a trailing/leading digit-or-word boundary, use `\y`, never `\b`. Verify
any such leg on a real scratch clone before trusting a green (and treat an unexpected RED as
"check my own regex escape first," not only "the body must be wrong") — [[feedback_verify_causal_mechanism_before_stating]]
and [[feedback_scratch_db_pgtap_harness_gotchas]] both generalize here. I did not sweep the
rest of the tree for a pre-existing `\b` used as a boundary elsewhere — out of scope for the
brief that surfaced this; worth a grep (`\\\\b` inside a regex string literal, not inside an
`E'...'` string where different escaping rules apply) if this class of leg gets reused.
