#!/usr/bin/env python3
#
# tz-sweep-identical — the TimeZone role-sweep query drift fence (R3 Part A).
#
# WHAT IT ENFORCES, stated as the artifact's own claim so the fence cannot assert more
# than the thing it fences:
#
#   docs/deployment-runbook.md §4.1 says of its catalog sweep:
#     "Kept query-identical — token-for-token, modulo indentation — to (T3) in
#      supabase/tests/01_session_timezone.sql, so the two cannot drift."
#   supabase/tests/01_session_timezone.sql (T3) says of itself:
#     "the runbook §4.1 sweep as an executable assertion, kept query-identical to the
#      runbook so the two cannot drift."
#
#   THIS FENCE ENFORCES EXACTLY THAT CLAIM AND NOTHING STRONGER: the two query texts are
#   identical after whitespace normalization. It deliberately does NOT assert byte
#   identity, and it deliberately does NOT assert that the query contains any particular
#   clause. Both would be asserting more than the artifacts claim, and a fence that reds
#   on something the artifact never promised is a false red — which is how fences get
#   deleted rather than fixed.
#
# WHY WHITESPACE NORMALIZATION IS REQUIRED AND NOT A WEAKENING:
#   The two copies live in structurally different contexts and CANNOT be byte-identical:
#     - the runbook copy is a shell double-quoted argument to `psql -Atc`;
#     - the (T3) copy is a `$$ … $$` dollar-quoted SQL literal inside `is_empty(...)`.
#   Their indentation differs by construction. MEASURED at build time: token-identical,
#   byte-different. A byte-compare fence would have RED on day one and been deleted or
#   neutered within a week. Normalizing whitespace is what makes the enforced property
#   equal to the claimed property.
#
# WHY THIS FENCE EXISTS AT ALL — the divergence is not hypothetical:
#   The two copies HAD already drifted when the claim was written. The runbook copy
#   lacked BOTH `s.setrole <> 0` (so it returned a row against a correctly pinned
#   database and STOPped a correct deploy on 061's own pin) and the `unnest` + anchored
#   `c ilike 'timezone=%'` form (so it printed the whole `setconfig` array — including
#   `app.settings.jwt_secret`, the LIVE JWT SIGNING SECRET — into the deploy operator's
#   terminal, the Coolify deploy log, and any Discord notification body). Both were found
#   by RUNNING the sweep, not by reading it, and fixed by adopting (T3)'s form. The claim
#   "kept query-identical so the two cannot drift" was therefore FALSE AT THE MOMENT IT
#   WAS WRITTEN, held only by prose. Prose is not a fence. This is the fence.
#
# WHAT A RED MEANS:
#   The deployment runbook's operator-facing sweep and the CI assertion that proves the
#   sweep's property have diverged. One of them is now checking something the other is
#   not. Fix by making them identical again — and prefer changing the RUNBOOK to match
#   (T3), because (T3) is the copy that executes in CI and is therefore the copy that has
#   been measured.
#
# EXTRACTION-VALIDITY GUARD (deliberate, and narrower than a content assertion):
#   If either anchor is not found, or the extracted text does not mention
#   `pg_db_role_setting`, this fence exits 1 — NOT 0. A fence that cannot locate the thing
#   it compares must fail closed; comparing "" to "" and reporting green is the exact
#   defect class this whole surface exists to remove. Note this guards the EXTRACTION
#   (did I find the query?), not the QUERY (does it contain the right clauses?) — a
#   distinction that keeps the fence aligned with the claim above. A rewrite that moved
#   the sweep off `pg_db_role_setting` entirely would red here, which is correct: a change
#   of that magnitude should force someone to look at this fence.
#
# Dual-mode via args (mirrors fence-rt22/rt26/tbc/secrets-nonoverlap/dedup-hash):
#   PRODUCTION — no args: the real runbook vs the real test file → expect exit 0.
#   INVERSION  — golden fixtures → expect exit 1 (semantic) or exit 0 (whitespace-only).
#
# Usage:
#   python3 scripts/ci/check-tz-sweep-identical.py
#     [--runbook <path>]   (default: docs/deployment-runbook.md)
#     [--test <path>]      (default: supabase/tests/01_session_timezone.sql)
#
# Run from the repo root (matches the other security-scan.yml fences).
#
# Exit codes:
#   0 — the two query texts are token-identical (modulo indentation).
#   1 — drift, OR extraction failed (fail-closed).
#   2 — argument / environment error (a named file is missing).

import argparse
import difflib
import re
import sys

DEFAULT_RUNBOOK = "docs/deployment-runbook.md"
DEFAULT_TEST = "supabase/tests/01_session_timezone.sql"

# Structural anchors, deliberately NOT content anchors: anchoring on the query text itself
# would make the fence blind to exactly the drift it exists to catch (both copies could
# change in lockstep away from the anchor and still "match").
RUNBOOK_ANCHOR = re.compile(r'psql\s+"\$PROD_DB_URL"\s+-Atc\s*\\')
TEST_ANCHOR = re.compile(r"select\s+is_empty\(")

SANITY_TOKEN = "pg_db_role_setting"


def normalize(text: str) -> str:
    """Collapse every whitespace run to a single space and trim.

    This is the whole of the normalization, and it is exactly what "token-for-token,
    modulo indentation" means. It is intentionally NOT case-folding, NOT punctuation-
    stripping, and NOT comment-stripping — each of those would let a real semantic
    difference through.
    """
    return re.sub(r"\s+", " ", text).strip()


