-- Chapter 17: authorize one consumer
-- Relationship: separate stage; Inspect the share grants first; same-region consumer account required.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

USE ROLE SYSADMIN;
ALTER SHARE MERCHANT_SHARE ADD ACCOUNTS =
  <REPLACE: consumer_org.consumer_account>;
SHOW SHARES LIKE 'MERCHANT_SHARE';
