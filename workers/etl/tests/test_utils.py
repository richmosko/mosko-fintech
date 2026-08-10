"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Unit tests for utility functions in pfin_back_etl.utils.
    These tests run without any external dependencies (no DB, no API).
"""

import pytest
import polars as pl
import sqlalchemy as sqla
import sqlalchemy.ext.automap as sqla_automap
from unittest.mock import patch, MagicMock
from pfin_back_etl import utils


# ===================================================================
# col_to_snake
# ===================================================================
class TestColToSnake:
    """Tests for camelCase -> snake_case column name conversion."""

    @pytest.mark.unit
    def test_basic_conversion(self):
        result = utils.col_to_snake(["reportedCurrency", "fillingDate"])
        assert result == {
            "reportedCurrency": "reported_currency",
            "fillingDate": "filling_date",
        }

    @pytest.mark.unit
    def test_already_snake_case(self):
        result = utils.col_to_snake(["net_income", "gross_profit"])
        assert result == {
            "net_income": "net_income",
            "gross_profit": "gross_profit",
        }

    @pytest.mark.unit
    def test_single_word(self):
        result = utils.col_to_snake(["revenue", "eps", "price"])
        assert result == {
            "revenue": "revenue",
            "eps": "eps",
            "price": "price",
        }

    @pytest.mark.unit
    def test_multiple_capitals(self):
        result = utils.col_to_snake(["weightedAverageShsOut", "costOfRevenue"])
        assert result == {
            "weightedAverageShsOut": "weighted_average_shs_out",
            "costOfRevenue": "cost_of_revenue",
        }

    @pytest.mark.unit
    def test_empty_list(self):
        result = utils.col_to_snake([])
        assert result == {}

    @pytest.mark.unit
    def test_full_column_set(self, sample_camel_case_columns):
        result = utils.col_to_snake(sample_camel_case_columns)
        assert len(result) == len(sample_camel_case_columns)
        for original, converted in result.items():
            # No uppercase letters in the result
            assert converted == converted.lower()
            # Original key is preserved
            assert original in sample_camel_case_columns


# ===================================================================
# clean_empty_str_df
# ===================================================================
class TestCleanEmptyStrDf:
    """Tests for cleaning empty strings to None in DataFrames."""

    @pytest.mark.unit
    def test_replaces_empty_strings(self):
        df = pl.DataFrame({"a": ["hello", "", "world"], "b": ["", "foo", ""]})
        result = utils.clean_empty_str_df(df)
        assert result["a"].to_list() == ["hello", None, "world"]
        assert result["b"].to_list() == [None, "foo", None]

    @pytest.mark.unit
    def test_non_string_columns_unchanged(self):
        df = pl.DataFrame({"name": ["a", "", "c"], "value": [1, 2, 3]})
        result = utils.clean_empty_str_df(df)
        assert result["name"].to_list() == ["a", None, "c"]
        assert result["value"].to_list() == [1, 2, 3]

    @pytest.mark.unit
    def test_no_empty_strings(self):
        df = pl.DataFrame({"a": ["hello", "world"]})
        result = utils.clean_empty_str_df(df)
        assert result["a"].to_list() == ["hello", "world"]

    @pytest.mark.unit
    def test_all_empty_strings(self):
        df = pl.DataFrame({"a": ["", "", ""]})
        result = utils.clean_empty_str_df(df)
        assert result["a"].to_list() == [None, None, None]


# ===================================================================
# apply_schema_df
# ===================================================================
class TestApplySchemaDf:
    """Tests for casting DataFrame schemas from source to target."""

    @pytest.mark.unit
    def test_cast_int_to_float(self):
        df_src = pl.DataFrame({"val": [1.0, 2.0, 3.0]})
        df_tgt = pl.DataFrame({"val": [10, 20, 30]})
        result = utils.apply_schema_df(df_src, df_tgt)
        assert result["val"].dtype == pl.Float64

    @pytest.mark.unit
    def test_mismatched_columns_preserved(self):
        """Columns in target but not in source keep their original type."""
        df_src = pl.DataFrame({"a": [1.0]})
        df_tgt = pl.DataFrame({"a": [1], "b": ["hello"]})
        result = utils.apply_schema_df(df_src, df_tgt)
        assert result["a"].dtype == pl.Float64
        assert result["b"].dtype == pl.String

    @pytest.mark.unit
    def test_same_schema_noop(self):
        df_src = pl.DataFrame({"a": [1, 2], "b": ["x", "y"]})
        df_tgt = pl.DataFrame({"a": [3, 4], "b": ["z", "w"]})
        result = utils.apply_schema_df(df_src, df_tgt)
        assert result.schema == df_src.schema


# ===================================================================
# ldict_to_df
# ===================================================================
class TestLdictToDf:
    """Tests for converting list-of-dicts to Polars DataFrame."""

    @pytest.mark.unit
    def test_with_data(self):
        mock_table = MagicMock()
        mock_table.columns.keys.return_value = ["id", "name"]
        ldict = [{"id": 1, "name": "AAPL"}, {"id": 2, "name": "NVDA"}]
        result = utils.ldict_to_df(ldict, mock_table)
        assert len(result) == 2
        assert result["id"].to_list() == [1, 2]

    @pytest.mark.unit
    def test_empty_list(self):
        mock_table = MagicMock()
        mock_table.columns.keys.return_value = ["id", "name"]
        result = utils.ldict_to_df([], mock_table)
        assert len(result) == 0
        assert list(result.columns) == ["id", "name"]


# ===================================================================
# fetch_cpi_df
# ===================================================================
class TestFetchCpiDf:
    """Tests for BLS CPI data fetching (mocked HTTP)."""

    @pytest.mark.unit
    def test_successful_fetch(self, sample_bls_cpi_json):
        import json

        mock_response = MagicMock()
        mock_response.text = json.dumps(sample_bls_cpi_json)

        with patch("pfin_back_etl.utils.requests.post", return_value=mock_response):
            df = utils.fetch_cpi_df("fake_key", 2024, 2024, ["CUUR0000SA0"])

        assert len(df) == 2
        assert "year" in df.columns
        assert "month" in df.columns
        assert "series_value" in df.columns
        assert "series_id" in df.columns
        assert "ref_date" in df.columns
        # Check types
        assert df["year"].dtype == pl.Int64
        assert df["month"].dtype == pl.Int64
        assert df["series_value"].dtype == pl.Float64

    @pytest.mark.unit
    def test_failed_request_raises(self):
        import json

        failed_json = {"status": "REQUEST_FAILED", "Results": {}}
        mock_response = MagicMock()
        mock_response.text = json.dumps(failed_json)

        with patch("pfin_back_etl.utils.requests.post", return_value=mock_response):
            with pytest.raises(Exception, match="unsuccessful"):
                utils.fetch_cpi_df("fake_key", 2024, 2024, ["CUUR0000SA0"])

    @pytest.mark.unit
    def test_month_parsing(self, sample_bls_cpi_json):
        """Verify M12 -> 12 and M11 -> 11 conversion."""
        import json

        mock_response = MagicMock()
        mock_response.text = json.dumps(sample_bls_cpi_json)

        with patch("pfin_back_etl.utils.requests.post", return_value=mock_response):
            df = utils.fetch_cpi_df("fake_key", 2024, 2024, ["CUUR0000SA0"])

        months = sorted(df["month"].to_list())
        assert months == [11, 12]


# ===================================================================
# load_env_variables
# ===================================================================
class TestLoadEnvVariables:
    """Tests for environment variable loading."""

    # ⚠ THE TWO TESTS THAT USED TO LIVE HERE ASSERTED THAT THE LOADER RAISES
    # ON AN ABSENT KEY. That behaviour is REMOVED by S12, deliberately: both
    # workers load through this function, and `nav_daily` makes zero external
    # API calls, so requiring the keys at load time forced the NAV cron to hold
    # two credentials scoped to other jobs or die on its first scheduled run.
    # They are REPOINTED rather than deleted — the requirement did not vanish,
    # it MOVED to the point of use, and these now pin where.

    @pytest.mark.unit
    def test_loader_does_not_raise_on_absent_api_keys(self):
        """The loader raises for nothing; absent keys are None."""
        with patch("pfin_back_etl.utils.dotenv.load_dotenv"):
            with patch("pfin_back_etl.utils.os.getenv", return_value=None):
                params = utils.load_env_variables("PFIN_")
        assert params["FMP_API_KEY"] is None
        assert params["BLS_API_KEY"] is None

    @pytest.mark.unit
    @pytest.mark.parametrize("key_name", ["FMP_API_KEY", "BLS_API_KEY"])
    def test_require_api_key_raises_at_the_point_of_use(self, key_name):
        """The raise MOVED here — and it names the key, so the failure says
        which credential the operation actually needed."""
        with pytest.raises(ValueError, match=key_name):
            utils.require_api_key({key_name: None}, key_name)

    @pytest.mark.unit
    def test_require_api_key_returns_the_value_when_present(self):
        assert utils.require_api_key({"BLS_API_KEY": "abc"}, "BLS_API_KEY") == "abc"

    @pytest.mark.unit
    def test_require_api_key_tolerates_a_missing_params_dict(self):
        """A worker that loaded only DB params has no key entry at all — that
        must raise the same located error, not a KeyError/TypeError."""
        with pytest.raises(ValueError, match="FMP_API_KEY"):
            utils.require_api_key(None, "FMP_API_KEY")

    @pytest.mark.unit
    def test_db_params_carry_no_api_keys(self):
        """`load_db_params` is what a no-API worker calls; it must not even
        surface the key names, so a reader can see the job's credential needs
        from WHICH FUNCTION IT CALLS."""
        with patch("pfin_back_etl.utils.dotenv.load_dotenv"):
            with patch("pfin_back_etl.utils.os.getenv", return_value=None):
                params = utils.load_db_params("PFIN_")
        assert "FMP_API_KEY" not in params
        assert "BLS_API_KEY" not in params
        assert set(params) == {
            "DB_USER", "DB_HOST", "DB_PORT", "DB_NAME", "DB_PASSWORD", "DB_SSLMODE",
        }

    # --- BLS_API_KEY_TEST override ---------------------------------------
    @pytest.mark.unit
    def test_bls_test_name_is_preferred_when_present(self):
        """So a dev machine holds the test key under the TEST name and the
        PRODUCTION name is absent from the laptop entirely. Not a fence —
        nothing can inspect a local .env — but it extends the manifest's
        name-carries-tier convention across the boundary where it snapped."""
        env = {"BLS_API_KEY_TEST": "test-value", "BLS_API_KEY": "prod-value"}
        with patch("pfin_back_etl.utils.dotenv.load_dotenv"):
            with patch(
                "pfin_back_etl.utils.os.getenv", side_effect=lambda k: env.get(k)
            ):
                keys = utils.load_api_keys()
        assert keys["BLS_API_KEY"] == "test-value"

    @pytest.mark.unit
    def test_bls_falls_back_to_the_production_name(self):
        """Deployed containers set only the production name; the override must
        not become a requirement."""
        env = {"BLS_API_KEY": "prod-value"}
        with patch("pfin_back_etl.utils.dotenv.load_dotenv"):
            with patch(
                "pfin_back_etl.utils.os.getenv", side_effect=lambda k: env.get(k)
            ):
                keys = utils.load_api_keys()
        assert keys["BLS_API_KEY"] == "prod-value"

    @pytest.mark.unit
    def test_fmp_has_no_test_override(self):
        """Anti-vacuity: the override is PER-KEY, and only BLS has one today.
        A blanket `<NAME>_TEST` rule would silently change FMP's behaviour too."""
        assert utils._API_KEY_SOURCES.get("FMP_API_KEY") is None
        assert utils._API_KEY_SOURCES["BLS_API_KEY"] == (
            "BLS_API_KEY_TEST",
            "BLS_API_KEY",
        )

    @pytest.mark.unit
    def test_successful_load(self):
        env_vars = {
            "FMP_API_KEY": "fmp_test",
            "BLS_API_KEY": "bls_test",
            "PFIN_DB_USER": "user",
            "PFIN_DB_HOST": "localhost",
            "PFIN_DB_PORT": "5432",
            "PFIN_DB_NAME": "postgres",
            "PFIN_DB_PASSWORD": "secret",
        }

        with patch("pfin_back_etl.utils.dotenv.load_dotenv"):
            with patch(
                "pfin_back_etl.utils.os.getenv", side_effect=lambda k: env_vars.get(k)
            ):
                params = utils.load_env_variables("PFIN_")

        assert params["FMP_API_KEY"] == "fmp_test"
        assert params["BLS_API_KEY"] == "bls_test"
        assert params["DB_USER"] == "user"
        assert params["DB_HOST"] == "localhost"
        assert params["DB_PORT"] == "5432"


