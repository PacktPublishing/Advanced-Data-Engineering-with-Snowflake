"""Section 4.3: Snowpark ML Feature Store + Model Registry sketch.

Demonstrates the three steps the chapter walks through:

1. Stand up a feature store with a customer entity.
2. Build a feature DataFrame and register it as a versioned ``FeatureView``.
3. Open a ``Registry`` so a trained model can be logged for SQL-side scoring.

The model-training step itself is intentionally omitted: the chapter sends
readers to the dedicated Snowpark ML resources for that part of the lifecycle.

Run directly to materialize the feature store and feature view::

    python -m snowpark.ml.feature_store_registry
"""

from __future__ import annotations

import sys

from snowflake.ml.feature_store import (
    CreationMode,
    Entity,
    FeatureStore,
    FeatureView,
)
from snowflake.ml.registry import Registry
from snowflake.snowpark.functions import (
    countDistinct,
    max as sf_max,
    sum as sf_sum,
)

from snowpark.session import build_session


def main() -> int:
    session = build_session()
    try:
        fs = FeatureStore(
            session=session,
            database="GOLD_DB",
            name="ML_FEATURE_STORE",
            default_warehouse="BOOK_WH",
            creation_mode=CreationMode.CREATE_IF_NOT_EXIST,
        )

        customer_entity = Entity(name="customer", join_keys=["customer_id"])
        fs.register_entity(customer_entity)

        features_df = (
            session.table("fact_transactions")
            .group_by("customer_id")
            .agg(
                sf_sum("amount").alias("lifetime_spend"),
                countDistinct("merchant_id").alias("unique_merchants"),
                sf_max("transaction_ts").alias("last_seen_ts"),
            )
        )

        fv = FeatureView(
            name="customer_velocity_features",
            entities=[customer_entity],
            feature_df=features_df,
            refresh_freq="1 hour",
        )
        fs.register_feature_view(feature_view=fv, version="v1", block=False)
        print("registered feature view customer_velocity_features:v1")

        # Opening the Registry is cheap; logging a model requires a trained
        # artifact, which the chapter sends to the dedicated Snowpark ML
        # references rather than reproducing here.
        Registry(
            session=session,
            database_name="GOLD_DB",
            schema_name="ML_REGISTRY",
        )
        print("opened model registry at GOLD_DB.ML_REGISTRY")
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
