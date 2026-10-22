"""Chapter 18 self-service plan generator. No Snowflake connection or execution.

Requires Python 3.11+ standard library. Uses only registry-derived SQL identifiers.
Reader-specific values belong in request.json; credentials never belong here.
Run tests before use. SQL is documentation-checked, not live-account validated.
The committed sample_plan.sql is this generator's output for request.json.
"""
from __future__ import annotations

import argparse
from datetime import date
from hashlib import sha256
import json
from pathlib import Path
import re
import sys

POLICY_VERSION = 'sandbox-v1'
REGISTRY = {
    'PAYMENTS': ('CC_PAYMENTS', 'SS_PAYMENTS_SANDBOX'),
    'RISK': ('CC_RISK', 'SS_RISK_SANDBOX'),
}
FIELDS = {
    'request_id', 'team', 'cost_center', 'environment', 'data_classification',
    'warehouse_size', 'monthly_credit_limit', 'expires_on',
}


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def invalid_constant(value):
    raise ValueError(f'invalid JSON constant: {value}')


def read_request(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=unique_keys,
                      parse_constant=invalid_constant)


def validate(request, as_of):
    if not isinstance(request, dict) or set(request) != FIELDS:
        raise ValueError('request must contain only the documented fields')
    for key in FIELDS - {'monthly_credit_limit'}:
        if not isinstance(request[key], str):
            raise ValueError(f'{key} must be a string')
    if not re.fullmatch(r'REQ-[0-9]{3}', request['request_id']):
        raise ValueError('request_id must match REQ-NNN')
    team = request['team']
    if team not in REGISTRY:
        raise ValueError('team is not registered')
    cost_center, prefix = REGISTRY[team]
    if request['cost_center'] != cost_center:
        raise ValueError('cost_center does not match the registered team')
    for key, expected in [('environment', 'SANDBOX'),
                          ('data_classification', 'SYNTHETIC'),
                          ('warehouse_size', 'XSMALL')]:
        if request[key] != expected:
            raise ValueError(f'{key} must be {expected}')
    quota = request['monthly_credit_limit']
    if type(quota) is not int or not 1 <= quota <= 100:
        raise ValueError('monthly_credit_limit must be an integer from 1 through 100')
    try:
        expiry = date.fromisoformat(request['expires_on'])
    except ValueError as exc:
        raise ValueError('expires_on must be an ISO date') from exc
    if expiry.isoformat() != request['expires_on']:
        raise ValueError('expires_on must use YYYY-MM-DD')
    if not 1 <= (expiry - as_of).days <= 30:
        raise ValueError('expires_on must be within the next 30 days')
    return prefix


def render_plan(request, prefix):
    # Identifiers originate only from the protected registry, not free-form JSON.
    # The quota is validated as a bounded integer before rendering, and the cost
    # center has already been checked against the registry entry for the team.
    quota = request['monthly_credit_limit']
    cost_center = request['cost_center']
    return f'''-- Chapter 18: generated sandbox provisioning plan. NOT executed by generator.
-- Prerequisites: approved target account; inspect reserved names before running.
-- Validation: docs checked October 2026; SQL not run live during authoring.
-- Placeholders: none; this template uses fixed registry identifiers.
-- Roles: USERADMIN roles; SECURITYADMIN hierarchy; SYSADMIN warehouse and
-- database handoff; the team ADMIN role builds inside its database;
-- ACCOUNTADMIN monitor creation. Stop on every error, including existing names.
-- The default PUBLIC schema is dropped so every team schema is managed access.
-- The warehouse comment records the cost center; Enterprise accounts can tag it too.
-- User/group assignment, accounting registration and expiry enforcement are separate.
USE ROLE USERADMIN;
CREATE ROLE {prefix}_ADMIN;
CREATE ROLE {prefix}_BUILDER;
CREATE ROLE {prefix}_READER;
USE ROLE SECURITYADMIN;
GRANT ROLE {prefix}_BUILDER TO ROLE {prefix}_ADMIN;
GRANT ROLE {prefix}_READER TO ROLE {prefix}_ADMIN;
GRANT ROLE {prefix}_ADMIN TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
USE SECONDARY ROLES NONE;
CREATE WAREHOUSE {prefix}_WH
  WAREHOUSE_TYPE = STANDARD
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 60
  STATEMENT_TIMEOUT_IN_SECONDS = 300
  COMMENT = 'cost_center={cost_center}';
GRANT USAGE ON WAREHOUSE {prefix}_WH TO ROLE {prefix}_BUILDER;
GRANT USAGE ON WAREHOUSE {prefix}_WH TO ROLE {prefix}_READER;
CREATE DATABASE {prefix};
DROP SCHEMA {prefix}.PUBLIC;
GRANT OWNERSHIP ON DATABASE {prefix}
  TO ROLE {prefix}_ADMIN COPY CURRENT GRANTS;
USE ROLE {prefix}_ADMIN;
CREATE SCHEMA {prefix}.WORK WITH MANAGED ACCESS;
CREATE SCHEMA {prefix}.PUBLISHED WITH MANAGED ACCESS;
GRANT USAGE ON DATABASE {prefix} TO ROLE {prefix}_BUILDER;
GRANT USAGE ON SCHEMA {prefix}.WORK TO ROLE {prefix}_BUILDER;
GRANT CREATE TABLE ON SCHEMA {prefix}.WORK TO ROLE {prefix}_BUILDER;
CREATE DATABASE ROLE {prefix}.WORK_READER;
GRANT USAGE ON DATABASE {prefix} TO DATABASE ROLE {prefix}.WORK_READER;
GRANT USAGE ON SCHEMA {prefix}.WORK TO DATABASE ROLE {prefix}.WORK_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA {prefix}.WORK
  TO DATABASE ROLE {prefix}.WORK_READER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA {prefix}.WORK
  TO DATABASE ROLE {prefix}.WORK_READER;
GRANT DATABASE ROLE {prefix}.WORK_READER TO ROLE {prefix}_READER;
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR {prefix}_RM
  WITH CREDIT_QUOTA = {quota}
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 70 PERCENT DO NOTIFY
           ON 90 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE {prefix}_WH SET RESOURCE_MONITOR = {prefix}_RM;
SHOW WAREHOUSES LIKE '{prefix}_WH';
SHOW RESOURCE MONITORS LIKE '{prefix}_RM';
USE ROLE SYSADMIN;
SHOW SCHEMAS IN DATABASE {prefix};
SHOW GRANTS TO ROLE {prefix}_BUILDER;
SHOW GRANTS TO ROLE {prefix}_READER;
-- EXPECT: one warehouse with its named monitor, quota {quota}, monthly frequency;
-- the ADMIN role owns the database and both managed schemas;
-- builder creation access in WORK only.
-- Inspect exact names because underscores in SHOW LIKE are wildcard characters.
-- No user membership was assigned. Finish acceptance before releasing access.
'''


