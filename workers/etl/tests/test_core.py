"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Unit tests for core ETL logic in pfin_back_etl.core.
    Tests the DataFrame manipulation methods without requiring
    database or API connections.
"""

import pytest
import polars as pl
from datetime import date
from unittest.mock import MagicMock, patch
from pfin_back_etl.core import SBaseConn, PFinFMP, PFinBackend, CPI_U_SOURCE


# ===================================================================
# SBaseConn row isolation logic (tested via a mock subclass)
# ===================================================================
class TestIsolateNewRows:
    """Tests for _isolate_new_rows_df — identifies rows to INSERT."""

    @pytest.mark.unit
    def test_new_rows_detected(self, sample_df_old, sample_df_new):
        """META and MSFT are new (not in old), should be returned."""
        # We need to test the method directly, so we create a minimal mock
        conn = object.__new__(SBaseConn)

        key_list = ["symbol"]
        result = conn._isolate_new_rows_df(key_list, sample_df_old, sample_df_new)

        symbols = sorted(result["symbol"].to_list())
        assert symbols == ["META", "MSFT"]

    @pytest.mark.unit
    def test_no_new_rows(self, sample_df_old):
        """When all new rows already exist, result should be empty."""
        conn = object.__new__(SBaseConn)

        df_new = pl.DataFrame(
            {
                "symbol": ["AAPL", "NVDA"],
                "description": ["Apple", "NVIDIA"],
            }
        )
        key_list = ["symbol"]
        result = conn._isolate_new_rows_df(key_list, sample_df_old, df_new)
        assert len(result) == 0

    @pytest.mark.unit
    def test_all_new_rows_when_old_empty(self, sample_df_new):
        """When old table is empty, all rows should be returned as new."""
        conn = object.__new__(SBaseConn)

        df_old = pl.DataFrame(schema={"symbol": pl.String, "description": pl.String})
        key_list = ["symbol"]
        result = conn._isolate_new_rows_df(key_list, df_old, sample_df_new)
        assert len(result) == 4  # All rows are new


class TestIsolateUpdatedRows:
    """Tests for _isolate_updated_rows_df — identifies rows to UPDATE."""

    @pytest.mark.unit
    def test_overlapping_rows_detected(self, sample_df_old, sample_df_new):
        """AAPL and NVDA exist in both, should be returned for update."""
        conn = object.__new__(SBaseConn)

        key_list = ["symbol"]
        result = conn._isolate_updated_rows_df(key_list, sample_df_old, sample_df_new)

        symbols = sorted(result["symbol"].to_list())
        assert symbols == ["AAPL", "NVDA"]

    @pytest.mark.unit
    def test_no_overlapping_rows(self, sample_df_old):
        """When there's no overlap, result should be empty."""
        conn = object.__new__(SBaseConn)

        df_new = pl.DataFrame(
            {
                "symbol": ["META", "MSFT"],
                "description": ["Meta", "Microsoft"],
            }
        )
        key_list = ["symbol"]
        result = conn._isolate_updated_rows_df(key_list, sample_df_old, df_new)
        assert len(result) == 0

    @pytest.mark.unit
    def test_empty_old_returns_empty(self, sample_df_new):
        """When old table is empty, no rows to update."""
        conn = object.__new__(SBaseConn)

        df_old = pl.DataFrame(schema={"symbol": pl.String, "description": pl.String})
        key_list = ["symbol"]
        result = conn._isolate_updated_rows_df(key_list, df_old, sample_df_new)
        assert len(result) == 0


