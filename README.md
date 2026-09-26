# Bouncer: The Access Reviewer Agent

> **My AI agent's job: kick people out. Its most important skill: not doing it.**

Bouncer is an AI agent that reviews database access and finds permissions that may no longer be needed.

The important part is that Bouncer does **not** use a simple rule like:

```text
unused for 90 days → revoke
```

Instead, it investigates the reason behind the access, checks ownership and usage, looks for service dependencies, considers the possible blast radius, prepares a least-privilege cleanup plan, and then stops before the destructive action.

A human must approve the actual revoke.

---

# The Problem

Database access becomes difficult to manage over time.

People leave companies. Old roles stay behind. Service accounts may lose their owners. Some permissions are never used. Other permissions may look stale but are still required by an important scheduled job.

A simple cleanup script can therefore remove something that a real service still needs.

For example:

```text
91 days unused
       ↓
Looks stale
       ↓
But a quarterly payment job depends on it
       ↓
Removing it could break the job
```

Bouncer is designed around this problem.

It separates **finding suspicious access** from **deciding what should actually happen**.

---

# What Bouncer Does

Bouncer follows this general flow:

```text
┌───────────────────────┐
│   PostgreSQL Access   │
│ roles + grants + DB   │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│     Read the Context  │
│ HR + usage + ownership│
│ + service dependencies│
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│    Flag for Review    │
│      6 rules          │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Investigate Further  │
│ permissions + owner   │
│ + dependencies        │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│   KEEP / REVOKE /     │
│        HOLD           │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Revoke Plan + SQL    │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Sandbox Safety Check │
│  lint + simulation    │
└───────────┬───────────┘
            │
            ▼
       ┌──────────┐
       │   STOP   │
       └────┬─────┘
            │
            ▼
┌───────────────────────┐
│   Human Approval      │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Shielded Revoker MCP │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Verify Final State   │
│     using Reader     │
└───────────────────────┘
```

The main idea is simple:

> **Bouncer can recommend a revoke, but it cannot complete the destructive action without human approval.**

---

# Flagging Is Not Revoking

This is one of the most important parts of the design.

Bouncer has two separate stages.

## Stage 1 — Flagging

The agent applies six rules to find access that needs review.

A flag means:

> "Look at this access more carefully."

It does **not** automatically mean:

> "Revoke this access."

## Stage 2 — Decision

After flagging, Bouncer checks the complete context and decides whether the access should be:

```text
KEEP

REVOKE

HOLD
```

This prevents the six rules from becoming six automatic revoke rules.

---

# How Bouncer Flags Access

## Rule 1 — Employee Left the Company

```text
employment_status == 'left'
```

If a person has left the company, their database grants are flagged for review.

The person does **not** need to have been gone for 90 days.

For example:

```text
Employee left 1 month ago
        ↓
Rule 1 flags the access
        ↓
Review permissions
        ↓
Check dependencies
        ↓
Create decision
```

The 90-day condition belongs to the stale-access rule, not this rule.

---

## Rule 2 — Unowned Superuser

A role is flagged when:

```text
rolsuper == true
```

and the role is not present in the HR roster.

A superuser without a known owner is especially important because it has very high database privileges.

Example:

```text
test_final_2
```

It is a superuser, has no usage rows, and is not in the HR roster.

---

## Rule 3 — Unowned Role

A database role is flagged when it cannot be matched to the HR roster.

The purpose is to find database access that has no known human owner.

---

## Rule 4 — Orphaned Service Account

A service account is flagged when its owner has left the company.

For example:

```text
svc_legacy_reports
        ↓
Owner = ravi
        ↓
Ravi has left
        ↓
Service account becomes orphaned
```

The service account is then investigated separately.

---

## Rule 5 — Stale Access

Access is flagged when it has not been used for more than 90 days.

```text
(today - last_used).days > 90
```

This is only a **flagging rule**.

It does not automatically mean the permission should be revoked.

A dependency can change the final decision.

---

## Rule 6 — Never Used

Access is flagged when there is no usage record or the last-used value is missing.

Examples:

```text
No usage row

      OR

last_used IS NULL
```

Again, this means the access needs investigation. It is not automatic proof that the access is unnecessary.

---

# From Flag to Decision

After access is flagged, Bouncer looks at the complete context.

