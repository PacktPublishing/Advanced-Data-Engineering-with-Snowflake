# Chapter 16 optional warehouse reference

These are reference definitions, not part of core setup. All three definitions
were created, inspected, and dropped on Snowflake 10.33.101 in AWS_US_WEST_2 on
2026-09-21. Gen2 and memory candidates remained suspended; no performance or
cost benchmark was run. Adaptive SHOW output reported `Medium` and multiplier 2.
Run only the candidate you intend to benchmark. `SYSADMIN` owns each candidate.
All names are literal lab names; no substitutions are required.

## Standard Gen2 candidate

Use in a supported region. Record effective generation, size, Query Acceleration
Service settings, credit rate, query identifiers, input size, and concurrency.

```sql
USE ROLE SYSADMIN;
CREATE WAREHOUSE GEN2_WH
  WAREHOUSE_TYPE = 'STANDARD'
  GENERATION = '2'
  WAREHOUSE_SIZE = 'SMALL'
  ENABLE_QUERY_ACCELERATION = FALSE
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
```

## Memory candidate

Use only when the procedure requires the selected memory capacity. Startup can
take longer than for standard warehouses.

```sql
USE ROLE SYSADMIN;
CREATE WAREHOUSE MEMORY_WH
  WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
  WAREHOUSE_SIZE = 'MEDIUM'
  RESOURCE_CONSTRAINT = 'MEMORY_16X'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
```

## Adaptive candidate

Requires Enterprise or higher and regional support. Do not add conventional
size, auto-suspend, or cluster-count parameters.

```sql
USE ROLE SYSADMIN;
CREATE ADAPTIVE WAREHOUSE ADAPTIVE_WH
  MAX_QUERY_PERFORMANCE_LEVEL = MEDIUM
  QUERY_THROUGHPUT_MULTIPLIER = 2;
SHOW WAREHOUSES LIKE 'ADAPTIVE_WH';
```

## Benchmark and cleanup

Grant only the benchmark role USAGE on the candidate, attach an appropriate
resource monitor, and run the same reviewed workload under the same conditions.
Record result equality, accepted rows, elapsed time, concurrency, and measured
credits before choosing the candidate. Disable persisted result reuse for a
compute benchmark with `ALTER SESSION SET USE_CACHED_RESULT = FALSE`, then
restore the session setting. Treat cold and warm warehouse-cache runs separately.
Use query tags to identify each run. Do not label an illustrative cost as observed.

Drop only candidates created for this exercise, after collecting their results:

```sql
USE ROLE SYSADMIN;
DROP WAREHOUSE IF EXISTS GEN2_WH;
DROP WAREHOUSE IF EXISTS MEMORY_WH;
DROP WAREHOUSE IF EXISTS ADAPTIVE_WH;
```