def generate(request, as_of):
    prefix = validate(request, as_of)
    canonical = json.dumps(request, sort_keys=True, separators=(',', ':'))
    plan = render_plan(request, prefix)
    receipt = {
        'status': 'VALIDATED', 'policy_version': POLICY_VERSION,
        'validated_as_of': as_of.isoformat(),
        'request_sha256': sha256(canonical.encode()).hexdigest(),
        'plan_sha256': sha256(plan.encode()).hexdigest(),
        'request': request, 'object_prefix': prefix,
        'approval_status': 'NOT_APPROVED', 'deployment_status': 'NOT_DEPLOYED',
        'acceptance_required': [
            'Bind approval to protected policy, actual target account and plan digest.',
            'Validate allowed and denied access with approved test identities.',
            'Inspect warehouse controls and resource monitor attachment.',
            'Register actual account/warehouse IDs and effective cost ownership.',
            'Record owner, recovery instructions and an enforced expiry workflow.',
            'Assign approved user/group membership only after acceptance.',
        ],
    }
    cleanup = f'''-- Chapter 18 optional cleanup for generated workspace {prefix}.
-- Inspect ownership, consumers, retention and approval BEFORE uncommenting.
-- Not run by the generator. SQL not live-validated. No placeholders.
-- Roles: ACCOUNTADMIN removes monitor; SYSADMIN objects (it inherits the ADMIN
-- role that owns the database); USERADMIN roles.
-- USE ROLE SYSADMIN;
-- DROP WAREHOUSE IF EXISTS {prefix}_WH;
-- DROP DATABASE IF EXISTS {prefix};
-- USE ROLE ACCOUNTADMIN;
-- DROP RESOURCE MONITOR IF EXISTS {prefix}_RM;
-- USE ROLE USERADMIN;
-- DROP ROLE IF EXISTS {prefix}_BUILDER;
-- DROP ROLE IF EXISTS {prefix}_READER;
-- DROP ROLE IF EXISTS {prefix}_ADMIN;
'''
    return plan, receipt, cleanup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('request', type=Path)
    parser.add_argument('--as-of', type=date.fromisoformat, default=date.today(),
                        help='fixture date override; a deployed service must protect its clock')
    parser.add_argument('--out', type=Path, required=True,
                        help='new output directory; existing paths are never overwritten')
    args = parser.parse_args()
    try:
        plan, receipt, cleanup = generate(read_request(args.request), args.as_of)
        # Validation completes before any output directory or artifact is created.
        args.out.mkdir(parents=False, exist_ok=False)
        for name, data in [('plan.sql', plan),
                           ('receipt.json', json.dumps(receipt, indent=2) + '\n'),
                           ('cleanup.sql', cleanup)]:
            with (args.out / name).open('x') as output:
                output.write(data)
        print(json.dumps(receipt, indent=2))
    except (ValueError, OSError) as exc:
        print(f'REJECTED: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