```text
             FLAG
               │
               ▼
       ┌─────────────────┐
       │ Check exact     │
       │ permissions     │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Check owner and │
       │ HR status       │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Check usage     │
       │ history         │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Check service   │
       │ dependencies    │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Evaluate blast  │
       │ radius          │
       └────────┬────────┘
                │
           ┌────┼────┐
           ▼    ▼    ▼
         KEEP REVOKE HOLD
```

### KEEP

The access is still needed or the available evidence does not support removing it.

### REVOKE

The specific access is identified as removable.

The agent should remove only the necessary privilege when possible.

### HOLD

The access looks suspicious but removing it could cause a problem or needs more review.

The key example is:

```text
svc_payments_sync
        ↓
91 days unused
        ↓
Looks stale
        ↓
Critical quarterly job depends on it
        ↓
HOLD
```

---

# What Bouncer Checks

Bouncer uses multiple pieces of information before creating the final plan.

| Information | Why it matters |
|---|---|
| HR roster | Checks whether a person is active or has left |
| Database roles | Finds roles and accounts |
| Database grants | Shows exact permissions |
| Superuser status | Finds high-privilege roles |
| Usage history | Shows when access was last used |
| Never-used information | Finds permissions with no usage |
| Service-account owner | Finds orphaned accounts |
| Service dependencies | Checks whether a service still depends on access |
| Blast radius | Helps explain what could be affected by a revoke |

The goal is not to collect more data just for the sake of it.

Each check helps answer one question:

> **"Is this access actually safe to remove?"**

---

# Important Examples

## `test_final_2`

```text
SUPERUSER
No usage rows
Not in HR roster
      ↓
Flagged
      ↓
REVOKE
```

The final change removes its superuser and login capability:

```sql
ALTER ROLE test_final_2 NOSUPERUSER NOLOGIN;
```

This is a high-impact change, so it can only reach the destructive path after human approval.

---

## `intern_2023`

```text
Left 425 days ago
SELECT / INSERT / UPDATE on payments
Last used 412–430 days ago
        ↓
REVOKE all database access
```

---

## `ravi`

```text
Left 200 days ago
SELECT on customers and payments
Last used around 205–210 days ago
        ↓
REVOKE all database access
```

---

## `svc_legacy_reports`

```text
Service account
Owner = ravi
Ravi has left
Unused for 97 days
No dependency found
        ↓
REVOKE
```

---

## `priya`

This case shows why Bouncer can revoke a **specific permission** instead of removing everything.

```text
Active employee
        ↓
Has DELETE on payments
        ↓
DELETE was never used
        ↓
Keep other useful permissions
        ↓
REVOKE DELETE only
```

Her other required access remains.

---

## `svc_payments_sync`

This is the key demo case.

```text
Unused for 91 days
        ↓
Rule 5 flags it
        ↓
Dependency check
        ↓
payments-reconciliation
critical quarterly job
depends on it
        ↓
HOLD
        ↓
DO NOT REVOKE
```

This is why:

```text
unused > 90 days
```

is not enough to safely revoke database access.

---

# Answer Key

The demo uses fictional company data.

The expected decisions are:

| Role | Situation | Decision |
|---|---|---|
| `test_final_2` | Superuser, no usage, not in HR | Revoke superuser + login |
| `intern_2023` | Left 425 days ago, old usage | Revoke all |
| `ravi` | Left 200 days ago, old usage | Revoke all |
| `svc_legacy_reports` | Owner left, unused 97 days, no dependency | Revoke all |
| `priya` | Active, DELETE never used | Revoke DELETE only |
| `svc_payments_sync` | Unused 91 days, but critical job depends on it | **HOLD** |
| `alice` | Active and recently used | Keep |
| `bob` | Active and recently used | Keep |
| `svc_etl` | Active and recently used | Keep |

The verified end-to-end run produced the expected final database state, including the `svc_payments_sync` HOLD.

---

# How the Agent Works

Bouncer works in labelled phases.

