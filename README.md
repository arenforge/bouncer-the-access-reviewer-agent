# Bouncer: The Access Reviewer Agent

> My AI agent's job: kick people out. Its most important skill: not doing it.

Bouncer is an agent that reviews database access and finds access that may no longer be needed.

The important part is that Bouncer does not follow one simple rule like:

```text
unused for 90 days = revoke
```

Instead, it first flags suspicious access, checks the reason behind the flag, looks at the exact permissions, checks service dependencies and possible blast radius, and then prepares a safe action plan.

Before any real access is removed, Bouncer stops and asks a human for approval.

---

## The Problem

Database access can stay behind even when it is no longer needed.

For example:

- An employee may have left the company but still have database access.
- A database role may not belong to anyone in the HR roster.
- A superuser role may be unowned.
- A service account may belong to an employee who has already left.
- A permission may not have been used for a long time.
- A permission may never have been used.

But removing access automatically can also cause problems.

A service account may look unused while an important scheduled job still depends on it.

So the real problem is not only:

> "Which access looks old?"

It is:

> "Which access needs review, and is it actually safe to remove?"

That is what Bouncer is built to handle.

---

## What Bouncer Does

Bouncer works in two stages.

### Stage 1: Flagging

Bouncer applies six rules to find database access that needs review.

### Stage 2: Decision

After something is flagged, Bouncer checks the complete context and classifies it as:

- **KEEP**
- **REVOKE**
- **HOLD**

A flag does **not** automatically mean revoke.

This distinction is important because stale or unused access can still be required by another service.

---

# How Bouncer Flags Access

Bouncer currently uses six flagging rules.

## 1. Left the Company

```text
employment_status == 'left'
```

If a person is marked as `left` in the HR roster, their database grants are flagged for review.

Examples:

- `intern_2023`
- `ravi`

An employee does not need to be gone for 90 days for this rule to trigger.

For example, if someone left one month ago, Rule 1 can still flag their database access.

The 90-day condition belongs to the stale-access rule, not the employee-left rule.

---

## 2. Unowned Superuser

```text
rolsuper == True
AND role is not in the HR roster
```

This rule looks for PostgreSQL roles that have superuser status but do not have a matching person in the HR roster.

Example:

```text
test_final_2
```

A superuser role has much broader database privileges, so an unowned superuser role needs review.

---

## 3. Unowned Role

This rule checks whether a database role has no matching entry in the HR roster.

```text
role not in roster
```

In the current demo data, the main example is:

```text
test_final_2
```

It is also caught by the unowned-superuser rule.

---

## 4. Orphaned Service Account

A service account can belong to a person even though the account itself is not an employee account.

Bouncer checks the owner of the service account against the HR roster.

If the account is a service account and its owner has left, it is flagged.

Example:

```text
svc_legacy_reports
        |
        └── owner = ravi
```

Ravi has left the company, so the service account is considered orphaned and is flagged for review.

---

## 5. Stale Access

Bouncer also checks when access was last used.

The stale rule is:

```text
(today - last_used).days > 90
```

For the demo:

```text
today = 2026-09-26
```

Examples from the demo data:

| Account | Approx. unused time |
|---|---:|
| `intern_2023` | 412–430 days |
| `ravi` | 205–210 days |
| `svc_legacy_reports` | 97 days |
| `svc_payments_sync` | 91 days |

More than 90 days without use is a **stale-access signal**.

It is not an automatic revoke decision.

---

## 6. Never Used

Bouncer also looks for permissions that have never been used.

The condition is:

```text
no usage row
OR
last_used IS NULL
```

Examples:

- Priya's `DELETE` permission on `payments`
- Unused privileges of `svc_legacy_reports`

Again, this only means that the access needs review.

It does not mean the complete role should automatically be deleted.

---

# What Information Bouncer Checks

Bouncer combines information from different parts of the access picture.

### HR Roster

Used to check whether a person is still with the company.

### Database Roles

Used to see which roles exist in PostgreSQL.

### Database Grants

Used to understand exactly what permissions a role has.

Examples include:

```text
SELECT
INSERT
UPDATE
DELETE
```

### Superuser Status

