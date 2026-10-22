"""Create the Prefect Snowflake blocks used by ``transform.py``.

All connection values come from validated environment variables. The private
key is supplied as PEM content rather than a caller-controlled file path, so
this script cannot be redirected to read an arbitrary local file. Saving
blocks happens only when :func:`main` is called.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections.abc import Mapping
from dataclasses import dataclass, field

from prefect_snowflake import SnowflakeCredentials
from prefect_snowflake.database import SnowflakeConnector

ACCOUNT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,254}$")
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]{0,254}$")
BLOCK_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,127}$")
PRIVATE_KEY_PATTERN = re.compile(
    rb"\A-----BEGIN (?P<label>PRIVATE KEY|ENCRYPTED PRIVATE KEY|RSA PRIVATE KEY)"
    rb"-----\r?\n[A-Za-z0-9+/=\r\n]+-----END (?P=label)-----\s*\Z"
)
MAX_PRIVATE_KEY_BYTES = 64 * 1024
MAX_PASSPHRASE_CHARACTERS = 4 * 1024


@dataclass(frozen=True)
class BlockConfig:
    """Validated inputs for the credentials and connector blocks."""

    account: str
    user: str
    role: str
    database: str
    schema: str
    warehouse: str
    credentials_block_name: str
    connector_block_name: str
    private_key: bytes = field(repr=False)
    private_key_passphrase: str | None = field(default=None, repr=False)


def _required(environ: Mapping[str, str], name: str) -> str:
    raw_value = environ.get(name, "")
    if not isinstance(raw_value, str):
        raise ValueError(f"{name} must be text")
    value = raw_value.strip()
    if not value:
        raise ValueError(f"{name} is required")
    return value


def _validated(
    value: str,
    *,
    name: str,
    pattern: re.Pattern[str],
) -> str:
    if pattern.fullmatch(value) is None:
        raise ValueError(f"{name} has an invalid format")
    return value


def _private_key_from_env(environ: Mapping[str, str]) -> bytes:
    value = _required(environ, "SNOWFLAKE_PRIVATE_KEY").encode()
    if len(value) > MAX_PRIVATE_KEY_BYTES:
        raise ValueError("SNOWFLAKE_PRIVATE_KEY exceeds 64 KiB")
    if PRIVATE_KEY_PATTERN.fullmatch(value) is None:
        raise ValueError(
            "SNOWFLAKE_PRIVATE_KEY must contain one complete PEM private key"
        )
    return value


def _private_key_passphrase(environ: Mapping[str, str]) -> str | None:
    value = environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
    if value in (None, ""):
        return None
    if not isinstance(value, str):
        raise ValueError("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE must be text")
    if "\0" in value or len(value) > MAX_PASSPHRASE_CHARACTERS:
        raise ValueError("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE has an invalid format")
    return value


def load_config(environ: Mapping[str, str] | None = None) -> BlockConfig:
    """Load and validate block configuration without contacting any service."""
    values = os.environ if environ is None else environ

    account = _validated(
        _required(values, "SNOWFLAKE_ACCOUNT"),
        name="SNOWFLAKE_ACCOUNT",
        pattern=ACCOUNT_PATTERN,
    )
    user = _validated(
        _required(values, "SNOWFLAKE_USER"),
        name="SNOWFLAKE_USER",
        pattern=IDENTIFIER_PATTERN,
    )
    role = _validated(
        _required(values, "SNOWFLAKE_ROLE"),
        name="SNOWFLAKE_ROLE",
        pattern=IDENTIFIER_PATTERN,
    )
    database = _validated(
        values.get("SNOWFLAKE_DATABASE", "OPS_DB").strip(),
        name="SNOWFLAKE_DATABASE",
        pattern=IDENTIFIER_PATTERN,
    )
    schema = _validated(
        values.get("SNOWFLAKE_SCHEMA", "PIPELINES").strip(),
        name="SNOWFLAKE_SCHEMA",
        pattern=IDENTIFIER_PATTERN,
    )
    warehouse = _validated(
        values.get("SNOWFLAKE_WAREHOUSE", "BOOK_WH").strip(),
        name="SNOWFLAKE_WAREHOUSE",
        pattern=IDENTIFIER_PATTERN,
    )
    credentials_block_name = _validated(
        values.get(
            "PREFECT_SNOWFLAKE_CREDENTIALS_BLOCK",
            "techflow-snowflake-credentials",
        ).strip(),
        name="PREFECT_SNOWFLAKE_CREDENTIALS_BLOCK",
        pattern=BLOCK_NAME_PATTERN,
    )
    connector_block_name = _validated(
        values.get(
            "PREFECT_SNOWFLAKE_CONNECTOR_BLOCK",
            "techflow-snowflake",
        ).strip(),
        name="PREFECT_SNOWFLAKE_CONNECTOR_BLOCK",
        pattern=BLOCK_NAME_PATTERN,
    )
    return BlockConfig(
        account=account,
        user=user,
        role=role,
        database=database,
        schema=schema,
        warehouse=warehouse,
        credentials_block_name=credentials_block_name,
        connector_block_name=connector_block_name,
        private_key=_private_key_from_env(values),
        private_key_passphrase=_private_key_passphrase(values),
    )


def save_blocks(config: BlockConfig, *, overwrite: bool = False) -> None:
    """Save key-pair credentials and a manual-commit connector block."""
    credentials = SnowflakeCredentials(
        account=config.account,
        user=config.user,
        role=config.role,
        authenticator="snowflake_jwt",
        private_key=config.private_key,
        private_key_passphrase=config.private_key_passphrase,
        autocommit=False,
    )
    credentials.save(config.credentials_block_name, overwrite=overwrite)

    connector = SnowflakeConnector(
        credentials=credentials,
        database=config.database,
        schema=config.schema,
        warehouse=config.warehouse,
    )
    connector.save(config.connector_block_name, overwrite=overwrite)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="replace existing blocks with the same names",
    )
    args = parser.parse_args()

    config = load_config()
    save_blocks(config, overwrite=args.overwrite)
    print(
        "Saved Prefect blocks "
        f"{config.credentials_block_name!r} and "
        f"{config.connector_block_name!r} with autocommit disabled."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
