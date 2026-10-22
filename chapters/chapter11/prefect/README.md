# How To Run the TechFlow Transform with Prefect

This companion implements manuscript blocks 4–6 as separate setup, flow, and
deployment files. It runs the cleanse procedure before refreshing daily
merchant revenue and records both operations as Prefect tasks.

## Prerequisites

- Python 3.11
- Prefect 3 and `prefect-snowflake` from `requirements.txt`
- A Prefect Cloud workspace or self-hosted Prefect server
- A Snowflake service user configured for key-pair authentication
- An existing Prefect work pool named `techflow-pool`, or another validated
  name supplied through `PREFECT_WORK_POOL_NAME`
- Human review of the data-modifying SQL in `transform.py` before running it

## Steps

1. Install the dependencies in an isolated Python environment.

   ```bash
   pip install -r requirements.txt
   ```

2. Supply the Snowflake configuration through environment variables. Keep the
   private key in your secret manager in deployed environments. For local use,
   the following reads a fixed, user-owned key file into the environment; the
   Python setup script never accepts a file path.

   ```bash
   export SNOWFLAKE_ACCOUNT="<organization-account>"
   export SNOWFLAKE_USER="<service-user>"
   export SNOWFLAKE_ROLE="<orchestrator-role>"
   export SNOWFLAKE_PRIVATE_KEY="$(< "$HOME/.snowflake/keys/techflow.p8")"
   # Set only when the key is encrypted:
   export SNOWFLAKE_PRIVATE_KEY_PASSPHRASE="<secret>"
   ```

3. Save the credentials and connector blocks.

   ```bash
   python setup_blocks.py
   ```

   The connector is saved as `techflow-snowflake` with autocommit disabled.
   Each task explicitly commits after success and rolls back after failure.

4. Run the flow locally after reviewing its SQL.

   ```bash
   python transform.py
   ```

   `wait_for=[cleanse]` is a control dependency: the aggregate task receives no
   cleanse data, but Prefect will not start it unless cleanse succeeds.
   `aggregate.result()` resolves the terminal future so an aggregate failure
   also fails the flow run.

5. Pin and register the deployment. `TECHFLOW_CODE_COMMIT_SHA` must be the full
   40-hexadecimal commit ID already pushed to the repository.

   ```bash
   export TECHFLOW_CODE_COMMIT_SHA="$(git rev-parse HEAD)"
   export PREFECT_WORK_POOL_NAME="techflow-pool"
   export PREFECT_WORK_POOL_KIND="hybrid"
   python deploy.py
   ```

   The deployment runs at `02:00 UTC` and checks out that exact commit rather
   than a moving branch.

6. Match the runtime to the existing work-pool type.

   - **Hybrid**: run a Prefect worker in infrastructure that can reach
     Snowflake, for example `prefect worker start --pool techflow-pool`.
   - **Push**: Prefect submits runs directly to the configured serverless
     provider; do not run a worker.
   - **Managed**: Prefect runs the flow on Prefect-managed infrastructure; do
     not run a worker.

   `PREFECT_WORK_POOL_KIND` documents the expected behavior and controls the
   final operator message. It does not create or change the server-side pool.

## Expected Results

- Prefect contains a credentials block and a `techflow-snowflake` connector.
- A local flow run shows cleanse completing before aggregate starts.
- Prefect contains `techflow-transform/techflow-nightly` with a `0 2 * * *`
  schedule in the `UTC` timezone.
- The deployment version and Git checkout both use the validated commit SHA.

## Troubleshooting

- **Private key rejected**: provide one complete PEM key, including matching
  `BEGIN` and `END` lines. Do not provide a path.
- **Block already exists**: review the new values, then run
  `python setup_blocks.py --overwrite`.
- **Deployment rejects the SHA**: use the full output of `git rev-parse HEAD`;
  abbreviated SHAs are intentionally rejected.
- **Scheduled hybrid run stays late**: start a worker that polls the deployment
  work pool. Push and managed pools do not use that worker.
- **Aggregate did not run**: inspect the cleanse task. The explicit `wait_for`
  dependency blocks the aggregate after an upstream failure.

## Additional Information

No Docker Compose file is included. Prefect Cloud or a locally configured
Prefect server provides everything this small example needs, so a second
container stack would add setup without changing the flow. Importing any Python
module in this folder performs no SQL, block save, deployment, or network call.
