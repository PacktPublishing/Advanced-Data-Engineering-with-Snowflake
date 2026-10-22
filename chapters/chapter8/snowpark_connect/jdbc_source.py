"""Chapter 8, Section 4.3: connecting JDBC sources.

Snowpark Connect supports the Spark JDBC datasource for SQL Server, MySQL,
PostgreSQL, Neo4j, and Derby as of June 2026. The one thing native Spark did
not ask for: the driver JAR must be on the classpath of the environment running
the translation layer (an env var locally, an uploaded JAR plus external access
integration for Snowflake Notebooks).

After the read, the rows land in a temporary Snowflake table and every
subsequent DataFrame operation runs as warehouse SQL, so the JDBC pull is the
only slow link in the chain. Once more than one job wants the same source, land
it once through the Chapter 3 ingestion patterns and let every consumer read
the table.

The password below MUST come from a secret manager, never hard-coded
(secure-development rule 9: no hardcoded credentials).

Run with:  python -m snowpark_connect.jdbc_source
"""

import os

from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

ref_accounts = spark.read.jdbc(
    "jdbc:postgresql://refdb.techflow.internal:5432/reference",
    "public.merchant_accounts",
    properties={
        "user": "etl_reader",
        # Resolved from the environment / secret manager, not stored in source.
        "password": os.environ["REFDB_PASSWORD"],
        "driver": "org.postgresql.Driver",
    },
)

ref_accounts.show(5)