| Phase | Where | What happens |
|---|---|---|
| **1 · Scan** | `bouncer-reader` MCP | Reads roles, grants and governance data |
| **2 · Analyse** | Sandbox | Generated Python code joins grants with HR and usage data |
| **3 · Diff** | Agent conversation | Builds the least-privilege plan with reasons and blast radius |
| **4 · Scripts** | Sandbox | Creates `revoke-plan.sql` and `rollback-plan.sql` |
| **5 · Safety Check** | Sandbox | Lints and simulates the planned changes |
| **6 · Ask** | `ask-user-question` | Shows the plan and asks for human approval |
| **7 · Execute** | `bouncer-revoker` MCP | Runs the approved destructive SQL |
| **8 · Verify** | `bouncer-reader` MCP | Checks the database after the change |

The actual project uses the sandbox for a **Python lint and simulation** because the sandbox has no network path to the database. It does not connect directly to PostgreSQL during the dry run.

The verified run reported:

```text
LINT PASSED: 7 statements
ROLLBACK VERIFIED
DRY RUN PASSED
```

before the destructive execution step.

---

# The Safety Flow

The safety design has several separate layers.

```text
              ┌──────────────────────┐
              │  READ-ONLY READER    │
              │  Investigate freely  │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  AGENT ANALYSIS      │
              │  Flags + context     │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  SANDBOX             │
              │  Lint + simulation   │
              └──────────┬───────────┘
                         │
                         ▼
                    ┌────────┐
                    │  STOP  │
                    └───┬────┘
                        │
                        ▼
              ┌──────────────────────┐
              │ HUMAN APPROVAL #1    │
              │ Yes / No             │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ SHIELDED REVOKER     │
              │ TrueForge approval   │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ HUMAN APPROVAL #2    │
              │ Harness approval     │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ ACTUAL REVOKE        │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ VERIFY WITH READER   │
              └──────────────────────┘
```

There are **two human gates** in the current implementation:

1. The agent asks the human whether to continue.
2. TrueForge's shield requires approval before the revoker tool runs.

The second gate is enforced by the harness rather than being only an instruction in the agent prompt.

---

# Architecture

The project has three main parts:

```text
                         ┌──────────────────────┐
                         │      TrueForge       │
                         │   Agent: bouncer     │
                         │                      │
                         │  Analysis            │
                         │  Approval checkpoints│
                         │  Sandbox             │
                         └──────────┬───────────┘
                                    │
                       ┌────────────┼────────────┐
                       │                         │
                       ▼                         ▼
            ┌────────────────────┐    ┌────────────────────┐
            │   BOUNCER READER   │    │  BOUNCER REVOKER   │
            │                    │    │                    │
            │ Restricted MCP    │    │ Unrestricted MCP   │
            │ Read-only path     │    │ Destructive path   │
            │ Port 8000          │    │ Port 8001          │
            └─────────┬──────────┘    └─────────┬──────────┘
                      │                         │
                      └──────────────┬──────────┘
                                     │
                                     ▼
                           ┌──────────────────────┐
                           │      PostgreSQL      │
                           │                      │
                           │ DB: company          │
                           │ Host port: 5433      │
                           │ Container port: 5432 │
                           └──────────────────────┘
```

All exposed service ports are bound to localhost in the current Compose setup.

## Components

| Component | Purpose |
|---|---|
| PostgreSQL | Demo database and access data |
| `bouncer-reader` | Restricted/read-only investigation path |
| `bouncer-revoker` | Access-changing path |
| TrueForge | Agent runtime, tools and approval handling |
| Sandbox | Safe Python analysis, linting and simulation |
| Bouncer agent | Connects the pieces and makes the review plan |

The reader and revoker are intentionally separate.

The agent can use the reader during investigation, but the destructive path is shielded.

---

# MCP Design

## Read-only Reader

The reader is used for investigation.

It reads:

- PostgreSQL roles
- database grants
- HR roster
- access usage
- service dependencies

It does not perform the final access-changing operation.

---

## Shielded Revoker

The revoker is used only when an approved plan needs to change database access.

In TrueForge, the revoker is configured so that **all of its tools require approval**.

This matters because the PostgreSQL MCP tools do not provide the annotations that TrueForge's default destructive-tool rule would rely on. The project therefore shields the entire revoker path with `@all`.

The revoker uses a powerful database connection because the demo includes removing superuser status from `test_final_2`.

That makes the approval boundary especially important:

```text
Agent
  │
  │ cannot directly execute destructive SQL
  ▼
Shielded Revoker
  │
  │ human approval required
  ▼
Database change
```

