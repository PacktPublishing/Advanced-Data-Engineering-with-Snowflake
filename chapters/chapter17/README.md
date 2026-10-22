# Chapter 17 companion materials

These files accompany *Data Sharing & Marketplace Strategies*. All input data
is synthetic. Use separate provider and consumer accounts in the same region
for the core exercises. Stop on any error. Do not use Run All for expected-failure
checks, revocation, publication, or teardown. Existing lab objects require review.

| Stage | Account | File | Chapter section | Expected evidence |
|---|---|---|---|---|
| Provider setup | Provider | chapter17_0_provider_setup.sql | 1.2 | Four private rows |
| Product | Provider | chapter17_1_product.sql | 1.2 | Two USD rows, total 250, no duplicates |
| Identity | Both | chapter17_2_identity.sql | 2.2 | Recorded account IDs and region |
| Share | Provider | chapter17_2_provider_share.sql | 2.2 | Only intended grants |
| Onboard | Provider | chapter17_2_provider_onboard.sql | 2.2 | Intended recipient only |
| Share audit with CoCo | Provider | chapter17_2_coco_share_audit.md | 2.2 | Four grants, no private-table grant, one consumer |
| Consumer setup | Consumer | chapter17_0_consumer_setup.sql | 2.3 | Role and warehouse |
| Import | Consumer | chapter17_2_consumer_import.sql | 2.3 | Two merchant-101 rows |
| Negative checks | Consumer | chapter17_2_consumer_negative.sql | 2.3 | Hidden rows and denied column/table |
| Revoke | Provider | chapter17_2_provider_revoke.sql | 2.3 | Recipient removed |
| Verify revocation | Consumer | chapter17_2_consumer_revocation_check.sql | 2.3 | Fresh query denied |
| Private listing | Provider | chapter17_2_private_listing.sql | 2.4 | Dedicated share, published listing |
| Get private listing | Consumer | chapter17_2_consumer_listing.sql | 2.4 | Two USD rows, total 250 |
| Marketplace draft share | Provider | chapter17_3_listing_preparation.sql | 3.1 | Dedicated synthetic share |
| Local internal access | Provider | chapter17_4_internal_mesh.sql | 4.1 | Two rows under limited role |
| Organizational listing | Provider | chapter17_4_org_listing.sql | 4.2 | Dedicated share, published internal listing |
| Discovery-only role and get | Consumer | chapter17_4_org_listing_consumer.sql | 4.2 | Two rows for SHARE_READER, denial for LISTING_BROWSER |
| Clean room fixtures | Both | chapter17_5_cleanroom_fixture.sql | 5.2 | 60 distinct hashes; small fixture 5 |
| Clean room workflow | Both | cleanroom_coco_runbook.md | 5.2, 5.3 | Overlap 20, denials, suppression |
| Clean room status | Both | chapter17_5_cleanroom_status.sql | 5.2 | Joined status |

`product_contract.yaml` holds the lab scope and marks the proposed scheduled
service commitments as unimplemented. `product_inventory.csv` starts with
NOT_RUN evidence fields. Replace them only after observing the corresponding
query results. `chapter17_static_checks.py` verifies local fixtures and the
alignment between this folder and the chapter markdown.

## Prerequisites by exercise

- Sections 1.2, 2.2, 2.3, 2.4, and 4.1: two accounts in the same region.
- Section 4.2: a second account in the provider's organization (ORGADMIN can
  create it with CREATE ACCOUNT in a paid organization, not in a trial) holding SHARE_READER and CONSUMER_WH from
  chapter17_0_consumer_setup.sql, plus CREATE ORGANIZATION LISTING in the
  provider account.
- Section 3.1: a full account with an approved provider profile and accepted
  provider terms. The draft is never submitted.
- Sections 5.2 and 5.3: two Enterprise Edition or higher accounts with the Data
  Clean Rooms environment installed and SAMOOHA_APP_ROLE available.

## Listings

Each listing gets its own share, because one share backs one listing:
PARTNER_LISTING_SHARE for the private listing (2.4), MARKETPLACE_LISTING_SHARE for the
Marketplace draft (3.1), and INTERNAL_LISTING_SHARE for the organizational
listing (4.2). MERCHANT_SHARE stays a direct share.

The private and organizational listings are created with SQL (CREATE EXTERNAL
LISTING and CREATE ORGANIZATION LISTING) and acquired with CREATE DATABASE ...
FROM LISTING, so the consumer never needs Snowsight for them. OFFLINE listing
terms mean no acceptance step. The Marketplace draft is a Snowsight exercise in
Provider Studio and stops at the draft; no file here submits or publishes it.

Manifest references:

- https://docs.snowflake.com/en/progaccess/listing-manifest-reference
- https://docs.snowflake.com/en/user-guide/collaboration/listings/organizational/org-listing-manifest-reference

## Cleanup

Remove listing access and retire the test listings first (DROP LISTING or
Provider Studio), reviewing their existing-consumer behavior. Complete the clean
room teardown and retire its registry entries before dropping fixture objects.
Provider cleanup may then drop MERCHANT_SHARE, PARTNER_LISTING_SHARE,
MARKETPLACE_LISTING_SHARE, INTERNAL_LISTING_SHARE, PRODUCT_DB, SOURCE_DB, and the
lab-owned warehouses and INTERNAL_ANALYST role. Consumer cleanup may drop
PARTNER_DB, PARTNER_LISTING_DB, INTERNAL_PRODUCT_DB, CONSUMER_WH, SHARE_READER,
and LISTING_BROWSER. Only remove objects created for this lab and inspect
dependencies first. Do not revoke SYSADMIN's CREATE SHARE privilege if it
predated this exercise or other workloads require it.

## Companion notes

- Private and organizational listing flows use SQL scripts you can rerun; consumer
  discovery finds listings by **title** when no listing name is visible.
- `chapter17_4_org_listing.sql` requires a `locations` block in the listing
  manifest. The manifest omits `organization_profile` (optional; defaults to
  INTERNAL).
- `chapter17_4_org_listing_consumer.sql` uses SHOW AVAILABLE LISTINGS columns as
  documented in the script headers (uniform listing locator, `discover_only`).

## Validation status

On 2026-10-07 the provider product checks (section 1.2), the MERCHANT_SHARE grants
(2.2), the post-revocation refusal (2.3), and the private listing (2.4) were checked
or executed in Snowflake with a consumer in another organization. The Marketplace
draft (3.1) stops at Create listing until the provider profile is submitted.
Its Provider Studio steps (Create listing, Snowflake Marketplace, Secure share,
Free, sample-query validation, and the preview) were cross-checked on 2026-10-10
against the records of a published Marketplace listing, not executed in the lab
account.

Section 4.2 (chapter17_4_org_listing.sql and chapter17_4_org_listing_consumer.sql)
was executed on 2026-10-05 between two accounts in one organization: the listing
published, SHARE_READER read two rows through the database and through the
uniform listing locator, and LISTING_BROWSER was refused both ways.

Documentation reviewed October 2026. Local checks cover fixture arithmetic,
source/snippet identity, and editorial structure. Apart from sections 1.2 to 2.4 and 4.2, the SQL, two-account access
flow, listings, and CoCo-generated clean room collaboration have not been
executed in Snowflake. No listing has been submitted to the Marketplace.
Expected results in the chapter are acceptance criteria, not observed output.
