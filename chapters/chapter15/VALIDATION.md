# Chapter 15 validation

> **20 September 2026: clean SQL lab passed.** The existing guarded teardown, scripts 0–5, and all **20 live assertions** succeeded on the `book` connection after the classification-scope fix. The row access policy remained attached throughout the quality exercise. Details and historical evidence follow.


## 20 September 2026 clean run

The existing guarded teardown succeeded, followed by scripts 0–5 and the live checks through `run_chapter15_validation.sh`, with no manual SQL modifications between scripts. All 20 passing assertions completed and the runner exited 0. All five metric associations use the default owner context (`USE_ROLE` empty), remain STARTED, and report notifications ENABLED.

| Existing script | Result | Successful statements |
|---|---|---|
| `chapter15_0_setup.sql` | PASS | 107 |
| `chapter15_1_tagging.sql` | PASS | 19 |
| `chapter15_2_masking.sql` | PASS | 57 |
| `chapter15_3_row_security.sql` | PASS | 22 |
| `chapter15_4_quality.sql` | PASS | 24 |
| `chapter15_5_documentation.sql` | PASS | 12 |
| `chapter15_live_checks.sql` | PASS | 51 |

NULL_COUNT and DUPLICATE_COUNT produced scheduled zero/nonviolated results in both incident and recovery cycles. The original `MERCHANT_ROWS` definition stayed attached; no policy bypass or extra evaluation role was added.

| Live assertion | Result |
|---|---|
| `owner_masked_names` | TRUE |
| `owner_full_fact` | TRUE |
| `merchant_exception` | TRUE |
| `merchant_name_tag` | TRUE |
| `secondary_pii_clear_hash` | TRUE |
| `type_masks_and_nulls` | TRUE |
| `primary_pii_clear_hash` | TRUE |
| `type_masks_authorized` | TRUE |
| `support_current_emails` | TRUE |
| `portal_fact_scope` | TRUE |
| `portal_view_scope` | TRUE |
| `denied_customer_pii` | TRUE |
| `denied_fact_scope` | TRUE |
| `denied_view_scope` | TRUE |
| `entitlement_table_has_no_policy_dependencies` | TRUE |
| `metric_associations` | TRUE |
| `scheduled_failure_and_recovery` | TRUE |
| `scheduled_system_column_metrics` | TRUE |
| `reviewed_channel_comment` | TRUE |
| `preserved_refund_grain` | TRUE |

The owner sees 50,024 payments; the portal sees 2,607 through both fact and view; the denied role sees zero. Current support-email checks cover 513 versions, including 10 NULL emails. The self-cleaning historical support fixture also passed in script 2. Script 5 generated metadata-only descriptions and preserved the reviewed comments and refund grain.

All four GOLD_DB tables retained the same row counts, HASH_AGG values, DDL hashes, and column-tag hashes across the clean run:

| Source | Rows | Data HASH_AGG | DDL hash | Tag hash |
|---|---|---|---|---|
| Customers | 513 | 7712352513173473378 | -6850964747392509063 | 0 |
| Merchants | 47 | 9139775003656783264 | 8577878397219630549 | 0 |
| Payments | 50,024 | 7607045848680237402 | 6949933610084092393 | 0 |
| Refunds | 2,148 | 6033958192499823327 | 757571114896908542 | 0 |

**Boundaries:** this re-run covers all executable SQL in scripts 0–5 and the final checks. The optional custom-classifier worksheet and four interactive CoCo prompts were not rerun; their observations below are historical. Alert configuration passed, but inbox delivery was not confirmed in this run. The lab is left intact, with its five-minute metric schedule active, following the existing runner's behavior. Use the existing guarded teardown when finished. Temporary run logs were summarized here and removed at the author's request to keep changes in existing files.

## 20 September 2026 diagnosis and corrections

The account runs Snowflake 10.33.101; the CLI is 3.16.0. The failed lab used `GOVERNANCE_DB` and the v3 marker.

- `MERCHANT_ACCESS.ROLE_NAME` had `PII_CATEGORY=OCCUPATION`, `SEMANTIC_CATEGORY=OCCUPATION`, and `PRIVACY_CATEGORY=QUASI_IDENTIFIER`, all applied by classification. `POLICY_REFERENCES` showed active `PII_MASK_STRING` on that column.
- Calling the custom orphan metric as its owner exposed error **003542**: “Policy body contains a UDF or Select statement that refers to a column attached to another Policy.” The same dependency broke direct fact-table reads.- Explicit `EXECUTE AS ROLE GOVERNANCE_OWNER` did not help: all three column-based metrics suspended again.- Narrowing classification to the business schemas and removing the false entitlement tags immediately restored NULL_COUNT=0, DUPLICATE_COUNT=0, and ORPHAN_MERCHANT_COUNT=1, with the original row access policy still attached. The partial-run wait was then cancelled deliberately so validation could start from the existing guarded teardown.