---

# Dry Run

The dry run is intentionally isolated from the database.

The sandbox cannot reach PostgreSQL.

Instead, Bouncer:

1. Collects the database state through the reader.
2. Generates the revoke plan.
3. Generates the rollback plan.
4. Runs a Python safety check in the sandbox.
5. Checks that only expected SQL operations are present.
6. Simulates the planned changes against the collected grant data.
7. Checks that held access is not removed.
8. Verifies that the rollback plan restores the original simulated state.
9. Prints:

```text
DRY RUN PASSED
```

This design came from an actual problem during development: the first dry-run attempt tried to reach the database from the sandbox and was blocked. Instead of bypassing the sandbox restriction, the team redesigned the dry run as a local simulation.

---

# Why This Is an Agent

A normal SQL script could use a fixed rule:

```text
unused > 90 days
        ↓
REVOKE
```

That is not enough for this problem.

Bouncer has to:

```text
Read multiple sources
       ↓
Understand employee status
       ↓
Inspect exact permissions
       ↓
Check usage
       ↓
Check ownership
       ↓
Check service dependencies
       ↓
Consider blast radius
       ↓
Create a plan
       ↓
Generate SQL
       ↓
Run a safety check
       ↓
Stop
       ↓
Ask for approval
       ↓
Use the shielded tool
       ↓
Verify the result
```

The agent is therefore doing more than running one fixed SQL cleanup query. It is using tools, combining information, making a contextual decision, preparing an action, and stopping at a defined safety boundary.

---

# What Makes Bouncer Different

The project is built around a few simple design choices:

### 1. Six flagging rules

There is no single "90 days = revoke" rule.

### 2. Exact permissions matter

Bouncer can remove one unnecessary permission without removing the user's other access.

### 3. HR status matters

Someone who left the company is handled differently from an active employee.

### 4. Service ownership matters

A service account can become risky when its owner leaves.

### 5. Dependencies matter

An apparently stale account may still be required by another system.

### 6. Blast radius matters

The plan explains what could be affected by removing access.

### 7. Dry run happens before execution

The generated revoke plan is checked before it can reach the destructive path.

### 8. Human approval is required

The agent does not make the final destructive decision alone.

### 9. Read and write paths are separated

Investigation and access-changing actions use different MCP paths.

### 10. The destructive path is shielded

TrueForge enforces an approval checkpoint before the revoker tool can run.

---

# Demo Flow

The demo is built around one important question:

> **What happens when access looks stale, but removing it could break something?**

The flow:

```text
┌────────────────────┐
│ 1. Explain Problem │
└─────────┬──────────┘
          ↓
┌────────────────────┐
│ 2. Scan Database   │
└─────────┬──────────┘
          ↓
┌────────────────────┐
│ 3. Apply 6 Rules   │
└─────────┬──────────┘
          ↓
┌─────────────────────────┐
│ 4. Review Flagged Access│
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│ 5. Check Dependencies   │
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│  svc_payments_sync      │
│  91 days unused         │
│  but critical job found │
│                         │
│          → HOLD         │
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│ 6. Generate Revoke Plan │
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│ 7. Sandbox Dry Run      │
│                         │
│  DRY RUN PASSED         │
└────────────┬────────────┘
             ↓
       ┌───────────┐
       │   STOP    │
       └─────┬─────┘
             ↓
┌─────────────────────────┐
│ 8. Agent asks human     │
│                         │
│ Yes, revoke / No, stop  │
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│ 9. TrueForge Shield     │
│                         │
│ Approval required       │
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│ 10. Execute Revoke      │
└────────────┬────────────┘
             ↓
┌─────────────────────────┐
│ 11. Verify with Reader  │
└─────────────────────────┘
```

The most important moment is not the SQL execution.

It is the moment where the agent **stops before the destructive action**.

---

# Example Walkthrough

## Case 1 — Employee left recently

```text
Employee left 1 month ago
        ↓
Rule 1 flags access
        ↓
Check permissions
        ↓
Check dependencies
        ↓
Create plan
        ↓
Human approval required
```

The employee does not need to have crossed 90 days for Rule 1 to flag the access.

---

## Case 2 — Stale service account with a dependency

