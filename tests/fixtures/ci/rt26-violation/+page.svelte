<!--
  tests/fixtures/ci/rt26-violation/+page.svelte

  DELIBERATELY OUT OF ALLOWLIST — RT-26 golden-test fixture per ARCH §6 Phase 5
  detail item (c). A client-side Svelte page in a routes-tree-shape path that
  references SUPABASE_SERVICE_ROLE_KEY. This file's path is NOT on the ADR-016 D1
  allowlist registry, so the RT-26 fence MUST report violation against it.

  CI inversion check (per Sec rubric (b)1 + ARCH §6.1 RT-26 row):
    The RT-26 fence script MUST flag this fixture at every CI invocation. If the
    fence reports clean, CI fails closed — the fence is broken.

  Fixture path discipline (per Sec rubric (b)3 + agent-def):
    This file lives at tests/fixtures/ci/rt26-violation/ and is excluded from the
    V1 web-app build context via .dockerignore at repo root. SvelteKit does NOT
    discover this path as a real route — it's outside src/.

  DO NOT use this Svelte component as a template for any production work.
-->
<script>
  // SUPABASE_SERVICE_ROLE_KEY referenced verbatim (not a mock variable name)
  // per Sec rubric (b)1 flag for "literal mock variable name" failure mode.
  // In a real client-side Svelte page, this would leak service_role to the
  // browser bundle — the failure mode the RT-26 fence is designed to catch.
  const k = import.meta.env.SUPABASE_SERVICE_ROLE_KEY;
</script>

<h1>RT-26 violation fixture</h1>
<p>This page deliberately references SUPABASE_SERVICE_ROLE_KEY to exercise the
fence's inversion-mode check. It is never rendered or built in production.</p>
