# TechFlow isolation contract (worked example)

Chapter 18 fills in the companion template for TechFlow's three parties. Each row
names the chapter exercise that tests it.

| Clause | Payments | Risk | Partner |
|---|---|---|---|
| Data protected | PAYMENTS_DB; WORK private, consumers read PUBLISHED only | RISK_DB | Its own account and data |
| Administrator | PAYMENTS_ADMIN, trusted with its own data | Central SYSADMIN (consumer only) | Its own administrators |
| Delegation model | Delegated grants, WORK grants audited | Central | Separate account |
| Contention tolerated | Settlement finishes by 06:00; no other team runs on PAYMENTS_WH | Interactive, queue no longer than 60 seconds | Own compute |
| Recovery scope | Settlement tables (Chapter 16 restore drill) | Review queue | Its own plan |
| Payer | CC_PAYMENTS, plus 60% of the shared reporting warehouse | CC_RISK, plus 40% of the shared reporting warehouse | CC_PARTNER, from the per-account metering query, because its credits land on TechFlow's organization invoice |
| Spending limit | 20-credit notify-only budget, owned by COST_ADMIN | Shared warehouse share | Its own budget in its account |
| Account-split trigger | Regulator requires central approval of every grant (central schemas) or its own administrators | Own administrators or region | Already split |
| Tested by | Denial tests, publication, grant audit, budget | Denial tests, warehouse denial, concurrency settings | Topology review, per-account metering |
