-- Chapter 17: revoke recipient access
-- Relationship: separate stage; Run after consumer positive and negative checks; leave access revoked.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

USE ROLE SYSADMIN;
ALTER SHARE MERCHANT_SHARE REMOVE ACCOUNTS =
  <REPLACE: consumer_org.consumer_account>;
SHOW SHARES LIKE 'MERCHANT_SHARE';
