# Bouncer: the access-reviewer agent (project context for Claude Code)

This file gives complete context for the project. Read it fully before making changes.

---

## 1. Who and when

- **Builder:** Arhan Khan (SDE intern, full-stack developer), possibly with teammates.
- **Event:** Agents That Act, the TrueFoundry × Polaris hackathon.
- **Date and place:** Saturday, 26 September 2026, Polaris School of Technology, Bengaluru. One in-person build day (about 7 hours), live demos and prizes the same evening.
- **Machine:** MacBook Air (Apple Silicon), macOS, zsh, Homebrew, Docker Desktop, VS Code-style editor.

## 2. Hackathon rules that constrain this project

- The agent **must be built on TrueForge**, TrueFoundry's open-source (MIT) agent harness.
- Every submission must show the harness doing real work:
  1. **a real tool reached** (a real system over MCP),
  2. **code run in a sandbox**,
  3. **a pause before anything irreversible** (human approval).
- **Projects must be built on the day.** Pre-built projects aren't eligible.
- **Judging, out of 100:**
  - harness doing real work: 30
  - it actually runs: 25
  - **where it stops** (the approval pause and blast-radius awareness): 20
  - a job worth handing over: 15
  - demo clarity: 10
- The official "access reviewer" brief mentions walking IAM roles, service accounts, and permissions unused for 90 days, and producing a least-privilege diff with the **blast radius** of each revocation spelled out.

**Priority order when making trade-offs:** it runs end to end > the pause is harness-enforced > blast radius is clear > polish.

## 3. What the agent does

**Bouncer** reviews who has access to what, and proposes cleanup:

1. **Scans** database roles and their grants (read-only).
2. **Cross-checks** each grant against:
   - the **usage log** (when each privilege was last used),
   - the **HR roster** (who still works here, who owns each service account).
3. **Flags** stale access: unused for 90+ days, never used, belonging to people who've left, ownerless accounts, and over-privileged grants.
4. **Works out the blast radius** of each removal using a service-dependency table ("if I remove this, what breaks?").
5. **Writes a revocation SQL script.**
6. **Dry-runs** the script in the sandbox inside `BEGIN … ROLLBACK`, so nothing changes.
7. **Pauses.** It presents the plan (each grant, the reason, and the blast radius), holds back anything risky, and waits for human approval.
8. Only after approval does it **run the revocation through a shielded tool**, which the harness forces to ask before running.

**Core idea: "the pause is the product."** Any tool that can revoke access can also lock out an on-call team, so this agent never revokes without a human yes. Tagline: *"My AI agent's job: kick people out. Its most important skill: not doing it."*

## 4. Architecture

```
Postgres (fake company DB, Docker, host port 5433, db "company")
   ├── MCP "reader"  → crystaldba/postgres-mcp --access-mode=restricted   → port 8000 → read-only scanning
   └── MCP "revoker" → crystaldba/postgres-mcp --access-mode=unrestricted → port 8001 → marked SHIELDED in TrueForge
TrueForge sandbox → runs the revoke script with psql inside BEGIN … ROLLBACK (dry run)
TrueForge agent   → model: claude-fable-5 (or whatever the event's AI Gateway provides)
```

Why two MCP servers: the agent can read everything freely, but it physically can't change anything except through the shielded revoker. Shielded tools always ask before running, so the pause is **enforced by the harness, not just requested in the prompt.** That's the strongest possible answer to the "where it stops" criterion.

## 5. TrueForge setup (already installed)

- Start: `OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]' npx @truefoundry/trueforge` (the env var lets it reach the local MCP servers; same command every time; data persists in `~/Library/Application Support/trueforge/db/db.sqlite`). Stop: `Ctrl + C`.
- Version: TrueForge v0.2.1, standalone mode.
- UI: http://localhost:8790. API docs: http://localhost:8790/api/v1/docs.
- Standalone mode is **localhost-only, not hardened**. Never expose it to the venue network.
- Auth is disabled in standalone mode.
- The log shows **"Local sandbox fallback is available"** (Mac bash + Python 3.14). The sandbox likely runs directly on the Mac rather than in an isolated container. Hence the `BEGIN … ROLLBACK` dry-run for safety. `psql` must be installed on the Mac (`brew install libpq && brew link --force libpq`).
- **Build Agent screen fields:** model (`claude-fable-5`, reasoning effort low), Instructions, Runtime Config (iteration limit 100, sandbox on, compaction on, large tool response on, dynamic sub-agents on, generative UI on, ask user questions on), MCP Servers, Skills.
- The **"Select MCP Tools"** dialog is empty until MCP servers are registered. Registration is probably in **Settings** or documented in **Docs** in the sidebar. The dialog footer reads: *"Shielded tools always ask before the agent runs them."*
- **Open questions to confirm with mentors or docs:**
  - exactly where and how to register an MCP server (URL-based SSE vs. streamable HTTP),
  - how to mark a tool as shielded,
  - whether an isolated sandbox is available.
