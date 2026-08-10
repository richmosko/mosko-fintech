"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Integration tests for database initialization and table reflection.
    Requires valid .env credentials to connect to the SupaBase instance.
"""

import pytest
import sqlalchemy as sqla


@pytest.mark.integration
def test_backend_init(backend):
    backend.print_schema_info()
    assert backend


@pytest.mark.integration
def test_table_reflection(backend):
    insp = sqla.inspect(backend.engine)
    print(insp.get_table_names(schema="pfin"))
    pfin_tab_check_list = [
        "account",
        "account_users",
        "account_trans",
        "account_type",
        "asset",
        "asset_cat",
        "balance_sheet_statement",
        "cash_flow_statement",
        "cpi",
        "earning",
        "eod_price",
        "equity_profile",
        "income_statement",
        "nav",
        "reporting_period",
        "schema_version",
        "tax_cat",
        "trans_cat",
        "user_profile",
        "watchlist",
    ]
    print(f"Table Check List: {pfin_tab_check_list}")
    for tab_name in pfin_tab_check_list:
        print(f"CHECKING TABLE pfin.{tab_name}")
        tab = backend.get_reflected_table("pfin", tab_name)
        assert tab.__table__.schema == "pfin"
        assert tab.__table__.name == tab_name
        c_dict = backend.get_column_dict(tab)
        assert c_dict


# ===================================================================
# BACKLOG §7.6 S13 — PFinBackend() must be CONSTRUCTIBLE
# ===================================================================
# ⚠ SCOPE OF PROTECTION, STATED PLAINLY. These need a live database, so they
# carry @pytest.mark.integration and CI's `pytest -m unit --strict-markers`
# DESELECTS them. They do NOT protect main on their own — the hermetic guard
# that does is TestAutomapRelationshipNaming in tests/test_utils.py. These are
# the end-to-end confirmation, run against a stack by hand or in a future
# integration lane.
#
# WHY NOT THE `backend` FIXTURE. conftest's session-scoped `backend` wraps
# PFinBackend() in `except Exception: pytest.skip(...)`. That converts a
# production-fatal construction failure into a GREEN SKIP — which is part of why
# S13 survived ~50 migrations. These construct directly and skip ONLY on the two
# environmental causes (absent credentials, unreachable DB), so a mapper defect
# reaches the report as a FAILURE.


def _construct_backend_or_skip():
    """Construct PFinBackend(), skipping only on environment, never on defect."""
    import pfin_back_etl as pfbe

    try:
        return pfbe.PFinBackend()
    except ValueError as e:
        # utils.load_env_variables raises on absent FMP_API_KEY / BLS_API_KEY
        # (see BACKLOG §7.6 S12) — an environment fact, not a defect here.
        pytest.skip(f"ETL env not configured: {e}")
    except sqla.exc.OperationalError as e:
        pytest.skip(f"No database reachable: {e}")
    # Everything else — notably sqlalchemy.exc.ArgumentError from automap —
    # propagates and FAILS. That is the whole point of this test.


@pytest.mark.integration
def test_pfin_backend_is_constructible():
    """S13's acceptance test. Against the unfixed code this raises
    ArgumentError: "column 'tax_character' conflicts with property
    '<_RelationshipDeclared ... tax_character>'" — inside base.prepare(), i.e.
    before any ETL work begins, making main.py's entry point unstartable."""
    pfb = _construct_backend_or_skip()
    assert pfb.base is not None
    assert pfb.engine is not None


@pytest.mark.integration
def test_tax_character_column_survives_the_disambiguation():
    """Non-vacuity. Constructing successfully is not enough: the fix must not
    have bought that by taking the column's name away or dropping the FK. The
    COLUMN keeps `tax_character`; the RELATIONSHIP moves off it."""
    pfb = _construct_backend_or_skip()
    ut = pfb.get_reflected_table("pfin", "user_taxonomy")

    # 1. the column is still reachable under its ratified domain name
    assert "tax_character" in ut.__table__.columns.keys()

    # 2. the FK relationship still exists, and is NOT named after the column
    rels = {r.key: r for r in sqla.inspect(ut).relationships}
    to_tax_character = [
        key
        for key, rel in rels.items()
        if rel.target.name == "tax_character" and rel.target.schema == "pfin"
    ]
    assert to_tax_character, "the FK relationship to pfin.tax_character was dropped"
    assert "tax_character" not in to_tax_character
