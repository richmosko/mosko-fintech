"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for the BLS drop reconciliation in `utils.fetch_cpi_df`.

    ⚠ WHAT THIS EXISTS FOR. BLS returns a period it has published nothing for
    with the literal value `"-"` — measured against the live API for
    **2025-M10**, a real non-publication. A `strict=False` cast turns that into
    null and `drop_nulls` removes the row. **Storing it is impossible anyway**
    (`053` has NOT NULL plus a finiteness CHECK), so the drop is FORCED BY THE
    SCHEMA and is correct.

    The defect was that it was SILENT. Nothing at any layer distinguished "BLS
    published no value" from "we lost a row", and `pfin.cpi_u_index` asserts
    nothing about contiguity — so the gap is undetectable by construction and
    propagates into inflation-adjusted figures.

    ⚠ THE RECONCILIATION IS THE LOAD-BEARING HALF. A per-row warning alone
    would still be silent about a SYSTEMATIC drop: a future change that removed
    rows for a different reason would log nothing. Counting in and out catches
    the class; naming the period explains the instance. Both are tested, and
    the count test is deliberately written so it FAILS if only the per-row
    warning survives a refactor.

    `unit`-tier: the HTTP call is stubbed, so no network, no BLS key.
"""

import json
import logging

import pytest

from pfin_back_etl import utils

_SERIES = "CUUR0000SA0"


def _bls_payload(values_by_period):
    """A BLS v2 response shaped exactly like the live one."""
    return json.dumps(
        {
            "status": "REQUEST_SUCCEEDED",
            "Results": {
                "series": [
                    {
                        "seriesID": _SERIES,
                        "data": [
                            {
                                "year": "2025",
                                "period": period,
                                "periodName": "Month",
                                "value": value,
                                "footnotes": [{}],
                            }
                            for period, value in values_by_period.items()
                        ],
                    }
                ]
            },
        }
    )


@pytest.fixture
def stub_bls(monkeypatch):
    """Patch the HTTP seam. Returns a setter for the payload."""

    def _install(values_by_period):
        class _Resp:
            text = _bls_payload(values_by_period)

        monkeypatch.setattr(utils.requests, "post", lambda *a, **k: _Resp())

    return _install


# ---------------------------------------------------------------------------
# The instance — a named period with no published value
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_a_period_with_no_published_value_is_named_in_a_warning(stub_bls, caplog):
    """The real 2025-M10 shape: BLS returns the period, value is `"-"`."""
    stub_bls({"M09": "324.800", "M10": "-", "M11": "324.122"})
    with caplog.at_level(logging.WARNING, logger="pfin_etl"):
        df = utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])

    assert len(df) == 2, "the valueless period must still be dropped — 053 forbids it"
    warnings = [r.message for r in caplog.records if r.levelno == logging.WARNING]
    assert warnings, "the drop was silent — that is the defect this closes"
    assert any("2025-10" in m for m in warnings), (
        f"the warning must NAME the period; got {warnings}"
    )


@pytest.mark.unit
def test_the_warning_says_it_is_a_real_gap_not_a_fetch_failure(stub_bls, caplog):
    """⚠ The distinction the log exists to make.

    A reader seeing "dropped a row" reasonably suspects a fetch bug. The
    message must say the series genuinely has no value here, or it trades
    silence for a false alarm — which is worse, because it invites someone to
    "fix" a correct drop.
    """
    stub_bls({"M10": "-"})
    with caplog.at_level(logging.WARNING, logger="pfin_etl"):
        utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])
    joined = " ".join(r.message for r in caplog.records)
    assert "not a fetch failure" in joined.lower()


# ---------------------------------------------------------------------------
# The class — reconciliation counts
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_counts_are_reconciled_in_and_out(stub_bls, caplog):
    """⚠ THE LOAD-BEARING HALF, and it is tested separately on purpose.

    A future change that drops rows for a DIFFERENT reason would emit no
    per-row warning and would otherwise be as silent as the original defect.
    The reconciliation catches the class rather than the instance.
    """
    stub_bls({"M01": "1.0", "M02": "-", "M03": "3.0", "M04": "-"})
    with caplog.at_level(logging.INFO, logger="pfin_etl"):
        df = utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])

    assert len(df) == 2
    recon = [m for m in (r.message for r in caplog.records) if "returned" in m]
    assert recon, "no reconciliation line — a systematic drop would be silent"
    line = recon[0]
    assert "4 period(s) returned" in line, line
    assert "2 kept" in line, line
    assert "2 dropped" in line, line


@pytest.mark.unit
def test_reconciliation_is_emitted_even_when_nothing_is_dropped(stub_bls, caplog):
    """⚠ ANTI-VACUITY ON THE LOG ITSELF.

    If the reconciliation only appeared when something was dropped, its ABSENCE
    would be ambiguous — "nothing dropped" and "the logging broke" would look
    identical, which is the same indistinguishability the whole change exists
    to remove. It must be emitted unconditionally.
    """
    stub_bls({"M01": "1.0", "M02": "2.0"})
    with caplog.at_level(logging.INFO, logger="pfin_etl"):
        utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])
    recon = [m for m in (r.message for r in caplog.records) if "returned" in m]
    assert recon, "reconciliation must be unconditional"
    assert "0 dropped" in recon[0], recon[0]
    assert not [r for r in caplog.records if r.levelno == logging.WARNING], (
        "a clean fetch must not warn — otherwise the warning stops meaning anything"
    )


@pytest.mark.unit
def test_a_kept_period_is_not_reported_as_dropped(stub_bls, caplog):
    """Non-vacuity: the fixture must be able to distinguish kept from dropped,
    or every assertion above could pass on a stub that drops everything."""
    stub_bls({"M05": "5.0", "M06": "-"})
    with caplog.at_level(logging.WARNING, logger="pfin_etl"):
        df = utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])
    joined = " ".join(r.message for r in caplog.records)
    assert "2025-06" in joined
    assert "2025-05" not in joined, "a KEPT period was reported as dropped"
    assert df["month"].to_list() == [5]
