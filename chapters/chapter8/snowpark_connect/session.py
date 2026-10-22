"""Reusable Spark Connect session builder for the chapter 8 interactive demos.

``snowpark_connect.init_spark_session()`` starts the local translation server
and returns a standard ``SparkSession``, so everything after the import line is
plain PySpark. Each demo in this folder calls :func:`init_session` so the
chapter has one place to change how the client reaches Snowflake.

The session resolves the ``spark-connect`` profile in ``~/.snowflake/config.toml``
(see ``config.toml.example`` next to this folder).

The batch job in ``jobs/daily_settlement.py`` deliberately does NOT use this
helper: Snowpark Submit handles its connection wiring, so it stays pure PySpark.
"""

from __future__ import annotations


def init_session():
    """Start the local translation server and return a ``SparkSession``.

    Teams that prefer zero Snowflake-specific packages can instead install
    ``pyspark[connect]`` and connect with::

        from pyspark.sql import SparkSession
        spark = SparkSession.builder.remote(
            "sc://<account>.snowflakecomputing.com:443;token=<PAT>"
        ).getOrCreate()

    The resulting session behaves identically; the trade-off is managing PATs
    instead of reusing ``connections.toml`` profiles.
    """
    from snowflake import snowpark_connect

    return snowpark_connect.init_spark_session()