```text
svc_payments_sync
91 days unused
        ↓
Rule 5 flags it
        ↓
Dependency found
        ↓
Critical quarterly job
        ↓
HOLD
        ↓
Do not revoke
```

---

## Case 3 — Active employee with one unused permission

```text
priya

Active employee
DELETE never used
        ↓
Review exact permission
        ↓
REVOKE DELETE only
        ↓
Keep other permissions
```

These cases show why Bouncer needs context before making an access-changing plan.

---

# Safety Rules

The current demo follows these safety rules:

- **Never revoke without explicit human approval.**
- Use the read-only reader for investigation.
- Use the shielded revoker for actual access changes.
- Run a safety check before real execution.
- Never touch the `postgres` role.
- Never modify the `governance` schema.
- Never modify application data.
- Use fictional/demo data.
- Keep local services restricted to localhost.
- Never expose API keys or secrets.

The project is designed so that the agent's ability to investigate is much broader than its ability to make changes.

---

# Project Structure

```text
bouncer-the-access-reviewer-agent/
│
├── README.md
├── CLAUDE.md
├── docker-compose.yml
│
├── db/
│   └── seed.sql
│
├── agent/
│   ├── instructions.md
│   └── mcp-config.md
│
├── scripts/
│   └── setup-trueforge.sh
│
└── demo/
```

The main files have these roles:

| File / Folder | Purpose |
|---|---|
| `README.md` | Project documentation |
| `docker-compose.yml` | Starts PostgreSQL and both MCP services |
| `db/seed.sql` | Creates the fictional database and governance data |
| `agent/instructions.md` | Source of truth for Bouncer's agent instructions |
| `agent/mcp-config.md` | MCP and shielding setup |
| `scripts/setup-trueforge.sh` | Registers MCP servers and creates/updates the Bouncer agent |
| `demo/` | Demo material |

---

# How to Run

> **Note:** The verified setup uses Docker Desktop, Node 22+, and an Anthropic API key configured in TrueForge. The complete end-to-end flow has been tested successfully on the team's demo setup.

## 1. Clone the repository

```bash
git clone https://github.com/arenforge/bouncer-the-access-reviewer-agent.git
cd bouncer-the-access-reviewer-agent
```

## 2. Start PostgreSQL and the MCP servers

```bash
docker compose up -d
```

This starts:

```text
PostgreSQL → 127.0.0.1:5433
Reader     → 127.0.0.1:8000
Revoker    → 127.0.0.1:8001
```

The database inside the container still uses PostgreSQL port `5432`. The host uses `5433` because port `5432` was already in use during development.

## 3. Start TrueForge

Open another terminal and run:

```bash
OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]' npx @truefoundry/trueforge
```

Leave this terminal running.

The local TrueForge UI is available at:

```text
http://localhost:8790
```

The localhost allowlist is required so TrueForge can register the local MCP endpoints.

## 4. Configure the model provider

For the first setup:

```text
TrueForge
   ↓
Settings
   ↓
Add model provider
   ↓
Use your own API key
```

Do not commit API keys or other secrets to the repository.

## 5. Create the Bouncer agent

Run:

```bash
./scripts/setup-trueforge.sh
```

This registers the MCP servers and creates or updates the `bouncer` agent using the project instructions.

## 6. Start a Bouncer run

In TrueForge:

```text
Agents
  ↓
bouncer
  ↓
New chat
```

Use:

```text
Review database access and propose a cleanup.
```

Bouncer should then move through its investigation, analysis, dry run, approval and verification flow.

---

# Useful Checks

Check the running containers:

```bash
docker compose ps
```

Connect directly to the demo database:

```bash
psql postgresql://postgres:postgres@localhost:5433/company
```

Or use:

```bash
docker exec -it bouncer-db psql -U postgres -d company
```

Check the reader endpoint:

```bash
curl -N --max-time 2 http://localhost:8000/sse
```

Check logs:

```bash
docker logs bouncer-reader
docker logs bouncer-db
docker logs bouncer-revoker
```

---

# Reset Between Demo Runs

A Bouncer run can actually change the demo database.

To reset the database back to the seeded state:

```bash
docker compose down -v && docker compose up -d
```

The `-v` removes the existing database volume so the seed data is created again.

Use this before another clean demo run.

---

# Stop the Project

```bash
docker compose down
```

---