- **Model access:** Arhan's Anthropic Console org hit a self-set $1 monthly spend limit (resets Oct 1). Either raise it in the Console settings (Limits) or use the model access provided through TrueFoundry's AI Gateway at the event.

## 6. Repository

- **GitHub:** https://github.com/arenforge/bouncer-the-access-reviewer-agent
- **Local path:** `~/Desktop/bouncer/bouncer-the-access-reviewer-agent` on Arhan's laptop (originally planned for `~/projects/…`, because macOS blocked Terminal from reading Desktop with "Operation not permitted"). Use the editor's built-in terminal, or grant Terminal "Files & Folders → Desktop" or "Full Disk Access" in System Settings.

Intended structure:
```
bouncer-the-access-reviewer-agent/
├── CLAUDE.md               ← this file
├── README.md               ← what it does, how to run it
├── docker-compose.yml      ← Postgres
├── db/seed.sql             ← fake company data + governance tables
├── agent/instructions.md   ← agent instructions (source of truth; pasted into TrueForge)
├── agent/mcp-config.md     ← how the two MCP servers are registered
├── scripts/                ← generated revoke scripts saved for the demo
└── demo/                   ← demo script, screenshots, recordings
```

**TrueForge stores the agent locally on one laptop (the demo laptop).** The repo is the source of truth: edit `agent/instructions.md` in Git, then paste the latest version into TrueForge.

### Team workflow
- Everyone: `git pull` → edit only your own files → `git add` → `git commit -m "…"` → `git push`. On a rejected push: `git pull --rebase && git push`.
- Suggested roles for four people:
  - lead: TrueForge, MCP and `agent/`,
  - second: `db/seed.sql`,
  - third: `scripts/`, testing and README,
  - fourth: `demo/`, recording and posts.
- Never commit real secrets. All credentials in this project are fake demo values.

## 7. docker-compose.yml

```yaml
services:
  db:
    image: postgres:16
    container_name: bouncer-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: company
    ports:
      - "5433:5432" # 5433 on the host so it never clashes with a local Postgres on 5432
    volumes:
      - ./db/seed.sql:/docker-entrypoint-initdb.d/seed.sql
```

The seed runs only on first start with an empty volume. After editing `seed.sql`, run `docker compose down -v && docker compose up -d`.

## 8. db/seed.sql (current version)

Contents: a fake company with `customers`, `payments` and `reports` tables; nine login roles; grants; and a `governance` schema with `hr_roster`, `access_usage` and `service_dependencies`.

### Expected findings (the "answer key" for testing the agent)

| Role | Situation | Correct outcome |
|---|---|---|
| `intern_2023` | Left 425 days ago. Has SELECT/INSERT/UPDATE on payments, last used 412–430 days ago | **Revoke all** |
| `ravi` | Left 200 days ago. SELECT on customers and payments, last used 205–210 days ago | **Revoke all** |
| `test_final_2` | **SUPERUSER**, no usage rows, **not in HR roster** (no owner) | **Revoke** (`ALTER ROLE … NOSUPERUSER NOLOGIN`). Highest risk |
| `svc_legacy_reports` | Service account, owner `ravi` has left, unused 97 days, **no dependencies** | **Revoke all** |
| `priya` | Active employee, has DELETE on payments that she has **never used** | **Revoke only DELETE** (over-privileged) |
| `svc_payments_sync` | Unused 91 days, **but** `payments-reconciliation` (critical, quarterly, next run soon) depends on it | **HOLD, do not revoke.** Blast-radius catch; explain why it looks stale |
| `alice`, `bob`, `svc_etl` | Active, recently used | **Keep** |

`svc_payments_sync` is the key demo moment: the agent must notice that "unused for 91 days" is explained by a quarterly schedule, and hold it for human review.

### Full file

