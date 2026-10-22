# =============================================================================
# Chapter 13, Section 3.3: Querying the Service (Python API)
# Needs: chapter13_0_setup.sql + chapter13_2_cortex_search.sql already run,
#   and a `techflow` connection profile in ~/.snowflake/connections.toml
#   (Chapter 7 pattern; see chapter7/config.toml.example).
# Tested August 2026 with Python 3.11, snowflake-snowpark-python, snowflake.core.
#   pip install snowflake-snowpark-python snowflake -q
# =============================================================================

import os

from snowflake.core import Root
from snowflake.snowpark import Session

session = Session.builder.config(
    "connection_name",
    os.environ.get("SNOWFLAKE_CONNECTION", "techflow")).create()

svc = (Root(session)
       .databases["gold_db"]
       .schemas["support"]
       .cortex_search_services["ticket_search"])

hits = svc.search(
    query="refund promised but never arrived",
    columns=["ticket_id", "kb_text"],
    limit=3)

# Expect three lines; the top hit should be a refund-delay ticket
# (TKT-CH13-015, TKT-CH13-007, or TKT-CH13-022).
for r in hits.results:
    print(r["ticket_id"], r["kb_text"][:80])

session.close()
