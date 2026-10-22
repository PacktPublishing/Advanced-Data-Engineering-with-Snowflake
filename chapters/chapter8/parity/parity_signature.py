"""Chapter 8, Section 6.4: the parity harness.

Parity is measured, never assumed. The protocol closes every review, in this
order:

  1. Normalize types on both outputs (cast the integer family to one width and
     money to an agreed DECIMAL), because Section 2.2's coercions otherwise
     produce false mismatches on correct code.
  2. Compare row counts.
  3. Compare an order-independent checksum on the normalized sample.

Run the SAME function against the Spark output and the Snowpark output on the
same 1 percent sample. The job passes review when both pairs match. The sum of
per-row checksums ignores row order, which spares us a sort neither engine
would perform identically anyway.

Match before commit, every job, no exceptions for jobs that look trivial.

Example (money_cols names the AMOUNT-family columns for this table):
    spark_sig  = parity_signature(spark_df,   cols, money_cols={"settled_amount_usd"})
    snow_sig   = parity_signature(snowpark_df, cols, money_cols={"settled_amount_usd"})
    assert spark_sig == snow_sig
"""

from pyspark.sql.functions import concat_ws, crc32, sum as sf_sum, col


def parity_signature(df, cols, money_cols):
    normalized = df.select(
        *[
            col(c).cast("decimal(18,2)") if c in money_cols
            else col(c).cast("string")
            for c in cols
        ]
    )
    return normalized.select(
        sf_sum(crc32(concat_ws("|", *cols))).alias("checksum")
    ).collect()[0]["checksum"], normalized.count()
