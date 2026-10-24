# Chapter 19: Analytics Consumption & BI Integration Patterns

This chapter uses 12 synthetic payment attempts and a merchant-day reporting contract, plus a
generated 20-million-row benchmark table for the load test in section 2.3. The chapter text never
names these files (book convention since Chapter 5) except `manifest.yml` and `SKILL.md`, which are
the subject being taught, and the two Python clients and `requirements.txt`, which appear in the
commands the reader types. Otherwise it refers to each file by the role in the second column.

## Validation status

Official documentation checked October 2026. Fixture arithmetic, source-to-excerpt alignment,
YAML structure, package paths and Python syntax are checked locally by `static_checks.py`.

The author rebuilt the lab from a clean state and ran it live on a sandbox account on 2026-10-24
(Python 3.12, Snowflake Connector for Python 5.1.0): setup with the test user block, the BI
worksheet, the interactive worksheet including the freshness block and three load runs, the
Native App release with the four uploaded files (Snowflake reports `streamlit==1.35.0`), the
semantic view with five metrics, the agent with `tool_not_accessible: reject`, and the chat
client for both identities (the `NO_DATA_READER` run returned HTTP 403 `TOOL_NOT_ACCESSIBLE`).
The Sigma page and its Snowsight queries were captured live on 2026-10-24 (see *BI client
notes: Sigma*). Findings from that run, now reflected in the files:

- the freshness block needs a UTC session, because `source_updated_at` stores UTC wall time;
  with it, the refreshed table caught up 28 to 45 seconds after the update;
- eight workers send more than 10,000 queries per run, the most `QUERY_HISTORY_BY_USER`
  returns, so the load results block gives Snowflake-side latency for the latest 10,000
  queries and a commented `ACCOUNT_USAGE` query gives exact counts;
- slow client samples can be client or network stalls (one run had eight at 33 to 95 seconds
  that took under 130 ms in Snowflake), so check server time before calling a sample fallback;
- the agent's generated SQL arrives in the `response.tool_result` event and reads
  `DAILY_METRICS` directly, so the agent relies on `BI_READER`'s grant on that view.

The chat client's revised SQL branch and the commented `ACCOUNT_USAGE` query were rerun live
on 2026-10-24 after the fixes. The Native App UI and the CoWork section were run in the browser on
2026-10-24 as the author's own user with BI_READER, not as a separate test user: the app showed
the expected totals, all four prompts returned the expected figures with no invented cause, the
artifact refreshed, the user skill was created in chat, and an hourly automation ran (Run now and
the scheduled run, both delivered by email) before it was paused and deleted.

## Execution order

1. Inspect the reserved lab names. Use a sandbox account. Stop on every error.
2. Run `chapter19_0_setup.sql` once. Re-running fails at the existing fixture table before
   inserting duplicate data. Do not skip that error and continue with the INSERT.
3. Run `chapter19_1_bi.sql` (the reporting view is a prerequisite for sections 2 to 5).
4. Run only the optional sections you need from the table below.
5. Section 2 is one billed session: interactive table, benchmark data, warehouse block (resume),
   measurement, reconciliation, freshness, three load-test runs with the load results block after
   each, suspension. The three runs take about 21 minutes of the billed hour. A resume incurs a
   minimum one-hour charge. Run the suspension block even after an error.
6. Delete any CoWork automation, remove the chat-client tokens, then review the opt-in teardown.

`payment_fixture.csv` holds the same 12 rows as the setup SQL for independent calculation checks.

