from datetime import date

TODAY = date(2026, 9, 26)
STALE_DAYS = 90

roles = {  # rolname: (rolsuper, rolcanlogin)
 'alice':(False,True),'bob':(False,True),'intern_2023':(False,True),'priya':(False,True),
 'ravi':(False,True),'svc_etl':(False,True),'svc_legacy_reports':(False,True),
 'svc_payments_sync':(False,True),'test_final_2':(True,True)}

grants = [
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
 ('svc_payments_sync','payments','SELECT'),('svc_payments_sync','payments','UPDATE')]

roster = {  # username: (status, left_on, owner)
 'alice':('active',None,None),'bob':('active',None,None),'priya':('active',None,None),
 'intern_2023':('left',date(2025,7,28),None),'ravi':('left',date(2026,3,10),None),
 'svc_etl':('service_account',None,'alice'),
 'svc_legacy_reports':('service_account',None,'ravi'),
 'svc_payments_sync':('service_account',None,'bob')}

usage = {  # (user, object, priv): last_used
 ('alice','payments','SELECT'):date(2026,9,25),('alice','payments','INSERT'):date(2026,9,24),
 ('alice','payments','UPDATE'):date(2026,9,23),('alice','customers','SELECT'):date(2026,9,25),
 ('alice','customers','INSERT'):date(2026,9,20),('alice','customers','UPDATE'):date(2026,9,18),
 ('bob','reports','SELECT'):date(2026,9,21),('bob','payments','SELECT'):date(2026,9,24),
 ('priya','payments','SELECT'):date(2026,9,25),('priya','payments','INSERT'):date(2026,9,22),
 ('priya','payments','UPDATE'):date(2026,9,16),('priya','payments','DELETE'):None,
 ('intern_2023','payments','SELECT'):date(2025,8,10),('intern_2023','payments','INSERT'):date(2025,8,10),
 ('intern_2023','payments','UPDATE'):date(2025,7,23),
 ('ravi','customers','SELECT'):date(2026,3,5),('ravi','payments','SELECT'):date(2026,2,28),
 ('svc_etl','payments','SELECT'):date(2026,9,26),('svc_etl','customers','SELECT'):date(2026,9,26),
 ('svc_etl','reports','SELECT'):date(2026,9,26),('svc_etl','reports','INSERT'):date(2026,9,26),
 ('svc_legacy_reports','reports','SELECT'):date(2026,6,21),('svc_legacy_reports','payments','SELECT'):date(2026,6,21),
 ('svc_payments_sync','payments','SELECT'):date(2026,6,27),('svc_payments_sync','payments','UPDATE'):date(2026,6,27)}

deps = {'svc_etl':('daily-analytics-load','daily','medium'),
        'svc_payments_sync':('payments-reconciliation','quarterly (next run soon)','critical')}

def days(d): return (TODAY-d).days if d else None

findings=[]
# role-level: unowned superuser / unowned role
for r,(sup,login) in roles.items():
    if r not in roster:
        why = 'UNOWNED SUPERUSER' if sup else 'unowned role (not in HR roster)'
        findings.append(dict(role=r, kind='role', why=why, last_used=None,
                             dep=deps.get(r), decision='HOLD' if deps.get(r) else 'REVOKE'))

for g in grants:
    u,t,p = g
    reasons=[]
    st = roster.get(u)
    if st:
        status,left_on,owner = st
        if status=='left': reasons.append(f'left the company ({left_on})')
        if status=='service_account' and roster.get(owner,('',None,None))[0]=='left':
            reasons.append(f'orphaned service account (owner {owner} left)')
    lu = usage.get((u,t,p),'MISSING')
    if lu=='MISSING': reasons.append('never used (no usage row)')
    elif lu is None: reasons.append('never used (last_used NULL)')
    elif days(lu)>STALE_DAYS: reasons.append(f'stale ({days(lu)} days)')
    if reasons:
        findings.append(dict(role=u, kind='grant', grant=(t,p), why='; '.join(reasons),
                             last_used=None if lu in('MISSING',None) else lu,
                             dep=deps.get(u), decision='HOLD' if deps.get(u) else 'REVOKE'))

print(f"{'ROLE':<20}{'ITEM':<28}{'DECISION':<8} WHY  [dep]")
for f in sorted(findings,key=lambda f:(f['decision']!='REVOKE')):
    item = 'ROLE ITSELF' if f['kind']=='role' else f"{f['grant'][1]} on {f['grant'][0]}"
    print(f"{f['role']:<20}{item:<28}{f['decision']:<8} {f['why']}  dep={f['dep']}")

flagged_roles = {f['role'] for f in findings}
print('\nKept roles (no findings):', sorted(set(roles)-flagged_roles))
