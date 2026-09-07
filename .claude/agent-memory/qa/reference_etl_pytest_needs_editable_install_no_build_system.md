---
name: etl-pytest-needs-editable-install-no-build-system
description: workers/etl's pyproject.toml declares no [build-system], so `uv sync` alone never makes `pfin_back_etl` importable (`ModuleNotFoundError: No module named 'pfin_back_etl'` at test collection) — the CI recipe (etl-ci.yml) always follows sync with `uv pip install -e .` before running pytest.
metadata:
  type: reference
---

Hit this during the SELF-362 P10 close-gate verdict (2026-09-07) trying to run cited
`workers/etl/tests/test_connection.py` / `test_monthly_report_cron.py` tests locally.
`uv sync --group test` (or `--all-groups`) installs pytest/pytest-cov/etc cleanly but
does NOT make the project's own `pfin_back_etl` package importable — every test file
starts `import pfin_back_etl as pfbe` and collection fails outright with
`ModuleNotFoundError`. Tried `PYTHONPATH=.` first; `uv run` does not honor it the way a
plain venv activation would.

**The real fix, found in `.github/workflows/etl-ci.yml`'s own comments** ("PACKAGE-IMPORT
NOTE: pyproject.toml declares no [build-system], so `uv sync` alone ... fails at
collection. We mirror the Dockerfile's `uv pip install -e .` to make the package
importable, then run pytest with `--no-sync`"):

```
cd workers/etl
uv sync --group test          # or --all-groups
uv pip install -e .           # the missing step — installs pfin_back_etl itself, editable
uv run --no-sync pytest ...   # --no-sync: don't let this re-trigger a sync that drops the editable install
```

**How to apply**: for ANY local pytest run against `workers/etl`, always run `uv pip
install -e .` after `uv sync` and before the first `pytest` invocation — check the
relevant CI workflow's own comments first when a project's test-run recipe isn't in its
README, since the workflow is often where the non-obvious step is actually documented.
