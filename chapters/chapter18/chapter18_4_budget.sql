-- Chapter 18: team budget (section "Applying team budgets").
-- Run the setup script first. Independent of the role and allocation worksheets.
-- Prerequisites: sandbox account; setup completed.
-- Validation: official Snowflake docs checked October 2026; SQL run live October 2026.
-- Placeholders: none.
-- Roles: ACCOUNTADMIN grants the SNOWFLAKE database roles once, because only it
-- can; COST_ADMIN then owns and administers the budget without ACCOUNTADMIN.
-- Budget usage refreshes up to every 6.5 hours, so spend appears later.

-- BLOCK: delegate budget administration
USE ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.BUDGET_CREATOR TO ROLE COST_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER TO ROLE COST_ADMIN;
GRANT CREATE SNOWFLAKE.CORE.BUDGET ON SCHEMA CONTROL_DB.COST
  TO ROLE COST_ADMIN;
GRANT APPLYBUDGET ON WAREHOUSE PAYMENTS_WH TO ROLE COST_ADMIN;

-- BLOCK: Payments budget
USE ROLE COST_ADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE ADMIN_WH;
CREATE SNOWFLAKE.CORE.BUDGET CONTROL_DB.COST.PAYMENTS_BUDGET();
CALL CONTROL_DB.COST.PAYMENTS_BUDGET!SET_SPENDING_LIMIT(20);
CALL CONTROL_DB.COST.PAYMENTS_BUDGET!ADD_RESOURCE(
  SYSTEM$REFERENCE('warehouse', 'PAYMENTS_WH', 'SESSION', 'applybudget'));
CALL CONTROL_DB.COST.PAYMENTS_BUDGET!GET_SPENDING_LIMIT();
CALL CONTROL_DB.COST.PAYMENTS_BUDGET!GET_LINKED_RESOURCES();
-- EXPECT (observed October 2026): Instance PAYMENTS_BUDGET successfully created.
-- ADD_RESOURCE returns: Successfully added resource to resource group.
-- GET_SPENDING_LIMIT returns 20, and GET_LINKED_RESOURCES returns one row,
-- PAYMENTS_WH in the WAREHOUSE domain.
-- The budget notifies and reports only. It suspends nothing unless a custom
-- action procedure is attached, which this lab deliberately does not do.
