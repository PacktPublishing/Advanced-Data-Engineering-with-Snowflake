# Chapter 19: Analytics Consumption & BI Integration Patterns

This chapter uses 12 synthetic payment attempts and a merchant-day reporting contract, plus a
generated 20-million-row benchmark table for the load test in section 2.3. The chapter text never
names these files (book convention since Chapter 5) except `manifest.yml` and `SKILL.md`, which are
the subject being taught, and the two Python clients and `requirements.txt`, which appear in the
commands the reader types. Otherwise it refers to each file by the role in the second column.

## Validation status

Official documentation checked October 2026. Fixture arithmetic, source-to-excerpt alignment,
YAML structure, package paths, Python syntax, the load-test percentile helper, and the chat
client's event parser (against the documented event shapes) were checked locally.
Snowflake SQL, the Native App installation, BI clients, the REST client, and CoWork were
**not run live**. Record versions and execution evidence in `acceptance.md` before treating the
lab as account-validated. First live run, watch for:

- `REGISTER VERSION` and the DEFAULT release channel (new packages have release channels on by default);
- the interactive warehouse created with `TABLES (...)` while `INITIALLY_SUSPENDED = TRUE`;
- the agent answering as `BI_READER` with SELECT on the semantic view only (no base-table grants);
- the MINUS reconciliation reading the interactive table from `BI_WH`;
- whether fallback retries appear in `QUERY_HISTORY_BY_USER` under `BI_WH` or only in Query Profile;
- the CoWork skill folder upload accepting `SKILL.md` with `name` and `description` frontmatter.

## Execution order

1. Inspect the reserved lab names. Use a sandbox account. Stop on every error.
2. Run `chapter19_0_setup.sql` once. Re-running fails at the existing fixture table before
   inserting duplicate data. Do not skip that error and continue with the INSERT.
3. Run `chapter19_1_bi.sql` (the reporting view is a prerequisite for sections 2 to 5).
4. Run only the optional sections you need from the table below.
5. Section 2 is one billed session: interactive table, benchmark data, warehouse block (resume),
   measurement, reconciliation, both load-test runs, load results, suspension. A resume incurs a
   minimum one-hour charge. Run the suspension block even after an error.
6. Pause any CoWork automation, remove the chat-client tokens, then review the opt-in teardown.

`payment_fixture.csv` holds the same 12 rows as the setup SQL for independent calculation checks.

| File | Referred to in the chapter as | Chapter section | Needs |
|---|---|---|---|
| `chapter19_0_setup.sql` | the companion setup script | Technical Requirements; 1.2 step 1 | USERADMIN and SYSADMIN |
| `payment_fixture.csv` | (not cited) | Shared synthetic fixture | None; local reference |
| `chapter19_1_bi.sql` | the companion BI worksheet | Integrating Tableau, Power BI, Sigma, and Omni (1.2 to 1.5) | Common setup; multi-cluster line needs Enterprise Edition |
| `chapter19_2_interactive.sql` | the companion interactive worksheet | Implementing interactive tables and measuring query latency (2.2, 2.3) | Common setup, reporting view; supported region; billing acceptance |
| `chapter19_2_load_test.py` | the companion load client | 2.3 Measuring latency under concurrent load | `connections.toml` profile for a user holding BI_READER; `pip install -r requirements.txt` |
| `chapter19_3_native_app.sql` | the companion Native App worksheet | Building Snowflake Native Apps for embedded analytics (3.2 step 1) | Account-level application privileges |
| `native_app/manifest.yml` | the manifest | 3.2 Packaging, releasing, and installing the dashboard | Upload to stage root |
| `native_app/setup.sql` | the application's setup script | 3.2 | Runs inside the app at installation |
| `native_app/streamlit/app.py` | the Streamlit application | 3.2 | Upload under `streamlit/` |
| `chapter19_3_install.sql` | the companion release worksheet | 3.2 step 5; 3.3 listing template | Provider preparation and uploaded files |
| `chapter19_4_agents.sql` | the companion agent worksheet | Configuring Cortex Agents for conversational analytics (4.1 to 4.3) | Reporting view; approved Cortex access |
| `chapter19_4_chat_client.py` | the companion chat client | 4.4 Building a streaming conversational client | PAT per tested identity (Chapter 13, section 4.1 pattern) |
| `chapter19_5_cowork.md` | the companion CoWork runbook | Using Snowflake CoWork for advanced analysis (5.1 to 5.3) | Agent worksheet |
| `cowork_skill/review-payment-performance/SKILL.md` | the companion skill folder | 5.2 Saving artifacts and reusing a workflow | CoWork user skills (preview) |
| `acceptance.md` | the companion acceptance record | All verification exercises | Record observed results and query IDs |
| `requirements.txt` | (not cited) | Python dependencies for both clients | Python 3.10 or later |
| `static_checks.py` | (not cited) | Maintainer validation | Python 3, PyYAML; optional manuscript path |
| `chapter19_teardown.sql` | the companion teardown script | End of chapter | Review and uncomment selected statements |

## Identity and configuration

The setup creates `BI_READER` and `NO_DATA_READER` and places both under SYSADMIN.
An administrator must assign the appropriate role to the test user. Use a dedicated
test user if the connector or CoWork uses a default role. Do not change a working
user's default role merely to run this exercise.

Use `BI_READER`, `BI_WH`, database `ANALYTICS_DB`, schema `SERVING`, and
view `DAILY_METRICS` for BI checks. `BI_READER` never receives SELECT on
`PAYMENT_ATTEMPTS`: the view, the interactive table, the semantic view, and the app all
expose merchant-day rows only. The benchmark tables are the one row-level exception,
and they hold generated data. For negative agent tests, use `NO_DATA_READER`
with secondary roles disabled and verify that PUBLIC or another inherited grant
does not supply data access.

The chat client authenticates with a programmatic access token. Create one token per identity,
each with `ROLE_RESTRICTION` set to the role under test (`payment_chat` for BI_READER,
`payment_chat_restricted` for NO_DATA_READER), following the Chapter 13 network-policy note.
Never put credentials in this repository.

## Native App upload

Run the provider preparation script, then upload the three application files through
Snowsight to `@ANALYTICS_DB.APP_CODE.SRC` with these paths:

```text
manifest.yml
setup.sql
streamlit/app.py
```

The stage root must contain `manifest.yml`, not `native_app/manifest.yml`.
Run `LIST @ANALYTICS_DB.APP_CODE.SRC;` and check all paths. Then execute the
release worksheet. The provider data is a snapshot, not an automatic refresh of
the reporting view. All installations see the same synthetic data.

An ordinary warehouse worksheet must not execute `native_app/setup.sql` directly.
It requires Snowflake's application installation context and shared package content.

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
- [Omni: Snowflake connection](https://docs.omni.co/connect-data/setup/snowflake)
