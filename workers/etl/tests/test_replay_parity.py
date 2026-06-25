"""
RT-15 parity — record-replay tier proof tests.

These exercise the synthetic record-replay fixtures end-to-end through the real
ETL fetch/parse path with NO network and NO credentials. They are the API-half
of the parity fixture; the DB-write half is held pending the supabase/ scaffold.

Governance + MUST-NOT discipline: tests/fixtures/parity/README.md (central).
"""

import polars as pl
import pytest

from pfin_back_etl.utils import fetch_cpi_df
from pfin_back_etl.core import PFinFMP


@pytest.mark.replay
def test_bls_cpi_replay_is_deterministic_and_offline(bls_replay):
    """fetch_cpi_df parses the synthetic BLS payload with no network/creds.

    `bls_replay` patches `utils.requests.post`; any api_key is accepted because
    the seam is replaced. Asserts the synthetic 3-row CPI shape round-trips
    through the real parse path.
    """
    df = fetch_cpi_df(
        api_key="not-a-real-key",
        startyear="2024",
        endyear="2024",
        series_id_lst=["CUUR0000SA0"],
    )

    assert df.height == 3  # three synthetic months
    assert "series_value" in df.columns
    assert "series_id" in df.columns
    assert df["series_id"].unique().to_list() == ["CUUR0000SA0"]
    # synthetic values are exactly 298 / 299 / 300
    assert sorted(df["series_value"].to_list()) == [298.0, 299.0, 300.0]


@pytest.mark.replay
def test_fmp_income_replay_snake_cases_offline(fmp_replay):
    """PFinFMP.fetch_fmp_df converts synthetic FMP columns to snake_case offline.

    `fmp_replay` is a factory: `fmp_replay("fmp_income_statement")` returns a
    replay `fmp_func` matching the `fetch_fmp_df(fmp_func, **kwargs)` contract.
    No FMP client construction / no API key required.
    """
    fmp = object.__new__(PFinFMP)
    fmp_func = fmp_replay("fmp_income_statement")

    result = fmp.fetch_fmp_df(fmp_func, symbol="ZZTEST")

    assert isinstance(result, pl.DataFrame)
    assert result.height == 2  # two synthetic quarters
    # camelCase -> snake_case conversion exercised on the real path
    assert "reported_currency" in result.columns
    assert "net_income" in result.columns
    assert "reportedCurrency" not in result.columns
    assert result["symbol"].unique().to_list() == ["ZZTEST"]