```sql
-- Bouncer demo database: a fake company with stale access to clean up.
-- All names, passwords and data are fictional.

-- 1. Application tables
CREATE TABLE customers (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  email TEXT NOT NULL
);

CREATE TABLE payments (
  id          SERIAL PRIMARY KEY,
  customer_id INT REFERENCES customers(id),
  amount      NUMERIC(10,2) NOT NULL,
  status      TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE reports (
  id         SERIAL PRIMARY KEY,
  title      TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO customers (name, email) VALUES
  ('Asha Traders', 'billing@asha.example'),
  ('Blue Kite Labs', 'finance@bluekite.example'),
  ('Coral Foods', 'accounts@coral.example');

INSERT INTO payments (customer_id, amount, status) VALUES
  (1, 12500.00, 'settled'),
  (2, 4800.50, 'pending'),
  (3, 990.00, 'settled');

INSERT INTO reports (title) VALUES
  ('Monthly revenue'),
  ('Churn summary');

-- 2. Database roles
CREATE ROLE alice              LOGIN PASSWORD 'demo';
CREATE ROLE bob                LOGIN PASSWORD 'demo';
CREATE ROLE priya              LOGIN PASSWORD 'demo';
CREATE ROLE intern_2023        LOGIN PASSWORD 'demo';
CREATE ROLE ravi               LOGIN PASSWORD 'demo';
CREATE ROLE test_final_2       LOGIN SUPERUSER PASSWORD 'demo';
CREATE ROLE svc_etl            LOGIN PASSWORD 'demo';
CREATE ROLE svc_legacy_reports LOGIN PASSWORD 'demo';
CREATE ROLE svc_payments_sync  LOGIN PASSWORD 'demo';

-- 3. Grants
GRANT SELECT, INSERT, UPDATE         ON payments, customers TO alice;
GRANT SELECT                         ON reports, payments   TO bob;
GRANT SELECT, INSERT, UPDATE, DELETE ON payments            TO priya;
GRANT SELECT, INSERT, UPDATE         ON payments            TO intern_2023;
GRANT SELECT                         ON customers, payments TO ravi;
GRANT SELECT                         ON customers, payments, reports TO svc_etl;
GRANT INSERT                         ON reports             TO svc_etl;
GRANT ALL                            ON reports             TO svc_legacy_reports;
GRANT SELECT                         ON payments            TO svc_legacy_reports;
GRANT SELECT, UPDATE                 ON payments            TO svc_payments_sync;

-- 4. Governance data the agent cross-checks
CREATE SCHEMA governance;

CREATE TABLE governance.hr_roster (
  username          TEXT PRIMARY KEY,
  full_name         TEXT,
  team              TEXT,
  employment_status TEXT NOT NULL CHECK (employment_status IN ('active', 'left', 'service_account')),
  left_on           DATE,
  owner             TEXT
);

INSERT INTO governance.hr_roster VALUES
  ('alice',              'Alice Menon',       'Payments',  'active',          NULL,               NULL),
  ('bob',                'Bob Dsouza',        'Finance',   'active',          NULL,               NULL),
  ('priya',              'Priya Rao',         'Payments',  'active',          NULL,               NULL),
  ('intern_2023',        'Summer Intern',     'Payments',  'left',            CURRENT_DATE - 425, NULL),
  ('ravi',               'Ravi Kumar',        'Analytics', 'left',            CURRENT_DATE - 200, NULL),
  ('svc_etl',            'ETL pipeline',      'Analytics', 'service_account', NULL,               'alice'),
  ('svc_legacy_reports', 'Old reporting job', 'Analytics', 'service_account', NULL,               'ravi'),
  ('svc_payments_sync',  'Payments sync',     'Payments',  'service_account', NULL,               'bob');

CREATE TABLE governance.access_usage (
  username    TEXT NOT NULL,
  object_name TEXT NOT NULL,
  privilege   TEXT NOT NULL,
  last_used   DATE
);

INSERT INTO governance.access_usage VALUES
  ('alice',              'payments',  'SELECT', CURRENT_DATE - 1),
  ('alice',              'payments',  'INSERT', CURRENT_DATE - 2),
  ('alice',              'payments',  'UPDATE', CURRENT_DATE - 3),
  ('alice',              'customers', 'SELECT', CURRENT_DATE - 1),
  ('alice',              'customers', 'INSERT', CURRENT_DATE - 6),
  ('alice',              'customers', 'UPDATE', CURRENT_DATE - 8),
  ('bob',                'reports',   'SELECT', CURRENT_DATE - 5),
  ('bob',                'payments',  'SELECT', CURRENT_DATE - 2),
  ('priya',              'payments',  'SELECT', CURRENT_DATE - 1),
  ('priya',              'payments',  'INSERT', CURRENT_DATE - 4),
  ('priya',              'payments',  'UPDATE', CURRENT_DATE - 10),
  ('priya',              'payments',  'DELETE', NULL),
  ('intern_2023',        'payments',  'SELECT', CURRENT_DATE - 412),
  ('intern_2023',        'payments',  'INSERT', CURRENT_DATE - 412),
  ('intern_2023',        'payments',  'UPDATE', CURRENT_DATE - 430),
  ('ravi',               'customers', 'SELECT', CURRENT_DATE - 205),
  ('ravi',               'payments',  'SELECT', CURRENT_DATE - 210),
  ('svc_etl',            'payments',  'SELECT', CURRENT_DATE),
  ('svc_etl',            'customers', 'SELECT', CURRENT_DATE),
  ('svc_etl',            'reports',   'SELECT', CURRENT_DATE),
  ('svc_etl',            'reports',   'INSERT', CURRENT_DATE),
  ('svc_legacy_reports', 'reports',   'SELECT', CURRENT_DATE - 97),
  ('svc_legacy_reports', 'payments',  'SELECT', CURRENT_DATE - 97),
  ('svc_payments_sync',  'payments',  'SELECT', CURRENT_DATE - 91),
  ('svc_payments_sync',  'payments',  'UPDATE', CURRENT_DATE - 91);

CREATE TABLE governance.service_dependencies (
  account     TEXT NOT NULL,
  service     TEXT NOT NULL,
  description TEXT,
  schedule    TEXT,
  criticality TEXT CHECK (criticality IN ('low', 'medium', 'high', 'critical'))
);

INSERT INTO governance.service_dependencies VALUES
  ('svc_etl',           'daily-analytics-load',    'Loads payments and customers into the analytics warehouse', 'daily',                     'medium'),
  ('svc_payments_sync', 'payments-reconciliation', 'Reconciles payments with the bank every quarter',          'quarterly (next run soon)', 'critical');
```

