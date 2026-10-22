"""Non-mutating checks for the Chapter 11 companion project."""

from __future__ import annotations

import ast
import json
import re
import unittest
from pathlib import Path


CHAPTER_DIR = Path(__file__).resolve().parents[1]
# The single shared dbt project lives in Chapter 6; there is no chapter-11 copy.
DBT_PROJECT_DIR = CHAPTER_DIR.parent / "chapter6" / "dbt" / "techflow_warehouse"

MANUSCRIPT_BLOCK_COUNT = 26

MAPPED_COMPANION_FILES = (
    "airflow/dags/techflow_common.py",
    "airflow/dags/techflow_transform.py",
    "airflow/dags/fraud_scores_ingest.py",
    "airflow/dags/transaction_transform.py",
    "airflow/dags/marketing_activation.py",
    "airflow/dags/sql/load_fraud_scores.sql",
    "airflow/dags/sql/build_daily_revenue_incremental.sql",
    "airflow/init_pools.sh",
    "airflow/config/dag_bundles.ini.example",
    "prefect/transform.py",
    "prefect/deploy.py",
    "dagster/src/techflow_orchestration/assets.py",
    "dagster/src/techflow_orchestration/sensors.py",
    "tests/test_dags.py",
    "sql/set_query_tag.sql",
)


def read(relative_path: str) -> str:
    """Read one UTF-8 companion file."""
    return (CHAPTER_DIR / relative_path).read_text(encoding="utf-8")


class CompanionStructureTests(unittest.TestCase):
    def test_all_manuscript_blocks_are_mapped(self) -> None:
        block_map = read("CODE_BLOCK_MAP.md")

        for block_number in range(1, MANUSCRIPT_BLOCK_COUNT + 1):
            self.assertRegex(
                block_map,
                rf"(?m)^\|\s*{block_number}\s*\|",
                f"Code block {block_number} is missing from CODE_BLOCK_MAP.md",
            )
        self.assertNotRegex(
            block_map,
            rf"(?m)^\|\s*{MANUSCRIPT_BLOCK_COUNT + 1}\s*\|",
            "CODE_BLOCK_MAP.md has a stale extra block row",
        )
        for relative_path in MAPPED_COMPANION_FILES:
            with self.subTest(path=relative_path):
                self.assertTrue(
                    (CHAPTER_DIR / relative_path).is_file(),
                    f"{relative_path} is mapped but missing",
                )

    def test_python_files_parse_without_importing_frameworks(self) -> None:
        python_files = [
            path
            for path in CHAPTER_DIR.rglob("*.py")
            if "_to_delete" not in path.parts
        ]
        self.assertGreaterEqual(len(python_files), 8)

        for python_file in python_files:
            with self.subTest(path=python_file.relative_to(CHAPTER_DIR)):
                ast.parse(python_file.read_text(encoding="utf-8"))

    def test_secret_files_are_ignored(self) -> None:
        gitignore = read(".gitignore")
        self.assertIn(".env", gitignore)
        self.assertIn(".venv/", gitignore)

    def test_shared_cross_system_artifacts_exist(self) -> None:
        for relative_path in (
            "sql/setup.sql",
            "sql/suspend_chapter9.sql",
            "upload_scores.py",
            "marketing_api/app.py",
            "marketing_api/Dockerfile",
        ):
            with self.subTest(path=relative_path):
                self.assertTrue((CHAPTER_DIR / relative_path).is_file())

    def test_setup_sql_is_review_only_and_matches_role_contract(self) -> None:
        setup_sql = read("sql/setup.sql")
        self.assertIn("REVIEW ONLY", setup_sql)
        self.assertIn("TYPE = SERVICE", setup_sql)
        self.assertIn("GRANT USAGE ON WAREHOUSE BOOK_WH", setup_sql)
        self.assertIn("GRANT CREATE TABLE, CREATE VIEW ON SCHEMA gold_db.transactions", setup_sql)
        self.assertIn("GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE", setup_sql)

    def test_marketing_api_honors_idempotency_key(self) -> None:
        api = read("marketing_api/app.py")
        self.assertIn("duplicate", api)
        self.assertIn("Idempotency-Key", api)


