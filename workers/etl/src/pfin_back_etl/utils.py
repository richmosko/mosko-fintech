"""
Project:       pfin_back_etl
Author:        Rich Mosko

Description:
    Common utility functions

"""

# library imports
import logging
import os
import dotenv
import re
import requests
import json
import polars as pl
import sqlalchemy.ext.automap as sqla_automap

logger = logging.getLogger("pfin_etl")


def col_to_snake(col_list):
    col_dict = {}
    for col in col_list:
        col_dict[col] = re.sub(r"([a-z])([A-Z])", r"\1_\2", col).lower()
    return col_dict


def ldict_to_df(ldict, tab):
    cols = tab.columns.keys()
    df = pl.DataFrame(schema=cols) if not ldict else pl.DataFrame(ldict)
    return df


def clean_empty_str_df(df):
    df_clean = df.with_columns(pl.col(pl.String).replace("", None))
    return df_clean


def apply_schema_df(df_src, df_tgt):
    """
    Cast datatypes from one polars dataframe(df_from) to another DF(df_to)

    args:
        df_src:            polars dataframe source to extract schema(datatypes)
        df_tgt:            polars dataframe target to apply schema(datatypes)

    returns:
        df_cast:           df_tgt with casted datatypes (polars DF)
    """
    schema_src = df_src.schema
    schema_tgt = df_tgt.schema
    for key in schema_tgt.keys():
        if key in schema_src:
            schema_tgt[key] = schema_src[key]
    df_cast = df_tgt.cast(schema_tgt)
    return df_cast


def load_env_variables(env_prefix):
    """
    Load the environmental variables from a '.env' file. The variables read
    should countain the specific setup constraints and passwords for use in
    the database access and API calls.

    returns: params (dictionary of the desired environmental variables)
    """
    params = {}

    # Load environment variables from local .env file
    dotenv.load_dotenv()

    # Check for API Key in FMP_API_KEY env variable
    key_name = "FMP_API_KEY"
    key_value = os.getenv(key_name)
    params["FMP_API_KEY"] = key_value
    if key_value is not None:
        logger.info(f"{key_name} value found...")
    else:
        raise ValueError(
            f"Environment variable {key_name} does not exist in .env file."
        )

    # Check for BLS API Key in env variable
    key_name = "BLS_API_KEY"
    key_value = os.getenv(key_name)
    params["BLS_API_KEY"] = key_value
    if key_value is not None:
        logger.info(f"{key_name} value found...")
    else:
        raise ValueError(
            f"Environment variable {key_name} does not exist in .env file."
        )

    # Fetch other env variables
    params["DB_USER"] = os.getenv(env_prefix + "DB_USER")
    params["DB_HOST"] = os.getenv(env_prefix + "DB_HOST")
    params["DB_PORT"] = os.getenv(env_prefix + "DB_PORT")
    params["DB_NAME"] = os.getenv(env_prefix + "DB_NAME")
    params["DB_PASSWORD"] = os.getenv(env_prefix + "DB_PASSWORD")

    # OPTIONAL, and the default is the security-load-bearing part. Unset -> "require",
    # so production is unchanged and an environment that simply forgot to set it still
    # demands TLS. Only an EXPLICIT value can weaken the transport, and only to a value
    # on the allowlist in build_database_url().
    params["DB_SSLMODE"] = os.getenv(env_prefix + "DB_SSLMODE")
    return params


# libpq's sslmode vocabulary. An explicit value must be one of these; anything else
# RAISES rather than being passed through, because a typo ("requre") would otherwise
# reach libpq as an error at connect time — far from the misconfiguration — and a
# silently-substituted default would be worse still: it would change the transport
# posture without anyone being told.
_SSLMODES = ("disable", "allow", "prefer", "require", "verify-ca", "verify-full")
_SSLMODE_DEFAULT = "require"


