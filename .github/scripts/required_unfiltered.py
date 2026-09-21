#!/usr/bin/env python3
"""Assert that every workflow backing a required status check is unskippable.

Backs the `required-unfiltered` job in .github/workflows/security-scan.yml.

WHY THIS EXISTS
---------------
GitHub: "If a workflow is skipped due to path filtering, branch filtering or a
commit message, then checks associated with that workflow will remain in a
'Pending' state." A required status check that never reports does not fail — it
hangs, and the PR is unmergeable with no red anywhere. Both doc-only PRs merged on
2026-08-10 (#388, #390) would have deadlocked had the three path-filtered contexts
been required at the time.

So the rule this encodes is: a workflow backing a required context must have no
`paths:` / `paths-ignore:` filter, and the backing job must have no job-level `if:`.

The `if:` half is the subtler one. A conditionally-skipped JOB reports "Success" to
branch protection (unlike a skipped workflow, which hangs). That is exactly what
makes it dangerous: the green is emitted by GitHub's skip semantics and is
indistinguishable in the checks list from a real pass. A required check that is
green because it did not run is unfalsifiable — permanently green and proving
nothing. This script refuses that shape for required jobs.

WHY A YAML PARSE AND NOT grep
-----------------------------
A grep for `paths:` cannot tell a real filter from the string appearing in a
comment — and the headers of db-tests.yml and worker-ci.yml both discuss `paths:`
at length, precisely because they explain why they must not have one. A grep fence
would go red on its own documentation. Structure has to be read as structure.

RUN IT LOCALLY — the same command CI runs:
    python3 .github/scripts/required_unfiltered.py
    python3 .github/scripts/required_unfiltered.py --selftest

Exit 0 = clean. Exit 1 = violation, or the check could not be performed. There is no
third outcome: an undetermined result is not a passing result.
"""

import sys
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO_ROOT, ".github", "required-contexts.tsv")
WORKFLOW_DIR = os.path.join(REPO_ROOT, ".github", "workflows")

# The trigger events a PR check can arrive from. `paths` under any of these can
# suppress the run. Other keys under `on:` (schedule, workflow_dispatch, ...) cannot
# carry a paths filter at all, so they are not examined.
FILTERABLE_EVENTS = ("pull_request", "pull_request_target", "push")
FILTER_KEYS = ("paths", "paths-ignore")

# Step-level `if:` expressions that are legitimate CLEANUP conditionals and must keep
# passing — `if: always()` on a stack-teardown step is correct and common (both
# db-tests.yml and worker-ci.yml have one).
#
# ⚠ EXACT MATCH, NOT SUBSTRING, AND THAT IS THE WHOLE POINT. `always() &&
# contains(..., 'supabase/')` CONTAINS an allowed conditional while being exactly the
# path-gate this fence exists to reject — a filter wearing cleanup clothing. A
# substring test would pass it. So a compound expression is rejected even when one of
# its terms is allowed. If a genuine compound cleanup conditional is ever needed, add
# it here deliberately, with a self-test case — do not loosen the matching rule.
CLEANUP_CONDITIONALS = frozenset(
    ("always()", "success()", "failure()", "cancelled()")
)


def _normalize_expr(expr):
    """Strip `${{ }}` wrapping and whitespace so `${{ always() }}` == `always()`."""
    text = str(expr).strip()
    if text.startswith("${{") and text.endswith("}}"):
        text = text[3:-2].strip()
    return "".join(text.split()).lower()


