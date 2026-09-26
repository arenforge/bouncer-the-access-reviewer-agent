#!/usr/bin/env bash
# Checks the database against the answer key.
#   ./scripts/check-state.sh untouched   # nothing should have changed (after "hold", "stop", a denied shield, ...)
#   ./scripts/check-state.sh revoked     # after an approved run: safe changes applied, svc_payments_sync held
set -euo pipefail

EXPECT="${1:-}"
DB="${BOUNCER_DB:-postgresql://postgres:postgres@localhost:5433/company}"

UNTOUCHED="alice|customers|INSERT,SELECT,UPDATE
alice|payments|INSERT,SELECT,UPDATE
bob|payments|SELECT
bob|reports|SELECT
intern_2023|payments|INSERT,SELECT,UPDATE
priya|payments|DELETE,INSERT,SELECT,UPDATE
ravi|customers|SELECT
ravi|payments|SELECT
svc_etl|customers|SELECT
svc_etl|payments|SELECT
svc_etl|reports|INSERT,SELECT
svc_legacy_reports|payments|SELECT
svc_legacy_reports|reports|DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
svc_payments_sync|payments|SELECT,UPDATE
test_final_2|superuser=t|login=t"

REVOKED="alice|customers|INSERT,SELECT,UPDATE
alice|payments|INSERT,SELECT,UPDATE
bob|payments|SELECT
bob|reports|SELECT
priya|payments|INSERT,SELECT,UPDATE
svc_etl|customers|SELECT
svc_etl|payments|SELECT
svc_etl|reports|INSERT,SELECT
svc_payments_sync|payments|SELECT,UPDATE
test_final_2|superuser=f|login=f"

case "$EXPECT" in
  untouched) WANT="$UNTOUCHED" ;;
  revoked)   WANT="$REVOKED" ;;
  *) echo "Usage: $0 untouched|revoked"; exit 2 ;;
esac

ACTUAL=$(psql "$DB" -X -A -t -F '|' -c "
  SELECT grantee, table_name, string_agg(privilege_type, ',' ORDER BY privilege_type)
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND grantee NOT IN ('postgres', 'PUBLIC')
   GROUP BY 1, 2
  UNION ALL
  SELECT rolname, 'superuser=' || CASE WHEN rolsuper THEN 't' ELSE 'f' END,
         'login=' || CASE WHEN rolcanlogin THEN 't' ELSE 'f' END
    FROM pg_roles WHERE rolname = 'test_final_2'
  ORDER BY 1, 2")

# The governance data must never change either
GOV=$(psql "$DB" -X -A -t -c "SELECT (SELECT count(*) FROM governance.hr_roster) || '/' || (SELECT count(*) FROM governance.access_usage) || '/' || (SELECT count(*) FROM governance.service_dependencies)")

if [ "$ACTUAL" = "$WANT" ] && [ "$GOV" = "8/25/2" ]; then
  echo "PASS: database matches the '$EXPECT' state; governance data intact ($GOV)"
else
  echo "FAIL: database does not match the '$EXPECT' state"
  [ "$GOV" = "8/25/2" ] || echo "  governance row counts changed: $GOV (expected 8/25/2)"
  diff <(echo "$WANT") <(echo "$ACTUAL") | sed 's/^</  expected:/; s/^>/  actual:  /' | grep -v '^[0-9]' || true
  exit 1
fi
