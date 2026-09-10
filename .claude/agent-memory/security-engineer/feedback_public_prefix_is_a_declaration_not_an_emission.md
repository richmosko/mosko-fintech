---
name: public-prefix-is-a-declaration-not-an-emission
description: A PUBLIC_-prefixed env var is a declaration of browser-exposability, not proof the value is currently served — measure the framework's emission gate before resting a ruling on "it's already public"
metadata:
  type: feedback
---

A `PUBLIC_`-prefixed value is a **declaration** that a value MAY ship to the browser. It is
not evidence that it currently DOES. Measure the framework's emission gate before resting any
posture ruling on "this is already served to every visitor".

**Why:** on the `SUPABASE_ANON_KEY` naming-split review (2026-09-09) the inbound brief asserted
the anon key was "compiled into the browser bundle and served to every visitor" and asked me to
reclassify on that ground. Measured: `@sveltejs/kit` gates the SSR HTML inlining of `public_env`
on `client.uses_env_dynamic_public` (`src/runtime/server/page/render.js`, the
`properties.push(\`env: ...\`)` branch), so the object is inlined ONLY when CLIENT-side code
imports `$env/*/public`. In this repo the only importers were server-only files and `app.html`
carries no `%sveltekit.env%` — so the premise was false. Had I accepted it, the correct ruling
would have shipped on a rationale a future reader could refute, reopening the classification.

**How to apply:**
- Three measurements, all cheap: (1) `grep -rl -F '$env/dynamic/public' <src>` and
  `$env/static/public` — separately, and note which hits are server-only; (2) the framework's
  own emission branch in `node_modules`; (3) the HTML template for an env placeholder.
  ⚠ macOS BSD `grep` does not support `\|` alternation in BRE — it matches literally and
  returns the reassuring EMPTY answer. Use `-F` with one pattern per call, or `-E`.
- Rest the ruling on the **design model** of the credential (a Supabase anon key is a
  `role: anon` JWT, publishable by construction, RLS is the control), not on current emission.
  Emission is one client-side import away from flipping; the design model is stable.
- State the correction of the premise in the SAME message as the verdict, and say explicitly
  that the verdict does not depend on it. See [[feedback-name-your-own-errors]]-adjacent
  discipline and [[feedback_my_review_measurements_become_quoted_sources]].
- Related: a non-secret does not belong in `secrets-manifest.yml` at all — listing it asserts
  a blast radius that does not exist AND puts a production-tier NAME on developer machines that
  must hold a non-production value, which is the manifest's own local-dev rule 3 violated by the
  listing meant to protect it. See [[feedback_supplied_verbatim_text_ships_unfiltered]] for the
  commit-ready-note hand-off shape.
- ⚠ When removing an entry from a secrets contract, ask what the removal DELETES as a pointer.
  Here the manifest was the operator's only production-facing mention; removal had to be paired,
  same PR, with a non-secret injection list in the runbook, or the fix trades one boot failure
  for another. Same class as [[feedback_an_unblocking_fix_unmasks_every_input_class]].
