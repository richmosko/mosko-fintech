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
# WHY NOT THE `backend` FIXTURE (HISTORICAL — and the reason this comment is
# now a lesson rather than a rationale). conftest's `backend` used to wrap
# construction in `except Exception: pytest.skip(...)`, converting a
# production-fatal failure into a GREEN SKIP, which is part of why S13 survived
# ~50 migrations. So this file grew its OWN narrower helper to avoid it.
#
# ⚠ THAT HELPER THEN REPRODUCED A NARROWER VERSION OF THE SAME DEFECT, and it
# is the fourth instance today of a shape worth naming: it skipped on
# ValueError — the case the fixture policy deliberately makes FAIL, because
# `load_env_variables` raising on an absent API key IS the S12 defect and must
# be visible. `main` therefore carried TWO skip policies that DISAGREED about
# whether a missing credential is a defect, with the governed one covering the
# fixtures and the UNGOVERNED one covering S13's acceptance test — the green
# that matters most.
#
# Each file read correctly alone. The defect lived in the seam. Written in
# REACTION to the over-broad `except`, it inherited a milder form of it.
#
# The reconciliation is not "copy the narrower list here": it is ONE policy
# with TWO call sites. Two copies of one policy drift, which is how this
# happened. See tests/fixture_policy.py.
from fixture_policy import construct_or_skip  # noqa: E402


def _construct_backend_or_skip():
    """Construct PFinBackend() under the single shared failure policy.

    Skips ONLY when no database is reachable. Everything else — automap
    ArgumentError (S13), permission denied (S17), an absent credential (S12) —
    propagates and FAILS, which is the whole point of the tests below.
    """
    import pfin_back_etl as pfbe

    return construct_or_skip("PFinBackend", pfbe.PFinBackend)


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
