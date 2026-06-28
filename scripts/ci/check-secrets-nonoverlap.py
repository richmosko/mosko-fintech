#!/usr/bin/env python3
"""
check-secrets-nonoverlap.py — secrets-manifest CI/production non-overlap fence.

Phase 5 Step 8 (DevOps-owned; Sec-consult mandatory at manifest lock).

Catch criterion (fail-closed): the `ci_only` and `production_only` name-sets in
secrets-manifest.yml MUST be disjoint. A leaked CI secret must never grant
production access, and vice-versa (blast-radius containment).

Fails closed (exit 1) when:
  - the intersection of ci_only and production_only is NON-EMPTY, or
  - a name is duplicated within either set.
Fails on structural error (exit 2) when:
  - the manifest file is missing or unreadable,
  - YAML parsing fails,
  - either `ci_only` or `production_only` key is absent or not a list of strings.

Passes (exit 0) only when both sets are well-formed and disjoint.

Boring-choice justification: YAML is parsed with PyYAML (installed in the CI job)
rather than a hand-rolled bash/grep parser — deterministic structure handling is
the correct tool here, and the manifest is small. No novel CI machinery.

Usage:
  python3 scripts/ci/check-secrets-nonoverlap.py [path-to-manifest]
  (default path: secrets-manifest.yml at repo root)
"""

import sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment guard
    print("FATAL: PyYAML not available; cannot parse secrets-manifest. "
          "Install with `pip install pyyaml`. Failing closed.", file=sys.stderr)
    sys.exit(2)

DEFAULT_MANIFEST = "secrets-manifest.yml"
REQUIRED_KEYS = ("ci_only", "production_only")


def fail_struct(msg: str) -> "None":
    print(f"FATAL (manifest malformed): {msg} — failing closed.", file=sys.stderr)
    sys.exit(2)


def load_set(data: dict, key: str) -> list:
    if key not in data:
        fail_struct(f"required key '{key}' is absent")
    value = data[key]
    if value is None:
        # An explicitly-empty set (key: ) is allowed (disjoint-trivially), but
        # must be declared as a list, not left null — null is ambiguous.
        fail_struct(f"key '{key}' is null; declare an explicit list (use [] if empty)")
    if not isinstance(value, list):
        fail_struct(f"key '{key}' must be a list, got {type(value).__name__}")
    for item in value:
        if not isinstance(item, str) or not item.strip():
            fail_struct(f"key '{key}' contains a non-string / empty entry: {item!r}")
    return value


def main() -> int:
    manifest_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MANIFEST

    try:
        with open(manifest_path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        fail_struct(f"cannot read manifest at '{manifest_path}': {exc}")

    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        fail_struct(f"YAML parse error in '{manifest_path}': {exc}")

    if not isinstance(data, dict):
        fail_struct(f"top-level manifest must be a mapping, got {type(data).__name__}")

    ci_list = load_set(data, "ci_only")
    prod_list = load_set(data, "production_only")

    # Intra-set duplicate detection (a dup signals a copy-paste error).
    for label, items in (("ci_only", ci_list), ("production_only", prod_list)):
        seen = set()
        dups = sorted({x for x in items if x in seen or seen.add(x)})
        if dups:
            print(f"FAIL: duplicate name(s) within '{label}': {', '.join(dups)} — "
                  "failing closed.", file=sys.stderr)
            return 1

    ci_set = set(ci_list)
    prod_set = set(prod_list)
    overlap = sorted(ci_set & prod_set)

    if overlap:
        print("FAIL: secrets-manifest NON-OVERLAP invariant violated.", file=sys.stderr)
        print("      The following secret name(s) appear in BOTH ci_only and "
              "production_only:", file=sys.stderr)
        for name in overlap:
            print(f"        - {name}", file=sys.stderr)
        print("      A leaked CI secret must never grant production access. "
              "Rename the CI analogue to a distinct name (e.g. *_SANDBOX / *_TEST). "
              "Failing closed.", file=sys.stderr)
        return 1

    print(f"OK: secrets-manifest non-overlap holds — "
          f"{len(ci_set)} ci_only + {len(prod_set)} production_only, "
          f"intersection empty.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