Used to identify roles with PostgreSQL superuser privileges.

### Usage History

Used to find when access was last used.

### Never-Used Permissions

Used to identify permissions with no usage record or a `NULL` last-used value.

### Service-Account Ownership

Used to check whether a service account belongs to someone who has left.

### Service Dependencies

Used to check whether another service or scheduled job depends on an account.

### Blast Radius

Used to understand what could be affected if access is removed.

---

# From Flag to Decision

After an account or permission is flagged, Bouncer does not immediately revoke it.

It looks at the complete context.

| Decision | Meaning |
|---|---|
| **KEEP** | The access appears valid or is still being used. |
| **REVOKE** | The access is flagged, appears unnecessary, and no blocking dependency was found. |
| **HOLD** | The access looks suspicious, but removing it may affect a service or needs more review. |

### KEEP

Examples:

- `alice`
- `bob`
- `svc_etl`

These accounts are active or recently used.

### REVOKE

Example:

```text
ravi
```

Ravi has left the company and his database access is no longer needed.

### HOLD

Example:

```text
svc_payments_sync
```

It looks stale, but another important service depends on it.

HOLD is not a failure.

It is a safety decision.

---

# Important Examples

## `test_final_2`

Facts:

- Superuser
- No usage rows
- Not present in the HR roster

Expected decision:

```text
REVOKE
```

The demo SQL idea is:

```sql
ALTER ROLE test_final_2 NOSUPERUSER NOLOGIN;
```

The important point is that the role is both highly privileged and not owned by anyone in the HR roster.

---

## `intern_2023`

Facts:

- Left the company on `2025-07-28`
- Left around 425 days ago
- Has `SELECT`, `INSERT`, and `UPDATE` on `payments`
- Last used around 412–430 days ago

Expected decision:

```text
REVOKE
```

---

## `ravi`

Facts:

- Left the company on `2026-03-10`
- Left around 200 days ago
- Has `SELECT` access on `customers` and `payments`
- Last used around 205–210 days ago

Expected decision:

```text
REVOKE
```

This is also a good example of why HR status matters separately from the 90-day stale rule.

---

## `svc_legacy_reports`

Facts:

- Service account
- Owner is `ravi`
- Ravi has left
- Unused for 97 days
- No dependencies

Expected decision:

```text
REVOKE
```

The account is both stale and orphaned, and there is no dependency blocking its removal.

---

## `priya`

Facts:

- Active employee
- Has `DELETE` permission on `payments`
- The `DELETE` permission was never used

Expected decision:

```text
REVOKE DELETE ONLY
```

Bouncer should not remove all of Priya's database access just because one permission is unused.

This shows why Bouncer looks at the exact permission instead of treating the complete role as one block.

---

# The Important Case: `svc_payments_sync`

This is the main example that shows why Bouncer is not just a 90-day cleanup script.

The account has not been used for 91 days.

So Rule 5 flags it:

```text
svc_payments_sync
        ↓
unused for 91 days
        ↓
stale rule
        ↓
FLAG
```

But Bouncer then checks dependencies.

It finds that a critical quarterly:

```text
payments-reconciliation
```

job depends on this service account.

So the decision becomes:

```text
svc_payments_sync
        ↓
91 days unused
        ↓
Rule 5 flags it
        ↓
Dependency found
        ↓
Possible blast radius
        ↓
HOLD
```

Bouncer does **not** revoke it.

This is important because it shows:

```text
stale ≠ automatically revoke
```

The agent first checks whether removing the access could cause a problem.

---

# Demo Answer Key

| Account | Important evidence | Expected decision |
|---|---|---|
| `test_final_2` | Unowned superuser, no usage | **REVOKE** |
| `intern_2023` | Left company, stale access | **REVOKE** |
| `ravi` | Left company, stale access | **REVOKE** |
| `svc_legacy_reports` | Owner left, stale, no dependency | **REVOKE** |
| `priya` | Unused `DELETE` permission | **REVOKE DELETE ONLY** |
| `svc_payments_sync` | Stale but critical dependency exists | **HOLD** |
| `alice` | Active and recently used | **KEEP** |
| `bob` | Active and recently used | **KEEP** |
| `svc_etl` | Active and recently used | **KEEP** |

