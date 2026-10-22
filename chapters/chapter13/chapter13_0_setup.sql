-- =============================================================================
-- Chapter 13: Snowflake Cortex AI for Data Engineering — Shared Setup
-- Run this ONCE, before any chapter13_N_* section script.
--
-- File map: chapter13_1 (Section 2, Cortex AI Functions),
--   chapter13_2 + chapter13_2_search_client.py (Section 3, Cortex Search),
--   chapter13_3_analyst_api.py (Section 4, Cortex Analyst REST API),
--   chapter13_4 + chapter13_4_agent_run.py (Section 5, Agents/CoWork/Guardrails),
--   chapter13_teardown.sql (removes everything this chapter creates).
--   Sections 2 and 3 need only this setup. Sections 4 and 5 also need the
--   Chapter 12 semantic view (see the PREREQUISITE CHECK block below).
--
-- Prerequisites:
--   - setup/snowflake_setup.sql (BOOK_WH warehouse).
--   - For sections 4-5: chapter12_0_setup.sql .. chapter12_2_create_view.sql,
--     so gold_db.semantic.techflow_revenue exists.
--   - Edition: Standard+ for everything except Cortex AI Guardrails
--     (chapter13_4), which needs Enterprise+ and cross-region inference.
--   - Cortex AI Functions availability varies by region; enable cross-region
--     inference (CORTEX_ENABLED_CROSS_REGION) if a function reports an
--     unavailable model. Tested August 2026; check current function GA status
--     in the Snowflake docs, this surface changes monthly.
--
-- Placeholders: none in this file. Standard book objects (gold_db, BOOK_WH)
-- are used literally.
-- Role convention: USERADMIN creates roles, SYSADMIN creates objects,
-- ACCOUNTADMIN only where an account-level privilege requires it (noted).
-- =============================================================================

-- ACCOUNTADMIN required: granting a SNOWFLAKE database role.
USE ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;
-- Needed for the EXECUTE TASK smoke test at the end of chapter13_1.
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;
-- Narrower alternative for shared accounts (see chapter Section 1.3):
-- GRANT DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

-- Earlier chapters create these too; IF NOT EXISTS keeps re-runs safe.
CREATE WAREHOUSE IF NOT EXISTS BOOK_WH
    WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;
CREATE DATABASE IF NOT EXISTS gold_db
    COMMENT = 'Gold layer: Kimball facts and dimensions for analytics';

USE WAREHOUSE BOOK_WH;

-- Chapter-owned schema: everything Chapter 13 creates lives here, so
-- teardown never touches another chapter's objects.
CREATE SCHEMA IF NOT EXISTS gold_db.support
    COMMENT = 'Chapter 13: TechFlow support tickets and Cortex objects';

USE DATABASE gold_db;
USE SCHEMA support;

-- -----------------------------------------------------------------------------
-- PREREQUISITE CHECK block (sections 4-5 only) — commented because it errors
-- by design when Chapter 12 has not been run. Uncomment and run before
-- chapter13_3_analyst_api.py or chapter13_4_agent.sql. If it errors, run the
-- Chapter 12 companion scripts first (chapter12_0 through chapter12_2).
-- -----------------------------------------------------------------------------
-- DESC SEMANTIC VIEW gold_db.semantic.techflow_revenue;

-- -----------------------------------------------------------------------------
-- Ticket fixture: 40 tickets, June 2026, five merchant categories drawn from
-- the revenue-side vocabulary in gold_db.merchants.dim_merchants (travel,
-- groceries, retail, dining, streaming), so agent answers join cleanly.
--   - 28 RESOLVED (these become the Section 3 knowledge base), 12 OPEN.
--   - 12 rows carry expected_category hand labels for the Section 2 scoring
--     query; the other 28 leave it NULL.
--   - 3 OPEN rows contain explicit chargeback/legal threats (Section 2.3
--     expects three).
--   - Several bodies and resolutions carry deliberate PII (names, emails,
--     card fragments) so the Section 3.1 AI_REDACT pass has work to do.
-- Kept small on purpose: every AI function call bills per token.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold_db.support.support_tickets (
    ticket_id         VARCHAR NOT NULL,
    txn_id            VARCHAR,
    merchant_category VARCHAR,
    channel           VARCHAR,
    opened_at         TIMESTAMP_NTZ,
    status            VARCHAR,
    expected_category VARCHAR,
    body              VARCHAR,
    resolution        VARCHAR
);

INSERT INTO gold_db.support.support_tickets VALUES
('TKT-CH13-001', 'TXN-88214', 'travel', 'email', '2026-06-02 09:14:00', 'RESOLVED', 'billing dispute',
 'I was charged twice for the same booking and the airline confirmed only one ticket exists. Reverse the duplicate or I will dispute it with my bank.',
 'Confirmed duplicate capture. Reversed the second charge and refunded $482.19 within 3 business days.'),
