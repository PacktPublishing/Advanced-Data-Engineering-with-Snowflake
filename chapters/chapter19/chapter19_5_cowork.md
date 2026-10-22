# CoWork workflow (section 5)

Requires the common setup, `chapter19_1_bi.sql`, and the agent worksheet. Interactive tables and Native Apps are optional.
Documentation checked October 2026; UI and model outputs are not live-tested.

## 5.1 Investigation prompts

1. Open CoWork as the reporting identity and select PAYMENT_ANALYST. Use the existing account visibility configuration. Do not create or replace the account-wide Snowflake Intelligence object just for this lab.
2. Ask: Compare approved USD volume on September 2, 2026 with September 1, 2026 using UTC dates. Show totals, dollar change, and percentage change. Use the payment metrics tool.
3. Ask: Decompose that change by merchant and reconcile the signed contributions.
4. Ask: Compare attempt counts and approval rates. Report the approval-rate change in percentage points.
5. Ask: What caused the lower approval count? State what evidence is absent.

## 5.2 Artifact and user skill

6. Save the returned comparison table or chart as an artifact. Refresh and verify the same fixed dates. Do not share a conversation snapshot as if it were a live chart.
7. Add the user skill. Either ask CoWork to create it from the instructions in `cowork_skill/review-payment-performance/SKILL.md` (needs the code execution tool), or upload the `review-payment-performance` folder under Capabilities > Skills (no code execution needed). User skills are a preview feature as of October 2026.
8. Invoke it with `/review-payment-performance September 1 and September 2, 2026` and compare the output with the expected values below.

## 5.3 Automation

9. Optionally create a weekly automation for your own verified email. Inspect its time zone, next run, role, and warehouse. Check the first run, then pause the lab automation as its own action. No automation is created by any repository script.
10. Automations rely on `EXECUTE AGENT TASK`, which Snowflake grants to PUBLIC by default. An administrator who wants to restrict scheduling revokes it from PUBLIC and grants it to selected roles.

Expected: overall volume falls 375.00 to 300.00; change -75.00 (-20%). M100 rises 175.00 to 200.00 (+25); M200 falls 200.00 to 100.00 (-100). Attempts remain six per day; approvals fall four to three; approval rate falls 66.6667% to 50% (-16.6667 percentage points). The fixture contains no decline reasons or incident evidence.

For recurring business use, substitute a precisely defined rolling period after upstream completion. The source fixture itself does not advance or refresh automatically.
