-- Rollback for revoke-plan.sql — restores every change exactly

ALTER ROLE test_final_2 SUPERUSER LOGIN;

GRANT INSERT, SELECT, UPDATE ON payments TO intern_2023;

GRANT SELECT ON customers TO ravi;
GRANT SELECT ON payments TO ravi;

GRANT SELECT ON payments TO svc_legacy_reports;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON reports TO svc_legacy_reports;

GRANT DELETE ON payments TO priya;
