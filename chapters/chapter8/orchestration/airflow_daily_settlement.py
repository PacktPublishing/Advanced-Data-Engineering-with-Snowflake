"""Chapter 8, Section 3.3: scheduling Snowpark Submit through Airflow.

Snowpark Submit is a CLI, so the integration is the orchestrator's command
operator calling the same submit we ran by hand. The minimal task keeps the
same flags and adds the wait, so the Airflow task state mirrors the workload
state.

A Snowflake Task cannot wrap this submission: Tasks execute SQL statements and
Snowpark Submit is a local process. Native Task-based scheduling belongs to the
jobs we rewrite into Snowpark stored procedures (Chapter 7), not to rehosted
Spark scripts.

The operator runs on an Airflow worker that has the virtual environment and the
connections.toml profile available. Teams running managed Airflow bake the two
pip packages (snowpark-connect, snowpark-submit) into the worker image. The
same command drops into a cron entry or a CI/CD step unchanged.

Chapter 11, Orchestrators, covers the surrounding DAG in full.
"""

from airflow.operators.bash import BashOperator

submit_settlement = BashOperator(
    task_id="daily_settlement",
    bash_command=(
        "snowpark-submit "
        "--snowflake-workload-name DAILY_SETTLEMENT "
        "--snowflake-connection-name spark-connect "
        "--compute-pool TECHFLOW_SPARK_POOL "
        "--wait-for-completion "
        "{{ var.value.jobs_dir }}/daily_settlement.py"
    ),
)
