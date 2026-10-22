"""Register the TechFlow Prefect flow from an immutable Git revision.

Configuration is validated without contacting Prefect. The deployment API is
called only from :func:`main`, so importing this module has no network or
registration side effects.
"""

from __future__ import annotations

import os
import re
import sys
from collections.abc import Mapping
from dataclasses import dataclass

from prefect import flow
from prefect.runner.storage import GitRepository
from prefect.schedules import Cron

REPOSITORY_URL = (
    "https://github.com/PacktPublishing/"
    "Advanced-Data-Engineering-with-Snowflake.git"
)
ENTRYPOINT = "chapters/chapter11/prefect/transform.py:techflow_transform"
DEPLOYMENT_NAME = "techflow-nightly"
CRON = "0 2 * * *"
CRON_TIMEZONE = "UTC"

GIT_SHA_PATTERN = re.compile(r"^[0-9a-fA-F]{40}$")
WORK_POOL_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
WORK_POOL_KINDS = frozenset({"hybrid", "push", "managed"})


@dataclass(frozen=True)
class DeploymentConfig:
    """Validated values that vary between deployment environments."""

    git_sha: str
    work_pool_name: str
    work_pool_kind: str


def validate_git_sha(value: str) -> str:
    """Return a normalized, full Git object ID or raise."""
    if GIT_SHA_PATTERN.fullmatch(value) is None:
        raise ValueError(
            "TECHFLOW_CODE_COMMIT_SHA must be exactly 40 hexadecimal digits"
        )
    return value.lower()


def load_config(environ: Mapping[str, str] | None = None) -> DeploymentConfig:
    """Load deployment settings without performing a network call."""
    values = os.environ if environ is None else environ
    git_sha = values.get("TECHFLOW_CODE_COMMIT_SHA") or values.get(
        "GITHUB_SHA",
        "",
    )
    work_pool_name = values.get("PREFECT_WORK_POOL_NAME", "techflow-pool")
    work_pool_kind = values.get("PREFECT_WORK_POOL_KIND", "hybrid").lower()

    if WORK_POOL_NAME_PATTERN.fullmatch(work_pool_name) is None:
        raise ValueError("PREFECT_WORK_POOL_NAME has an invalid format")
    if work_pool_kind not in WORK_POOL_KINDS:
        raise ValueError(
            "PREFECT_WORK_POOL_KIND must be hybrid, push, or managed"
        )

    return DeploymentConfig(
        git_sha=validate_git_sha(git_sha),
        work_pool_name=work_pool_name,
        work_pool_kind=work_pool_kind,
    )


def work_pool_note(config: DeploymentConfig) -> str:
    """Describe the execution responsibility for the configured pool kind."""
    if config.work_pool_kind == "hybrid":
        return (
            "Hybrid pool selected: run a Prefect worker in your infrastructure "
            f"for pool {config.work_pool_name!r}."
        )
    return (
        f"{config.work_pool_kind.title()} pool selected: Prefect submits runs "
        "without a user-operated worker."
    )


def deploy(config: DeploymentConfig) -> None:
    """Register the pinned flow and its timezone-aware nightly schedule."""
    source = GitRepository(
        url=REPOSITORY_URL,
        commit_sha=config.git_sha,
    )
    flow.from_source(
        source=source,
        entrypoint=ENTRYPOINT,
    ).deploy(
        name=DEPLOYMENT_NAME,
        version=config.git_sha,
        work_pool_name=config.work_pool_name,
        schedule=Cron(CRON, timezone=CRON_TIMEZONE),
    )


def main() -> int:
    config = load_config()
    deploy(config)
    print(work_pool_note(config))
    return 0


if __name__ == "__main__":
    sys.exit(main())
