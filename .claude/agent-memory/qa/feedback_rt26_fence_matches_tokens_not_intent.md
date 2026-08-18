---
name: feedback-rt26-fence-matches-tokens-not-intent
description: On RT-26-fenced trees, never write the literal service-role key token in prose — even a comment ASSERTING its absence trips the CI fence, which matches tokens not intent
metadata:
  type: feedback
---

Wrote, in SELF-238's `nonReAllocation.tenant-isolation.server.test.ts` header
comment, a claim that neither `nonReAllocation.ts` nor `subcatMarketValue.ts`
references `SUPABASE_SERVICE_ROLE_KEY` — spelling out the literal token to be
precise about what I'd checked. The RT-26 CI fence (`docs/SECURITY/index.html`
/ [[ADR-016]]) went RED on that line. Team-lead: "the fence matches tokens not
intent (correctly — comment mentions are the rot path into real references)."
Backend reworded it to "the service-role key env var" on the branch; the
underlying inspection claim was correct and stands as written, only the
token-shaped surface was the problem.

**Why:** A grep-based security fence can't distinguish "this file uses X" from
"this file's comment says it doesn't use X" — both contain the literal
string. Allowing the token in prose-that-asserts-absence is exactly the seam
a REAL reference could later hide behind (a future editor changes the comment
context without noticing it's now a real reference, or copy-paste propagates
the literal token into a live import). The fence is deliberately blind to
intent for the same reason [[feedback_scope_the_grep_to_what_the_assertion_checks]]
argues the opposite discipline for MY OWN pgTAP/grep-based assertions (scope
the check to the executable body, not header prose) — same class of lesson,
opposite direction: there I own the instrument and must scope it correctly;
here I don't own the instrument (RT-26 is Sec/DevOps's fence) and must write
around its known blind spot instead.

**How to apply:** On any RT-26-fenced surface (or any other CI grep-fenced
surface), name a fenced credential/key by DESCRIPTION in prose — "the
service-role key env var," "the anon key," etc. — never spell out the literal
token, even inside a comment that asserts its ABSENCE. This applies to
structural/inspection claims in test file headers, ADR text, PR descriptions
committed to the repo — anywhere the literal string would land in a file the
fence scans. Only write the literal token where it is the actual, sanctioned
reference (the RT-26 allowlist's three endpoints) or in a context the fence
is configured to exclude.
