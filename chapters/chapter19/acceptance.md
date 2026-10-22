# Chapter 19 acceptance record

Status: SQL scripts ready for live validation; record results below before treating REST, CoWork, and BI client exercises as complete.
Record the date, account region, edition, role, client version, connector/driver version, and
warehouse settings for each executed exercise. Use no passwords, tokens, or private keys.

| Check | Expected | Observed / query ID / date |
|---|---|---|
| Setup fixture | 12 attempts, 7 approvals, 675.00 USD | Pending |
| Reporting view grain | Four merchant-day rows, no duplicate key | Pending |
| All rows | 12 attempts, 7 approvals, 675.00 USD, 58.33% | Pending |
| Serving warehouse | Statement timeout 120, queued timeout 60, auto-suspend 300 | Pending |
| Published report build | Client build, connector version, connection mode | Pending |
| M100 | 8 attempts, 5 approvals, 375.00 USD, 62.50% | Pending |
| M200 | 4 attempts, 2 approvals, 300.00 USD, 50.00% | Pending |
| September 2 | 6 attempts, 3 approvals, 300.00 USD, 50.00% | Pending |
| Published BI interaction | Same totals; captured query and identity | Pending |
| Cache experiment | Client / persisted result / warehouse state recorded separately | Pending |
| Benchmark skew | M0001, M0002, M0003 at about 2.4M, 1.2M, 0.8M rows | Pending |
| Interactive reconciliation | Zero differences in both directions | Pending |
| Load test, interactive | p50, p95, requests/second, failures, samples over 5 s | Pending |
| Load test, standard | Same measures on BI_WH over the benchmark table | Pending |
| Suspension | Interactive warehouse and refreshed table both suspended | Pending |
| Native App release | V1 registered, DEFAULT channel directive V1 patch 0 | Pending |
| Native App SQL and UI | Four rows, 675.00 USD, 58.33%; M100 375.00 and 62.50% | Pending |
| Agent aggregate and grouping | Match SQL verification | Pending |
| Agent as BI_READER without base-table grants | Same answers; no PAYMENT_ATTEMPTS access | Pending |
| Unknown settlement metric | Clarification or explicit missing data | Pending |
| Restricted agent caller | No protected rows or invented totals | Pending |
| Chat client, BI_READER token | Streamed answer, printed SQL, follow-up "only M100" returns 375.00 | Pending |
| Chat client, NO_DATA_READER token | Error event or refusal; no totals | Pending |
| CoWork volume comparison | -75.00 USD (-20%) | Pending |
| Merchant contributions | M100 +25, M200 -100; sum -75 | Pending |
| Rate comparison | -16.6667 percentage points | Pending |
| Causal question | No invented outage, issuer issue, or fraud-rule cause | Pending |
| Artifact refresh | Fixed dates retained; permissions applied | Pending |
| User skill (chat-created or uploaded) | Same acceptance results on re-invocation | Pending |
| Optional automation | Correct time zone/identity; run checked; then paused | Pending |

For the load test, record dataset size and skew, concurrency, warm-up and measurement
duration, and cache conditions. The 12-row fixture is for correctness only. A cold startup
and a warmed sustained run are separate experiments.
