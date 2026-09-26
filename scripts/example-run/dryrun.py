import re, sys

# --- Phase 1 state as data ---
ORIG_GRANTS = {
 ('alice','customers','INSERT'),('alice','customers','SELECT'),('alice','customers','UPDATE'),
 ('alice','payments','INSERT'),('alice','payments','SELECT'),('alice','payments','UPDATE'),
 ('bob','payments','SELECT'),('bob','reports','SELECT'),
 ('intern_2023','payments','INSERT'),('intern_2023','payments','SELECT'),('intern_2023','payments','UPDATE'),
 ('priya','payments','DELETE'),('priya','payments','INSERT'),('priya','payments','SELECT'),('priya','payments','UPDATE'),
 ('ravi','customers','SELECT'),('ravi','payments','SELECT'),
 ('svc_etl','customers','SELECT'),('svc_etl','payments','SELECT'),('svc_etl','reports','INSERT'),('svc_etl','reports','SELECT'),
 ('svc_legacy_reports','payments','SELECT'),('svc_legacy_reports','reports','DELETE'),('svc_legacy_reports','reports','INSERT'),
 ('svc_legacy_reports','reports','REFERENCES'),('svc_legacy_reports','reports','SELECT'),('svc_legacy_reports','reports','TRIGGER'),
 ('svc_legacy_reports','reports','TRUNCATE'),('svc_legacy_reports','reports','UPDATE'),
 ('svc_payments_sync','payments','SELECT'),('svc_payments_sync','payments','UPDATE')}
ORIG_ROLES = {'alice':(False,True),'bob':(False,True),'intern_2023':(False,True),'priya':(False,True),
 'ravi':(False,True),'svc_etl':(False,True),'svc_legacy_reports':(False,True),
 'svc_payments_sync':(False,True),'test_final_2':(True,True)}
HELD = {'svc_payments_sync'}
KEPT = {'alice','bob','svc_etl'}
EXPECT_REMOVED = {(u,t,p) for (u,t,p) in ORIG_GRANTS if u in ('intern_2023','ravi','svc_legacy_reports')} | {('priya','payments','DELETE')}
FLAGGED = ['test_final_2','intern_2023','ravi','svc_legacy_reports','priya','svc_payments_sync']

def stmts(path):
    sql = open(path).read()
    sql = re.sub(r'--[^\n]*','',sql)
    return [s.strip() for s in sql.split(';') if s.strip()]

fail = lambda m: (print(f"DRY RUN FAILED: {m}"), sys.exit(1))

REVOKE_RE = re.compile(r'^REVOKE (ALL|[A-Z, ]+) ON (\w+) FROM (\w+)$')
ALTER_RE  = re.compile(r'^ALTER ROLE (\w+) NOSUPERUSER NOLOGIN$')
BANNED = re.compile(r'\b(INSERT|UPDATE|DELETE|DROP|TRUNCATE|GRANT|ALTER TABLE)\b')

# 1. Lint
parsed=[]
for s in stmts('bouncer/revoke-plan.sql'):
    m = REVOKE_RE.match(s) or ALTER_RE.match(s)
    if not m: fail(f"unrecognised statement: {s}")
    if 'ON payments' not in s and 'ON customers' not in s and 'ON reports' not in s and not ALTER_RE.match(s):
        fail(f"unexpected object: {s}")
    if 'governance' in s: fail(f"touches governance: {s}")
    role = m.group(3) if m.re is REVOKE_RE else m.group(1)
    if role == 'postgres': fail(f"touches postgres: {s}")
    if role in HELD: fail(f"touches HELD role: {s}")
    if m.re is REVOKE_RE and BANNED.search(m.group(1)) and m.group(1)!='ALL':
        # privileges named DELETE etc. inside REVOKE are fine; ban applies to statement type
        pass
    parsed.append((m,s))
print("LINT PASSED:", len(parsed), "statements")

# 2. Simulate revoke
grants = set(ORIG_GRANTS); roles = dict(ORIG_ROLES)
for m,s in parsed:
    if m.re is ALTER_RE:
        roles[m.group(1)] = (False, False)
    else:
        privs, table, role = m.group(1), m.group(2), m.group(3)
        if privs=='ALL':
            grants = {g for g in grants if not (g[0]==role and g[1]==table)}
        else:
            for p in [x.strip() for x in privs.split(',')]:
                grants.discard((role, table, p))

print("\nPost-revoke grants for flagged roles:")
for r in FLAGGED:
    print(f"  {r}: {sorted((t,p) for (u,t,p) in grants if u==r)}")
print("Altered role test_final_2: rolsuper=%s rolcanlogin=%s" % roles['test_final_2'])

# 3. Assertions
for g in EXPECT_REMOVED:
    if g in grants: fail(f"expected removed but present: {g}")
for r in HELD|KEPT:
    if {g for g in grants if g[0]==r} != {g for g in ORIG_GRANTS if g[0]==r}:
        fail(f"held/kept role changed: {r}")
if roles['test_final_2'] != (False,False): fail("test_final_2 not neutralised")
print("\nASSERTIONS PASSED: all REVOKE rows gone, HELD/kept roles untouched")

# 4. Apply rollback
GRANT_RE = re.compile(r'^GRANT ([A-Z, ]+) ON (\w+) TO (\w+)$')
ALTER_UP = re.compile(r'^ALTER ROLE (\w+) SUPERUSER LOGIN$')
for s in stmts('bouncer/rollback-plan.sql'):
    m = GRANT_RE.match(s)
    if m:
        for p in [x.strip() for x in m.group(1).split(',')]:
            grants.add((m.group(3), m.group(2), p))
        continue
    m = ALTER_UP.match(s)
    if m: roles[m.group(1)] = (True, True); continue
    fail(f"rollback statement unrecognised: {s}")

if grants != ORIG_GRANTS: fail(f"rollback mismatch: {grants ^ ORIG_GRANTS}")
if roles != ORIG_ROLES: fail("rollback role state mismatch")
print("ROLLBACK VERIFIED: restores original grants and roles exactly")
print("\nDRY RUN PASSED")
