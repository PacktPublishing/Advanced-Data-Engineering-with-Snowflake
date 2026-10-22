# Isolation contract template

Chapter 18, section "Defining the isolation contract". One row per party (team or
tenant). Every clause names the exercise or check that proves it, so the release
checklist (Table 18.5 in the chapter) can point back to it.

| Clause | Question to answer | Evidence that proves it |
|---|---|---|
| Party | Team or tenant, and who speaks for it | Registry entry |
| Data protected | Which databases and schemas it owns or must keep apart | Denial tests |
| Administrator | Who grants access to its data, and is that person trusted to do so | Ownership and audit query |
| Delegation model | Central grants, delegated grants with audit, or separate account | Decision record |
| Contention tolerated | Deadlines, queue time it accepts, workloads it must not wait behind | Warehouse settings and contention query |
| Recovery scope | What must be restorable, to where, and in what time | Recovery test |
| Payer | Cost center, and how shared compute is split | Ownership map, allocation reconciliation |
| Spending limit | Monthly allowance and who may change it | Budget owner and linked resources |
| Account-split trigger | The requirement that would move it to its own account | Topology review |
