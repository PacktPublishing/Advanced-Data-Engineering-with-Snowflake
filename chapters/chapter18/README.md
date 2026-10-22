# Chapter 18 companion

Multi-Tenant & Multi-Team Platform Design. The core lab runs in one sandbox account:
a team administrator that owns its own database, builder and reader roles, two
warehouses tuned for different workloads, synthetic chargeback arithmetic, a team
budget, and local request validation. It does not provision additional Snowflake
accounts or connect to tenant data. Reference queries for organizations, tags, and
noisy-neighbor detection are included as optional files.

## Validation status

Official Snowflake documentation checked October 2026. Local Python checks run
with Python 3.12. The scripts require Python 3.11+ and only the standard library.
Seventeen local tests cover allocation arithmetic, invalid mappings, date boundaries,
request rejection, deterministic plans, the committed sample plan, the team-admin
handoff in generated plans, and output overwrite protection. One test executes the
allocation SELECT through SQLite after removing its table qualifiers; this verifies
relational arithmetic, not Snowflake dialect compatibility.
`chapter18_static_checks.py --chapter <manuscript>` confirms that every code block
in the chapter appears verbatim in this folder.

**Every SQL script in this folder was run against a live Snowflake account in
October 2026**, with additions from October 14 that are pending a live run: the
team administrator's CREATE WAREHOUSE denial, the publication block (view in
PUBLISHED, PUBLISHED_READER database role), the SHOW GRANTS audit line in the
WORK_READER block and the grant-audit query in the denials worksheet, the
reversed warehouse denial (Risk to PAYMENTS_WH), DROP SCHEMA PAYMENTS_DB.PUBLIC in
setup, and the blocked_s column and hourly block in the contention script. The
October run changed only the organization query, which now documents two paths
(see below). Performance isolation under load and deployment of a generated
self-service plan were not exercised.

## Files and prerequisites

| File | Chapter section | Needs |
|---|---|---|
| `chapter18_0_setup.sql` | Creating the delegated workspace, steps 1 and 2 | Sandbox; USERADMIN, SECURITYADMIN, SYSADMIN |
| `chapter18_1_organization.sql` | Governing the account fleet (optional) | GLOBALORGADMIN in an organization account, or ORGADMIN after a one-time ACCOUNTADMIN grant |
| `chapter18_2_roles.sql` | Creating the delegated workspace, steps 3 and 4 | Setup completed |
| `chapter18_2_denials.sql` | Testing denied access and delegation (three denials, one publication, one grant the design cannot stop) | Workspace worksheet completed; run statements individually |
| `isolation_contract_template.md` | Defining the isolation contract | Blank contract with the clauses and the evidence each needs |
| `isolation_contract_techflow.md` | Defining the isolation contract | TechFlow's completed contract, each clause mapped to its test |
| `chapter18_3_isolation.sql` | Verifying the warehouse boundary | Setup completed; final statement must fail |
| `chapter18_3_contention.sql` | Detecting noisy neighbors and planning tenant growth (optional, weekly and hourly) | Reporting role with SNOWFLAKE.GOVERNANCE_VIEWER |
| `chapter18_4_tags.sql` | Defining the chargeback ledger (optional) | Enterprise Edition; reporting role with SNOWFLAKE.GOVERNANCE_VIEWER and SNOWFLAKE.USAGE_VIEWER |
| `chapter18_4_allocation.sql` | Reconciling a shared compute allocation | Setup completed; stop on any validation exception |
| `chapter18_4_source.sql` | Reconciling a shared compute allocation (optional account projection) | Reporting role with SNOWFLAKE.USAGE_VIEWER |
| `chapter18_4_budget.sql` | Applying team budgets | Setup completed; ACCOUNTADMIN for the first block only |
| `request.json` | Validating a provisioning request, step 1 | Local validator |
| `request_over_limit.json` | Validating a provisioning request, step 4 | Local validator; must be rejected |
| `selfservice.py` | Validating a provisioning request | Python 3.11+, no Snowflake credentials |
| `sample_plan.sql` | Validating a provisioning request, step 3 | Generator output for `request.json`, committed for review |
| `warehouse_hours.csv`, `ownership_map.csv` | Allocation fixture | Same synthetic rows as the setup script |
| `allocation.py` | Reconciling a shared compute allocation, step 3 | Python standard library |
| `test_local.py` | Local correctness checks | Python standard library |
| `chapter18_static_checks.py` | Repo and manuscript alignment | Python standard library |
| `chapter18_cleanup.sql` | End-of-chapter cleanup | Review and uncomment selected statements |