---

# How the Agent Works

The complete Bouncer flow is:

```text
1. Scan database access
          ↓
2. Read HR roster
          ↓
3. Read usage history
          ↓
4. Apply six flagging rules
          ↓
5. Inspect exact permissions
          ↓
6. Check service ownership
          ↓
7. Check dependencies
          ↓
8. Evaluate possible blast radius
          ↓
9. Create KEEP / REVOKE / HOLD plan
          ↓
10. Generate revoke SQL
          ↓
11. Dry run
          ↓
12. STOP
          ↓
13. Ask for human approval
          ↓
14. If approved → Shielded MCP Revoker
          ↓
15. Verify result
```

The important part is that the agent does not go directly from:

```text
FLAG
```

to:

```text
REVOKE
```

There is a review and safety step in between.

---

# Human Approval

Bouncer does not perform the final destructive action immediately after deciding that access should be removed.

The agent first:

1. Investigates the access.
2. Prepares the action plan.
3. Generates the revoke SQL.
4. Performs a dry run.
5. Shows what it wants to change.
6. Stops.
7. Asks the human for explicit approval.

Only after the human says yes should the actual revoke be executed through the shielded revoker.

> **The agent can recommend a revoke, but it cannot complete the destructive action without human approval.**

This approval is for the actual revocation. It does not mean that every individual permission needs a separate approval.

---

# Dry Run

Before making the real change, Bouncer tests the planned SQL inside a transaction.

The basic idea is:

```sql
BEGIN;

-- planned revoke statements

ROLLBACK;
```

The purpose is to test the planned changes without permanently applying them.

After the dry run, Bouncer stops and waits for human approval.

---

# MCP Architecture

Bouncer separates investigation from destructive actions.

## Read-only MCP Reader

The reader is used for investigation.

It provides the information Bouncer needs to review:

- database roles
- permissions
- usage
- HR-related information
- governance information

The reader should not be used to make the final access changes.

## Shielded MCP Revoker

The revoker is used for actual access-changing operations.

It is separated from the reader so the destructive operation is not treated like a normal read operation.

The agent reaches the revoker only after the required approval step.

---

# Architecture

```text
                         Human
                           |
                           v
                    TrueForge Agent
                           |
              +------------+------------+
              |                         |
              v                         v
      Read-only MCP Reader       Approval Checkpoint
              |                         |
              v                         |
          PostgreSQL                    |
              |                         |
       +------+------+                  |
       |      |      |                  |
      HR    Usage  Grants               |
       |      |      |                  |
       +------+------+                  |
              |                         |
              v                         |
       Six Flagging Rules               |
              |                         |
              v                         |
   Permission / Ownership /             |
   Dependency Check                     |
              |                         |
              v                         |
       KEEP / REVOKE / HOLD             |
                                        |
                              Explicit Human YES
                                        |
                                        v
                              Shielded MCP Revoker
                                        |
                                        v
                                    PostgreSQL
                                        |
                                        v
                                    Verification
```

---

# Why This Is an Agent

A normal SQL script could use a fixed rule such as:

```text
unused > 90 days → revoke
```

Bouncer has to do more than that.

It has to:

- inspect multiple sources
- apply multiple rules
- understand employee status
- check service-account ownership
- inspect exact permissions
- identify stale access
- identify never-used permissions
- check dependencies
- consider possible blast radius
- create an action plan
- generate SQL
- dry-run the plan
- stop for approval
- call the destructive tool only after approval
- verify the result

The agent is not only generating text.

It reaches a real database environment, investigates the data, prepares an action, and is intentionally stopped before the irreversible part.

---

# What Makes Bouncer Different

Bouncer is built around a few important choices.

### 1. Six flagging rules

It does not depend only on the 90-day stale rule.

### 2. HR status matters

Someone who has left the company can be flagged even if they left recently.

### 3. Exact permissions matter

Bouncer can identify a specific permission that should be removed instead of removing everything.

### 4. Superuser status matters

An unowned superuser role gets special attention.

### 5. Usage matters

Bouncer checks when access was last used and whether it was ever used.

### 6. Service ownership matters