def build_database_url(params):
    """Build the psycopg2 SQLAlchemy URL from a loaded params dict (as returned by
    load_env_variables). Single source of the connection string so every engine —
    the ETL system engine (_sbase_setup) and the SELF-214 per-tenant NAV worker —
    constructs it identically.

    TLS: `sslmode` defaults to **require** and is overridable via `<prefix>DB_SSLMODE`.

    ⚠ THE DEFAULT IS THE SECURITY-LOAD-BEARING PART, NOT THE OVERRIDE. Unset, absent,
    or empty -> "require": production is unchanged, and an environment that forgot to
    set it still demands TLS. Only an EXPLICIT value can weaken the transport, and only
    to a member of _SSLMODES; anything else raises rather than silently falling back.

    WHY IT IS CONFIGURABLE AT ALL (BACKLOG §7.6 S11). It was hard-coded to "require",
    and the local Supabase CLI stack offers no TLS — so the ETL could not be pointed at
    the local stack AT ALL, and the barrier sat at connect time, before any logic. That
    made every worker unrunnable locally without editing this file, which is plausibly
    why the assembled NAV path went unrun until SELF-214 S10 forced it. A verification
    gate you must patch the code under test to execute does not get executed.

    args:    params (dict with DB_USER / DB_PASSWORD / DB_HOST / DB_PORT / DB_NAME,
             and optionally DB_SSLMODE)
    returns: database_url (str) for TenantBoundConnection.system()/.for_tenant().
    raises:  ValueError if DB_SSLMODE is set to something outside _SSLMODES.
    """
    sslmode = (params.get("DB_SSLMODE") or "").strip() or _SSLMODE_DEFAULT
    if sslmode not in _SSLMODES:
        raise ValueError(
            f"DB_SSLMODE={sslmode!r} is not a valid libpq sslmode. "
            f"Expected one of {_SSLMODES}. Refusing to guess: an unrecognised value "
            f"must not silently become the default, because that would change the "
            f"transport posture without saying so."
        )
    url = f"postgresql+psycopg2://{params['DB_USER']}:{params['DB_PASSWORD']}@"
    url += f"{params['DB_HOST']}:{params['DB_PORT']}/{params['DB_NAME']}"
    url += f"?sslmode={sslmode}"
    return url


def sqla_modulename_for_table(tablename, declarativetable, reflecttable):
    """
    This function needs to be defined with the above input arguments
    for sqlalchemy to automap the table names including the schemas
    when referencing through the 'by_module' class:
        ie: base.by_module.pfin.reporting_period

    used in the _sbase_setup() member function of PfinSBaseConn

    returns: schema (string of schema name to use)
    """
    if reflecttable.schema:
        return reflecttable.schema
    else:
        # Default module name if no schema is present
        return "public"


# ---------------------------------------------------------------------------
# Automap relationship-name collision guard (BACKLOG §7.6 S13).
# ---------------------------------------------------------------------------
# SQLAlchemy's automap names a generated SCALAR relationship after the REFERRED
# TABLE. When a table carries both an FK to table T and a column literally named
# T, the generated relationship and the mapped column claim the same attribute
# name, and automap RAISES rather than disambiguating:
#
#   ArgumentError: when configuring property 'tax_character' on
#   Mapper[user_taxonomy(user_taxonomy)], column 'tax_character' conflicts with
#   property '<_RelationshipDeclared ... tax_character>'
#
# That fires inside base.prepare(), i.e. during SBaseConn.__init__ — so
# PFinBackend() cannot be CONSTRUCTED and no ETL method is reachable at all.
# pfin.user_taxonomy (migration 009) + pfin.tax_character (011) is the instance
# that was found, ~50 migrations after it was introduced.
#
# THE GUARD IS GENERAL ON PURPOSE. A hard-coded exception for tax_character
# would fix one name and leave the next one to be discovered the same way — by
# a production entry point failing to start. This is a property of the SCHEMA
# SHAPE (any FK-to-T alongside a column named T), not of one table.
#
# THE COLUMN ALWAYS WINS. `tax_character` is a ratified domain term on a locked
# migration surface and the defect is in the mapper, not the model, so attribute
# access for the COLUMN is unchanged: `user_taxonomy.tax_character` is still the
# text column. It is the RELATIONSHIP that is renamed. Its new name is derived
# from the FK's own local column names:
#
#     pfin.user_taxonomy  ->  .tax_character        the text column (unchanged)
#                         ->  .tax_character_ref    the FK relationship to
#                                                   pfin.tax_character
#
# WHY THE FK COLUMNS AND NOT A FIXED SUFFIX. The disambiguator has to stay
# unique when one table holds several FKs to the same target — pfin.lot_match
# holds two to pfin.account_trans (buy_trans_id / sell_trans_id). Keying the
# fallback on the constraint's own columns keeps it unique without any
# cross-call state, so the hooks stay pure functions of their arguments and a
# second prepare() on a fresh base produces identical names.
#
# NON-COLLIDING NAMES ARE LEFT ALONE. The hooks delegate to automap's own
# defaults and only intervene on an actual collision, so every existing
# `base.by_module.<schema>.<table>.<rel>` access site is unaffected.

# Declarative attribute names a generated relationship must not take even though
# they are not columns; the column scan below would not catch them.
_SQLA_RESERVED_ATTRS = frozenset({"metadata", "registry"})


