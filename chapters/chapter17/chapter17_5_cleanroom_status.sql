-- Chapter 17: collaboration status check
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

USE ROLE SAMOOHA_APP_ROLE;
USE SECONDARY ROLES NONE;
CALL SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.COLLABORATION.GET_STATUS(
  '<REPLACE: collaboration_source_name>'
);
