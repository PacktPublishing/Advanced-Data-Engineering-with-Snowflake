# Chapter 16 Streamlit dashboard; requires setup and observability views.
# Warehouse runtime: Python 3.11; Snowflake-managed Streamlit/Snowpark packages.
# Validation: deployed and tested with native Streamlit AppTest in Snowflake, 2026-09-21.
# Python 3.11.16, Streamlit 1.52.2, pandas 2.3.3, Snowpark 1.55.0. See README.
# Role: private app owned by OPS_ENGINEER. Review grants before sharing.
# Placeholders: none. Companion to the Building observability section.

import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()
session.sql("ALTER SESSION SET TIMEZONE = 'UTC'").collect()
st.title("Snowflake operations")
st.caption("Seven UTC days ending before yesterday; delayed telemetry.")
st.button("Reload views")
daily = session.table("OPS_DB.MONITORING.DAILY_COMPUTE").to_pandas()
if daily.empty:
    st.info("No warehouse history in this reporting window.")
    st.stop()
warehouse = st.selectbox("Warehouse", sorted(daily.WAREHOUSE_NAME.unique()))
selected = daily[daily.WAREHOUSE_NAME == warehouse].sort_values("USAGE_DAY").copy()
st.metric("Compute credits", f"{selected.COMPUTE_CREDITS.sum():.2f}")
st.caption(f"Observed dates: {selected.USAGE_DAY.min()} to "
           f"{selected.USAGE_DAY.max()}")

if selected.IDLE_CREDITS.isna().any():
    st.info("Query and idle attribution are unavailable for part of this selection.")
chart = selected.set_index("USAGE_DAY")[["COMPUTE_CREDITS", "QUERY_CREDITS"]]
st.line_chart(chart.astype(float))
st.dataframe(selected, hide_index=True)
health = session.table("OPS_DB.MONITORING.QUERY_HEALTH").to_pandas()
health = health[health.WAREHOUSE_NAME == warehouse]
st.subheader("Successful query families")
st.dataframe(health.sort_values("P95_SECONDS", ascending=False).head(20),
             hide_index=True)
st.caption("Refresh queries the views again; source latency still applies.")