def check_workflow(doc, job_id, expected_context=None):
    """Return a list of violation strings for `job_id` within parsed workflow `doc`.

    Empty list == compliant. Every distinguishable failure gets its own message:
    a fence whose red does not say what is wrong is a fence that gets discounted.

    `expected_context`, when given, is the manifest's own context field for this
    row -- checked byte-exact against the job's own rendered `name:` (falling
    back to the job id, GitHub's own default when no `name:` is set). Sec, PR
    #855 review: `required_unfiltered.py` previously checked only that a
    manifested job EXISTS and is UNSKIPPABLE -- never that the manifest's
    context STRING actually matches what that job reports. A context matching
    no job's name never reports at all, hangs Pending forever at sync time, and
    is recoverable only by an F/CTO branch-protection edit -- proven live by
    appending ` XYZZY-NOT-A-REAL-CONTEXT` to a manifest row and observing this
    checker still print `OK` for it before this check existed.
    """
    violations = []

    # PyYAML parses the bare key `on` as the BOOLEAN True (YAML 1.1 treats on/off/
    # yes/no as booleans). A previous cut of this script read doc.get("on") and found
    # None on every real workflow, so it reported zero violations for every input —
    # a fence that had silently stopped looking at anything. Check both keys.
    on = doc.get("on", doc.get(True))
    if on is None:
        violations.append("workflow has no `on:` trigger block (or it failed to parse)")
        return violations

    # `on: push` (a bare string) or `on: [push, pull_request]` (a list) carry no
    # filters by construction — compliant, nothing to inspect.
    if isinstance(on, dict):
        for event in FILTERABLE_EVENTS:
            spec = on.get(event)
            if not isinstance(spec, dict):
                continue
            for key in FILTER_KEYS:
                if key in spec:
                    violations.append(
                        f"`on.{event}.{key}` is set — a filtered workflow's required "
                        f"context hangs Pending forever on a non-matching PR"
                    )

    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        violations.append("workflow has no `jobs:` block (or it failed to parse)")
        return violations

    if job_id not in jobs:
        violations.append(
            f"job `{job_id}` does not exist in this workflow — the manifest names a "
            f"job that is not here, so nothing is being enforced for that context"
        )
        return violations

    job = jobs[job_id] or {}

    if expected_context is not None:
        rendered_name = job.get("name", job_id)
        if rendered_name != expected_context:
            violations.append(
                f"manifest context {expected_context!r} does not byte-exactly "
                f"match job `{job_id}`'s own rendered name {rendered_name!r} -- "
                f"this context will never report, hangs Pending forever once "
                f"required, and deadlocks every PR. Fix the manifest row or the "
                f"job's `name:` so they agree exactly."
            )

    if "if" in job:
        violations.append(
            f"job `{job_id}` carries a job-level `if:` — a skipped job reports "
            f"SUCCESS to branch protection, so this context could go green without "
            f"ever running"
        )

    # `continue-on-error` at JOB level: the job's failure stops failing the check.
    # Distinct hazard from a skip — here the battery RAN, FAILED, and the context is
    # still green. Nothing about the run looks unusual.
    if job.get("continue-on-error"):
        violations.append(
            f"job `{job_id}` sets `continue-on-error` — the job can FAIL and still "
            f"report green, so this context would survive a genuinely broken battery"
        )

    # STEP level. Both hazards recur one level below where a job-only checker reads,
    # and this is the level a real refactor reaches for: gating the expensive step is
    # a smaller-looking diff than gating the job, and it defeats a job-level check
    # completely. The job runs, reports success, and the work inside it never happened.
    steps = job.get("steps")
    if steps is None:
        # A job with no `steps:` is a `uses:` reusable-workflow call. Its guts are in
        # another file this checker does not follow, so it cannot assert anything
        # about them. Undetermined is not passing.
        if "uses" in job:
            violations.append(
                f"job `{job_id}` delegates to a reusable workflow (`uses:`) — this "
                f"checker cannot see inside it, so it cannot assert the job is "
                f"unskippable. Inline the job or extend this checker before making "
                f"this context required"
            )
    elif isinstance(steps, list):
        for idx, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            label = step.get("name") or step.get("uses") or f"index {idx}"
            if "if" in step:
                expr = _normalize_expr(step["if"])
                if expr not in CLEANUP_CONDITIONALS:
                    violations.append(
                        f"step {label!r} in job `{job_id}` carries `if: {step['if']}` "
                        f"— a conditional step is silently skipped while the job "
                        f"still reports success, so the context can go green with "
                        f"the real work never having run. Only bare "
                        f"{sorted(CLEANUP_CONDITIONALS)} are permitted (cleanup)"
                    )
            if step.get("continue-on-error"):
                violations.append(
                    f"step {label!r} in job `{job_id}` sets `continue-on-error` — "
                    f"that step can FAIL while the job reports green"
                )

    return violations


# ---------------------------------------------------------------------------
# SELF-TEST — asserts on the VIOLATIONS RETURNED, never on exit status.
#
# This script is fail-closed, which is exactly what hides a broken checker: if
# check_workflow() were gutted to `return []`, every real workflow would pass and
# the job would be green forever, looking indistinguishable from a working fence.
# Asserting "the clean case exits 0" would therefore verify nothing at all — only
# the BAD cases discriminate, and only by their returned content.
#
# Encoding is validation: this is the mechanical version of "make it go red on
# purpose", run on every CI invocation rather than once by hand at review time.
# ---------------------------------------------------------------------------
CLEAN = {
    "on": {"pull_request": {"branches": ["main"]}, "push": {"branches": ["main"]}},
    "jobs": {"good": {"runs-on": "ubuntu-latest"}},
}

