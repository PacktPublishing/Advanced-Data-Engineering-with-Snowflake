# Chapter 16 recovery runbook reference

These definitions are for a reviewed deployment, not an execute-all script.
Requires two Business Critical accounts in the same organization for failover,
and replication enablement for both accounts. Verify feature availability and
supported object dependencies against the official references. The locked-backup
configuration requires Business Critical and APPLY BACKUP RETENTION LOCK.
Documentation reviewed in September 2026; no deployment or retention lock applied.

Replace only `<REPLACE: organization>`, `<REPLACE: target_account>`, and
`<REPLACE: source_account>` with your account identifiers. Create the target
warehouse and authorized restore/query role separately. This minimal group does
not replicate roles, warehouses, integration credentials, or client routing.

## Source-account portion

Confirm CURRENT_ACCOUNT() and CURRENT_ORGANIZATION_NAME() before creation.

```sql
USE ROLE ACCOUNTADMIN;
CREATE FAILOVER GROUP DR_FG
  OBJECT_TYPES = DATABASES
  ALLOWED_DATABASES = OPS_DB
  ALLOWED_ACCOUNTS = <REPLACE: organization>.<REPLACE: target_account>
  REPLICATION_SCHEDULE = '15 MINUTE';
```

## Target-account portion

Use an empty destination namespace; a colliding OPS_DB database must be reviewed.

```sql
USE ROLE ACCOUNTADMIN;
CREATE FAILOVER GROUP DR_FG AS REPLICA OF
  <REPLACE: organization>.<REPLACE: source_account>.DR_FG;
ALTER FAILOVER GROUP DR_FG REFRESH;
SHOW FAILOVER GROUPS LIKE 'DR_FG';
```

Use a target-account worksheet with a query warehouse to inspect refresh results:

```sql
SELECT *
FROM TABLE(OPS_DB.INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_HISTORY('DR_FG'));
SELECT COUNT(*), SUM(amount)
FROM OPS_DB.MONITORING.SETTLEMENT_LEDGER;
```

Expect completed refresh history and three rows totaling 60.00 for the initial
fixture. Compare full row content and the committed source position too.

## Planned promotion

Record source account, destination account, incident owner, RPO, RTO, and the
consumer-routing decision. Fence source writers, capture the final committed
position, finish a last refresh, and verify destination data. After refresh ends,
execute the following only in the approved destination account:

```sql
ALTER FAILOVER GROUP DR_FG PRIMARY;
```

Test user authentication, grants, warehouse access, application queries, and
source position before redirecting clients. Record recovery time at successful
application validation, not at DDL completion. In an outage, record any loss from
the last completed refresh before allowing new writes. Preserve one active writer.
For failback, refresh the recovered account from the temporary primary, fence
writers again, validate data, promote, and verify client routing.

## Locked-backup portion

This is an irreversible retention commitment once applied to a backup set.
Approve retention length and storage budget before executing. It is not part of
chapter16_5_restore.sql or core teardown.

```sql
USE ROLE ACCOUNTADMIN;
CREATE BACKUP POLICY OPS_DB.MONITORING.LOCKED_30D
  WITH RETENTION LOCK
  SCHEDULE = 'USING CRON 0 2 * * * UTC'
  EXPIRE_AFTER_DAYS = 30;
CREATE BACKUP SET OPS_DB.MONITORING.LEDGER_LOCKED_BACKUPS
  FOR TABLE OPS_DB.MONITORING.SETTLEMENT_LEDGER
  WITH BACKUP POLICY OPS_DB.MONITORING.LOCKED_30D;
```

Verify completed backup identifiers with SHOW BACKUPS. A scheduled set alone is
not proof of a usable recovery point. Use the restore syntax in the chapter's
restore worksheet, with the locked set and chosen backup identifier. Rehearse
restore authorization without using ACCOUNTADMIN for ordinary incident response.

## Cleanup after optional recovery work

For an expendable rehearsal, verify there are no clients or writers using the
replica. Suspend scheduled refresh on the secondary before removing the reviewed
secondary and primary groups using ALTER/DROP FAILOVER GROUP. Follow the official
drop restrictions and confirm group removal before dropping the lab database.
Do not issue promotion, group drop, or client changes through core teardown.

For a locked set, first stop scheduled backup creation using the documented
`ALTER BACKUP SET ... SUSPEND BACKUP CREATION POLICY` action. Keep expiration
running. Retain the set until all covered backups expire, then remove the set
and policy according to their drop requirements. The lock cannot be revoked.
Core teardown must wait until locked sets and failover membership are removed.
