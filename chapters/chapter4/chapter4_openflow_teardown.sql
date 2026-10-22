-- =============================================================================
-- Chapter 4: Real-Time Ingestion and Change Data Capture
-- OPENFLOW TEARDOWN -- Section 4 (Building Visual Integration Pipelines).
--
-- Removes the gen 2 OpenFlow runtime and deployment created by
-- chapter4_openflow_setup.sql (BLOCKS 3 and 4). Run it when you finish the
-- chapter: the deployment's management compute pool bills for as long as the
-- deployment exists, even with no runtime running.
--
-- IRREVERSIBLE: OpenFlow objects have no UNDROP. TERMINATE drains in-flight
-- data first; TERMINATE FORCE (not used here) purges queues and can lose data.
--
-- Before running: stop the flow on the canvas (right-click the process group
-- » Stop) so nothing is mid-flight. If you reused an existing deployment in
-- BLOCK 3, comment out the deployment statements at the bottom.
--
-- Leaves in place: OPENFLOW_DB, OPENFLOW_ADMIN, openflow_runtime_role, the
-- network rules, partner_api_access, the secret, and the RAW_DB.STREAMING
-- tables (other sections and later chapters can reuse them).
--
-- The wait functions raise an error if the named object does not exist; if a
-- previous run already removed the runtime, skip straight to the deployment.
-- Docs: https://docs.snowflake.com/en/user-guide/data-integration/openflow/gen2/openflow-generations
-- =============================================================================

USE ROLE OPENFLOW_ADMIN;

-- Runtime: ACTIVE -> SUSPENDED -> TERMINATED -> dropped
ALTER OPENFLOW RUNTIME IF EXISTS OPENFLOW_DB.CONTROL.partner_api_runtime SUSPEND;
SELECT SYSTEM$WAIT_FOR_STABLE_OPENFLOW_RUNTIMES(600, 'OPENFLOW_DB.CONTROL.PARTNER_API_RUNTIME');

ALTER OPENFLOW RUNTIME IF EXISTS OPENFLOW_DB.CONTROL.partner_api_runtime TERMINATE;
SELECT SYSTEM$WAIT_FOR_STABLE_OPENFLOW_RUNTIMES(600, 'OPENFLOW_DB.CONTROL.PARTNER_API_RUNTIME');

DROP OPENFLOW RUNTIME IF EXISTS OPENFLOW_DB.CONTROL.partner_api_runtime;

-- Deployment: must be TERMINATED before DROP (requires OWNERSHIP)
ALTER OPENFLOW DEPLOYMENT IF EXISTS techflow_ingest TERMINATE;
SELECT SYSTEM$WAIT_FOR_STABLE_OPENFLOW_DEPLOYMENTS(900, 'techflow_ingest');

DROP OPENFLOW DEPLOYMENT IF EXISTS techflow_ingest;

-- Verify: neither object is listed any more
SHOW OPENFLOW DEPLOYMENTS LIKE 'techflow_ingest';
SHOW OPENFLOW RUNTIMES IN SCHEMA OPENFLOW_DB.CONTROL;