| File | Referred to in the chapter as | Chapter section | Needs |
|---|---|---|---|
| `chapter19_0_setup.sql` | the companion setup script | Technical Requirements; 1.2 step 1 | USERADMIN and SYSADMIN |
| `payment_fixture.csv` | (not cited) | Shared synthetic fixture | None; local reference |
| `chapter19_1_bi.sql` | the companion BI worksheet | Integrating Tableau, Power BI, Sigma, and Omni (1.2 to 1.5) | Common setup; multi-cluster line needs Enterprise Edition |
| `sigma/merchant-dashboard.yaml` | (not cited) | 1.4 Building the dashboard page, Sigma version of Figure 19.1 | Sigma workbook specification; replace the folder and connection IDs |
| `sigma/merchant-dashboard.png` | (not cited) | 1.4 | The page as built on 2026-10-24, with the data-age tile |
| `chapter19_2_interactive.sql` | the companion interactive worksheet | Implementing interactive tables and measuring query latency (2.2, 2.3) | Common setup, reporting view; supported region; billing acceptance |
| `chapter19_2_load_test.py` | the companion load client | 2.3 Measuring latency under concurrent load | `connections.toml` profile (key-pair) for the test user, named `ch19_test` in the printed commands; `pip install -r requirements.txt` |
| `chapter19_3_native_app.sql` | the companion Native App worksheet | Building Snowflake Native Apps for embedded analytics (3.2 step 1) | Account-level application privileges |
| `native_app/manifest.yml` | the manifest | 3.2 Packaging, releasing, and installing the dashboard | Upload to stage root |
| `native_app/setup.sql` | the application's setup script | 3.2 | Runs inside the app at installation |
| `native_app/streamlit/app.py` | the Streamlit application | 3.2 | Upload under `streamlit/` |
| `native_app/streamlit/environment.yml` | the Streamlit version pin | 3.2 | Upload under `streamlit/`; pins Streamlit 1.35.0 |
| `chapter19_3_install.sql` | the companion release worksheet | 3.2 step 5; 3.3 listing template | Provider preparation and uploaded files |
| `chapter19_4_agents.sql` | the companion agent worksheet | Configuring Cortex Agents for conversational analytics (4.1 to 4.3) | Reporting view; approved Cortex access |
| `chapter19_4_chat_client.py` | the companion chat client | 4.4 Building a streaming conversational client | PAT per tested identity (Chapter 13, section 4.1 pattern) |
| `chapter19_5_cowork.md` | the companion CoWork runbook | Using Snowflake CoWork for advanced analysis (5.1 to 5.3) | Agent worksheet |
| `cowork_skill/review-payment-performance/SKILL.md` | the companion skill folder | 5.2 Saving artifacts and reusing a workflow | CoWork user skills |
| `acceptance.md` | the companion acceptance record | All verification exercises | Record observed results and query IDs |
| `requirements.txt` | (not cited) | Python dependencies for both clients | Python 3.11 or later (Snowflake Connector for Python 5.0 needs it) |
| `static_checks.py` | (not cited) | Maintainer validation | Python 3, PyYAML; optional manuscript path |
| `chapter19_teardown.sql` | the companion teardown script | End of chapter | Review and uncomment selected statements |

## Identity and configuration

The setup creates `BI_READER` and `NO_DATA_READER` and places both under SYSADMIN.
Its optional test user block (commented) creates a dedicated test user with `BI_READER` as the
default role, `BI_WH` as the default warehouse, no default secondary roles, an email address
for the section 5.3 automation, and a key-pair for the BI client and the load client. Power BI
single sign-on and CoWork both open sessions with the user's default role, so the default role
matters. Do not change a working user's default role merely to run this exercise.

Use `BI_READER`, `BI_WH`, database `ANALYTICS_DB`, schema `SERVING`, and
view `DAILY_METRICS` for BI checks. `BI_READER` never receives SELECT on
`PAYMENT_ATTEMPTS`. The view, the interactive table, the semantic view, and the app all
expose merchant-day rows only. The benchmark tables are the one row-level exception,
and they hold generated data. For negative agent tests, use `NO_DATA_READER`
with secondary roles disabled and verify that PUBLIC or another inherited grant
does not supply data access.

The chat client authenticates with a programmatic access token. Create one token per identity
on the test user, as USERADMIN, each with `ROLE_RESTRICTION` set to the role under test
(`payment_chat` for BI_READER, `payment_chat_restricted` for NO_DATA_READER), following the
Chapter 13 network-policy note. The agent spec sets `tool_not_accessible: reject`, so the
restricted run fails with an HTTP 4XX error instead of answering without its tool.
Never put credentials in this repository.

## Native App upload

Run the provider preparation script, then upload the four application files through
Snowsight (Ingestion > Add Data > Load files into a Stage) to `@ANALYTICS_DB.APP_CODE.SRC`
with these paths:

```text
manifest.yml
setup.sql
streamlit/app.py
streamlit/environment.yml
```

The stage root must contain `manifest.yml`, not `native_app/manifest.yml`.
Run `LIST @ANALYTICS_DB.APP_CODE.SRC;` and check all paths. Then execute the
release worksheet. The provider data is a snapshot, not an automatic refresh of
the reporting view. All installations see the same synthetic data.

An ordinary warehouse worksheet must not execute `native_app/setup.sql` directly.
It requires Snowflake's application installation context and shared package content.

## BI client notes: Sigma

The chapter's screenshots (Figures 19.1 and 19.2) come from Sigma. To reproduce them:

1. Create a Sigma connection to Snowflake that signs in as the test user with key-pair
   authentication, role `BI_READER`, and warehouse `BI_WH`. A connection that uses a shared
   service user shows that user in Query History, and Snowflake applies row access policies to it.
2. Build a workbook page on `ANALYTICS_DB.SERVING.DAILY_METRICS` with a merchant control, an
   event-date control defaulting to September 1 to 2, 2026, KPI elements for approved volume
   and approval rate, a data-age element, and a table by date and merchant.
3. Define the approval rate as `Sum([Approved Attempts]) / Sum([Attempts])` and format it as a
   percentage. Averaging the per-row rate gives 56.25% instead of 58.33%.
4. Define data age as `Max([Source Updated At])`.

