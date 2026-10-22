# Chapter 17 share audit with CoCo

Run this after `chapter17_2_provider_share.sql` and `chapter17_2_provider_onboard.sql`,
from a `cortex` session whose connection points at the provider account and whose
role can read share metadata but holds no grant on `SOURCE_DB.PRIVATE`. Start the
session in the `chapters/chapter17` folder so `product_contract.yaml` is readable.
Nothing here changes a grant. If CoCo proposes a wider grant, decline it.

```text
Read the grants of MERCHANT_SHARE with SHOW GRANTS TO SHARE and
compare them with product_contract.yaml in this folder. Use metadata
only. The contract allows four grants: usage on PRODUCT_DB, usage on
PRODUCT_DB.PRODUCT, reference usage on SOURCE_DB, and select on
PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1, plus one consumer account.
Report every grant or account outside that list. Change nothing.
```

Expected: a comparison that lists the four grants, reports no grant on
`SOURCE_DB.PRIVATE.MERCHANT_DAILY`, and names the one onboarded consumer. Any
extra line is a finding to investigate before the share goes further. Keep the
transcript with the `SHOW GRANTS TO SHARE` output as release evidence.

The clean room prompts live in `cleanroom_coco_runbook.md`.