class TestCalcCommonCols:
    """Tests for _calc_common_cols_df — finds common columns between DB and API."""

    @pytest.mark.unit
    def test_common_cols_found(self):
        conn = object.__new__(SBaseConn)

        # Mock the tab_sbase with column keys
        mock_table = MagicMock()
        mock_table.__table__ = MagicMock()
        mock_table.__table__.columns.keys.return_value = [
            "id",
            "symbol",
            "description",
            "created_at",
        ]

        df_sbase = pl.DataFrame(
            {
                "id": [1, 2],
                "symbol": ["AAPL", "NVDA"],
                "description": ["Apple", "NVIDIA"],
                "created_at": ["2024-01-01", "2024-01-02"],
            }
        )

        df_api = pl.DataFrame(
            {
                "symbol": ["AAPL", "NVDA", "META"],
                "description": ["Apple Inc.", "NVIDIA Corp.", "Meta"],
                "extra_field": [100, 200, 300],  # not in DB
            }
        )

        common_cols, df_old, df_new = conn._calc_common_cols_df(
            mock_table, df_sbase, df_api
        )

        assert "symbol" in common_cols
        assert "description" in common_cols
        assert "extra_field" not in common_cols
        assert "created_at" not in common_cols  # not in API data
        assert len(df_old) == 2
        assert len(df_new) == 3


# ===================================================================
# PFinFMP (tested with mocked API calls)
# ===================================================================
class TestPFinFMP:
    """Tests for FMP client wrapper methods."""

    @pytest.mark.unit
    def test_fetch_fmp_df_converts_to_snake_case(self):
        """Verify that FMP responses get their columns converted to snake_case."""
        fmp = object.__new__(PFinFMP)

        mock_func = MagicMock()
        mock_func.__name__ = "test_api"
        mock_response = MagicMock()
        mock_response.json.return_value = [
            {"reportedCurrency": "USD", "netIncome": 1000000}
        ]
        mock_func.return_value = mock_response

        result = fmp.fetch_fmp_df(mock_func, symbol="AAPL")

        assert "reported_currency" in result.columns
        assert "net_income" in result.columns
        assert "reportedCurrency" not in result.columns

    @pytest.mark.unit
    def test_fetch_fmp_df_empty_response(self):
        """An empty API response should return an empty DataFrame."""
        fmp = object.__new__(PFinFMP)

        mock_func = MagicMock()
        mock_func.__name__ = "test_api"
        mock_response = MagicMock()
        mock_response.json.return_value = []
        mock_func.return_value = mock_response

        result = fmp.fetch_fmp_df(mock_func, symbol="FAKE")
        assert len(result) == 0

    @pytest.mark.unit
    def test_fetch_fmp_list_df_concatenates(self):
        """Verify multiple API calls are concatenated into one DataFrame."""
        fmp = object.__new__(PFinFMP)

        call_count = 0

        def mock_fetch_fmp_df(func, **kwargs):
            nonlocal call_count
            call_count += 1
            return pl.DataFrame({"symbol": [kwargs["symbol"]], "value": [call_count]})

        fmp.fetch_fmp_df = mock_fetch_fmp_df

        mock_func = MagicMock()
        result = fmp.fetch_fmp_list_df(
            mock_func, "symbol", symbol=["AAPL", "NVDA", "META"]
        )

        assert len(result) == 3
        assert sorted(result["symbol"].to_list()) == ["AAPL", "META", "NVDA"]