# ===================================================================
# sqla_modulename_for_table
# ===================================================================
class TestSqlaModuleNameForTable:
    """Tests for SQLAlchemy automap module name resolution."""

    @pytest.mark.unit
    def test_with_schema(self):
        mock_reflect = MagicMock()
        mock_reflect.schema = "pfin"
        result = utils.sqla_modulename_for_table("some_table", None, mock_reflect)
        assert result == "pfin"

    @pytest.mark.unit
    def test_without_schema(self):
        mock_reflect = MagicMock()
        mock_reflect.schema = None
        result = utils.sqla_modulename_for_table("some_table", None, mock_reflect)
        assert result == "public"

# ===================================================================
# build_database_url  (BACKLOG §7.6 S11)
# ===================================================================
class TestBuildDatabaseUrl:
    """Transport posture of the single connection-string builder.

    The DEFAULT is what these tests are really guarding. S11 made sslmode
    configurable so the ETL could be run against a TLS-less local stack at all;
    the risk that change introduces is a silent downgrade in production, so the
    unset / empty / absent cases are asserted explicitly and separately.
    """

    BASE = {
        "DB_USER": "u", "DB_PASSWORD": "p", "DB_HOST": "h",
        "DB_PORT": "5432", "DB_NAME": "d",
    }

    @pytest.mark.unit
    def test_defaults_to_require_when_key_absent(self):
        """No DB_SSLMODE key at all -> require. Guards callers that build params
        dicts by hand and never learn the key exists."""
        assert utils.build_database_url(dict(self.BASE)).endswith("?sslmode=require")

    @pytest.mark.unit
    @pytest.mark.parametrize("value", [None, "", "   "])
    def test_defaults_to_require_when_unset_or_blank(self, value):
        """Present-but-empty is the realistic misconfiguration: an env var declared
        in a .env file and left blank. It must NOT read as 'disable'."""
        p = dict(self.BASE, DB_SSLMODE=value)
        assert utils.build_database_url(p).endswith("?sslmode=require")

    @pytest.mark.unit
    def test_explicit_disable_is_honoured(self):
        """The whole point of S11 — the local stack has no TLS."""
        p = dict(self.BASE, DB_SSLMODE="disable")
        assert utils.build_database_url(p).endswith("?sslmode=disable")

    @pytest.mark.unit
    @pytest.mark.parametrize("mode", ["disable", "allow", "prefer", "require",
                                      "verify-ca", "verify-full"])
    def test_every_libpq_mode_round_trips(self, mode):
        """Includes the hardening directions (verify-ca / verify-full), so the
        allowlist cannot be read as 'require or weaker'."""
        p = dict(self.BASE, DB_SSLMODE=mode)
        assert utils.build_database_url(p).endswith(f"?sslmode={mode}")

    @pytest.mark.unit
    @pytest.mark.parametrize("bad", ["requre", "REQUIRE", "true", "1", "yes", "off"])
    def test_unrecognised_value_raises_rather_than_falling_back(self, bad):
        """A typo must fail loudly. Falling back to the default would be worse than
        failing: it would change the transport posture without saying so. 'REQUIRE'
        is included deliberately — libpq is case-sensitive here, so a plausible
        capitalisation is a real defect, not a courtesy to absorb."""
        p = dict(self.BASE, DB_SSLMODE=bad)
        with pytest.raises(ValueError, match="not a valid libpq sslmode"):
            utils.build_database_url(p)

    @pytest.mark.unit
    def test_only_the_transport_parameter_changed(self):
        """Non-vacuity: the override must alter the sslmode and NOTHING else, or a
        future refactor could pass this suite while mangling the credentials."""
        req = utils.build_database_url(dict(self.BASE, DB_SSLMODE="require"))
        dis = utils.build_database_url(dict(self.BASE, DB_SSLMODE="disable"))
        assert req.replace("?sslmode=require", "") == dis.replace("?sslmode=disable", "")
        assert req.startswith("postgresql+psycopg2://u:p@h:5432/d?")