## SQL execution order

1. Check that none of the reserved names exist: databases `PAYMENTS_DB`, `RISK_DB`,
   `CONTROL_DB`; warehouses `PAYMENTS_WH`, `RISK_WH`, `ADMIN_WH`; roles
   `PAYMENTS_ADMIN`, `PAYMENTS_BUILDER`, `PAYMENTS_READER`, `RISK_READER`,
   `COST_READER`, `COST_ADMIN`; the denials worksheet also creates the view
   `PAYMENTS_DB.PUBLISHED.DAILY_SETTLEMENT` and the database role
   `PAYMENTS_DB.PUBLISHED_READER`, and must fail to create `PAYMENTS_SCRATCH_WH`.
   Setup deliberately uses plain CREATE so it will not overlay existing state.
2. Open a Snowsight worksheet and run the setup script's blocks in order. Stop on
   the first error. Never skip an existing-table error and run its INSERT.
3. Run the worksheet for the section you are following. The isolation, allocation,
   and budget worksheets need only the setup script, not the role exercises.
4. Run each negative-test statement individually and confirm its positive control
   first. Never treat every SQL error as a successful access test. If the builder's
   grant attempt succeeds, have PAYMENTS_ADMIN revoke it before continuing; if the
   administrator's CREATE WAREHOUSE succeeds, drop the warehouse as SYSADMIN.
5. Run every validation block in the allocation worksheet before its allocation and
   reconciliation blocks. Zero exception rows is required.
6. Inspect SHOW results for exact object names. Underscores in SHOW LIKE patterns
   are wildcards, so similarly named objects may appear.
7. Keep receipts and evidence, then review the commented cleanup script. The
   generated self-service plan has its own cleanup script.

SYSADMIN creates PAYMENTS_DB and transfers its ownership to PAYMENTS_ADMIN, which
creates the managed WORK and PUBLISHED schemas and makes every grant inside the
database. Cross-team access goes through a view in PUBLISHED and the
PUBLISHED_READER database role. Because PAYMENTS_ADMIN owns WORK_READER it could
still grant WORK to another team, so audit WORK_READER grantees regularly. SYSADMIN inherits PAYMENTS_ADMIN and can still drop the database. RISK_DB
and CONTROL_DB stay owned by SYSADMIN. The administrator assigns exercise roles to
the current lab user for switching between test contexts. User defaults are not
changed. Secondary roles are disabled in role tests, but users can still activate
any assigned primary role. Use separate, narrowly assigned identities for an
application isolation assessment.

XSmall standard warehouses start suspended with a 60-second auto-suspend and a
300-second statement timeout. The isolation worksheet then raises PAYMENTS_WH to a
1800-second statement timeout and gives RISK_WH a concurrency level of 4 and a
60-second queued timeout. These are lab settings, not performance commitments.

## Organization query paths

`METERING_DAILY_HISTORY` is a non-premium `ORGANIZATION_USAGE` view, so it exists
in both kinds of account. Premium views such as `QUERY_HISTORY` and
`TAG_REFERENCES` exist only in the organization account.

- Path A, organization account: `USE ROLE GLOBALORGADMIN`. No extra grant.
- Path B, ORGADMIN-enabled regular account, including a single-account trial:
  `USE ROLE ORGADMIN` after ACCOUNTADMIN runs
  `GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE ORGADMIN` once.
  ORGADMIN also needs a warehouse it can use.

Snowflake is phasing out ORGADMIN in regular accounts in favor of GLOBALORGADMIN
in the organization account, so Path B is the interim route.

## Expected outputs

- Setup: two Risk rows and three synthetic metering rows; SHOW GRANTS TO ROLE
  PAYMENTS_ADMIN lists the builder and reader roles.
- Workspace: WORK and PUBLISHED are managed access schemas owned by PAYMENTS_ADMIN.
- Payments builder and reader: two batches totaling $300.00.
- Risk: reads two own rows; the Payments-table SELECT is denied.
- Payments builder: cannot grant its table to Risk.
- Risk: cannot select PAYMENTS_WH, which protects the settlement deadline.
- Payments admin: cannot create a warehouse (account privilege stays central).
- Payments admin: publishes DAILY_SETTLEMENT, grants PUBLISHED_READER to Risk (Risk
  reads two batches from the view and is still denied on WORK), then revokes it.
