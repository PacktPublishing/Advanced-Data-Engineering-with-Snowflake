"""Assemble the Chapter 11 Dagster project.

The loader walks the ``defs`` folder for the dbt component and merges it with
the Python definitions below. A file that builds a ``Definitions`` object
exports only what that object names, so every asset, the resource, and the
sensor must appear here. The sensor is this graph's trigger; ``schedules.py``
holds the time-driven alternative described in the chapter.
"""

from pathlib import Path

import dagster as dg
from dagster_snowflake import SnowflakeResource

from techflow_orchestration.assets import (
    fraud_scores,
    marketing_segment,
    merchant_daily_revenue,
    transactions_clean,
)
from techflow_orchestration.sensors import scores_sensor

PROJECT_ROOT = Path(__file__).resolve().parents[2]

# The service user's key file is unencrypted, the same file every tool in this
# chapter loads, so no password field appears. An encrypted key adds
# private_key_password=dg.EnvVar("SNOWFLAKE_PRIVATE_KEY_PASSWORD") here.
snowflake_resource = SnowflakeResource(
    account=dg.EnvVar("SNOWFLAKE_ACCOUNT"),
    user=dg.EnvVar("SNOWFLAKE_USER"),
    private_key_path=dg.EnvVar("SNOWFLAKE_PRIVATE_KEY_PATH"),
    warehouse="BOOK_WH",
    role="TRANSFORMER_RL",
)


@dg.definitions
def defs() -> dg.Definitions:
    python_definitions = dg.Definitions(
        assets=[
            fraud_scores,
            transactions_clean,
            merchant_daily_revenue,
            marketing_segment,
        ],
        sensors=[scores_sensor],
        resources={"snowflake": snowflake_resource},
    )
    component_definitions = dg.load_from_defs_folder(project_root=PROJECT_ROOT)
    return dg.Definitions.merge(python_definitions, component_definitions)