# ===================================================================
# automap relationship-name collision guard  (BACKLOG §7.6 S13)
# ===================================================================
class TestAutomapRelationshipNaming:
    """Hermetic tests for the automap naming hooks — no DB, no credentials.

    S13: pfin.user_taxonomy carries a column `tax_character` AND an FK to table
    pfin.tax_character. Automap names the generated scalar relationship after
    the referred TABLE, it collides with the same-named column, and automap
    RAISES inside base.prepare() — so PFinBackend() cannot be constructed and
    the production ETL entry point (main.py) cannot start. Latent ~50 migrations.

    These build SQLAlchemy Table objects in an unbound MetaData, so they run in
    the `unit` lane (CI's `pytest -m unit --strict-markers`) with no stack up.
    """

    @staticmethod
    def _mapped(table):
        """A stand-in for an automap-generated class: automap's own default hooks
        read only `__name__` and the mapped columns."""
        return type(table.name, (), {"__table__": table})

    @staticmethod
    def _s13_metadata():
        """The measured S13 shape: a text column and an FK sharing one name."""
        md = sqla.MetaData()
        tax_character = sqla.Table(
            "tax_character",
            md,
            sqla.Column("code", sqla.Text, primary_key=True),
            schema="pfin",
        )
        user_taxonomy = sqla.Table(
            "user_taxonomy",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column(
                "tax_character", sqla.Text, sqla.ForeignKey("pfin.tax_character.code")
            ),
            schema="pfin",
        )
        return user_taxonomy, tax_character

    @classmethod
    def _s13_args(cls):
        local_tbl, referred_tbl = cls._s13_metadata()
        constraint = list(local_tbl.foreign_key_constraints)[0]
        return (None, cls._mapped(local_tbl), cls._mapped(referred_tbl), constraint)

    # -- the defect itself -------------------------------------------------

    @pytest.mark.unit
    def test_upstream_default_produces_the_colliding_name(self):
        """RED anchor. Asserts the DEFECT still exists upstream, so this suite
        cannot pass vacuously: if SQLAlchemy ever starts disambiguating on its
        own, this fails and tells us the guard's premise has changed. It is also
        the assertion that fails against a guard that does nothing."""
        _, local_cls, referred_cls, constraint = self._s13_args()
        default = sqla_automap.name_for_scalar_relationship(
            None, local_cls, referred_cls, constraint
        )
        assert default == "tax_character"
        assert default in local_cls.__table__.columns.keys()  # the collision

    @pytest.mark.unit
    def test_collision_renames_the_relationship_not_the_column(self):
        """The load-bearing assertion. `tax_character` is a ratified domain term
        on a locked migration surface — the COLUMN keeps its natural name and the
        RELATIONSHIP is the thing that moves, to `tax_character_ref`."""
        args = self._s13_args()
        name = utils.sqla_name_for_scalar_relationship(*args)
        local_cls = args[1]
        assert name == "tax_character_ref"
        assert name not in local_cls.__table__.columns.keys()
        assert "tax_character" in local_cls.__table__.columns.keys()

    # -- generality: the guard is not a special case for tax_character -----

    @pytest.mark.unit
    def test_non_colliding_names_are_left_alone(self):
        """Every existing base.by_module.<schema>.<table>.<rel> access site must
        be unaffected — the guard intervenes ONLY on a real collision."""
        md = sqla.MetaData()
        sqla.Table(
            "account", md, sqla.Column("id", sqla.Integer, primary_key=True),
            schema="pfin",
        )
        child = sqla.Table(
            "holding",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("account_id", sqla.Integer, sqla.ForeignKey("pfin.account.id")),
            schema="pfin",
        )
        constraint = list(child.foreign_key_constraints)[0]
        name = utils.sqla_name_for_scalar_relationship(
            None, self._mapped(child), self._mapped(md.tables["pfin.account"]),
            constraint,
        )
        assert name == "account"

    @pytest.mark.unit
    def test_arbitrary_table_name_collides_the_same_way(self):
        """Generality, stated as a test: nothing here knows the word
        `tax_character`. Any column named after a table it also FKs to gets the
        same treatment — which is the point of a guard over an exception list."""
        md = sqla.MetaData()
        sqla.Table(
            "widget", md, sqla.Column("code", sqla.Text, primary_key=True),
            schema="pfin",
        )
        local = sqla.Table(
            "gizmo",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("widget", sqla.Text, sqla.ForeignKey("pfin.widget.code")),
            schema="pfin",
        )
        name = utils.sqla_name_for_scalar_relationship(
            None, self._mapped(local), self._mapped(md.tables["pfin.widget"]),
            list(local.foreign_key_constraints)[0],
        )
        assert name == "widget_ref"

    @pytest.mark.unit
    def test_two_fks_to_one_target_get_distinct_names(self):
        """Why the fallback is keyed on the FK's own columns and not a fixed
        suffix: one table can hold several FKs to one target (pfin.lot_match holds
        two to pfin.account_trans). A `_ref` constant would collapse them onto one
        name — trading a loud failure for a silent wrong one."""
        md = sqla.MetaData()
        person = sqla.Table(
            "person", md, sqla.Column("id", sqla.Integer, primary_key=True),
            schema="pfin",
        )
        local = sqla.Table(
            "task",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("person", sqla.Text),  # the colliding column
            sqla.Column("owner", sqla.Integer, sqla.ForeignKey("pfin.person.id")),
            sqla.Column("manager", sqla.Integer, sqla.ForeignKey("pfin.person.id")),
            schema="pfin",
        )
        names = {
            utils.sqla_name_for_scalar_relationship(
                None, self._mapped(local), self._mapped(person), c
            )
            for c in local.foreign_key_constraints
        }
        assert names == {"owner_ref", "manager_ref"}

    @pytest.mark.unit
    def test_fallback_name_also_taken_gets_a_numeric_suffix(self):
        """Fail-closed on the second-order case: the disambiguated name must not
        itself land on a column."""
        md = sqla.MetaData()
        sqla.Table(
            "widget", md, sqla.Column("code", sqla.Text, primary_key=True),
            schema="pfin",
        )
        local = sqla.Table(
            "gizmo",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("widget", sqla.Text, sqla.ForeignKey("pfin.widget.code")),
            sqla.Column("widget_ref", sqla.Text),  # fallback already occupied
            schema="pfin",
        )
        name = utils.sqla_name_for_scalar_relationship(
            None, self._mapped(local), self._mapped(md.tables["pfin.widget"]),
            list(local.foreign_key_constraints)[0],
        )
        assert name == "widget_ref2"

    @pytest.mark.unit
    def test_declarative_reserved_names_are_also_guarded(self):
        """A relationship named `metadata` would shadow a declarative attribute
        without being a column, so the column scan alone would miss it."""
        md = sqla.MetaData()
        sqla.Table(
            "metadata", md, sqla.Column("id", sqla.Integer, primary_key=True),
            schema="pfin",
        )
        local = sqla.Table(
            "doc",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("meta_id", sqla.Integer, sqla.ForeignKey("pfin.metadata.id")),
            schema="pfin",
        )
        name = utils.sqla_name_for_scalar_relationship(
            None, self._mapped(local), self._mapped(md.tables["pfin.metadata"]),
            list(local.foreign_key_constraints)[0],
        )
        assert name == "meta_id_ref"

    # -- the collection side ----------------------------------------------

    @pytest.mark.unit
    def test_collection_default_is_preserved(self):
        """No collision of this shape exists at migration 062; the hook is wired
        because `<child>_collection` fails identically if a parent ever carries a
        column of that name."""
        md = sqla.MetaData()
        parent = sqla.Table(
            "account", md, sqla.Column("id", sqla.Integer, primary_key=True),
            schema="pfin",
        )
        child = sqla.Table(
            "holding",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("account_id", sqla.Integer, sqla.ForeignKey("pfin.account.id")),
            schema="pfin",
        )
        name = utils.sqla_name_for_collection_relationship(
            None, self._mapped(parent), self._mapped(child),
            list(child.foreign_key_constraints)[0],
        )
        assert name == "holding_collection"

    @pytest.mark.unit
    def test_collection_collision_is_disambiguated(self):
        md = sqla.MetaData()
        parent = sqla.Table(
            "account",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("holding_collection", sqla.Text),  # the collision
            schema="pfin",
        )
        child = sqla.Table(
            "holding",
            md,
            sqla.Column("id", sqla.Integer, primary_key=True),
            sqla.Column("account_id", sqla.Integer, sqla.ForeignKey("pfin.account.id")),
            schema="pfin",
        )
        name = utils.sqla_name_for_collection_relationship(
            None, self._mapped(parent), self._mapped(child),
            list(child.foreign_key_constraints)[0],
        )
        assert name == "holding_account_id_collection"
        assert name not in parent.columns.keys()

    # -- purity -------------------------------------------------------------

    @pytest.mark.unit
    def test_hooks_are_pure_and_repeatable(self):
        """Guards against a future rewrite that disambiguates via a module-level
        registry: that would make a second prepare() on a fresh base produce
        DIFFERENT names than the first, which is a worse defect than S13 because
        it is intermittent."""
        args = self._s13_args()
        first = utils.sqla_name_for_scalar_relationship(*args)
        second = utils.sqla_name_for_scalar_relationship(*self._s13_args())
        third = utils.sqla_name_for_scalar_relationship(*args)
        assert first == second == third == "tax_character_ref"
