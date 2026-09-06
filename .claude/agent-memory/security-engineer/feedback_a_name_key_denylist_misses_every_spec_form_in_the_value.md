---
name: a-name-key-denylist-misses-every-spec-form-in-the-value
description: Reviewing a denylist fence — enumerate the spec FORMS a value can take, and check whether a normalizer the fence already owns is applied to every input of that class
metadata:
  type: feedback
---

A denylist keyed on the dependency/identifier NAME catches only the naive shape. Enumerate the
spec FORMS the VALUE can take and walk each: registry range, `npm:`/alias protocol, direct tarball
URL, `git+`/`github:` shorthand, `file:`/`link:`, and the indirection fields
(`overrides` / `resolutions`) that redirect a benign name to the barred one.

**Why:** at PR #630 (SELF-350 A6, RT-22 PDF-worker manifest fence, 2026-09-05) my F-3 named the
`npm:` alias form specifically. DevOps fixed exactly that form — correctly and completely — and
four sibling forms stayed open. The sharpest one was self-inflicted: the fence had ALREADY written
`nameFromResolved()` to parse a package name out of a tarball URL, and applied it only to the
lockfile's `resolved` field, never to a manifest value of the identical shape. **A normalizer a
fence already owns, applied to one input surface and not the sibling surface of the same class, is
the highest-yield thing to grep for.** Also: `indexOf(marker)` in such a parser is a first-match
bug where `lastIndexOf` is wanted — a proxy URL with an earlier separator parses to the host.

**How to apply:** when reviewing any allow/denylist fence, (1) list the value grammars, not just
the key space, and probe each with a scratch case dir; (2) grep the fence for every parse/normalize
helper it defines and check each input surface it is NOT applied to; (3) always run a negative
control (a benign alias) so "catches everything" is distinguishable from "matches everything".
Report these as flag + fast-follow when the other defense-in-depth layers stand independently —
say so explicitly rather than escalating a low-reachability residual.

Related: [[feedback_measure_the_fence_regex_not_its_comment]],
[[feedback_probe_that_only_asserts_failure_goes_vacuous]],
[[feedback_hazard_mechanism_vs_reachability]].
