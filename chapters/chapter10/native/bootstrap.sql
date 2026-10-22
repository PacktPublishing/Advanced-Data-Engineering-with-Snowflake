-- =====================================================================
-- Chapter 10, Section 2.1: Bootstrapping the deployment roles
-- =====================================================================
-- Run once as ACCOUNTADMIN. Creates the Terraform deployer role, the
-- ops_db.dcm metadata schema, and the two DCM owner roles the manifest
-- references. Everything after this script runs under least-privilege roles.
--
-- Assumes TF_SERVICE_USER already exists with its key pair registered
-- (Technical Requirements). If that user is not yet created, comment out
-- the GRANT ROLE ... TO USER line and add it after the user exists.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS TERRAFORM_DEPLOYER;
GRANT CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE
    ON ACCOUNT TO ROLE TERRAFORM_DEPLOYER;
GRANT MANAGE GRANTS ON ACCOUNT TO ROLE TERRAFORM_DEPLOYER;
-- Uncomment after TF_SERVICE_USER exists with its key pair registered:
-- GRANT ROLE TERRAFORM_DEPLOYER TO USER TF_SERVICE_USER;

CREATE SCHEMA IF NOT EXISTS ops_db.dcm;

CREATE ROLE IF NOT EXISTS DCM_DEVELOPER;
GRANT USAGE ON DATABASE ops_db TO ROLE DCM_DEVELOPER;
GRANT USAGE, CREATE DCM PROJECT ON SCHEMA ops_db.dcm TO ROLE DCM_DEVELOPER;

CREATE ROLE IF NOT EXISTS DCM_PROD_DEPLOYER;
GRANT USAGE ON DATABASE ops_db TO ROLE DCM_PROD_DEPLOYER;
GRANT USAGE, CREATE DCM PROJECT ON SCHEMA ops_db.dcm TO ROLE DCM_PROD_DEPLOYER;

-- Each role can create its own project in this metadata schema. CREATE DCM
-- PROJECT alone does not authorize changes to the other role's project.
-- The manifest pairs TECHFLOW_PIPELINE_DEV with DCM_DEVELOPER and
-- TECHFLOW_PIPELINE_PROD with DCM_PROD_DEPLOYER. Central provisioning can
-- create both once and restrict ongoing access to their respective owners.

-- Verify: three account-level creates + MANAGE GRANTS, and DCM schema present.
SHOW GRANTS TO ROLE TERRAFORM_DEPLOYER;
SHOW SCHEMAS LIKE 'DCM' IN DATABASE ops_db;
