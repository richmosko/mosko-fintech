---
name: text-check-line-boundary-and-codepoint-mirror
description: Authoring a "single line, max N characters" CHECK — the Unicode line-boundary class in a Postgres bracket expression, and why a Zod mirror is not automatically equivalent
metadata:
  type: reference
---

Measured at `106` (SELF-352, 2026-09-05) on the local stack (PG 17.6).

**A "no embedded newline" fence written as LF-only does not cover its own rule.**
The ruled property is *single line*; a bare CR (U+000D) breaks a line in a renderer
and passes an LF-only test. The class is the Unicode line-boundary set — LF, VT, FF,
CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR. Postgres ARE accepts `\uXXXX`
character-entry escapes **inside a bracket expression**, so the pattern is written in
plain ASCII: `'[\u000A\u000B\u000C\u000D\u0085\u2028\u2029]'` in a
standard-conforming (non-`E''`) literal. All seven verified to match; the parity
example verified not to. Related: [[feedback_structural_fence_must_cover_the_same_class]].

**⚠ Do not let the escape sequences become real control characters in the file.**
Writing that pattern through the Write tool materialized LF / CR / NEL / U+2028 /
U+2029 as **actual control bytes inside the SQL literal**. It is semantically correct
and unreadable, ungreppable, and invisible in a diff. Build the literal with a script
(`python3` emitting `"\\u%04X"`) and then assert no character below 0x20 other than
`\n` — and none of 0x85 / 0x2028 / 0x2029 — survives anywhere in the file.

**A character-count CHECK and its Zod mirror are not automatically equivalent.**
`length(text)` counts **code points**; a JavaScript string's `.length` counts **UTF-16
code units**, so an astral character counts 2 there and 1 in the DB. Measured: 120
emoji code points = 480 bytes, accepted by `length(...) <= 120`. A Zod `.max(120)` on
`.length` is therefore equal-or-**stricter** and can never admit what the DB refuses —
the safe direction. A **byte**-counting mirror is looser for multi-byte text and is
the one form to avoid. State the direction in the CONTRACT block; the app owner cannot
derive it from the DDL.

**Name multi-CHECK constraints explicitly.** Three anonymous CHECKs on one column
become `_check`, `_check1`, `_check2`, which tells a caller nothing. Named, a
violation is legible — but a value breaking more than one is reported in constraint-
**NAME** order, so a battery leg asserting a specific name must violate that rule
alone. See [[reference_check_violation_reported_in_constraint_name_order]].