SELFTEST_CASES = [
    # (label, doc, job_id, expected_context, must_be_flagged)
    # expected_context=None means "not under test here" -- the byte-equality
    # check is skipped for that case, same as calling check_workflow() without
    # the argument at all (main()'s pre-#855 call shape).
    ("clean workflow", CLEAN, "good", None, False),
    (
        "paths under pull_request",
        {
            "on": {"pull_request": {"branches": ["main"], "paths": ["src/**"]}},
            "jobs": {"good": {"runs-on": "ubuntu-latest"}},
        },
        "good",
        None,
        True,
    ),
    (
        "paths-ignore under push",
        {
            "on": {"push": {"branches": ["main"], "paths-ignore": ["docs/**"]}},
            "jobs": {"good": {"runs-on": "ubuntu-latest"}},
        },
        "good",
        None,
        True,
    ),
    (
        "job-level if:",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"runs-on": "ubuntu-latest", "if": "false"}},
        },
        "good",
        None,
        True,
    ),
    ("job named in manifest is absent", CLEAN, "nonexistent", None, True),
    # `on` parsed as the YAML boolean True — the real-world shape, since PyYAML does
    # this to every workflow file in this repo. If this case ever stops being
    # flagged-or-clean correctly, the checker has stopped reading real workflows.
    (
        "boolean-True `on` key (YAML 1.1 on/off)",
        {True: {"pull_request": {"paths": ["x/**"]}}, "jobs": {"good": {}}},
        "good",
        None,
        True,
    ),
    ("missing `on` block entirely", {"jobs": {"good": {}}}, "good", None, True),
    # --- Step/job-level evasions (Sec F-1, 2026-08-10). A job-only checker passed
    # all of these. Each discriminator below gets its own probe, because an added
    # check with no probe is the next gutted checker.
    (
        "step-level if: (the rejected remedy, one level down)",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {
                "good": {
                    "steps": [
                        {"name": "heavy", "if": "contains(github.event.pull_request.changed_files, 'supabase/')"}
                    ]
                }
            },
        },
        "good",
        None,
        True,
    ),
    (
        "step-level if: always() — CLEANUP, must stay green",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"steps": [{"name": "teardown", "if": "always()"}]}},
        },
        "good",
        None,
        False,
    ),
    (
        "step-level if: ${{ always() }} — wrapped cleanup, must stay green",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"steps": [{"name": "teardown", "if": "${{ always() }}"}]}},
        },
        "good",
        None,
        False,
    ),
    (
        "compound always() && <filter> — a filter wearing cleanup clothing",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {
                "good": {
                    "steps": [
                        {"name": "heavy", "if": "always() && contains(github.event.head_commit.message, 'db')"}
                    ]
                }
            },
        },
        "good",
        None,
        True,
    ),
    (
        "continue-on-error at JOB level",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"continue-on-error": True, "steps": [{"name": "x"}]}},
        },
        "good",
        None,
        True,
    ),
    (
        "continue-on-error at STEP level",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"steps": [{"name": "x", "continue-on-error": True}]}},
        },
        "good",
        None,
        True,
    ),
    (
        "continue-on-error: false is not a violation",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"continue-on-error": False, "steps": [{"name": "x", "continue-on-error": False}]}},
        },
        "good",
        None,
        False,
    ),
    (
        "job delegating to a reusable workflow (opaque to this checker)",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"uses": "./.github/workflows/other.yml"}},
        },
        "good",
        None,
        True,
    ),
    # --- 16th probe (Sec, PR #855 review, F-1): the manifest-context-vs-job-name
    # byte-equality check. Proven both directions -- a mismatch (even a single
    # appended sentinel) must flag; an exact match must not.
    (
        "manifest context byte-exact match — must NOT flag",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"name": "Some real job name", "steps": [{"name": "x"}]}},
        },
        "good",
        "Some real job name",
        False,
    ),
    (
        "manifest context with an appended sentinel — must flag (Sec's own probe)",
        {
            "on": {"pull_request": {"branches": ["main"]}},
            "jobs": {"good": {"name": "Some real job name", "steps": [{"name": "x"}]}},
        },
        "good",
        "Some real job name XYZZY-NOT-A-REAL-CONTEXT",
        True,
    ),
]