('TKT-CH13-002', NULL, 'groceries', 'chat', '2026-06-02 11:40:00', 'OPEN', NULL,
 'The app says my card was declined but my bank shows a pending charge. Which one is real?',
 NULL),
('TKT-CH13-003', 'TXN-88310', 'retail', 'email', '2026-06-03 08:05:00', 'RESOLVED', NULL,
 'My name is Sarah Mitchell and I bought a laptop on June 1. The charge shows $1,299.00 but the receipt says $1,199.00. Please fix the $100 difference.',
 'Price adjustment approved. Refunded $100.00 to the card ending 4412. Receipt re-sent to s.mitchell@example.com.'),
('TKT-CH13-004', 'TXN-88342', 'groceries', 'phone', '2026-06-03 10:22:00', 'RESOLVED', 'failed payment',
 'My weekly grocery order failed at checkout three times yesterday evening. The card works everywhere else.',
 'Issuer was declining on a velocity rule after the third retry. Customer retried this morning and the payment captured normally.'),
('TKT-CH13-005', 'TXN-88377', 'travel', 'chat', '2026-06-04 14:31:00', 'RESOLVED', NULL,
 'Where is the refund for my cancelled hotel? The property confirmed the cancellation eight days ago.',
 'Refund of $356.40 was initiated on June 1 and settled June 5. Provided the ARN so the customer can trace it with their bank.'),
('TKT-CH13-006', NULL, 'retail', 'email', '2026-06-04 16:02:00', 'OPEN', NULL,
 'I cannot log in since the update. Password reset emails never arrive at my inbox, checked spam too.',
 NULL),
('TKT-CH13-007', 'TXN-88401', 'retail', 'email', '2026-06-05 09:47:00', 'RESOLVED', 'refund status',
 'I returned a monitor two weeks ago, tracking shows it delivered to your warehouse, and I still have no refund.',
 'Warehouse scan was missed. Processed the return manually and refunded $249.99 same day.'),
('TKT-CH13-008', 'TXN-88433', 'groceries', 'chat', '2026-06-05 12:19:00', 'RESOLVED', NULL,
 'I was charged $84.12 but my order total was $64.12. Contact me at j.alvarez@example.com.',
 'Substitution pricing error on two items. Refunded the $20.00 difference and flagged the store pricing feed.'),
('TKT-CH13-009', 'TXN-88450', 'travel', 'phone', '2026-06-06 10:03:00', 'OPEN', NULL,
 'Charged for seat selection twice on the same flight. If this is not fixed this week I am filing a chargeback with my card issuer.',
 NULL),
('TKT-CH13-010', NULL, 'groceries', 'email', '2026-06-06 15:44:00', 'RESOLVED', 'account access',
 'My account is locked after too many login attempts. I need access before my scheduled delivery tomorrow.',
 'Verified identity, unlocked the account, and reset the failed-attempt counter. Advised enabling passkey login.'),
('TKT-CH13-011', 'TXN-88492', 'streaming', 'chat', '2026-06-09 09:12:00', 'RESOLVED', NULL,
 'Payment went through but my plan still shows inactive and playback is blocked.',
 'Webhook to the subscription system had failed. Replayed the event and the plan activated the same day.'),
('TKT-CH13-012', 'TXN-88521', 'travel', 'email', '2026-06-09 11:58:00', 'RESOLVED', NULL,
 'The currency on my statement is wrong. I paid in CAD but was billed in USD with a worse rate.',
 'Dynamic currency conversion was applied at the kiosk. Refunded the $18.73 conversion spread as a goodwill credit and documented how to decline DCC.'),
('TKT-CH13-013', NULL, 'retail', 'chat', '2026-06-10 13:27:00', 'RESOLVED', 'feature question',
 'How do I set a spending alert for my kid''s account? I looked in settings and cannot find it.',
 'Walked through Family Controls, then Alerts, then New spending alert. Sent the help-center article link.'),
('TKT-CH13-014', 'TXN-88544', 'dining', 'phone', '2026-06-10 17:36:00', 'OPEN', NULL,
 'Second time this month my payment failed on delivery day and I lost my slot. What is going on?',
 NULL),
('TKT-CH13-015', 'TXN-88562', 'travel', 'email', '2026-06-11 08:41:00', 'RESOLVED', NULL,
 'Refund for flight cancelled by the airline has not arrived after 12 days. Booking reference RJK4LM.',
 'Airline released the funds June 9. Refund of $612.00 settled June 11. Shared the settlement reference.'),
