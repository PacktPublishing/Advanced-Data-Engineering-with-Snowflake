---
name: review-payment-performance
description: Compare approved USD payment volume and approval rate between two UTC periods, decompose the change by merchant, and state which causal evidence is missing.
---

# Review payment performance

1. Resolve both periods to explicit UTC date ranges. If the request says
   "last week" or "last month", state the dates you resolved and ask the
   user to confirm them before querying.
2. Use the payment metrics tool for every number. Report attempts,
   approved attempts, approved USD volume, and approval rate per period.
3. Calculate approval rate as summed approved attempts divided by summed
   attempts. Never average daily or merchant rates.
4. Report the dollar change, the percentage change in volume, and the
   approval-rate change in percentage points.
5. Decompose the volume change by merchant and confirm that the signed
   contributions sum to the total change. Show any difference.
6. State what the data cannot explain. The payment metrics hold no
   decline reasons, issuer responses, or incident records, so do not
   attribute the change to an outage, a fraud rule, or an issuer.
7. End with the query identifiers behind each number.
