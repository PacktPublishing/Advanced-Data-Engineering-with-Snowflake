-- Chapter 17: identity inventory in each account
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

SELECT CURRENT_ORGANIZATION_NAME() AS organization_name,
       CURRENT_ACCOUNT_NAME() AS account_name,
       CURRENT_ACCOUNT() AS account_locator,
       CURRENT_REGION() AS region_name;
