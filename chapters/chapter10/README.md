# Automating Snowflake with DCM and Infrastructure as Code

Companion code for Chapter 10, revised for the September 2026 review. Follow
native automation, Terraform scaffolding, DCM definitions, then CI/CD. The
active deployment order is Terraform, native stream SQL, then DCM. The old
schemachange example is retained for reference and is excluded from CI.

## Install tools and prepare the account

1. Install **Terraform CLI 1.14.4** using the [official guide](https://developer.hashicorp.com/terraform/install).
   Select the binary for your OS and architecture, add it to PATH, and run
   `terraform version`. The Snowflake provider is a separate plugin installed
   by `terraform init`; the committed lock file fixes its selected version.
2. Install Python 3.12. Create an isolated environment with `python -m venv .venv`
   and activate it with `source .venv/bin/activate` on macOS/Linux or
   `.venv\Scripts\Activate.ps1` in PowerShell. Run
   `python -m pip install "snowflake-cli==3.26.0"` and check `snow --version`.
   The GA DCM commands do not need the old project feature flag.
3. Complete Chapter 9 first: `RAW_DB`, `SILVER_DB`, `GOLD_DB`, `OPS_DB.PIPELINES`,
   `BOOK_WH`, the raw transaction table, and the pipeline audit table must exist.
   Bootstrap creates deployment identities and metadata; it does not recreate
   the entire Chapter 9 pipeline.
4. Prepare a key-pair service user and a named CLI connection, called `book`
   below. Replace TECHFLOW-MAIN in the manifest with your account. Keep the
   standardized book object names unchanged.

DCM Projects became [GA on 7 August 2026](https://docs.snowflake.com/en/release-notes/2026/other/2026-08-07-dcm-projects-ga).
[DEFINE STREAM remains open preview](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-supported-entities#label-dcm-projects-object-type-stream)
as of September 2026. The chapter retains the shared stream in native SQL by
choice, not because DCM cannot define streams.

## Find the code

All paths below are relative to `chapters/chapter10/`. Start commands there
unless a step changes directory.

| Path | Section and purpose |
|---|---|
| `native/warehouses.sql` | 1.1, idempotent warehouse example |
| `native/git_integration.sql` | 1.2, Git integration and versioned SQL |
| `native/bootstrap.sql` | 2.1, roles and metadata schema |
| `infra/` | 2.2–2.4, Terraform provider, resources, import, remote state |
| `techflow_pipeline/manifest.yml` | 3.2, targets and templating |
| `techflow_pipeline/sources/definitions/10_raw.sql` | 3.3, shared raw definitions, PROD only |
| `techflow_pipeline/sources/definitions/20_silver.sql` | 3.3, silver Dynamic Table |
| `techflow_pipeline/sources/definitions/30_gold.sql` | 3.3, gold objects and a suspended daily-revenue task |
| `native/streams.sql` | 3.4, shared stream retained in native SQL |
| `cicd/snowflake-plan.yml` | 4.2, DEV review plans |
| `cicd/snowflake-deploy.yml` | 4.2, PROD plans, approval, deployment |
| `.cortex/skills/` | 4.4, Terraform authoring and ownership guidance |
| `migrations/` | Legacy reference only; excluded from this exercise |

## Run the walkthrough

### Native automation and bootstrap

Follow each script's role prerequisites. Run the warehouse example before
importing BOOK_WH; after import, manage it through Terraform. Select the
Chapter 9 database/schema context for the Git repository example first.

```bash
snow sql -c book -f native/warehouses.sql
snow sql -c book -f native/git_integration.sql
snow sql -c book -f native/bootstrap.sql
```

Expect SQL success messages and SHOW output for the roles and DCM schema.
Enable the optional user grant only after that service user exists.

Each DCM role creates a distinct project in OPS_DB.DCM. CREATE DCM PROJECT
does not grant control of the other role's existing project. Before planning,
complete account-specific grants and the Chapter 9 ownership handoff:

| Role | Operating access to configure |
|---|---|
| `TERRAFORM_DEPLOYER` | Grant to each Terraform user; ownership/access to import and manage BOOK_WH and declared resources |
| `DCM_DEVELOPER` | Own DEV project; CREATE DATABASE; USAGE on BOOK_WH, raw containers and OPS_DB.PIPELINES; SELECT on raw table; CREATE TASK in task schema; execution privileges if tasks are started |
| `DCM_PROD_DEPLOYER` | Own PROD project and adopted objects; warehouse/container usage; privileges for declared objects; own the shared stream or have its creation privileges if absent |

Use the [DCM privilege guidance](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-use)
and inspect plans before deployment. The bootstrap does not automatically
transfer ownership of existing Chapter 9 objects.

### Terraform

Supply connection values through provider environment variables or an
uncommitted tfvars file. The explicit provider role is TERRAFORM_DEPLOYER;
the workflow's DCM session role does not override it.

```bash
cd infra
terraform init
terraform import snowflake_warehouse.book_wh '"BOOK_WH"'
terraform validate
terraform plan
cd ..
```

Initialization installs the provider; import records the existing warehouse.
Align the HCL until the adoption plan has no unintended changes. Commit the
lock file, never state, keys, or credential-containing tfvars.

### DCM and the shared stream

DEV creates suffixed silver/gold objects and reads the existing raw table.
Only PROD defines shared raw objects. Create both project objects before CI.

```bash
cd techflow_pipeline
snow dcm create -c book --role DCM_DEVELOPER --target DCM_DEV --if-not-exists
snow dcm plan -c book --role DCM_DEVELOPER --target DCM_DEV
snow dcm deploy -c book --role DCM_DEVELOPER --target DCM_DEV --alias "Add silver dynamic table"
snow dcm create -c book --role DCM_PROD_DEPLOYER --target DCM_PROD --if-not-exists
snow dcm plan -c book --role DCM_PROD_DEPLOYER --target DCM_PROD
cd ..
snow sql -c book --role DCM_PROD_DEPLOYER -f native/streams.sql
bash .cortex/skills/object-ownership/check_ownership.sh
```

Expect plan summaries, a DEV deployment, SQL success, and an ownership-check
pass. Review PROD adoption before deploying it. The stream script preserves
an existing offset but does not reconcile its properties. The daily-revenue
task arrives suspended and is not the complete Chapter 9 graph.

**Existing deployments:** an earlier example defined raw objects in both
targets. If DEV already manages them, do not simply deploy their removal:
DCM can interpret it as a drop. Follow the documented DCM unmanage procedure
first, establish PROD ownership, and review both plans. No account ownership
handoff was performed in this revision. Do not run the legacy migration
alongside the native stream script; Chapter 9 already supplies its audit table.

## Configure your own workflows

The YAML files in `cicd/` are templates. GitHub only discovers workflows in
[the root `.github/workflows/` directory](https://docs.github.com/en/actions/tutorials/create-an-example-workflow).
Copy both templates into your own repository after completing setup:

1. Configure shared remote state and import BOOK_WH into that state. For the
   commented HCP configuration, set your organization/workspace, select local
   execution mode for this runner-based saved-plan example, and deliberately
   migrate any existing local state before CI.
2. Configure `TF_API_TOKEN`, `SNOWFLAKE_CI_PRIVATE_KEY`, and
   `SNOWFLAKE_DEPLOY_PRIVATE_KEY`. Register each user's own public key. PROD
   planning needs its credential before approval, so an environment-only secret
   is unavailable to that job. Restrict repository access accordingly.
3. Grant CI_SERVICE_USER the Terraform and DEV roles. Grant DEPLOY_SERVICE_USER
   the Terraform and PROD roles. Finish object privileges from the table above.
4. Replace account/user names in both templates and the manifest. Retain the
   monorepo layout or change every working-directory and script path.
5. Create the GitHub environment `production` and configure required reviewers.
   Verify that your repository/plan supports this protection: the YAML environment
   name alone does not require approval.
6. Open an internal PR and inspect `dev-plans`. Fork PRs are skipped. After merge,
   inspect `prod-plans` and approve deployment when appropriate.

The merge workflow checks out its triggering commit, applies the saved
Terraform plan, runs native stream SQL, then deploys DCM. Artifacts are retained
for seven days; they can contain sensitive configuration, so restrict access.
The temporary key is removed after each job. Concurrency prevents overlapping
runs but does not guarantee every intermediate pending merge will deploy.
DCM compares the definitions to live state again at deployment; its earlier
plan is review evidence, not an executable saved plan.

The final timestamp query is an observation, not a freshness assertion. Add a
threshold appropriate to your data schedule if stale data must fail the run.
See `VALIDATION.md` for this revision's checks and limitations.
