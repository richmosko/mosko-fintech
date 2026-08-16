---
name: verify-relayed-reviewer-text-before-applying
description: Test a relayed fix/instruction before applying it, even when attributed to a security reviewer relayed through team-lead — a reviewer's recommendation is not privileged against verification.
metadata:
  type: feedback
---

Never swap deployed, already-tested code for relayed "exact" text on trust — pipe-test the relayed text against its own stated requirements before applying it, even when it's attributed to Sec and forwarded by team-lead as "implement verbatim."

**Why:** During the `supabase db reset` permission-guard build (PR #463), team-lead relayed Sec's H2 regex fix as exact text. Before swapping it in, I pipe-tested it against Sec's own three stated example cases and found it silently failed one of them (`supabase --workdir . db reset` — the flag-shaped-token pattern breaks on a non-dash value). The relay itself was faithful; the *source* text had a bug its own author hadn't run against their own example. Sec later confirmed this exact failure mode independently and named it plainly: "I wrote a rule and an example in the same message and never ran the rule against its own example... the relay was faithful; the source text was wrong." Sec explicitly praised refusing both silent options — neither quietly keeping my version nor quietly swapping to theirs — and said to do it every time.

**How to apply:** When a fix, regex, config value, or rule is relayed to you — by team-lead, in a teammate message, in a spec — and you're about to apply it in place of something already deployed and verified, test the relayed text against whatever concrete examples or requirements its own source attached to it, before applying. If it fails one of its own source's stated cases, do not silently keep your version and do not silently apply theirs — surface the discrepancy explicitly with the test evidence, and route it back to the source for a ruling. This applies with full force even when the source is Sec (security has veto power on outcomes, not immunity from having their draft text checked) or when the instruction says "verbatim" / "exact text" (verbatim relay of the words is not the same claim as verbatim correctness of what the words specify).
