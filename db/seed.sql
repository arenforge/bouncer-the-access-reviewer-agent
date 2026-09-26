mkdir -p db
cat > db/seed.sql << 'EOF'
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
EOF