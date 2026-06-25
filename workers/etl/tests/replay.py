"""
RT-15 parity fixture — record-replay loader for the ETL integration tier.

Purpose
-------
Make `pfin_back_etl`'s integration tests deterministic and credential-free by
replaying frozen *synthetic* BLS + FMP HTTP responses instead of hitting live
APIs. No production data, no PII, no real API keys — see the central governance
README at `tests/fixtures/parity/README.md`.

Seams replayed
--------------
- BLS CPI:  `utils.fetch_cpi_df` -> `requests.post("https://api.bls.gov/...")`.
            Patched at `pfin_back_etl.utils.requests.post`.
- FMP:      `PFinFMP.fetch_fmp_df(fmp_func, **kwargs)` calls `fmp_func(...)` and
            reads `rsp.json()`. Patched by substituting the `fmp_func` with a
            stub returning a `_ReplayResponse`.

Determinism discipline
----------------------
Payloads are frozen JSON artifacts under `tests/fixtures/replay/`. The
external-service-internal-state surface (BLS/FMP) is fully isolated from the
assertion surface: a test that uses these helpers never makes a network call and
never depends on a clock or random seed.

Wiring status (Phase 5 Step 4 W3-A)
-----------------------------------
This module is the **reviewable record-replay pattern**. It is intentionally a
plain helper (not yet exposed as autouse `conftest.py` fixtures, and no new
`replay` pytest marker is registered in `pyproject.toml`) so Sec + team-lead can
review the posture before it is wired into the suite. Proposed follow-up once
ratified:
  - register a `replay` marker in `pyproject.toml [tool.pytest.ini_options]`,
  - expose `bls_replay` / `fmp_replay` fixtures from `conftest.py`.
The DB-half (ephemeral Supabase `pfin.*` seed) remains HELD pending the
`supabase/` scaffold decision.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_REPLAY_DIR = Path(__file__).parent / "fixtures" / "replay"


def load_replay(name: str) -> Any:
    """Load a frozen synthetic replay payload by stem name (e.g. "bls_cpi")."""
    path = _REPLAY_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(
            f"replay payload {name!r} not found at {path}. "
            "Available synthetic payloads are governed by "
            "tests/fixtures/parity/README.md."
        )
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


class _ReplayResponse:
    """Minimal stand-in for a `requests.Response` — replays a frozen payload.

    Implements the surface the ETL touches across both seams:
      - `.json()`           — FMP path (`fetch_fmp_df` reads `rsp.json()`).
      - `.text` / `.content`— BLS path (`utils.fetch_cpi_df` does
                              `json.loads(p.text)`, NOT `p.json()`).
      - `.status_code`.
    """

    def __init__(self, payload: Any, status_code: int = 200) -> None:
        self._payload = payload
        self.status_code = status_code

    def json(self) -> Any:
        return self._payload

    @property
    def text(self) -> str:
        return json.dumps(self._payload)

    @property
    def content(self) -> bytes:
        return self.text.encode("utf-8")


def install_bls_replay(monkeypatch, payload_name: str = "bls_cpi") -> None:
    """Patch the BLS `requests.post` seam to return a synthetic CPI response.

    Usage:
        from tests import replay
        replay.install_bls_replay(monkeypatch)
        df = backend.update_table_cpi()   # no network, deterministic
    """
    payload = load_replay(payload_name)

    def _fake_post(*_args, **_kwargs):
        return _ReplayResponse(payload)

    # utils.py does `import requests` then `requests.post(...)`.
    import pfin_back_etl.utils as _utils

    monkeypatch.setattr(_utils.requests, "post", _fake_post)


def make_fmp_func(payload_name: str):
    """Return a stub `fmp_func` for `PFinFMP.fetch_fmp_df` that replays a payload.

    `fetch_fmp_df(fmp_func, **kwargs)` calls `fmp_func(**kwargs)` and reads
    `.json()` on the result. This returns a callable matching that contract.
    """
    payload = load_replay(payload_name)

    def _fmp_func(*_args, **_kwargs):
        return _ReplayResponse(payload)

    _fmp_func.__name__ = f"replay_{payload_name}"
    return _fmp_func
