---
name: feedback-backslash-u-escape-notation-gets-silently-converted
description: Typing literal "\uXXXX" (4-hex, lowercase u) notation in tool-call content (Write/Edit/Bash) gets silently converted into a real Unicode control/separator character before it lands in the file — discovered authoring SELF-352's single-line CHECK battery leg, 2026-09-05.
metadata:
  type: feedback
---

Authoring a pgTAP leg that needed to match the LITERAL ASCII text `
` / `` /
` ` etc. (the Postgres ARE regex-engine escape notation the migration's own CHECK
used, e.g. `'[
  ]'`), I typed that notation
directly into a Write tool call's file content. It did NOT land as the 6 literal ASCII
characters (backslash, u, 0, 0, 0, A) — it landed as an ACTUAL raw control/separator
character (a real LF, and real UTF-8-encoded NEL/LINE-SEPARATOR/PARAGRAPH-SEPARATOR
bytes), silently, with no error from the Write tool. Confirmed by `od -c` / a byte scan
(`\xc2\x85`, `\xe2\x80\xa8`, `\xe2\x80\xa9` present in the written file) after the fact —
not caught by re-reading the file with the Read tool, which round-trips the raw bytes
without flagging anything odd.

**The tell that surfaced it:** the Bash tool actively REJECTS a command containing
"control characters that would be hidden in the approval dialog" — so a heredoc/python
script built to inspect or fix the same content failed with `InputValidationError:
command contains control characters`, even though my own authored Python source used
only the safe `\uXXXX`-as-literal-text form. Write/Edit have no equivalent guard; they
silently accept and store whatever bytes actually arrive.

**What did NOT get corrupted:** `\n`, `\r` (2-char, lowercase, common escapes) and
`\U0001F600` (8-hex, UPPERCASE U) survived as literal ASCII text every time. Only the
4-hex **lowercase-u** form triggered the silent conversion — consistent with JSON's
`\uXXXX` unicode-escape syntax (tool-call parameters are JSON-marshalled under the
hood), which recognizes exactly that shape and no other.

**How to apply:** never type `\uXXXX` (4 hex digits, lowercase u) literal-escape
notation directly into ANY tool-call content — Write, Edit, or Bash — whether inside a
SQL string, a code comment, or prose describing a Unicode codepoint. Two safe
alternatives, both used to fix this file:
1. In prose: write "U+000A" (with a plus sign) or spell out the name (LF, NEL, LINE
   SEPARATOR) instead of the bare escape form.
2. In executable SQL that must produce/match the literal escape text: build it at
   runtime via `chr(92) || 'u000A'` (backslash from `chr()`, concatenated with the
   plain hex-digit string) — the file then never carries the dangerous notation at
   all. This is what the final (CATLINE1) leg in
   `supabase/tests/rls/106_owner_identification_rls.sql` does.

After any such fix, verify with a byte-level scan (not just Read/grep, which don't
flag control bytes specially) — `python3` reading the file as bytes and checking for
control-range bytes (excluding legitimate LF/CR/TAB) and the specific UTF-8 sequences
for NEL/LS/PS, before trusting the file is clean.
