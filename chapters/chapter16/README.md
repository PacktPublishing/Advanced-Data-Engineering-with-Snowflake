# Chapter 16 companion

Snowflake Operations: Cost Optimization, Monitoring, and Reliability.

The worksheets implement the chapter's disposable `OPS_DB` lab. They do not
depend on tables from earlier chapters. Start with setup, then run only the
sections you need. SQL snippets in the manuscript are matching excerpts.

## Validation status

The **core lab passed live validation on 2026-09-21**, including all seven SQL
worksheets, native dashboard behavior tests, and teardown. Tests used Snowflake
**10.33.101**, region **AWS_US_WEST_2**, through the `book` connection.
`OPS_DB` was substituted in memory with `OPS_DB_CH16_TEST_20260921` because the
account already contained an unrelated `OPS_DB.PIPELINES.PIPELINE_RUN_LOG`.
The normal lab role was `OPS_ENGINEER` on `OPS_WH`; role-isolated checks disabled
secondary roles. Administrative blocks used the roles declared in the scripts.

| Area | Observed result |
|---|---|
| Setup and grants | Passed; one heartbeat, three ledger rows, and `60.00` |
| Costs and observability | All three cost queries and both views passed under `OPS_ENGINEER` with secondary roles disabled; 48 billed rows, 20 ranked attribution rows, zero optional Adaptive rows, 15 daily rows, and 10,192 query families in `[2026-09-13, 2026-09-20)` UTC |
| Resource monitor | Quota 10, daily frequency, 70/90/100% triggers, and assignment to the XSmall warehouse verified; threshold spending was not induced |
| Alert lifecycle | Stale, repeat, null, and missing-heartbeat runs reached `TRIGGERED`; recovery reached `CONDITION_FALSE`; one row per incident key, preserved first-seen time, and advancing last-seen time verified; schedule resumed and suspended successfully |
| Backup and restore | Unlocked backup created and restored; three rows, `60.00`, and zero bidirectional row/multiplicity differences |
| Streamlit | Private app deployment and package resolution passed; native AppTest inside Snowflake passed all three warehouse selections, totals, both tables, chronological order, top 20 sorting, reload, empty history, empty health, and null attribution |
| Optional warehouses | Gen2, Snowpark-optimized MEMORY_16X, and Adaptive definitions created, properties inspected, and candidates dropped; no performance/cost benchmark was run |
| Edge cases | Read-only fixtures passed reporting boundaries, incomplete attribution, blank/null query tags, successful-query filtering, percentile/unit conversion, spill totals, freshness cases, and restore-comparison missing/duplicate/extra rows |
| Teardown | Existing script passed; database, core/optional warehouses, monitor, role, alert, backup set, app, and stage removed; original `OPS_DB` table preserved |

The live Python tests used **Python 3.11.16**, **Streamlit 1.52.2**,
**pandas 2.3.3**, and **Snowpark 1.55.0**. These are observed validation versions,
not permanent package pins. SQL execution used Snowflake Connector **3.18.0**;
earlier local checks also used Python 3.12.12 and Connector 4.5.0. Native AppTest
used the actual Snowpark session and account views. Empty/null test inputs were
injected in memory; no companion test file was added. Browser rendering was not
verified, and a successful headless deployment command alone was not counted as
app execution evidence.

Corrections from validation: `SQL_ERROR_MESSAGE` replaces the invalid alert
history column; the alert-name filter is applied inside `ALERT_HISTORY`; Python
uses `3.11.*`; incomplete hourly attribution leaves both daily attribution totals
null; blank query tags join the untagged group; dashboard rows are date ordered.
Matching code excerpts in the existing manuscript were updated.

**Changes after the 2026-09-21 validation (not yet live-tested):** the
attribution query in `chapter16_1_costs.sql` reads `QUERY_TAG` and
`QUERY_PARAMETERIZED_HASH` directly from `QUERY_ATTRIBUTION_HISTORY` instead of
joining `QUERY_HISTORY`; setup no longer sets `AUTO_SUSPEND` on `OPS_WH`; and
`chapter16_2_warehouses.sql` gains an `ALTER WAREHOUSE OPS_WH SET AUTO_SUSPEND = 60`
block under `SYSADMIN`. Rerun setup, costs, and warehouses before relying on
the observed results above for those three files.