## 9. Commands

### Prerequisites (Docker Desktop must be open and show "Engine running")
```
docker pull postgres:16
docker pull crystaldba/postgres-mcp
brew install libpq && brew link --force libpq
```

### Start
```
cd ~/Desktop/bouncer/bouncer-the-access-reviewer-agent
docker compose up -d
docker exec -it bouncer-db psql -U postgres -d company -c "\du"
docker exec -it bouncer-db psql -U postgres -d company -c "SELECT * FROM governance.hr_roster;"

docker run -d --name bouncer-reader -p 8000:8000 -e DATABASE_URI=postgresql://postgres:postgres@host.docker.internal:5433/company crystaldba/postgres-mcp --access-mode=restricted --transport=sse --sse-host=0.0.0.0

docker run -d --name bouncer-revoker -p 8001:8000 -e DATABASE_URI=postgresql://postgres:postgres@host.docker.internal:5433/company crystaldba/postgres-mcp --access-mode=unrestricted --transport=sse --sse-host=0.0.0.0

docker ps
```
Register in TrueForge: reader at `http://localhost:8000/sse`, and revoker at `http://localhost:8001/sse` (**Shielded**). postgres-mcp only supports `stdio` and `sse`, so SSE it is. `--sse-host=0.0.0.0` is required, or the server binds to localhost inside the container and is unreachable. TrueForge must be started with `OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]'` or it rejects localhost MCP URLs. Full steps: `agent/mcp-config.md`.

### Maintenance
```
docker logs bouncer-db | bouncer-reader | bouncer-revoker
docker compose down -v && docker compose up -d        # reset DB after seed changes
docker restart bouncer-reader bouncer-revoker          # after a DB reset
docker rm -f bouncer-reader                            # recreate an MCP container
docker exec -it bouncer-db psql -U postgres -d company # DB shell (\q to exit)
```

### Dry-run pattern (sandbox)
```
psql postgresql://postgres:postgres@localhost:5433/company -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
-- revoke statements here
-- verification queries here (e.g. \dp payments, SELECT rolsuper FROM pg_roles WHERE rolname='test_final_2')
ROLLBACK;
SQL
```

### Stop
```
docker compose down
docker rm -f bouncer-reader bouncer-revoker
```

