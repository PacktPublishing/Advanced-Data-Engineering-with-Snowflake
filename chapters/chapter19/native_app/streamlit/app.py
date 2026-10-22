"""Chapter 19 Native App dashboard; run inside the installed application.

Requires the package's app_public.daily_metrics proxy view.
Uses default Native App Streamlit/Snowpark packages, no external dependencies.
Validation: Python syntax and fixture calculations checked locally; not run live.
No placeholders or credentials. Snowflake supplies the active application session.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

st.title("Payment performance")
st.caption("Synthetic fixture. UTC dates. All amounts in USD.")

session = get_active_session()
# Two-part name resolves within the installed Native App, not the provider database.
data = (
    session.table("app_public.daily_metrics")
    .select("EVENT_DATE", "MERCHANT_ID", "ATTEMPTS",
            "APPROVED_ATTEMPTS", "APPROVED_AMOUNT_USD")
    .sort("EVENT_DATE", "MERCHANT_ID")
    .to_pandas()
)

merchant = st.selectbox("Merchant", ["All"] + sorted(data["MERCHANT_ID"].unique()))
if merchant != "All":
    data = data.loc[data["MERCHANT_ID"] == merchant]

attempts = int(data["ATTEMPTS"].sum())
approved = int(data["APPROVED_ATTEMPTS"].sum())
volume = data["APPROVED_AMOUNT_USD"].sum()
st.metric("Approved volume (USD)", f"${volume:,.2f}")
st.metric("Approval rate", f"{approved / attempts:.2%}" if attempts else "No attempts")
st.dataframe(data, hide_index=True, use_container_width=True)
st.bar_chart(data, x="EVENT_DATE", y="APPROVED_AMOUNT_USD", color="MERCHANT_ID")
st.caption("Provider snapshot. The merchant filter does not enforce tenant access.")