('TKT-CH13-016', 'TXN-88579', 'streaming', 'email', '2026-06-11 10:15:00', 'RESOLVED', 'billing dispute',
 'There is a $59.99 subscription charge I never signed up for. This is Marcus Chen, account under m.chen@example.com.',
 'Trial had auto-converted. Cancelled the subscription, refunded $59.99, and confirmed no further renewals.'),
('TKT-CH13-017', NULL, 'dining', 'chat', '2026-06-12 09:55:00', 'RESOLVED', NULL,
 'App crashes every time I open order history on Android 16.',
 'Known defect in 8.2.0. Advised updating to 8.2.1 where the crash is fixed. Confirmed resolved with the customer.'),
('TKT-CH13-018', 'TXN-88603', 'travel', 'chat', '2026-06-12 14:08:00', 'OPEN', NULL,
 'Hotel charged a deposit that was supposed to be released at checkout five days ago. Still holding $200.',
 NULL),
('TKT-CH13-019', 'TXN-88615', 'groceries', 'email', '2026-06-13 08:30:00', 'RESOLVED', 'failed payment',
 'Checkout keeps saying payment could not be processed, tried two cards, both fine elsewhere.',
 'Our fraud rule was blocking the delivery address mismatch. Verified the new address, allowlisted it, payment captured on retry.'),
('TKT-CH13-020', 'TXN-88637', 'retail', 'phone', '2026-06-13 11:47:00', 'RESOLVED', NULL,
 'Was billed for two keyboards, ordered one. Invoice INV-20260613-118 attached.',
 'Duplicate line item from a double-click at checkout. Refunded $89.00 and added a client-side double-submit guard ticket.'),
('TKT-CH13-021', 'TXN-88659', 'travel', 'email', '2026-06-16 09:02:00', 'RESOLVED', NULL,
 'I need an itemized receipt for my expense report, the email receipt only shows the total.',
 'Generated the itemized receipt from the merchant portal and emailed it. Showed where to self-serve under Trips, then Documents.'),
('TKT-CH13-022', 'TXN-88671', 'groceries', 'chat', '2026-06-16 15:23:00', 'RESOLVED', 'refund status',
 'Store said the refund for my returned items would take 5 days. It has been 9. Where is my money?',
 'Refund was initiated but stuck in a retry queue after an issuer timeout. Forced settlement, $47.62 arrived next morning.'),
('TKT-CH13-023', NULL, 'streaming', 'email', '2026-06-17 10:11:00', 'OPEN', NULL,
 'Two-factor codes go to my old phone number. I no longer have that number.',
 NULL),
('TKT-CH13-024', 'TXN-88702', 'travel', 'phone', '2026-06-17 13:59:00', 'RESOLVED', NULL,
 'Charged a foreign transaction fee on a domestic booking. The merchant is registered abroad apparently.',
 'Merchant of record is EU-based, fee is issuer-applied. Explained the mechanics and credited a $6.90 goodwill adjustment.'),
('TKT-CH13-025', NULL, 'travel', 'chat', '2026-06-18 09:34:00', 'RESOLVED', 'account access',
 'I changed my email and now I am locked out. Old email was p.novak@example.com, new one is on file with support.',
 'Re-verified identity against government ID, updated the login email, and cleared the lockout. Sessions on old devices revoked.'),
('TKT-CH13-026', 'TXN-88718', 'dining', 'email', '2026-06-18 12:20:00', 'OPEN', NULL,
 'You charged me for a cancelled order. Refund this today or my lawyer will be in touch.',
 NULL),
('TKT-CH13-027', 'TXN-88734', 'retail', 'chat', '2026-06-19 08:48:00', 'RESOLVED', NULL,
 'Trade-in credit of $180 was approved but never applied to my final invoice.',
 'Credit had expired between approval and checkout. Re-issued the credit, refunded $180.00 against the invoice, extended validity policy note filed.'),
('TKT-CH13-028', NULL, 'dining', 'phone', '2026-06-19 16:05:00', 'RESOLVED', 'feature question',
 'Can I split one payment across two cards for a large order?',
 'Explained split tender is available above $200: choose Pay, then Split payment, amounts editable per card.'),
('TKT-CH13-029', 'TXN-88756', 'travel', 'email', '2026-06-22 09:19:00', 'RESOLVED', NULL,
 'Duplicate charge for checked bags, gate agent swiped twice. Frequent flyer FF-2291083.',
 'Second swipe confirmed as duplicate. Reversed $70.00 and notified the airline''s ground-handling vendor.'),
('TKT-CH13-030', 'TXN-88771', 'streaming', 'chat', '2026-06-22 11:52:00', 'RESOLVED', NULL,
 'Payment shows completed but no order confirmation email after 4 hours.',
 'Confirmation email was queued behind a provider outage. Replayed the send; customer received it. Added a 15-minute SLA alert on confirmation lag.'),