A service account whose owner has left can be flagged as orphaned.

### 7. Dependencies matter

A stale account can still be required by another service.

### 8. Blast radius matters

Bouncer considers what could be affected if the access is removed.

### 9. Partial revoke is possible

For example:

```text
Priya
   ↓
unused DELETE
   ↓
REVOKE DELETE
```

instead of removing all access.

### 10. Dry run happens first

The planned SQL is tested before the real change.

### 11. Human approval is required

The agent stops before the destructive action.

### 12. Read and write paths are separated

The read-only MCP reader and shielded MCP revoker have different roles.

---

# Safety Design

Bouncer follows these safety rules:

- Never revoke without explicit human approval.
- Use the read-only reader for investigation.
- Use the shielded revoker for actual access changes.
- Dry-run planned changes before real execution.
- Never touch `postgres`.
- Never modify the governance schema.
- Never modify application data.
- Use fictional/demo data.
- Keep local services restricted to localhost.
- Never expose API keys or secrets.

The goal is not to make the agent completely autonomous.

The goal is to let it do the investigation and preparation while keeping the irreversible action behind a human checkpoint.

---

# TrueForge

Bouncer runs through TrueForge as the agent harness.

For this project, the important parts are:

- agent execution
- MCP tool access
- approval checkpoints
- sandbox or safe execution where actually used

TrueForge provides the execution layer around the agent so Bouncer can reach tools and stop at the approval point instead of only returning a text recommendation.

The important part of the demo is that the approval step is part of the agent workflow.

---

# Demo Flow

The demo follows this path:

```text
Problem
   ↓
Scan
   ↓
Six flagging rules
   ↓
Review flagged access
   ↓
Dependency / blast-radius check
   ↓
svc_payments_sync → HOLD
   ↓
Generate revoke plan
   ↓
Dry run
   ↓
WAITING FOR APPROVAL
   ↓
Human says YES
   ↓
Shielded revoker
   ↓
Verification
```

The most important moment is when Bouncer **stops and waits for approval** before the real access-changing operation.

---

# Example Walkthrough

## Example 1: Employee Left Recently

Suppose an employee left one month ago.

```text
HR status = left
        ↓
Rule 1 flags the access
        ↓
Review permissions
        ↓
Check dependencies
        ↓
Create plan
        ↓
Human approval required
```

The employee does not need to have crossed 90 days for Rule 1 to flag the access.

---

## Example 2: Stale Service Account With Dependency

```text
svc_payments_sync
        ↓
91 days unused
        ↓
Rule 5 flags it
        ↓
Dependency found
        ↓
HOLD
```

The account is not revoked because another important job depends on it.

---

## Example 3: Unused Permission

```text
priya
   ↓
Active employee
   ↓
DELETE never used
   ↓
Review exact permission
   ↓
REVOKE DELETE only
```

The rest of Priya's access is not removed just because one permission was unused.

---

# Project Structure

The repository currently contains these main areas:

```text
agent/
db/
demo/
scripts/
```

The exact files and final run commands may change as the team completes the implementation.

---

# How to Run

The final run instructions will be added after the team verifies the complete setup.

Known setup components include:

- PostgreSQL
- Docker
- database: `company`
- PostgreSQL port: `5432`
- MCP reader: port `8000`
- MCP revoker: port `8001`
- TrueForge
- model provider configured through TrueForge

No unverified commands are included here.

---

# Limitations

Bouncer is a hackathon prototype, not a production access-governance system.

Some limitations are:

- The demo uses fictional/sample data.
- The system depends on the quality of the HR, usage and dependency information available to it.
- A flag does not prove that access is unnecessary.
- Human review is intentionally required before destructive changes.
- Dependency information may not cover every possible real-world relationship.

The system is designed to help with access review, not to remove the need for human responsibility.

---

# Future Improvements

Some possible next steps are:

- richer dependency discovery
- audit history for every decision
- better approval records
- scheduled access reviews
- support for more database systems
- more detailed policy configuration

---

# AI Assistance

AI tools were used during development for brainstorming, debugging, documentation and improving explanations.

The team reviewed the suggestions and tested the final implementation.

The team can explain the architecture and the decisions made in the project.