def run_selftest():
    failures = []
    for label, doc, job_id, expected_context, must_flag in SELFTEST_CASES:
        got = check_workflow(doc, job_id, expected_context=expected_context)
        if bool(got) != must_flag:
            failures.append(
                f"  case {label!r}: expected "
                f"{'a violation' if must_flag else 'no violation'}, got {got!r}"
            )
    if failures:
        print("FATAL: the required-unfiltered checker does not discriminate.")
        print("\n".join(failures))
        print(
            "       Every case below would still have been reported the same way, so\n"
            "       the fence had stopped distinguishing filtered from unfiltered\n"
            "       while continuing to look like a working fence."
        )
        return 1
    print(f"OK: checker discriminates all {len(SELFTEST_CASES)} probed shapes.")
    return 0


def parse_manifest(path):
    """Yield (workflow_file, job_id, context_name). Malformed lines are fatal."""
    entries = []
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 3 or not all(f.strip() for f in fields):
                raise ValueError(
                    f"{path}:{lineno}: expected 3 tab-separated non-empty fields "
                    f"(workflow, job id, context name), got {len(fields)}: {line!r}. "
                    f"A manifest line that does not parse is a required context that "
                    f"is not being checked — that is fatal, not skippable."
                )
            entries.append(tuple(f.strip() for f in fields))
    return entries


def main():
    if "--selftest" in sys.argv:
        return run_selftest()

    if run_selftest() != 0:
        return 1

    try:
        import yaml
    except ImportError:
        print("FATAL: PyYAML is not importable, so no workflow can be parsed.")
        print("       This check cannot be performed, and a check that cannot be")
        print("       performed is not a check that passed. Install with `pip install pyyaml`.")
        return 1

    try:
        entries = parse_manifest(MANIFEST)
    except FileNotFoundError:
        print(f"FATAL: manifest {MANIFEST} is missing. Nothing is being enforced.")
        return 1
    except ValueError as exc:
        print(f"FATAL: {exc}")
        return 1

    if not entries:
        print(f"FATAL: manifest {MANIFEST} lists zero contexts.")
        print("       An empty manifest passes vacuously, which is the exact shape")
        print("       this fence exists to prevent. If every context were genuinely")
        print("       de-required, delete this fence deliberately instead.")
        return 1

    failed = False
    cache = {}
    for wf_file, job_id, context in entries:
        path = os.path.join(WORKFLOW_DIR, wf_file)
        if path not in cache:
            try:
                with open(path, encoding="utf-8") as fh:
                    cache[path] = yaml.safe_load(fh)
            except FileNotFoundError:
                print(f"FAIL  {context}")
                print(f"      workflow .github/workflows/{wf_file} does not exist.")
                failed = True
                cache[path] = None
                continue
            except yaml.YAMLError as exc:
                print(f"FAIL  {context}")
                print(f"      .github/workflows/{wf_file} is not parseable YAML: {exc}")
                failed = True
                cache[path] = None
                continue
        doc = cache[path]
        if doc is None:
            continue
        violations = check_workflow(doc, job_id, expected_context=context)
        if violations:
            failed = True
            print(f"FAIL  {context}")
            print(f"      .github/workflows/{wf_file}  (job: {job_id})")
            for v in violations:
                print(f"      - {v}")
        else:
            print(f"ok    {context}")

    if failed:
        print()
        print("FATAL: a workflow backing a required status check can be skipped.")
        print("       Fix the workflow (remove the filter / the job-level `if:`), or —")
        print("       if the context is genuinely no longer required — remove its line")
        print("       from .github/required-contexts.tsv in the same change that")
        print("       removes it from branch protection.")
        return 1

    print()
    print(f"OK: all {len(entries)} manifested required contexts are unskippable.")
    print("NOTE: this proves only that what IS listed is unfiltered. It cannot prove")
    print("      the manifest matches branch protection — that read needs admin scope")
    print("      CI's GITHUB_TOKEN does not have. See the header of")
    print("      .github/required-contexts.tsv for the F/CTO-run sync command.")
    print("NOTE: required contexts are ONE of five branch-protection fields that")
    print("      matter, and this check sees only that one. A required context gates")
    print("      the merge of a PULL REQUEST; a direct push opens no PR, so no context")
    print("      is ever evaluated against one. What resists a force-push is")
    print("      allow_force_pushes=false — a field no CI check can observe. Do not")
    print("      read this green as a statement about push safety.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
