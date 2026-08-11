"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for how `utils.fetch_cpi_df` REPORTS AND RETAINS the BLS periods
    published with no usable value.

    ⚠ FILENAME NOTE — THE DROP THIS FILE IS NAMED AFTER NO LONGER EXISTS.
    Written for BACKLOG §7.6 S20, when `fetch_cpi_df` dropped value-null rows
    and the defect was that it did so SILENTLY. S21 (2026-08-10) LIFTED that
    drop: those rows are the subject of `pfin.cpi_u_nonpublication` (063 /
    ADR-049) and could not reach any writer while the transport discarded them.
    The name is kept so this file stays findable as S20's discharge; read
    "drop" here as "the periods that used to be dropped".

    ⚠ WHAT THIS EXISTS FOR, RESTATED FOR THE POST-LIFT WORLD. BLS returns a
    period it has published nothing for with the literal token `"-"` — measured
    against the live API for **2025-M10**, a real non-publication. A
    `strict=False` cast turns that into null. `053` still cannot store it (NOT
    NULL plus a finiteness CHECK), so it is still dropped — but by
    `_map_cpi_u_index_df`, WHERE THE CONSTRAINT LIVES, not by the transport,
    where the drop destroyed the row for every consumer at once.

    The original defect was SILENCE: nothing at any layer distinguished "BLS
    published no value" from "we lost a row", and `pfin.cpi_u_index` asserts
    nothing about contiguity — so the gap was undetectable by construction and
    propagated into inflation-adjusted figures.

    ⚠ THE COUNTS HERE ARE OBSERVABILITY; THE GATE IS ELSEWHERE. S20's note said
    the reconciliation is the load-bearing half and that is still true — but a
    count this function computes about its own return value cannot see a row
    lost AFTER it returns, which is exactly what S21 found. The gate lives in
    `PFinBackend._prepare_cpi_u_frames` and is tested in
    `test_cpi_nonpublication_writer.py`. What is tested HERE is that the
    transport hands both halves onward, names the instance, carries the raw
    token, and counts unconditionally.

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

    # ⚠ THIS ASSERTION INVERTED AT S21, AND THE INVERSION IS THE POINT.
    # It used to read `len(df) == 2, "the valueless period must still be
    # dropped — 053 forbids it"`. What 053 forbids is STORING the period, and
    # the transport is not 053. Enforcing 053's constraint one layer early made
    # `pfin.cpi_u_nonpublication` unpopulable by any writer.
    assert len(df) == 3, "the valueless period must be RETAINED by the transport"
    assert df["series_value"].null_count() == 1
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

    assert len(df) == 4, "post-S21 the transport returns both halves"
    # ⚠ Match on "period(s) returned", not bare "returned": the per-row WARNING
    # also contains the word, and a looser selector would pick it up and assert
    # the count line's content against a line that never carries counts.
    recon = [m for m in (r.message for r in caplog.records) if "period(s) returned" in m]
    assert recon, "no reconciliation line — a systematic drop would be silent"
    line = recon[0]
    assert "4 period(s) returned" in line, line
    assert "2 with a published value" in line, line
    assert "2 published with no usable value" in line, line


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
    # ⚠ Match on "period(s) returned", not bare "returned": the per-row WARNING
    # also contains the word, and a looser selector would pick it up and assert
    # the count line's content against a line that never carries counts.
    recon = [m for m in (r.message for r in caplog.records) if "period(s) returned" in m]
    assert recon, "reconciliation must be unconditional"
    assert "0 published with no usable value" in recon[0], recon[0]
    assert not [r for r in caplog.records if r.levelno == logging.WARNING], (
        "a clean fetch must not warn — otherwise the warning stops meaning anything"
    )


@pytest.mark.unit
def test_a_valued_period_is_not_reported_as_valueless(stub_bls, caplog):
    """Non-vacuity: the fixture must be able to distinguish a valued period from
    a valueless one, or every assertion above could pass on a stub that reports
    everything."""
    stub_bls({"M05": "5.0", "M06": "-"})
    with caplog.at_level(logging.WARNING, logger="pfin_etl"):
        df = utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])
    joined = " ".join(r.message for r in caplog.records)
    assert "2025-06" in joined
    assert "2025-05" not in joined, "a VALUED period was reported as valueless"
    assert df["month"].to_list() == [5, 6]
    assert df["series_value"].to_list() == [5.0, None]


# ---------------------------------------------------------------------------
# The raw token — 063.published_value_raw's only possible source
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_the_raw_token_survives_the_float_cast(stub_bls):
    """⚠ `cast(pl.Float64, strict=False)` overwrites `value` IN PLACE, so the
    literal '-' was destroyed one layer before any consumer could see it —
    while `063.published_value_raw` is documented as "what the source actually
    emitted". The column is nullable, so had this been missed the table would
    have filled with legal, evidence-free rows and nothing would have noticed.
    """
    stub_bls({"M09": "324.800", "M10": "-"})
    df = utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])

    assert "series_value_raw" in df.columns
    raw = dict(zip(df["month"].to_list(), df["series_value_raw"].to_list()))
    assert raw[10] == "-", "the BLS non-publication token must survive verbatim"
    assert raw[9] == "324.800"


@pytest.mark.unit
def test_the_raw_token_is_named_in_the_warning(stub_bls, caplog):
    """The per-row line must carry the evidence, not just the period — a reader
    checking whether a gap is real needs to see what BLS actually sent."""
    stub_bls({"M10": "-"})
    with caplog.at_level(logging.WARNING, logger="pfin_etl"):
        utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])
    joined = " ".join(r.message for r in caplog.records)
    assert "'-'" in joined, joined
