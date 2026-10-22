-- =====================================================================
-- Chapter 10, Section 1.2: Running versioned SQL from a Git repository
-- =====================================================================
-- Wire Snowflake to the TechFlow repo so the same file that sits in a pull
-- request is the file the account executes, with no copy-paste step.
--
-- Run as a role that can create API integrations (ACCOUNTADMIN, or a role
-- with CREATE INTEGRATION). The prefix names the one repository this
-- integration can reach. ALLOWED_AUTHENTICATION_SECRETS = NONE stops the
-- integration from ever using a stored credential (correct for a public repo).
-- =====================================================================

-- 1.2a  API integration + Git repository object (public-repo form)
CREATE OR REPLACE API INTEGRATION techflow_git_api
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/PacktPublishing/')
    ALLOWED_AUTHENTICATION_SECRETS = NONE
    ENABLED = TRUE;

CREATE OR REPLACE GIT REPOSITORY techflow_repo
    API_INTEGRATION = techflow_git_api
    ORIGIN = 'https://github.com/PacktPublishing/Advanced-Data-Engineering-with-Snowflake.git';

-- ---------------------------------------------------------------------
-- PRIVATE-REPO ALTERNATIVE (uncomment and set your own token/username)
-- For a private repository, replace NONE with the secret name, and pass
-- GIT_CREDENTIALS to the repository object.
-- ---------------------------------------------------------------------
-- CREATE OR REPLACE SECRET techflow_git_secret
--     TYPE = password
--     USERNAME = '<github_username>'
--     PASSWORD = '<github_personal_access_token>';   -- classic PAT with repo scope
--
-- CREATE OR REPLACE API INTEGRATION techflow_git_api
--     API_PROVIDER = git_https_api
--     API_ALLOWED_PREFIXES = ('https://github.com/PacktPublishing/')
--     ALLOWED_AUTHENTICATION_SECRETS = (techflow_git_secret)
--     ENABLED = TRUE;
--
-- CREATE OR REPLACE GIT REPOSITORY techflow_repo
--     API_INTEGRATION = techflow_git_api
--     GIT_CREDENTIALS = techflow_git_secret
--     ORIGIN = 'https://github.com/PacktPublishing/Advanced-Data-Engineering-with-Snowflake.git';

SHOW GIT REPOSITORIES LIKE 'techflow_repo';

-- 1.2b  Fetch latest commits and execute a versioned script from a branch.
-- For automation, prefer an immutable path such as
-- @techflow_repo/commits/<commit-sha>/... so a new push cannot change the
-- file between review and execution.
ALTER GIT REPOSITORY techflow_repo FETCH;

EXECUTE IMMEDIATE FROM
    @techflow_repo/branches/main/chapters/chapter10/native/warehouses.sql;
