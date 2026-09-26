-- Bouncer access cleanup — generated 2026-09-26
-- HELD: svc_payments_sync — payments-reconciliation (critical, quarterly, next run soon); 91-day silence is by design, revoking would break the next run.

ALTER ROLE test_final_2 NOSUPERUSER NOLOGIN;

REVOKE ALL ON payments FROM intern_2023;

REVOKE ALL ON customers FROM ravi;
REVOKE ALL ON payments FROM ravi;

REVOKE ALL ON payments FROM svc_legacy_reports;
REVOKE ALL ON reports FROM svc_legacy_reports;

REVOKE DELETE ON payments FROM priya;