`sigma/merchant-dashboard.yaml` describes the same page as a Sigma workbook specification, with
the merchant and date controls, the three KPI elements, and the table. Replace `folderId` and
`connectionId` with your own Sigma folder and the connection from step 1. The page in
`sigma/merchant-dashboard.png`, data-age element included, was built in Sigma on 2026-10-24.

What to expect in Snowflake: each Sigma query ends with a comment that starts with `Sigma Σ`
and names the source workbook, and the Snowsight client driver column shows Sigma's Go driver.
Filter Query History on SQL text `Sigma` to find them. On a result as small as this view, Sigma
fetches every row in one prefetch query (all columns, a row limit, no `WHERE` clause) and runs
the merchant and date filters as browser calculations, so selecting M200 adds no row in Query
History. The workbook's own query history panel lists warehouse queries and browser
calculations separately. Sigma documents its cache order (browser, browser recalculation, query
ID cache, universal result cache, warehouse) at
https://help.sigmacomputing.com/docs/caching-and-data-freshness. A manual workbook refresh
bypasses those caches and resends the prefetch query. The comment's workbook URL contains your
Sigma organization name, so crop or redact it before sharing a screenshot.

## Expected outputs

| Selection | Attempts | Approvals | Approved USD | Approval rate |
|---|---:|---:|---:|---:|
| Both dates, all merchants | 12 | 7 | 675.00 | 58.33% |
| M100, both dates | 8 | 5 | 375.00 | 62.50% |
| M200, both dates | 4 | 2 | 300.00 | 50.00% |
| September 1 | 6 | 4 | 375.00 | 66.67% |
| September 2 | 6 | 3 | 300.00 | 50.00% |

Volume change is -75.00, or -20%. M100 contributes +25.00 and M200 -100.00.
Approval rate decreases by approximately 16.67 percentage points, not 16.67 percent.
The semantic view returns a fractional rate; the UI formats it as a percentage.

Benchmark table: about 20,000,000 rows over 2,000 merchants and 180 days. With a Zipf
exponent of 1, M0001 holds roughly 12% of rows (about 2.4 million), M0002 about 1.2 million,
and M0003 about 0.8 million. Exact counts vary per run because the generator uses RANDOM().

## Source references

Printed in the chapter: interactive cloud availability, interactive analytics, interactive
performance, Native App release channels, semantic-view query privileges, Cortex Agents run API,
CoWork user skills and automations, Tableau and Power Query Snowflake connectors, Omni caching.
Additional references:

- [Interactive table SQL](https://docs.snowflake.com/en/sql-reference/sql/create-interactive-table)
- [Interactive warehouse SQL](https://docs.snowflake.com/en/sql-reference/sql/create-interactive-warehouse)
- [Interactive refresh state](https://docs.snowflake.com/en/sql-reference/sql/show-interactive-tables)
- [Persisted query results](https://docs.snowflake.com/en/user-guide/querying-persisted-results)
- [Warehouse parameters](https://docs.snowflake.com/en/sql-reference/sql/create-warehouse)
- [Native App framework overview](https://docs.snowflake.com/en/developer-guide/native-apps/native-apps-about)
- [Native App shared content](https://docs.snowflake.com/en/developer-guide/native-apps/preparing-data-content)
- [Native App Streamlit](https://docs.snowflake.com/en/developer-guide/native-apps/adding-streamlit)
- [Native App manifest](https://docs.snowflake.com/en/developer-guide/native-apps/manifest-reference)
- [Native App local installation](https://docs.snowflake.com/en/developer-guide/native-apps/installing-testing-application)
- [Streamlit owner's rights](https://docs.snowflake.com/en/developer-guide/streamlit/object-management/owners-rights)
- [CREATE LISTING](https://docs.snowflake.com/en/sql-reference/sql/create-listing)
- [Semantic-view SQL](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [Agent SQL](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
- [Agent access](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-setup)
- [Agent threads](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-threads)
- [CoWork](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork)
- [CoWork agent visibility](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/deploy-agents)
- [CoWork artifacts](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/artifacts)
- [Sigma: connect to Snowflake](https://help.sigmacomputing.com/docs/connect-to-snowflake)
- [Sigma: caching and data freshness](https://help.sigmacomputing.com/docs/caching-and-data-freshness)
- [Snowflake semantic views in Sigma (beta)](https://help.sigmacomputing.com/docs/query-and-extend-snowflake-semantic-views-in-sigma)
- [Omni: Snowflake semantic views](https://docs.omni.co/connect-data/snowflake-semantic-views)
- [Cortex Agents: inaccessible tool handling](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-inaccessible-tool-handling)
- [Cortex Agent evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
- [Native App shared content in the manifest](https://docs.snowflake.com/en/developer-guide/native-apps/sharing-manifest-about)
- [Omni: Snowflake connection](https://docs.omni.co/connect-data/setup/snowflake)
