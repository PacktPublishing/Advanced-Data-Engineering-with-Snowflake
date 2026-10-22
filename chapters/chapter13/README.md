# How To Run Chapter 13 (Snowflake Cortex AI for Data Engineering)

This chapter runs AI inside the platform: Cortex AI Functions over a support-ticket fixture, a Cortex Search service with a RAG pattern, the Cortex Analyst REST API over the Chapter 12 semantic view, and a Cortex Agent published to Snowflake CoWork with Cortex AI Guardrails enabled.

Everything the chapter creates lives in the chapter-owned schema `gold_db.support`, so `chapter13_teardown.sql` removes it without touching earlier chapters. The chapter text never names these files (book convention since Chapter 5); it refers to each by the role in the second column. One script per main section, each embedding its own data and ending with its validation set:

| File | Referred to in the chapter as | Chapter section | Needs |
|------|-------------------------------|-----------------|-------|
| [chapter13_0_setup.sql](chapter13_0_setup.sql) | the companion setup script | Schema + 40-ticket fixture (2.1 Loading the TechFlow ticket fixture) — **run once first**; ends with the optional, commented per-user AI spend quota (1.3) | Any edition; quota block needs `SNOWFLAKE.QUOTA_CREATOR` |
| [chapter13_1_ai_functions.sql](chapter13_1_ai_functions.sql) | the companion AI functions script | Enriching and classifying text at scale with Cortex AI Functions (2.2 to 2.6) | Any edition, CORTEX_USER; EXECUTE TASK for the smoke test |
| [chapter13_2_cortex_search.sql](chapter13_2_cortex_search.sql) | the companion search script | Building hybrid retrieval and RAG pipelines with Cortex Search (3.1, 3.2, 3.3 SQL, 3.4, 3.5) | Any edition, CORTEX_USER |
| [chapter13_2_search_client.py](chapter13_2_search_client.py) | the companion search client | 3.3 Querying the service (step 2, Python) | `connections.toml` profile |
| [chapter13_3_analyst_api.py](chapter13_3_analyst_api.py) | the companion Analyst client | Integrating Cortex Analyst through the REST API (4.1, 4.2) | **Chapter 12 semantic view**, PAT |
| [chapter13_4_agent.sql](chapter13_4_agent.sql) | the companion agent script | Orchestrating tools with Cortex Agents and Snowflake CoWork (5.1, 5.3, 5.4 incl. the commented red-team block) | **Chapter 12 view + section 3 service**; Guardrails block: **Enterprise+**, ACCOUNTADMIN |
| [chapter13_4_agent_run.py](chapter13_4_agent_run.py) | the companion agent client | 5.2 Testing in the playground and running via the API | Agent from chapter13_4, PAT |
| [chapter13_teardown.sql](chapter13_teardown.sql) | the companion teardown script | Removes every Chapter 13 object (5.4 cleanup paragraph) | — |

Dependencies between section files: sections 2 and 3 need only the setup. Section 4 needs the Chapter 12 semantic view (`gold_db.semantic.techflow_revenue`; run the chapter12 companion scripts if missing). Section 5 needs both the Chapter 12 view and the section 3 search service.

## Prerequisites

- `setup/snowflake_setup.sql` (BOOK_WH) and, for sections 4-5, the [chapter12](../chapter12/README.md) companion scripts.
- A role with `SNOWFLAKE.CORTEX_USER` (granted in setup), `CREATE CORTEX SEARCH SERVICE` and `CREATE AGENT` on `gold_db.support`; agent consumers additionally need `SNOWFLAKE.CORTEX_AGENT_USER`.
- **Python 3.11+** with `requests` for the REST clients, plus `snowflake-snowpark-python` and `snowflake` for the search client. A Snowflake CLI profile in `~/.snowflake/connections.toml` (see [chapter7/config.toml.example](../chapter7/config.toml.example)), or `snow sql -c book` as documented in [setup/SETUP.md](../../setup/SETUP.md).
- AI features are disabled on self-service trial accounts until a credit card is added to the account (the trial stays a trial).
- A programmatic access token exported as `SNOWFLAKE_PAT` for the two REST clients. Without a network policy on the account, create it with `ALTER USER ADD PROGRAMMATIC ACCESS TOKEN ... MINS_TO_BYPASS_NETWORK_POLICY_REQUIREMENT = 240` (see the header of `chapter13_3_analyst_api.py`). Set `SNOWFLAKE_ACCOUNT_URL=https://<account_identifier>.snowflakecomputing.com` (or replace the placeholder in both Python files).
- Cross-region inference (`CORTEX_ENABLED_CROSS_REGION`) if a function reports an unavailable model in your region, and always for Cortex AI Guardrails.

## Cost notes (this chapter is the first where re-runs cost tokens)

- Every `AI_*` function call bills per token. The 40-row fixture keeps each statement to a rounding error; price anything bigger first with the `AI_COUNT_TOKENS` estimate at the end of `chapter13_1_ai_functions.sql`.
- The search service's serving meter runs per GB-month **while the service exists**, queries or not. Run `chapter13_teardown.sql` when you finish the chapter.
- Guardrails bill per token scanned once enabled (account-level).

## Fixture v2 (2026-08-23)

The ticket fixture's `merchant_category` values now come from the revenue-side vocabulary in `gold_db.merchants.dim_merchants` (travel, groceries, retail, dining, streaming, all lowercase), so the agent's cross-tool answer connects refund spikes to complaints in the same categories. Re-run after pulling this version: `chapter13_0_setup.sql` (reload), `chapter13_1_ai_functions.sql` (re-enrich and re-score; the 12 hand labels are on unchanged rows), `chapter13_2_cortex_search.sql` (rebuild the knowledge base and service; the SEARCH_PREVIEW filter is now `"travel"`), and the agent playground question. Revenue-side figures are unaffected.

## Round 2 changes (2026-10-02)

- `mistral-large2` replaced by `llama3.3-70b` in `chapter13_1_ai_functions.sql` (AI_COMPLETE extraction, AI_COUNT_TOKENS) and `chapter13_2_cortex_search.sql` (RAG and refusal). mistral-large2 went legacy on 2026-08-12 and reaches end of life on 2026-10-14. **Re-run sections 2.4, 2.6 step 3, and 3.4** and check the outputs the chapter prints (extraction rows, token count, grounded answer and refusal).
- Optional per-user AI spend quota added (commented) at the end of `chapter13_0_setup.sql`, with the matching commented DROP in the teardown.
- PAT network-policy note added to `chapter13_3_analyst_api.py`.

## Verification notes

When you run the chapter, confirm `AI_CLASSIFY` labels all fixture rows, SEARCH_PREVIEW returns the expected ticket id first for a known query, RAG answers cite the knowledge base and refuse off-topic prompts, and `CREATE AGENT` succeeds. `AI_CLASSIFY` on the full fixture can take longer than a small smoke test.

Cortex Analyst REST and agent `:run` need `SNOWFLAKE_PAT` in the shell. CoWork and account-level Guardrails are optional extensions in the manuscript. Drop `gold_db.support` with `chapter13_teardown.sql` when you finish — the search service bills while it exists.
