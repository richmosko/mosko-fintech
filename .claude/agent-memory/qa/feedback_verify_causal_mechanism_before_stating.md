---
name: feedback-verify-causal-mechanism-before-stating
description: A true result plus an unverified "why" is still a defect — architect caught a plausible-sounding but wrong causal explanation I attached to a correct green result (SELF-218 harness investigation, 2026-08-12).
metadata:
  type: feedback
---

Reported a battery result as green (correct) alongside a causal explanation for
why a *different* battery's failure didn't apply to it ("067 avoided the
`auth`-schema permission gap because it reads `auth.uid()` indirectly through
RLS policy evaluation"). The result was right; the mechanism was wrong and
unverified — I hadn't tested it, just reasoned it sounded plausible. An
architect teammate pushed back with the correct counter-reasoning (RLS quals
evaluate as the invoking role, so an indirect call should need the same schema
USAGE a direct one does) and asked for the real mechanism to be established
before the harness gets reused.

**Why this matters:** a plausible-sounding but false "why" attached to a true
"what" is not caught by re-checking the result — it's caught only by someone
independently reasoning about the mechanism, or by directly testing it. It cost
a round trip and would have shipped a wrong technical claim into a durable
record (a hand-off message, potentially a memory or doc) if unquestioned.

**How to apply:** when a result needs an explanation for *why* it diverged from
an expected/comparable case (not just *that* it did), treat the causal claim as
falsifiable and either (a) verify it with a minimal, targeted repro before
stating it, or (b) state the result without the mechanism and flag the "why" as
open/unverified. Do not fill an explanatory gap with the most plausible-sounding
story and present it with the same confidence as the measured result next to
it. [[feedback_instrument_cannot_observe_the_property]]
[[feedback_verifying_a_measurement_is_not_verifying_a_claim]]