class AirflowCompanionTests(unittest.TestCase):
    def test_airflow_uses_current_public_api_and_cosmos_mapping(self) -> None:
        dag = read("airflow/dags/techflow_transform.py")
        common = read("airflow/dags/techflow_common.py")

        self.assertIn("from airflow.sdk import DAG", dag)
        self.assertIn("CronDataIntervalTimetable", dag)
        self.assertIn("SnowflakePrivateKeyPemProfileMapping", common)
        self.assertNotIn("SnowflakeUserPrivateKeyProfileMapping", dag + common)
        self.assertNotIn("SnowflakeOperator", dag + common)

    def test_airflow_cross_system_chain_is_complete(self) -> None:
        dag = read("airflow/dags/techflow_transform.py")
        compact = re.sub(r"\s+", " ", dag)

        self.assertIn("S3KeySensor", dag)
        self.assertIn("deferrable=True", dag)
        self.assertIn("push_segment_for_interval", dag)
        self.assertIn(
            "wait_for_scores >> load_scores >> cleanse >> dbt_transform "
            ">> build_daily_revenue >> push_segment_for_interval()",
            compact,
        )

    def test_airflow_push_is_retry_safe(self) -> None:
        common = read("airflow/dags/techflow_common.py")
        self.assertIn("Idempotency-Key", common)
        self.assertIn("raise_for_status", common)
        self.assertIn("float(revenue)", common)

    def test_airflow_sql_files_are_present_and_warn(self) -> None:
        cleanse_sql = read("airflow/dags/sql/cleanse_transactions.sql")
        aggregate_sql = read("airflow/dags/sql/build_daily_revenue.sql")
        load_sql = read("airflow/dags/sql/load_fraud_scores.sql")
        incremental_sql = read("airflow/dags/sql/build_daily_revenue_incremental.sql")

        self.assertIn("CALL ops_db.pipelines.run_cleanse()", cleanse_sql)
        self.assertIn("INSERT OVERWRITE", aggregate_sql)
        self.assertIn("entire target table", aggregate_sql.lower())
        self.assertIn("COPY INTO raw_db.streaming.fraud_scores", load_sql)
        self.assertIn("BEGIN;", incremental_sql)
        self.assertIn("split_statements=False", read("airflow/dags/techflow_transform.py"))

    def test_split_dags_exist_with_matching_partition_format(self) -> None:
        ingest = read("airflow/dags/fraud_scores_ingest.py")
        transform = read("airflow/dags/transaction_transform.py")
        activation = read("airflow/dags/marketing_activation.py")

        for source in (ingest, transform):
            self.assertIn('key_format="%Y-%m-%d"', source)
            self.assertIn("run_offset=-1", source)
        self.assertIn("PartitionedAssetTimetable", activation)
        self.assertIn("IdentityMapper", activation)
        self.assertIn("push_segment_for_partition", activation)
        self.assertIn("timedelta(hours=2)", activation)
        self.assertNotIn("pendulum.duration(hours=2)", activation)

    def test_snowflake_asset_uris_include_account_database_schema_table(self) -> None:
        common = read("airflow/dags/techflow_common.py")
        self.assertIn("snowflake://book/raw_db/streaming/fraud_scores", common)
        self.assertIn(
            "snowflake://book/gold_db/transactions/merchant_daily_revenue",
            common,
        )
        self.assertNotIn('uri="snowflake://raw_db/', common)
        self.assertNotIn('uri="snowflake://gold_db/', common)

    def test_airflow_manifest_selects_a_nightly_model(self) -> None:
        manifest = json.loads(read("airflow/manifests/manifest.json"))
        nightly_models = [
            node
            for node in manifest["nodes"].values()
            if node.get("resource_type") == "model"
            and "nightly" in node.get("tags", [])
        ]

        self.assertTrue(nightly_models)

    def test_airflow_compose_is_local_with_marketing_api(self) -> None:
        compose = read("airflow/docker-compose.yml")
        env_example = read("airflow/.env.example")

        self.assertIn("127.0.0.1:8080:8080", compose)
        self.assertIn("DAGS_ARE_PAUSED_AT_CREATION", compose)
        self.assertIn("marketing-api", compose)
        self.assertIn("AIRFLOW_CONN_AWS_TECHFLOW", compose)
        self.assertNotIn("BEGIN PRIVATE KEY", env_example)


