"""Chapter 7 Snowpark Python examples for *Advanced Snowflake Data Engineering*.

Submodules mirror the chapter sections:

- ``dataframe_api`` covers Section 1, DataFrame API and pushdown.
- ``pandas_on_snowflake`` covers Section 2, Modin-backed pandas on Snowflake.
- ``udfs`` covers Section 3, scalar and vectorized UDFs.
- ``udtfs`` covers Section 4.1, UDTF velocity flagger.
- ``sprocs`` covers Section 4.2, stored procedure orchestration.
- ``ml`` covers Section 4.3, Snowpark ML Feature Store and Model Registry.
"""

from .session import build_session

__all__ = ["build_session"]
