# Chapter 15: Governance, Security, and Data Quality

Run these exercises against a dedicated copy of the book's gold data. Setup creates `GOVERNANCE_DB` and five roles: `GOVERNANCE_OWNER`, `PII_READER`, `SUPPORT_AGENT`, `MERCHANT_PORTAL`, and `UNENTITLED_READER`. It fails before changes if any reserved name exists. The gold tables receive no data, policy, tag, or comment changes.

## Prerequisites and cost

- Enterprise Edition, `BOOK_WH`, and the Chapter 14 gold tables before teardown: customers, merchants, payments, and refunds.
- An authenticated Snowflake CLI connection, named `book` in the examples. Replace that connection name if yours differs.
- Python 3 for the offline checker and the validation runner's assertion checks.
- Ability to activate ACCOUNTADMIN and USERADMIN for setup. USERADMIN creates the roles; ACCOUNTADMIN grants account-level privileges to the disposable owner role. GOVERNANCE_OWNER owns the lab beneath SYSADMIN. The PII role is granted only to the user.
- Verify the email address on your Snowflake user. Setup captures that user's address; notifications use that one direct recipient. The example `data_owner` tag addresses are metadata, not delivery addresses.
- Classification, scheduled DMFs, and Cortex generation consume credits. The schedule runs every five minutes until teardown. Quality waits are bounded at 30 minutes per phase and may take 10–20 minutes during initial schedule activation.
- Native `DATA_QUALITY_MONITORING_SETTINGS` is marked Preview in the ALTER DATABASE reference, checked 2026-09-08. See [notifications](https://docs.snowflake.com/en/user-guide/data-quality-notifications) and [ALTER DATABASE](https://docs.snowflake.com/en/sql-reference/sql/alter-database).

## Run order

Run each command from the repository root and stop on any error. Each SQL file establishes its own role and secondary-role context. Run setup once; these scripts deliberately use CREATE without replacement. For a fresh run, use guarded teardown first.

| File | Purpose | Dependencies |
|---|---|---|
| `chapter15_0_setup.sql` | Guard names, grant disposable roles, copy four tables using CTAS, create local star view and incident state | Chapter 14 fixture |
| `chapter15_1_tagging.sql` | Taxonomy, inheritance, profile, dry classification | Setup |
| `chapter15_2_masking.sql` | Type policies, tag binding, classification, scoped exception, support override | Setup and tagging |
| `chapter15_3_row_security.sql` | Merchant entitlements, fact/view allow and deny tests | Setup |
| `chapter15_4_quality.sql` | Five metrics, email configuration, plant, scheduled failure wait, delete, scheduled recovery wait | Setup; row security recommended to test owner evaluation |
| `chapter15_5_documentation.sql` | Metadata-only descriptions, reviewed comments, schema-change maintenance | Setup; optional CoCo audit prompts need sections 1–4 |
| `chapter15_coco_audit.sql` | Read-only evidence baseline for CoCo: UTC quality measurements, object lifecycles, access and secondary-role records | Setup and earlier quality/access exercises; before teardown |
| `chapter15_teardown.sql` | Guard and remove only the dedicated lab database and roles | Any partial or full lab run |
| `chapter15_live_checks.sql` | Outcome checks for real roles, four mask types, scheduled results, and comments | Completed scripts 0–5; before teardown |
| `chapter15_static_checks.py` | Offline scope, ordering, and manuscript alignment checks | Python 3; no account |

```bash
snow sql -c book -f chapters/chapter15/chapter15_0_setup.sql
snow sql -c book -f chapters/chapter15/chapter15_1_tagging.sql
snow sql -c book -f chapters/chapter15/chapter15_2_masking.sql
snow sql -c book -f chapters/chapter15/chapter15_3_row_security.sql
snow sql -c book -f chapters/chapter15/chapter15_4_quality.sql
snow sql -c book -f chapters/chapter15/chapter15_5_documentation.sql
snow sql -c book -f chapters/chapter15/chapter15_live_checks.sql
```

Every `PASSED` value from the live checks must be `TRUE`. These checks derive their row counts and clear-data hash from your source fixture. The masking script also creates one temporary closed customer version, tests it under the support role, removes it, and verifies restoration.

The quality file intentionally waits inside Snowflake. Its first wait requires orphan value 1 and a failed expectation from a schedule after the insert. Only then does it delete the planted row. A second wait requires a later zero/nonviolated result. It never treats old results or an ad hoc function call as scheduled proof. A suspended metric raises an error at the next poll instead of waiting for the 30-minute timeout. If a wait fails, inspect `lab_state`, `DATA_METRIC_FUNCTION_REFERENCES`, and the expectation-status view. Do not blindly skip ahead to deletion. Teardown remains available if abandoning the exercise.

Automatic classification is attached only to CUSTOMERS, MERCHANTS, and TRANSACTIONS. Keep control schemas outside that scope. The previous database-wide attachment classified `POLICIES.MERCHANT_ACCESS.ROLE_NAME` as OCCUPATION, which attached `PII_MASK_STRING` to the entitlement lookup. Reads through `MERCHANT_ROWS` then failed with error 003542 (a policy refers to a column attached to another policy), and the three column-based DMFs suspended. `EXECUTE AS ROLE` cannot repair this dependency. Snowflake documents the restriction under [row access policy usage notes](https://docs.snowflake.com/en/sql-reference/sql/alter-view).

If an older lab has this failure, use the existing guarded teardown and run the updated scripts from setup. Merely removing the database profile leaves the earlier column tags in place. Do not rerun the quality script's CREATE or INSERT statements against a partial run.

The local star view joins the copied payment and merchant tables and derives `month_start` from the payment timestamp. CTAS omits the source RELY constraints; substituting CLONE would invalidate the deliberately broken-key experiment.

## Optional work and review boundaries

The named custom-classifier block in the tagging script is commented out. Copy it to a worksheet to opt in. It attaches to a separate review profile with `auto_tag: FALSE`; inspect its recommendations without masking business keys. Deployment needs consistent treatment on both sides of every join.

The documentation script's named CoCo prompts are comments, not SQL. Send them separately in a CoCo session connected to the lab. Prompts 1 and 2 are the chapter's exercises. Prompts 3 (classification drift against the existing tags) and 4 (reconstructing the orphan incident and its access records from audit history) are optional and read-only. Keep metadata inspection within GOVERNANCE_DB. The scripts apply explicit reviewed comments; they do not execute arbitrary model-generated DDL. Unresolved business meanings must stay out of executable comment statements. The policy draft exercise ends at review, so it does not attach an additional policy unless you choose to apply the reviewed proposal.

For the audit prompt, run `chapter15_coco_audit.sql` as the evidence baseline. It selects `QUERY_HISTORY.SECONDARY_ROLE_STATS` explicitly and joins quality measurements to table lifecycle metadata by ID. Historical records can outlive teardown; the same object name does not identify the same table incarnation. ACCESS_HISTORY can lag three hours, and QUERY_HISTORY can lag 45 minutes.

The recipient in `QUALITY.LAB_STATE` retains its owner-only direct masking policy. This also protects notification configuration if an EMAIL tag is applied later: the shared string policy must not redact the address the owner uses for delivery.

Classification recommendations and AI wording vary. The masking exercise explicitly tags known customer name/email columns and tests the merchant exception against a forced NAME category. For access audits, join ACCESS_HISTORY and QUERY_HISTORY by query ID and distinguish recorded role metadata from uncertain historical membership. Notification configuration or server-side success does not prove inbox arrival.

## Verification and cleanup

Run offline checks from any directory:

```bash
python3 chapters/chapter15/chapter15_static_checks.py --manuscript '/path/to/Chapter_15_Governance_Security_and_Data_Quality.md'
```

See [VALIDATION.md](VALIDATION.md) for observed results and remaining live checks. An offline pass does not establish DDL compatibility, classification output, policy behavior, or delivery.

After any partial or full run:

```bash
snow sql -c book -f chapters/chapter15/chapter15_teardown.sql
```

Teardown checks the lab marker on the database and all five reserved roles before dropping any of them. An unmarked collision stops the script. Dropping the database removes its classification profile, DMFs, schedules, policies, comments, and incident rows; dropping the roles removes their temporary grants, including reads on the source fixture. No preexisting roles, source comments, or shared-table policies are removed. Run teardown only while this dedicated lab is disposable; it is not a migration tool for a database other people have adopted.
