---
name: text-array-concat-literal-picks-array-operator
description: In plpgsql, `text[] || '<bare literal>'` resolves to the array||array operator and errors "malformed array literal" — use array_append or cast ::text
metadata:
  type: reference
---

`v_bad text[] := array[]::text[]; v_bad := v_bad || 'some message'` **fails at runtime** with `ERROR: malformed array literal: "some message"`.

**Why:** with a `text[]` on the left and an **unknown-typed literal** on the right, `||` resolves to the `anyarray || anyarray` operator (not `anyarray || anyelement`), so Postgres casts the string to `text[]` — parsing it as an array literal, which fails on any string without `{}`/with commas.

**The tell it hides behind:** the SAME code works when the RHS is a **known-type** expression — `v_bad || format(...)` or `v_bad || some_text_var` succeeds, because a known `text` value selects the element-append operator. So a mix of `format(...)` appends (pass) and bare-literal appends (fail) in one block looks inconsistent and is easy to misread as a data problem.

**Fix:** `array_append(v_bad, 'message')` (unambiguous), or `v_bad || 'message'::text`.

**How I hit it:** the migration-118 C8 apply-time assertion accumulated failure strings this way. The correct-role path and the `format()`-based membership leg passed; only the bare-literal legs (`createdb`, missing-`createrole`) errored. **The [[inversion-test-the-rationale-not-the-presence]] discipline is what caught it** — a structural assertion only ever run against a correct role would have shipped green and never fired on the violations it exists to catch. Related: [[reference_pgtap_isnt_passes_on_null]].