**Scope limits:** cross-account replication/failover and irreversible retention
locks in `chapter16_recovery_runbook.md` received documentation review only; they
were excluded from this disposable validation. The CoCo file is a prompt
reference and was not run as an agent investigation. No notification delivery,
resource-monitor threshold action, or performance benchmark is claimed. All
13 original companion files remain; no new local files were created.

## Files and execution order

| File | Chapter section | Needs |
|---|---|---|
| `chapter16_0_setup.sql` | Technical Requirements | Administrative setup access |
| `chapter16_1_costs.sql` | Analyzing financial operations | Setup; historical account activity |
| `chapter16_2_warehouses.sql` | Setting suspension and spending controls | Setup; SYSADMIN for idle policy; ACCOUNTADMIN for monitor |
| `chapter16_optional_warehouses.md` | Choosing a compute model | Selected candidate only; region/edition support |
| `chapter16_3_observability.sql` | Building observability | Setup; USAGE_VIEWER and GOVERNANCE_VIEWER |
| `chapter16_dashboard.py` | Creating the Streamlit dashboard | Observability views; private Streamlit app |
| `environment.yml` | Creating the Streamlit dashboard | Snowflake warehouse runtime |
| `chapter16_4_alerts.sql` | Implementing alerting | Setup; execute individual named blocks |
| `chapter16_5_restore.sql` | Restoring a table from a backup set | Setup; substitute returned backup identifier |
| `chapter16_recovery_runbook.md` | Preparing replication and failover; Planning retention-locked backups | Separate deployment planning |
| `chapter16_coco_prompts.md` | Reviewing FinOps and reliability with CoCo | Restricted reporting connection |
| `chapter16_teardown.sql` | Cleanup | Core lab only; inspect optional state first |

## Account and role setup

Run each statement in a Snowsight worksheet and **stop on the first error**.
Do not select all files and execute them together. Setup intentionally uses plain
CREATE for dedicated names so existing data is not replaced. Check for existing
`OPS_DB`, `OPS_WH`, `OPS_ENGINEER`, and `DAILY_RM` names before starting.
If any name exists, verify its ownership and contents. Use teardown only for
objects positively identified as this disposable Chapter 16 lab. An unrelated
`OPS_DB` can contain other chapters' data; use a separate account or consistently
substitute an unused database name across the SQL and dashboard instead.

The administrator creating the role grants it to the current user. If your
organization separates administrative duties, have the named role administrator
perform each corresponding block. `OPS_ENGINEER` reads account-wide telemetry
through two SNOWFLAKE database roles and owns the lab objects it creates. Do not
share the resulting Streamlit app broadly under this role. A viewer-specific
deployment needs approved aggregates and a separate app owner.

The core warehouse is XSmall. Setup leaves it at Snowflake's 600-second
auto-suspend default, and the first block of `chapter16_2_warehouses.sql` sets
the lab's 60-second policy as a reader step. The core setup
does not promise a particular warehouse generation. The optional Gen2 candidate
specifies its generation explicitly. Check rate and Query Acceleration Service
settings before comparing cost across generations. Ordinary SELECT statements,
the Streamlit app, and serverless alert tests consume credits.

## Dashboard deployment

Create a private Streamlit app as `OPS_ENGINEER` in `OPS_DB.MONITORING`, named
`OPERATIONS_DASHBOARD`, with **warehouse runtime** and `OPS_WH`. Copy the existing
`chapter16_dashboard.py` code into the app entrypoint and use the supplied
`environment.yml`. The Python dependency is `python=3.11.*`: the wildcard admits
supported patch releases. In this account, `python=3.11` was translated to an
unresolvable exact `python==3.11` package specification during headless execution.
If testing in another database, substitute that database in both dashboard view
references as well as the SQL. Keep this account-wide telemetry app private.

A successful `EXECUTE STREAMLIT` response alone is not proof that the dashboard
ran. During validation, that command returned success without reaching an
end-of-script marker. Native `streamlit.testing.v1.AppTest` in a Snowflake Python
3.11 anonymous procedure provided the execution and widget evidence instead.