('TKT-CH13-031', 'TXN-88790', 'groceries', 'email', '2026-06-23 10:28:00', 'RESOLVED', 'billing dispute',
 'Charged $312.44 for an order I never placed. I want this investigated now.',
 'Confirmed account takeover via credential stuffing. Reversed the charge in full, forced password reset, enrolled the account in passkeys.'),
('TKT-CH13-032', NULL, 'travel', 'chat', '2026-06-23 14:40:00', 'RESOLVED', NULL,
 'How do I add my partner as an authorized traveler so they can use the stored payment method?',
 'Directed to Account, then Shared travelers, explained the verification the partner completes, and the per-trip spending cap option.'),
('TKT-CH13-033', 'TXN-88805', 'retail', 'phone', '2026-06-24 09:03:00', 'OPEN', NULL,
 'Warranty refund approved on June 10, still nothing received. I am done waiting: issuing a chargeback through my bank tomorrow.',
 NULL),
('TKT-CH13-034', 'TXN-88819', 'travel', 'email', '2026-06-24 12:36:00', 'RESOLVED', 'failed payment',
 'Booking failed at payment but seats were held, then released. Card was charged then auto-refunded. Very confusing.',
 'Authorization succeeded but capture timed out, auto-reversal worked as designed. Rebooked the itinerary at the held fare and documented the timeout window.'),
('TKT-CH13-035', 'TXN-88831', 'dining', 'chat', '2026-06-25 08:57:00', 'RESOLVED', NULL,
 'Loyalty discount did not apply, paid full price on a 20 percent promo.',
 'Promo excluded delivery fees, which the checkout did not surface. Refunded the $12.30 difference and filed the UX gap.'),
('TKT-CH13-036', NULL, 'streaming', 'email', '2026-06-25 15:14:00', 'OPEN', NULL,
 'Cannot remove an old card from my wallet, delete button is greyed out.',
 NULL),
('TKT-CH13-037', 'TXN-88846', 'travel', 'phone', '2026-06-26 10:09:00', 'RESOLVED', NULL,
 'Charged twice for travel insurance on one booking.',
 'Insurance add-on double-fired in an A/B variant. Refunded $24.50, variant rolled back by the merchant.'),
('TKT-CH13-038', 'TXN-88860', 'dining', 'email', '2026-06-26 13:26:00', 'OPEN', NULL,
 'My refund for the June 14 cancelled order has not arrived. Bank says nothing is pending.',
 NULL),
('TKT-CH13-039', 'TXN-88874', 'streaming', 'chat', '2026-06-27 09:41:00', 'OPEN', NULL,
 'Declined at checkout with error PAY-4092 but I have plenty of balance.',
 NULL),
('TKT-CH13-040', NULL, 'travel', 'email', '2026-06-27 16:33:00', 'OPEN', NULL,
 'Please explain the difference between the trip hold and the final charge on my statement.',
 NULL);

-- -----------------------------------------------------------------------------
-- Verification (chapter Section 2.1 expects 28 RESOLVED / 12 OPEN, 12 labeled).
-- -----------------------------------------------------------------------------
SELECT status, COUNT(*) AS tickets
FROM gold_db.support.support_tickets
GROUP BY status;

SELECT COUNT(*) AS labeled
FROM gold_db.support.support_tickets
WHERE expected_category IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Optional: per-user AI spend quota (chapter Section 1.3, Controlling access,
-- models, and spend). Commented out because a quota applies to EVERY user on
-- the account until you scope it with INCLUDE_USERS / EXCLUDE_USERS.
-- One quota monitors either warehouse compute or the AI domains, not both.
-- Weekly cycle resets Monday 00:00 UTC. Not live-run yet (2026-10-02):
-- confirm the 'AI FUNCTION' domain string and the limit unit on your account.
-- -----------------------------------------------------------------------------
-- USE ROLE ACCOUNTADMIN;
-- GRANT DATABASE ROLE SNOWFLAKE.QUOTA_CREATOR TO ROLE SYSADMIN;
-- USE ROLE SYSADMIN;
-- GRANT CREATE SNOWFLAKE.CORE.QUOTA ON SCHEMA gold_db.support TO ROLE SYSADMIN;
--
-- CREATE SNOWFLAKE.CORE.QUOTA gold_db.support.ai_spend_quota();
--
-- CALL gold_db.support.ai_spend_quota!ADD_SHARED_RESOURCE('AI FUNCTION');
-- CALL gold_db.support.ai_spend_quota!SET_PER_USER_LIMIT(20, 'WEEKLY');
--
-- Scope it (optional):
-- CALL gold_db.support.ai_spend_quota!INCLUDE_USERS(['<REPLACE: pipeline_user>']);
-- CALL gold_db.support.ai_spend_quota!EXCLUDE_USERS('USER', ['<REPLACE: user>']);
