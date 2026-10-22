"""Drop a sample fraud-score file into S3 so the workflow has something to wait on.

This stands in for the fraud team's Kubernetes scoring job. It writes a small
Parquet file named ``fraud_scores_<date>.parquet`` under the ``scores/`` prefix
of the target bucket, with the columns the landing table and the reverse-ETL
join expect: ``merchant_id``, ``risk_score``, and ``scored_date``.

Credentials come from the standard boto3 chain (environment, shared config, or
instance role); none are read from arguments. Importing this module has no side
effects. Run it directly to upload one file.
"""

from __future__ import annotations

import argparse
import io
import re
import sys
from datetime import date, timedelta

import boto3
import pyarrow as pa
import pyarrow.parquet as pq

BUCKET_PATTERN = re.compile(r"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$")
PREFIX_PATTERN = re.compile(r"^[A-Za-z0-9!_.*'()/-]{0,512}$")

# A fixed, tiny sample. The merchant ids are the string ids the Chapter 5 fact
# table seeds and Chapter 9 cleanses into silver, so the reverse-ETL join on
# merchant_id actually matches rows. Two merchants clear the > 0.8 high-risk
# threshold the push filters on, so the pushed segment is never empty.
SAMPLE_SCORES = [
    ("MERCH_GROC_1", 0.92),
    ("MERCH_GROC_2", 0.11),
    ("MERCH_ELEC_1", 0.87),
    ("MERCH_TRVL_1", 0.44),
]


def build_parquet_bytes(scored_date: date) -> bytes:
    """Serialize the sample scores for one day to an in-memory Parquet blob."""
    table = pa.table(
        {
            "merchant_id": pa.array([m for m, _ in SAMPLE_SCORES], pa.string()),
            "risk_score": pa.array([s for _, s in SAMPLE_SCORES], pa.float64()),
            "scored_date": pa.array(
                [scored_date] * len(SAMPLE_SCORES), pa.date32()
            ),
        }
    )
    buffer = io.BytesIO()
    pq.write_table(table, buffer)
    return buffer.getvalue()


def upload(bucket: str, prefix: str, scored_date: date) -> str:
    """Upload the sample file and return the key it was written to."""
    if BUCKET_PATTERN.fullmatch(bucket) is None:
        raise ValueError("bucket is not a valid S3 bucket name")
    normalized_prefix = prefix.strip("/")
    if PREFIX_PATTERN.fullmatch(normalized_prefix) is None:
        raise ValueError("prefix has an invalid format")

    key = f"{normalized_prefix}/fraud_scores_{scored_date.isoformat()}.parquet"
    boto3.client("s3").put_object(
        Bucket=bucket,
        Key=key,
        Body=build_parquet_bytes(scored_date),
    )
    return key


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", default="techflow-ml")
    parser.add_argument("--prefix", default="scores")
    parser.add_argument(
        "--date",
        default=(date.today() - timedelta(days=1)).isoformat(),
        help="scored date (YYYY-MM-DD); defaults to yesterday, matching {{ ds }}",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    scored_date = date.fromisoformat(args.date)
    key = upload(args.bucket, args.prefix, scored_date)
    print(f"Uploaded s3://{args.bucket}/{key}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