## Reporting conventions

Run accounting queries in UTC. The window is `[UTC today minus 8 days, UTC today
minus 1 day)`, seven complete days excluding yesterday and today. For example,
with UTC today 2026-09-14, the interval is September 6 through September 12,
inclusive. This intentional delay gives accounting sources time to populate.
View predicates depend on the caller's session date, so UTC is set in every
worksheet and by the Streamlit app.

`METERING_DAILY_HISTORY.CREDITS_BILLED` includes its cloud-services adjustment.
`QUERY_ATTRIBUTION_HISTORY` excludes idle compute; do not call its sum an invoice.
The idle calculation uses conventional-warehouse metering at its own hourly grain.
Adaptive query metering is a separate optional block and can be unavailable by
region. Aggregate its hourly rows by query before joining other query-level data.
If any hourly attribution is missing, both the daily query-credit total and
idle-credit total stay unavailable; a partial sum must not appear as a complete
total. Null attribution is never treated as zero.

## Expected checks

1. Setup returns one heartbeat row and three ledger rows totaling `60.00`.
2. Cost queries show only the declared date window. Empty history is permissible
   and does not imply zero account cost outside that window.
3. The warehouse monitor has quota 10, daily frequency, and 70/90/100% triggers.
   Verify the assignment without deliberately spending ten credits.
4. The dashboard's selected warehouse matches both panels. Compare a displayed
   daily total with the worksheet view result. Check the empty-history state too.
5. A fresh heartbeat yields zero stale rows. The injected 20-minute-old heartbeat
   yields one incident after asynchronous alert execution completes. Repeat
   EXECUTE ALERT without changing the heartbeat: one row per incident key remains.
6. Restoring the heartbeat produces zero stale rows. Check the latest alert
   history for a false condition; keep earlier incident records as evidence.
7. Restoring the fixture backup gives three rows and `60.00`. The bidirectional
   comparison also checks row multiplicity and must return zero differences.

The alert remains suspended unless you separately enable its schedule. Its action
records evidence; it sends no email or external message and does not implement
incident acknowledgement or closure. Configure and test notification delivery
separately before describing it as a paging system. The heartbeat must be written
by the real publisher only after validated output commits.

## Troubleshooting

| Symptom | Check |
|---|---|
| Existing-object error during setup | Stop and inspect prior lab state; never change CREATE to CREATE OR REPLACE |
| Account Usage authorization error | Verify both SNOWFLAKE database-role grants and active role |
| No historical warehouse rows | Wait for qualifying history or select an existing warehouse |
| Adaptive metering view unavailable | Check regional availability; skip only the optional Adaptive block |
| Alert command returns but no incident exists | Wait for asynchronous execution; inspect ALERT_HISTORY state and error |
| Fresh heartbeat still looks stale | Confirm fixture uses UTC TIMESTAMP_NTZ and SYSDATE(), as supplied |
| Restore fails on backup identifier | Use backup_id from SHOW BACKUPS, not the set name or creation timestamp |
| Core teardown encounters a lock/group | Stop; follow optional recovery cleanup, preserving retained backups |

## Official references

- [Account Usage roles](https://docs.snowflake.com/en/sql-reference/account-usage)
- [Gen2 warehouses](https://docs.snowflake.com/en/user-guide/warehouses-gen2)
- [Snowpark-optimized warehouses](https://docs.snowflake.com/en/user-guide/warehouses-snowpark-optimized)
- [Adaptive Compute](https://docs.snowflake.com/en/user-guide/warehouses-adaptive)
- [Query metering](https://docs.snowflake.com/en/sql-reference/account-usage/query_metering_history)
- [Warehouse metering](https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history)
- [Resource monitors](https://docs.snowflake.com/en/user-guide/resource-monitors)
- [Alert execution](https://docs.snowflake.com/en/sql-reference/sql/execute-alert)
- [Backups](https://docs.snowflake.com/en/user-guide/backups)
- [Restore syntax](https://docs.snowflake.com/en/sql-reference/sql/create-table)
- [Failover configuration](https://docs.snowflake.com/en/user-guide/account-replication-config)
