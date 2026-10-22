"""Pure configuration tests for the Chapter 11 Prefect example."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


CHAPTER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CHAPTER_DIR / "prefect"))

try:
    from deploy import load_config as load_deployment_config
    from deploy import validate_git_sha
    from setup_blocks import load_config as load_block_config

    PREFECT_AVAILABLE = True
except ImportError:
    # Prefect is not part of the non-mutating static environment. These tests
    # exercise the pure configuration helpers and are skipped when the
    # framework is not installed.
    PREFECT_AVAILABLE = False


@unittest.skipUnless(PREFECT_AVAILABLE, "prefect is not installed")
class PrefectDeploymentConfigTests(unittest.TestCase):
    def test_full_git_sha_is_normalized(self) -> None:
        git_sha = "ABCDEF0123456789ABCDEF0123456789ABCDEF01"
        self.assertEqual(git_sha.lower(), validate_git_sha(git_sha))

    def test_branch_name_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            validate_git_sha("main")

    def test_hybrid_pool_configuration_is_pure(self) -> None:
        config = load_deployment_config(
            {
                "TECHFLOW_CODE_COMMIT_SHA": "a" * 40,
                "PREFECT_WORK_POOL_NAME": "techflow-pool",
                "PREFECT_WORK_POOL_KIND": "hybrid",
            }
        )

        self.assertEqual("a" * 40, config.git_sha)
        self.assertEqual("techflow-pool", config.work_pool_name)


@unittest.skipUnless(PREFECT_AVAILABLE, "prefect is not installed")
class PrefectBlockConfigTests(unittest.TestCase):
    def test_environment_values_are_validated_without_saving_blocks(self) -> None:
        config = load_block_config(
            {
                "SNOWFLAKE_ACCOUNT": "organization-account",
                "SNOWFLAKE_USER": "TECHFLOW_SERVICE",
                "SNOWFLAKE_ROLE": "TRANSFORMER_RL",
                "SNOWFLAKE_PRIVATE_KEY": (
                    "-----BEGIN ENCRYPTED PRIVATE KEY-----\n"
                    "QUJDRA==\n"
                    "-----END ENCRYPTED PRIVATE KEY-----"
                ),
                "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE": "not-a-real-secret",
            }
        )

        self.assertEqual("OPS_DB", config.database)
        self.assertEqual("PIPELINES", config.schema)
        self.assertNotIn("not-a-real-secret", repr(config))

    def test_malformed_private_key_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            load_block_config(
                {
                    "SNOWFLAKE_ACCOUNT": "organization-account",
                    "SNOWFLAKE_USER": "TECHFLOW_SERVICE",
                    "SNOWFLAKE_ROLE": "TRANSFORMER_RL",
                    "SNOWFLAKE_PRIVATE_KEY": "not a PEM",
                }
            )


if __name__ == "__main__":
    unittest.main()