# ===================================================================
# CPI-U -> pfin.cpi_u_index mapping (SELF-230)
#   PFinBackend._map_cpi_u_index_df is a @staticmethod pure transform:
#   BLS CPI-U dataframe -> first-of-month cpi_u_index grain. No DB, no API.
# ===================================================================
class TestMapCpiUIndexDf:
    """Tests for the CPI-U -> pfin.cpi_u_index first-of-month mapping."""

    @staticmethod
    def _df_api(rows):
        """Build a df in the shape utils.fetch_cpi_df returns (relevant cols)."""
        return pl.DataFrame(
            rows,
            schema={
                "year": pl.Int64,
                "month": pl.Int64,
                "series_value": pl.Float64,
            },
        )

    @pytest.mark.unit
    def test_first_of_month_grain(self):
        """Each (year, month) maps to a first-of-month DATE cpi_period."""
        df_api = self._df_api(
            [
                {"year": 2024, "month": 12, "series_value": 315.605},
                {"year": 2024, "month": 11, "series_value": 315.493},
                {"year": 2015, "month": 12, "series_value": 236.525},
            ]
        )
        out = PFinBackend._map_cpi_u_index_df(df_api)

        assert list(out.columns) == ["cpi_period", "cpi_value", "source"]
        assert out["cpi_period"].dtype == pl.Date
        periods = out["cpi_period"].to_list()
        assert date(2015, 12, 1) in periods
        assert date(2024, 11, 1) in periods
        assert date(2024, 12, 1) in periods

    @pytest.mark.unit
    def test_m13_annual_average_dropped(self):
        """Month 13 (BLS annual average) is NOT a calendar month -> dropped."""
        df_api = self._df_api(
            [
                {"year": 2024, "month": 12, "series_value": 315.605},
                {"year": 2024, "month": 13, "series_value": 313.689},  # annual avg
            ]
        )
        out = PFinBackend._map_cpi_u_index_df(df_api)

        assert len(out) == 1
        assert out["cpi_period"].to_list() == [date(2024, 12, 1)]

    @pytest.mark.unit
    def test_value_and_source_mapped(self):
        """series_value -> cpi_value; source is the BLS provenance constant."""
        df_api = self._df_api(
            [{"year": 2020, "month": 6, "series_value": 257.797}]
        )
        out = PFinBackend._map_cpi_u_index_df(df_api)

        assert out["cpi_value"].to_list() == [257.797]
        assert out["source"].to_list() == [CPI_U_SOURCE]
        assert CPI_U_SOURCE == "BLS_CUUR0000SA0"

    @pytest.mark.unit
    def test_nonfinite_and_null_values_dropped(self):
        """NaN / null cpi_value rows are dropped (053 CHECK + NOT NULL fail-closed)."""
        df_api = self._df_api(
            [
                {"year": 2024, "month": 12, "series_value": 315.605},
                {"year": 2024, "month": 10, "series_value": float("nan")},
                {"year": 2024, "month": 9, "series_value": None},
            ]
        )
        out = PFinBackend._map_cpi_u_index_df(df_api)

        assert out["cpi_period"].to_list() == [date(2024, 12, 1)]

    @pytest.mark.unit
    def test_duplicate_period_deduped(self):
        """Duplicate cpi_period collapses to one row (upsert key must be unique)."""
        df_api = self._df_api(
            [
                {"year": 2024, "month": 12, "series_value": 315.605},
                {"year": 2024, "month": 12, "series_value": 315.605},
            ]
        )
        out = PFinBackend._map_cpi_u_index_df(df_api)
        assert len(out) == 1

    @pytest.mark.unit
    def test_maps_through_fetch_cpi_df(self, sample_bls_cpi_json):
        """End-to-end: BLS payload -> fetch_cpi_df -> _map, incl. an M13 row."""
        import json
        from pfin_back_etl import utils

        payload = json.loads(json.dumps(sample_bls_cpi_json))  # deep copy
        payload["Results"]["series"][0]["data"].append(
            {
                "year": "2024",
                "period": "M13",
                "periodName": "Annual",
                "value": "313.689",
                "footnotes": [{}],
            }
        )
        mock_response = MagicMock()
        mock_response.text = json.dumps(payload)
        with patch("pfin_back_etl.utils.requests.post", return_value=mock_response):
            df_api = utils.fetch_cpi_df("fake_key", 2024, 2024, ["CUUR0000SA0"])

        out = PFinBackend._map_cpi_u_index_df(df_api)
        # M13 dropped; the two real months (M11, M12) survive as first-of-month.
        assert sorted(out["cpi_period"].to_list()) == [
            date(2024, 11, 1),
            date(2024, 12, 1),
        ]
        assert out["source"].unique().to_list() == [CPI_U_SOURCE]
