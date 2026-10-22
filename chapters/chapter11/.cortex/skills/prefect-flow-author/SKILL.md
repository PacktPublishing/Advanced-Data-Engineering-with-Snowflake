---
name: prefect-flow-author
description: Author Prefect 3 flows, Snowflake connector-block setup, and immutable deployments following Chapter 11's secure TechFlow patterns.
---

# prefect-flow-author

A CoCo skill for turning reviewed Snowflake operations into Prefect 3 tasks,
flows, and deployments. It keeps runtime code, one-time block setup, and
deployment registration separate so every file is safe to import and easy to
test without contacting Prefect or Snowflake.

## When to use

Use this skill when asked to create or revise a Prefect flow that orchestrates
Snowflake SQL, configures a `SnowflakeConnector`, or registers a deployment.
Do not use it to execute SQL, save blocks, register deployments, create work
pools, install packages, or start workers.

## Required file split

1. Put tasks, flows, and source-controlled SQL in `prefect/transform.py`.
2. Put environment validation and block creation in
   `prefect/setup_blocks.py`.
3. Put Git source, schedule, and work-pool deployment logic in
   `prefect/deploy.py`.
4. Put Prefect 3 and `prefect-snowflake` constraints in
   `prefect/requirements.txt`.
5. Keep all network and state-changing calls behind functions invoked only
   from an `if __name__ == "__main__"` guard.

## Flow rules

1. **Preserve reviewed SQL.** Keep the manuscript's statement text and object
   names unchanged. Never build SQL from flow parameters or external input.
2. **Load blocks inside tasks.** Use
   `with SnowflakeConnector.load(block_name) as connector:` so every task owns
   and closes its connection.
3. **Make transactions explicit.** Open the underlying connection with
   `autocommit=False`, commit only after `connector.execute` succeeds, and
   roll back before re-raising an execution failure. Save the credentials
   block with `autocommit=False` too.
4. **Express control dependencies.** When task B consumes no value from task A
   but must run after it, submit B with `wait_for=[a_future]`. Do not rely on
   source order alone.
5. **Resolve the terminal task.** Assign the last submitted task to a named
   future and call `.result()` before the flow returns. This propagates a
   terminal task failure to the flow run.
6. **Keep retries at task scope.** Follow the chapter default of two retries
   with a 30-second delay unless the manuscript explicitly changes it.

## Key-pair block rules

1. Read account, service user, role, and private-key PEM from environment or a
   reviewed configuration provider. Never hardcode credentials.
2. Do not accept an arbitrary private-key file path. Prefer PEM content from a
   secret-injected environment variable, validate its size and matching PEM
   boundaries, and mark secret-bearing fields as non-repr.
3. Validate account names, unquoted Snowflake identifiers, and Prefect block
   names before constructing blocks.
4. Set `authenticator="snowflake_jwt"` and use
   `private_key_passphrase`, never a Snowflake password.
5. Saving blocks is an explicit setup action. Importing the setup module must
   only define validation and save functions.

## Deployment rules

1. Use an HTTPS repository URL fixed in reviewed source. Do not accept an
   arbitrary target URL from flow or environment input.
2. Pin `GitRepository` with `commit_sha`. Accept only a full SHA matching
   `^[0-9a-fA-F]{40}$`; reject branch names and abbreviated SHAs.
3. Use a `Cron` schedule object with an explicit IANA timezone. A bare cron
   string is incomplete because its wall-clock timezone is ambiguous.
4. Treat the work pool as pre-existing. Validate its name but do not create or
   mutate it from the deployment script.
5. Distinguish pool behavior in docs and operator output:
   - hybrid pools require a user-operated worker;
   - push pools submit to configured serverless infrastructure without one;
   - managed pools run on Prefect infrastructure without one.
6. Do not claim that an informational pool-kind setting verifies the actual
   server-side pool type.

## Static verification checklist

Before presenting generated files for review:

1. Compile or parse every Python file without importing Prefect.
2. Confirm no top-level call saves a block, loads a block, deploys a flow,
   starts a worker, opens a connection, or executes SQL.
3. Confirm the terminal future calls `.result()`.
4. Confirm every control-only edge uses `wait_for`.
5. Confirm both block setup and task execution disable autocommit and the task
   has explicit commit and rollback paths.
6. Confirm deployment validation requires all 40 hexadecimal SHA characters
   and the cron schedule names its timezone.
7. Show all data-modifying SQL to a human for review. Never run it as part of
   verification.

## Limitations

This skill authors files for review only. It does not prove that a Prefect
server, block, work pool, worker, Git revision, Snowflake role, or target object
exists. Those checks require separately approved runtime actions.