class PrefectCompanionTests(unittest.TestCase):
    def test_prefect_flow_composes_cross_system_workflow(self) -> None:
        flow = read("prefect/transform.py")

        self.assertIn("def wait_for_scores", flow)
        self.assertIn("def push_segment", flow)
        self.assertIn("PrefectDbtRunner", flow)
        self.assertIn("PrefectDbtSettings", flow)
        self.assertIn("retry_condition_fn", flow)
        self.assertIn("scheduled_start_time", flow)
        self.assertIn("def _resolve_run_date", flow)
        self.assertIn("def rebuild_revenue_partition", flow)
        self.assertIn("DELETE_REVENUE_SQL", flow)
        self.assertRegex(flow, r"\bpush\.result\(\)")
        self.assertRegex(flow, r"\bcleanse\.result\(\)")

    def test_prefect_deployment_pins_full_commit(self) -> None:
        deployment = read("prefect/deploy.py")

        self.assertIn("TECHFLOW_CODE_COMMIT_SHA", deployment)
        self.assertIn("{40}", deployment)
        self.assertIn("timezone=", deployment)

    def test_prefect_setup_has_no_import_time_save(self) -> None:
        setup_source = read("prefect/setup_blocks.py")
        module = ast.parse(setup_source)
        top_level_calls = [
            node
            for node in module.body
            if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
        ]

        self.assertEqual([], top_level_calls)


class DagsterCompanionTests(unittest.TestCase):
    def test_dagster_registers_all_assets_and_the_sensor(self) -> None:
        definitions = read(
            "dagster/src/techflow_orchestration/definitions.py"
        )

        self.assertIn("load_from_defs_folder", definitions)
        self.assertIn("Definitions.merge", definitions)
        self.assertIn("sensors=[scores_sensor]", definitions)
        self.assertIn("SNOWFLAKE_PRIVATE_KEY_PATH", definitions)
        for asset in (
            "fraud_scores",
            "transactions_clean",
            "merchant_daily_revenue",
            "marketing_segment",
        ):
            self.assertIn(asset, definitions)

    def test_dagster_assets_are_partitioned_and_loadable(self) -> None:
        assets = read("dagster/src/techflow_orchestration/assets.py")
        sql = read("dagster/src/techflow_orchestration/sql.py")

        self.assertNotRegex(assets, r"(?m)^from __future__ import annotations")
        self.assertIn("dg.AssetExecutionContext", assets)
        self.assertIn("partitions_def=DAILY_PARTITIONS", assets)
        self.assertIn('dg.AssetKey("merchant_activity")', assets)
        self.assertIn("DELETE_REVENUE_SQL", sql)
        self.assertIn("INSERT_REVENUE_SQL", sql)
        self.assertIn("fraud_scores_{run_date}.parquet", sql)
        self.assertNotIn("|| %(run_date)s", sql)
        self.assertNotIn("MAX(revenue_date)", sql)

    def test_dagster_sensor_uses_current_helper(self) -> None:
        sensor = read("dagster/src/techflow_orchestration/sensors.py")

        self.assertNotRegex(sensor, r"(?m)^from __future__ import annotations")
        self.assertIn("dg.SensorEvaluationContext", sensor)
        self.assertIn("from dagster_aws.s3.sensor import get_objects", sensor)
        self.assertNotIn("get_s3_keys", sensor)
        self.assertIn("update_cursor", sensor)
        self.assertIn("RunRequest", sensor)
        self.assertIn("partition_key=", sensor)
        self.assertIn("ETag", sensor)

    def test_dbt_component_uses_current_project_root(self) -> None:
        component = read(
            "dagster/src/techflow_orchestration/defs/"
            "techflow_dbt/defs.yaml"
        )

        self.assertIn("context.project_root", component)
        self.assertIn('select: "tag:nightly"', component)
        self.assertIn("chapter6/dbt/techflow_warehouse", component)

    def test_no_local_dbt_copy_exists(self) -> None:
        self.assertFalse((CHAPTER_DIR / "dbt").exists())

    def test_chapter11_additions_live_in_shared_project(self) -> None:
        merchant_activity = (
            DBT_PROJECT_DIR / "models" / "gold" / "merchant_activity.sql"
        ).read_text(encoding="utf-8")
        source_yaml = (
            DBT_PROJECT_DIR / "models" / "gold" / "_chapter11_sources.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("source('transactions', 'transactions_clean')", merchant_activity)
        self.assertIn("'nightly'", merchant_activity)
        self.assertIn("transactions_clean", source_yaml)
        self.assertIn("asset_key", source_yaml)
        self.assertIn("config:", source_yaml)


if __name__ == "__main__":
    unittest.main()