- Payments admin: CAN grant WORK_READER to Risk (Risk reads two batches from WORK);
  SHOW GRANTS TO ROLE RISK_READER lists it; revoke it. The grant-audit query
  finds such grants after the fact. Publishing through
  PUBLISHED is a policy enforced by audit, not by privileges.
- Isolation: PAYMENTS_WH statement timeout 1800; RISK_WH concurrency 4, queued timeout 60.
- Allocation: CC_PAYMENTS gets 18 compute credits and 4.2 idle; CC_RISK gets 12 and 2.8.
- Reconciliation: both compute and idle differences are zero.
- Budget: GET_SPENDING_LIMIT returns 20; one linked resource, PAYMENTS_WH.
- Self-service: VALIDATED receipt, NOT_APPROVED, NOT_DEPLOYED; no SQL execution.

The metering account key TECHFLOW and warehouse IDs 101-103 are fictional. Never join
those IDs to account metadata. Allocation intervals are UTC, start-inclusive and
end-exclusive, with changes on hour boundaries. NULL attribution is unavailable,
not zero. The fixture allocation rejects it; Adaptive metering needs a separate
pipeline. The optional projection preserves all rows, including NULL attribution.

## Local commands

Run these commands from this chapter directory.

```bash
python3 -m unittest -v test_local.py
python3 allocation.py
```

All 17 tests pass and the allocation prints the two cost-center rows above.

The sample request expires on October 14, 2026, so the fixed validation date keeps
the lab reproducible:

```bash
python3 selfservice.py request.json --as-of 2026-09-14 --out ./request-review
```

The command creates `request-review/plan.sql`, `receipt.json`, and `cleanup.sql`,
and refuses to overwrite an existing output directory. The plan matches the
committed `sample_plan.sql`. For a request validated today, omit `--as-of` and
choose an expiry one to 30 days in the future.

To test rejection, run the over-limit request:

```bash
python3 selfservice.py request_over_limit.json --as-of 2026-09-14 --out ./review-200
```

Expect exit code 2, a REJECTED message, and no output directory. Copy `request.json`
and change the cost center or add a field to test the other rejections.

A deployed request service must use a protected clock, registry, identity, target
account, and approval state. Neither a JSON document nor its hash proves
authentication or authorization. The CLI is a local teaching component.

To check the manuscript against this folder:

```bash
python3 chapter18_static_checks.py --chapter /path/to/Chapter_18_Multi_Tenant_and_Multi_Team_Platform_Design.md
```

## Deployment acceptance and lifecycle

The generator does not implement a CI/CD executor, portal, user authentication,
identity-group assignment, automatic expiry, drift correction, or cost registration.
Bind protected approval to the actual target and plan digest in your deployment
system (Chapter 10 covers DCM and Terraform pipelines). Serialize changes by
workspace. Monitor attachment can fail after earlier DDL succeeds; withhold user
membership and inspect partial state before retrying.

Before releasing access, verify admin grants, builder creation and reader access in
WORK, publication through PUBLISHED only, negative cross-team tests at every layer,
warehouse controls, monitor attachment, and cost-owner registration using actual
account and warehouse identifiers.

## Primary references

- [Organization administrators](https://docs.snowflake.com/en/user-guide/organization-administrators)
- [Organization accounts](https://docs.snowflake.com/en/user-guide/organization-accounts)
- [ORGANIZATION_USAGE METERING_DAILY_HISTORY](https://docs.snowflake.com/en/sql-reference/organization-usage/metering_daily_history)
- [Access control](https://docs.snowflake.com/en/user-guide/security-access-control-overview)
- [Managed access schemas](https://docs.snowflake.com/en/user-guide/security-access-control-configure)
- [Grant semantics](https://docs.snowflake.com/en/sql-reference/sql/grant-privilege)
- [GRANT DATABASE ROLE](https://docs.snowflake.com/en/sql-reference/sql/grant-database-role)
- [Secondary roles](https://docs.snowflake.com/en/sql-reference/sql/use-secondary-roles)
- [SNOWFLAKE database roles](https://docs.snowflake.com/en/sql-reference/snowflake-db-roles)
- [QUERY_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)
- [Attributing cost](https://docs.snowflake.com/en/user-guide/cost-attributing)
- [Warehouse metering](https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history)
- [Budgets](https://docs.snowflake.com/en/user-guide/budgets)
- [Budget custom actions](https://docs.snowflake.com/en/user-guide/budgets/custom-actions)