def fail_closed(msg: str) -> "None":
    print(f"tz-sweep fence: EXTRACTION FAILED — {msg}", file=sys.stderr)
    print(
        "  Cannot verify the query-identical claim, so failing closed rather than "
        "reporting green.",
        file=sys.stderr,
    )
    print(
        "  If the surrounding formatting changed legitimately, update this fence's "
        "anchors in the same commit.",
        file=sys.stderr,
    )
    sys.exit(1)


def require_unique_anchor(pattern, text: str, path: str, human: str):
    """Return the sole anchor match, failing closed on ZERO **or MORE THAN ONE**.

    The >1 case is not defensive padding — it is a measured hazard. These anchors select
    *which* block gets compared, and both files are ones people add blocks to: the runbook
    grew a step (1b) catalog query in the very next change after this fence was written,
    and the pgTAP file would grow a second `select is_empty(` the moment a (T4) is added.
    A second match would silently move the comparison to a DIFFERENT query, and the fence
    would then be confidently checking the wrong pair — green while the property it claims
    to guard went unexamined. Ambiguity must fail closed, not resolve to "the first one".
    """
    matches = list(pattern.finditer(text))
    if not matches:
        fail_closed(f"{path}: no `{human}` anchor found.")
    if len(matches) > 1:
        lines = [text[: m.start()].count("\n") + 1 for m in matches]
        fail_closed(
            f"{path}: `{human}` anchor is AMBIGUOUS — {len(matches)} matches "
            f"(lines {', '.join(str(n) for n in lines)}). "
            "The fence cannot tell which block is the sweep, so it will not guess. "
            "Keep exactly one such block, or update this fence's anchor in the same commit."
        )
    return matches[0]


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        print(f"FATAL: cannot read {path}: {exc}", file=sys.stderr)
        sys.exit(2)


def extract_runbook(text: str, path: str) -> str:
    """The sweep is the shell double-quoted argument following the `psql … -Atc \\` line."""
    m = require_unique_anchor(RUNBOOK_ANCHOR, text, path, 'psql "$PROD_DB_URL" -Atc \\')
    rest = text[m.end():]
    open_q = rest.find('"')
    if open_q == -1:
        fail_closed(f"{path}: found the -Atc anchor but no opening double quote after it.")
    close_q = rest.find('"', open_q + 1)
    if close_q == -1:
        fail_closed(f"{path}: unterminated double-quoted psql argument after the anchor.")
    return rest[open_q + 1:close_q]


def extract_test(text: str, path: str) -> str:
    """The (T3) query is the `$$ … $$` dollar-quoted literal after `select is_empty(`."""
    m = require_unique_anchor(TEST_ANCHOR, text, path, "select is_empty(")
    rest = text[m.end():]
    open_d = rest.find("$$")
    if open_d == -1:
        fail_closed(f"{path}: found `select is_empty(` but no opening `$$` after it.")
    close_d = rest.find("$$", open_d + 2)
    if close_d == -1:
        fail_closed(f"{path}: unterminated `$$` dollar-quoted literal after the anchor.")
    return rest[open_d + 2:close_d]


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--runbook", default=DEFAULT_RUNBOOK)
    ap.add_argument("--test", default=DEFAULT_TEST)
    args = ap.parse_args()

    runbook_raw = extract_runbook(read(args.runbook), args.runbook)
    test_raw = extract_test(read(args.test), args.test)

    for label, path, raw in (
        ("runbook", args.runbook, runbook_raw),
        ("test", args.test, test_raw),
    ):
        if SANITY_TOKEN not in raw:
            fail_closed(
                f"{path}: the extracted {label} text does not mention `{SANITY_TOKEN}` — "
                "the anchor matched but the extraction is not the sweep query."
            )

    runbook_norm = normalize(runbook_raw)
    test_norm = normalize(test_raw)

    if runbook_norm == test_norm:
        print(
            "tz-sweep fence: the runbook §4.1 sweep and (T3) are query-identical "
            "(token-for-token, modulo indentation)."
        )
        print(f"  runbook : {args.runbook}")
        print(f"  test    : {args.test}")
        print(f"  {len(runbook_norm)} normalized chars, identical.")
        return 0

    print("", file=sys.stderr)
    print(
        "tz-sweep fence: DRIFT — the runbook §4.1 catalog sweep and (T3) in the pgTAP "
        "suite are no longer the same query.",
        file=sys.stderr,
    )
    print("", file=sys.stderr)
    print(f"  runbook ({args.runbook}):", file=sys.stderr)
    print(f"    {runbook_norm}", file=sys.stderr)
    print(f"  test    ({args.test}):", file=sys.stderr)
    print(f"    {test_norm}", file=sys.stderr)
    print("", file=sys.stderr)
    print("  word-level difference:", file=sys.stderr)
    for line in difflib.unified_diff(
        runbook_norm.split(), test_norm.split(), "runbook", "test", n=2, lineterm=""
    ):
        print(f"    {line}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "  Both copies claim to be kept identical to the other. One of them is now "
        "checking something the other is not.",
        file=sys.stderr,
    )
    print(
        "  PREFER changing the RUNBOOK to match (T3): (T3) is the copy that executes in "
        "CI, so it is the copy that has been measured.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