# What Broke During Development

We kept the failures that changed the final design because they explain why the current architecture looks the way it does.

### 1. Compose and seed files initially contained shell commands

Some committed files contained the commands that had been used to generate them instead of only the actual configuration.

They were fixed manually.

### 2. PostgreSQL port conflict

A local PostgreSQL instance was already using port `5432`.

The Docker database was therefore exposed on:

```text
127.0.0.1:5433
```

while PostgreSQL itself still uses `5432` inside the container.

### 3. Seed data did not match the expected answer

Some active accounts had grants without matching usage rows.

That would make a correct agent flag them incorrectly.

The usage data was fixed so the seed matches the intended answer key.

### 4. MCP server binding problem

`postgres-mcp` was initially binding only to localhost inside its container.

That made the service unreachable through the Docker port mapping.

The final setup uses:

```text
--sse-host=0.0.0.0
```

inside the container while the Docker ports themselves are published only on `127.0.0.1`.

### 5. TrueForge blocked localhost MCP URLs

TrueForge's outbound URL protection initially blocked the local MCP endpoints.

The final startup uses:

```bash
OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]'
```

### 6. The first sandbox dry run failed

The first design expected the sandbox to reach PostgreSQL.

It could not.

Instead of bypassing the restriction, the team changed the design.

The final dry run uses:

```text
Reader collects database state
        ↓
Sandbox receives the data
        ↓
Python lint + simulation
        ↓
Rollback verification
        ↓
DRY RUN PASSED
```

This is now part of the safety design.

### 7. The default destructive-tool rule was not enough

The PostgreSQL MCP tools did not carry the annotations required by TrueForge's default destructive-tool approval rule.

The revoker was therefore configured with:

```text
require_approval_for_tools = ["@all"]
```

This makes the approval boundary explicit.

### 8. Localhost binding was tightened

The MCP services were initially published on all interfaces.

The final Compose setup binds them to:

```text
127.0.0.1
```

so the unauthenticated local demo endpoints are not exposed to the venue network.

---

# Verified End-to-End Result

The first full end-to-end run was completed successfully.

The verified sequence was:

```text
Reader scan
    ↓
Sandbox analysis
    ↓
Revoke + rollback scripts
    ↓
LINT PASSED
    ↓
ROLLBACK VERIFIED
    ↓
DRY RUN PASSED
    ↓
Agent asks for approval
    ↓
TrueForge shield asks for approval
    ↓
Approved
    ↓
Revoker executes
    ↓
Reader verifies
```

The final database state matched the expected answer key, including keeping `svc_payments_sync` because of its critical dependency.

---

# Limitations

Bouncer is a hackathon prototype.

Some important limitations are:

- The demo uses fictional/sample data.
- The quality of the decision depends on the HR, usage and dependency information available to the agent.
- A flag is not proof that access is unnecessary.
- Human review is intentionally required before destructive changes.
- Dependency information in the demo comes from the provided governance data.
- The project is not presented as a production access-governance system.

---

# Future Improvements

Possible next steps include:

- richer dependency discovery
- audit history for every decision
- better approval records
- scheduled access reviews
- support for more database systems
- more detailed policy configuration

These are future ideas, not claims about the current implementation.

---

# Why the Pause Matters

The most important design decision in Bouncer is not the revoke SQL.

It is the boundary before the revoke.

```text
            Agent can investigate
                    │
                    ▼
            Agent can prepare
            a revoke plan
                    │
                    ▼
            Agent can dry-run
                    │
                    ▼
                 ┌───────┐
                 │ STOP  │
                 └───┬───┘
                     │
              Human approval
                     │
                     ▼
              Shielded revoker
                     │
                     ▼
               Database change
```

The agent is allowed to do the work needed to understand the problem.

It is **not** allowed to silently complete the destructive part.

That is the line Bouncer is built around.

---

# AI Assistance

AI tools were used during development for brainstorming, debugging, documentation and improving explanations.

The team reviewed the suggestions and tested the final implementation.

The architecture, safety boundaries and project decisions were reviewed by the team, and the team can explain how the system works.

---

## Built for the TrueFoundry × Polaris Build Agents That Act Hackathon

**Bouncer — The Access Reviewer Agent**

> Review first. Understand the blast radius. Ask before changing anything.