def _sqla_reserved_names(local_cls):
    """Attribute names already claimed on `local_cls` that a generated
    relationship must not collide with (its mapped columns, plus the declarative
    names above)."""
    return set(local_cls.__table__.columns.keys()) | _SQLA_RESERVED_ATTRS


def _sqla_fk_qualifier(constraint):
    """Constraint-unique disambiguator: the FK's own local column names.

    Unique per constraint, so several FKs from one table to one target resolve
    to distinct fallback names without any shared state.
    """
    return "_".join(col.name for col in constraint.columns)


def _sqla_disambiguate(default_name, local_cls, fallback_base):
    """Return `default_name` unless it is already claimed on `local_cls`, in
    which case return `fallback_base` (numerically suffixed if that is claimed
    too). Pure: no state carried between calls."""
    reserved = _sqla_reserved_names(local_cls)
    if default_name not in reserved:
        return default_name
    candidate = fallback_base
    n = 2
    while candidate in reserved:
        candidate = f"{fallback_base}{n}"
        n += 1
    return candidate


def sqla_name_for_scalar_relationship(base, local_cls, referred_cls, constraint):
    """automap hook — see the collision-guard block above.

    The argument signature is fixed by SQLAlchemy. Wired in core.py's
    SBaseConn._sbase_setup() at base.prepare(). Delegates to automap's own
    default so upstream naming is tracked, and only renames on a real collision.
    """
    default = sqla_automap.name_for_scalar_relationship(
        base, local_cls, referred_cls, constraint
    )
    fallback = f"{_sqla_fk_qualifier(constraint)}_ref"
    return _sqla_disambiguate(default, local_cls, fallback)


def sqla_name_for_collection_relationship(base, local_cls, referred_cls, constraint):
    """automap hook for the one-to-many side — see the collision-guard block.

    Here `local_cls` is the PARENT (referred) class and `constraint` lives on the
    CHILD table, so the fallback names the child table as well as its columns.
    No collision of this shape exists in the schema today (measured at migration
    062); the hook is wired because the default name is `<child>_collection` and
    a parent column of that name would fail identically.
    """
    default = sqla_automap.name_for_collection_relationship(
        base, local_cls, referred_cls, constraint
    )
    fallback = f"{constraint.table.name}_{_sqla_fk_qualifier(constraint)}_collection"
    return _sqla_disambiguate(default, local_cls, fallback)


def sqla_resolve_referred_schema(table, to_metadata, constraint, referred_schema):
    """
    Dynamically determines the target schema for a foreign key reference
    in sqlalchemy. Used when creating a temp table for a staging update.
    """
    if referred_schema == "source_schema":
        return "target_schema"  # Map 'source_schema' to 'target_schema'
    return referred_schema


def fetch_cpi_df(api_key, startyear, endyear, series_id_lst):
    """
    Fetch Consumer Price Index data from the Brureau of Labor Statistics.

    args:
        startyear:         starting year to fetch in 'yyyy' format
        endyear:           ending year to fetch in 'yyyy' format
        series_id_lst:     list of series IDs to fetch. id: ['CUUR0000SA0']

    returns:
        df_cpi:            polars dataframe of CPI index data
    """
    headers = {"Content-type": "application/json"}
    data = json.dumps(
        {
            "registrationkey": api_key,
            "seriesid": series_id_lst,
            "startyear": startyear,
            "endyear": endyear,
        }
    )
    p = requests.post(
        "https://api.bls.gov/publicAPI/v2/timeseries/data/", data=data, headers=headers
    )
    json_data = json.loads(p.text)

    logger.info(f"JSON STATUS: {json_data['status']}")
    if json_data["status"] != "REQUEST_SUCCEEDED":
        raise Exception("BLS CPI fetch request unsuccessful")

    df_list = []
    for series in json_data["Results"]["series"]:
        df = pl.DataFrame(series["data"])
        df = df.rename(col_to_snake(df.columns))
        df = df.with_columns(pl.lit(series["seriesID"]).alias("series_id"))
        df = df.rename({"period": "month"})
        df = df.with_columns(
            [
                pl.col("month")
                .str.strip_chars("M")
                .cast(pl.Int64, strict=False)
                .alias("month"),
                pl.col("year").cast(pl.Int64, strict=False).alias("year"),
                pl.col("value").cast(pl.Float64, strict=False).alias("value"),
            ]
        )
        df = df.drop_nulls(subset=["value"])
        df = df.rename({"value": "series_value"})
        df = df.drop("footnotes")
        df = df.with_columns(pl.format("{}-{}-14", "year", "month").alias("ref_date"))
        df_list.append(df)
    df_cpi = pl.concat(df_list, how="vertical_relaxed")
    return df_cpi