The permanent correction is in **script 2**: attach the profile only to CUSTOMERS, MERCHANTS, and TRANSACTIONS. POLICIES, CLASSIFICATION, and QUALITY stay outside automatic classification. No row-policy bypass, new role, or explicit DMF evaluation role is needed. Script 4 now raises a diagnostic exception at the next poll if a metric suspends. The live checks also test the entitlement table's policy dependencies and require actual scheduled NULL_COUNT/DUPLICATE_COUNT results. The existing shell runner rejects false or NULL live assertions.

The existing manuscript Markdown and DOCX contain the matching schema-level SQL and explanation. Offline alignment checks pass (40 code/prompt blocks); the DOCX retains 7 main headings, 9 subheadings, 2 callouts, and no hyperlinks. Its updated code and wait paragraphs were visually checked in a 33-page rendering. No additional companion files are required.

References checked on 20 September 2026: [classification scope](https://docs.snowflake.com/en/user-guide/classify-auto), [ALTER SCHEMA](https://docs.snowflake.com/en/sql-reference/sql/alter-schema), and [policy dependency restrictions](https://docs.snowflake.com/en/sql-reference/sql/alter-view).

## Historical 8 September 2026 run

Executed on 8 September 2026 against the Snowflake CLI `book` connection, using Snowflake CLI 3.16.0 and Snowflake 10.31.103. The main SQL exercises passed after the corrections below. **All 18 final checks in `chapter15_live_checks.sql` passed.** After explicit approval for metadata transfer, all four CoCo scenarios were also exercised through Cortex Code 1.1.78 in a fresh session. Generated answers required the review corrections recorded below.

## Observed outcomes

| Check | Result |
|---|---|
| Setup and name guards | Setup succeeded. Repeating setup refused the existing database with `-20150`. A role-only collision refused setup with `-20151`. |
| Classification | Four dry scans succeeded without applying tags. Profile creation, tag mapping, profile attachment, and classification with automatic tagging succeeded. The optional custom classifier reported TECHFLOW_CUSTOMER_ID with HIGH confidence and left tags unapplied. |
| Automatic classification interaction | Background classification tagged the operational recipient EMAIL. An owner-only direct policy now preserves its value for notification configuration, even with that tag present. |
| PII masking | Real primary and secondary PII-role contexts reproduced the original customer data hash. Owner/denied contexts remained masked; the forced merchant NAME exception stayed confined to merchant names. |
| Type and NULL behavior | String, NUMBER, DATE, and TIMESTAMP_NTZ policies passed allowed/denied checks, including NULL preservation. Current support emails matched the source, including its 10 NULL emails. |
| Historical support access | The source has 513 current versions and no closed versions. A temporary closed version was masked under the real support role, then deleted; the original customer data hash was restored. This fixture is now part of the masking script. |
| Tenant isolation | Owner: 50,024 payments. Portal: 2,607 payments across MERCH-CH12-07 (1,322) and MERCH-CH12-08 (1,285), with the same scope through the star view. Denied: zero rows through both table and view. An entitlement-update probe was rejected. |
| Scheduled quality | Five associations reached STARTED. NULL_COUNT and DUPLICATE_COUNT remained zero. ROW_COUNT was 50,025 during the incident and 50,024 after recovery. Scheduled FRESHNESS also returned a value. |
| Notification | All five associations reported ENABLED. A correlated incident email reached the recipient's inbox at 15:41:03 UTC, citing the lab table, orphan metric, NO_ORPHAN_MERCHANTS expectation, and 15:40 UTC schedule. |
| Documentation SQL | Metadata-only AI_GENERATE_TABLE_DESC returned table/column descriptions. Reviewed comments persisted; PROCESSING_CHANNEL was added and documented; the refund grain comment remained unchanged. This SQL also passed with setup alone. |
| Teardown guard | A deliberately mismatched lab-role marker caused `-20156` before database deletion. A subsequent query confirmed all 50,024 lab payments remained. |
| Full teardown | The marked lab database and all five roles were removed successfully. The final revised setup also passed from a clean namespace; documentation then ran with setup alone. Repeated teardown succeeded with no database or lab roles remaining. |
| Source preservation | All four gold tables retained identical row counts, HASH_AGG values, GET_DDL output, and column tags after the exercises and final cleanup. |

## Scheduled incident evidence

All timestamps below are UTC. Each wait requires a scheduled time and measurement time after its corresponding insert/delete boundary.

| Cycle | State | Scheduled time | Measurement time | Orphan value / violated |
|---|---|---|---|---|
| First | Failed | 15:30:00 | 15:30:23.080 | 1 / TRUE |
| First | Recovered | 15:35:00 | 15:35:51.214 | 0 / FALSE |
| Notifications enabled | Failed | 15:40:00 | 15:41:00.032 | 1 / TRUE |
| Notifications enabled | Recovered | 15:45:00 | 15:45:54.419 | 0 / FALSE |

Both bounded wait calls returned successfully in each cycle. The first notification configuration failed because the classifier had masked the stored recipient, producing an invalid address. After the owner-only direct policy was added, configuration succeeded and the second incident produced the confirmed email. The user also confirmed the address was verified. NOTIFICATION_HISTORY did not return a native quality-notification record in this run; inbox content supplied the delivery evidence.

## Corrections made during live execution

- Capture the quoted username with a scalar SELECT before switching to USERADMIN; use the captured value in dynamic GRANT statements. Re-select BOOK_WH under CH15_OWNER before creating/copying data.
- Supply object-age settings when creating the optional custom review profile.
- Remove redundant warehouse grants from the owner-run row-security script; bootstrap already provides them.
- Replace misleading POLICY_CONTEXT simulations with real-role checks. Tested context overrides did not reproduce IS_ROLE_IN_SESSION behavior in this account.
- Add a self-cleaning closed-version fixture and compare current email values with the source rather than assuming all emails are non-NULL.
- Give the stored operational recipient an owner-only direct masking policy so automatic classification does not redact the notification input.
- Require the optional CoCo policy prompt to identify missing merchant entitlement. The PII role has zero visible fact rows in this lab, so an empty query cannot prove the unmask branch.

## Limits and editorial checks

The initial approval block was resolved by the author's explicit approval of a fresh Cortex session and Chapter 15 metadata/test-result transfer. Cortex queried lab metadata and classification/audit results; it did not read manuscript files or raw business-table rows. The separate SQL AI_GENERATE_TABLE_DESC call also succeeded within Snowflake.

The original ACCESS_HISTORY/QUERY_HISTORY check returned no recent rows. By the CoCo follow-up, ten matching historical access records were visible. Two contained non-null secondary-role statistics, with roleCount 9; eight contained JSON null. Null alone does not establish that secondary roles were disabled. These are authorization statistics, not complete historical membership or returned-value evidence. ACCESS_HISTORY can lag three hours and QUERY_HISTORY 45 minutes, as documented in the references in `chapter15_coco_audit.sql`.

The manuscript and all 34 SQL/prompt excerpts pass the offline alignment checks. The latest draft is 7,044 words, estimated at about 30 Packt pages (28–32); Technical Requirements is unchanged from the approved short version. The DOCX builds with the correct author, two tables, 34 code-style blocks, no forced heading page breaks, and valid namespaces. Rendered pagination is not certified.

## CoCo prompt results

The lab was rebuilt from scripts 0–3 plus the documentation SQL through the new-column step. Scheduled incidents from the earlier completed SQL run supplied the historical audit evidence; no new incident or email was needed. The fresh Cortex session was `84caa848-8db1-4132-8f6e-997e4497edd0`.

| Scenario | Observed result and correction |
|---|---|
| Documentation generation and maintenance | Found four missing comments. The initial draft included unverified foreign-key and timestamp meanings, so the prompt now excludes unresolved meanings from executable SQL. The revised draft contained only the supplied PROCESSING_CHANNEL definition. After the reviewed comment was applied through SnowCLI, CoCo re-queried metadata, confirmed the exact comment and unchanged grain, and reported the other three gaps separately. |
| Policy drafting | Produced a NUMBER(5,2) masking policy with IS_ROLE_IN_SESSION('CH15_PII_READER'), an explicit NULL branch, and column attachment. Proposed tests disable secondary roles. CoCo correctly identified that the real PII context sees zero fact rows because of the row policy. The draft was reviewed, not applied; its positive branch cannot be verified through this fact table without a separately authorized entitlement. No grants or entitlement changes were executed. |
| Classification review | The first attempt used table-level tag lookup and did not capture a valid pre-call column snapshot. The prompt now specifies sequential TAG_REFERENCES_ALL_COLUMNS, an options-only dry call, and an after snapshot. The repeated sequence succeeded: all six PII_CATEGORY values matched and stayed unchanged; every tag_applied flag was false. POSTAL_CODE had LOW confidence and about 0.37 coverage. Missing recommendations were not treated as proof of nonsensitivity. |
| Quality and access audit | Initial output guessed view columns, omitted SECONDARY_ROLE_STATS, misattributed historical metrics to current objects, and misstated latency. Added and executed `chapter15_coco_audit.sql`, then repeated the CoCo audit against that evidence. It identified the latest failure at 15:41:00.032 UTC and following recovery at 15:45:54.419 UTC. Table ID 325640 was deleted at 15:52:16.414 UTC, proving those records belong to the earlier lab incarnation. Secondary-role null interpretation was explicitly corrected. |

Independent snapshots confirmed unchanged customer tags, fact policy references, and refund grain; PROCESSING_CHANNEL was the only changed column comment. The rebuilt lab and all five roles were removed through guarded teardown, with empty final SHOW results. All four source tables retained identical row counts, data hashes, DDL, and column tags after this cleanup. Treat model narratives as reviewable drafts; the recorded SQL results are the evidence baseline.