## 10. Current status (as of the morning of 26 Sep)

- [x] TrueForge installed and running locally
- [x] Repo created on GitHub and cloned to `~/projects/…`
- [x] `docker-compose.yml` and `db/seed.sql` committed (fixed: stray heredoc lines removed, host port moved to 5433, usage rows added so alice/svc_etl stay "keep")
- [x] Docker Desktop running; `docker compose up -d` succeeds; seed verified against the answer key
- [x] Both MCP containers running (with `--sse-host=0.0.0.0`)
- [x] Dry-run pattern verified with psql (`BEGIN … ROLLBACK` leaves the DB unchanged)
- [ ] TrueForge restarted with `OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]'`
- [ ] MCP servers registered in TrueForge (revoker marked Shielded, `@all`)
- [x] Agent instructions written in `agent/instructions.md`
- [ ] Instructions pasted into TrueForge
- [ ] First full end-to-end run
- [ ] Revoke scripts saved to `scripts/`
- [ ] README
- [ ] Demo recording of the approval pause

## 11. Next tasks, in order

1. **Get the database and MCP servers running** and verify with `docker ps` and the check queries.
2. **Register both MCP servers in TrueForge.** Test: *"Using the reader, list every role and its grants."*
3. **Write `agent/instructions.md`.** It should tell the agent to:
   - use only the **reader** for investigation,
   - query `pg_roles`, `information_schema.role_table_grants` (or `\dp`-equivalent queries), and the three `governance` tables,
   - apply the rules: flag access unused for 90+ days, never used, belonging to people who've left, ownerless (not in roster), superuser without an owner, or over-privileged (a privilege never used),
   - for every candidate, check `governance.service_dependencies`, and **hold** anything with a dependency, explaining why it looks stale (for example, a quarterly schedule),
   - produce a least-privilege plan as a table: role, privilege/object, reason, last used, blast radius, decision (revoke or hold),
   - generate a single revoke SQL script (REVOKE statements; `ALTER ROLE … NOSUPERUSER NOLOGIN` for `test_final_2`), save it to `scripts/`, and **dry-run it in the sandbox inside `BEGIN … ROLLBACK`** with psql, reporting the result,
   - then **stop and ask for approval** ("ask user questions"), showing counts (for example, "N changes ready, 1 held"),
   - only after an explicit yes, execute through the **shielded revoker**, then re-query with the reader to verify and report,
   - never revoke from `postgres`, and never touch the `governance` schema or application data.
4. **Run it end to end once**, compare against the answer key in section 8, and fix instructions or seed as needed. Write down what broke; it's material for the build-story post.
5. **Polish:** clear per-grant reasons, a clean approval summary, and the held payments row.
6. **README:** problem, architecture diagram, how to run, safety design (read-only reader, shielded revoker, sandbox dry run), and the answer key.
7. **Stretch, only if everything works:** GitHub MCP so the agent opens a pull request with the revoke script (a second real system plus an audit trail).
8. **Last hour: freeze features.** Record the approval moment and practise a 2-minute demo: problem → scan → blast-radius catch → dry run → pause → approve → verify.

## 12. Guardrails for anyone (human or AI) working on this repo

- Keep all data fictional. Never add real credentials, real names or real company data.
- Don't expose TrueForge or the databases beyond localhost.
- Don't weaken the safety design. The revoker stays shielded, the reader stays restricted, and dry runs always use `ROLLBACK`.
- Prefer the simplest thing that runs end to end. "It actually runs" is worth 25 points.
- Commit small and often, with clear messages.

## 13. Build-story context (the LinkedIn community prize)

- Prizes: ₹50,000 and ₹25,000 for the best public build stories (LinkedIn post, X thread, blog or demo video) explaining **what you built, how you wired it, and what surprised you.** A varied series beats one polished post.
- Tag TrueFoundry and Polaris School of Technology on LinkedIn (@truefoundry and @polariscodes on X). Hashtags: **#agentsthatact** #truefoundry #polarisschooloftechnology.
- Post 1 (published) introduced the idea with the hook above.
- Planned next posts:
  - the wiring (architecture diagram from section 4),
  - what broke and what surprised you, with a screen recording of the approval pause,
  - a reflection after results.
- During the build, capture:
  - team photos,
  - a screenshot of the flagged grants,
  - the revoke script diff,
  - **a screen recording of the "waiting for approval" moment**,
  - one memorable error message.
- Be honest in posts. Only describe things that really happened.
