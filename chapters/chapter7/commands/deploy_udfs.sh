#!/usr/bin/env bash
set -euo pipefail

# Chapter 7: deploy every Snowpark UDF, UDTF, and stored procedure.
# Each module's `main()` registers its artifact under @gold_db.public.udf_stage
# or @gold_db.public.sproc_stage with replace=True, so re-running is safe.

if [ -z "${VIRTUAL_ENV:-}" ]; then
    source .venv/bin/activate
fi

python -m snowpark.udfs.scalar_risk_tier
python -m snowpark.udfs.vectorized_risk_tier
python -m snowpark.udtfs.velocity_flagger
python -m snowpark.sprocs.promote_customer_batch

echo "Deployed: classify_risk_tier, classify_risk_tier_vec, flag_velocity_bursts, promote_customer_batch"
