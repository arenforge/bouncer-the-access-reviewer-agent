# Bouncer: 5-minute demo script

**Before you start:** `docker compose down -v && docker compose up -d`, TrueForge running, a new chat with the **bouncer** agent open, font size up, notifications off. Have `scripts/example-run/` and a backup recording ready in case the Wi-Fi or model is slow.

## 0:00 · The problem (30 s)

> "Every company has access nobody cleans up: people who left, service accounts whose owner left, a superuser someone made for a test. Cleaning it up is a job worth delegating, but a tool that can revoke access can also break production. So Bouncer's most important skill is knowing when *not* to."

## 0:30 · Start the run (15 s)

Type: **"Review database access and propose a cleanup."**

> "It's connected to a real Postgres database over MCP. Nothing here is mocked."

## 0:45 · Scan and analyse (45 s)

Point at **Phase 1**: "Reading live data via the bouncer-reader MCP server. This server is read-only; it physically can't change anything."

Point at **Phase 2**: "It writes Python and runs it in TrueForge's sandbox to apply six rules: left the company, unowned superuser, unowned role, orphaned service account, stale for 90+ days, never used."

## 1:30 · The report and the blast-radius catch (60 s)

Scroll the decision table and cards.

> "Five roles to revoke: two people who left, an intern account, an orphaned service account, and a test superuser nobody owns. For Priya, who's still here, it only removes the DELETE she has never used. That's least privilege, not all-or-nothing."

**Stop on `svc_payments_sync`:**

> "This one hasn't been used in 91 days, so a simple 90-day rule would delete it. Bouncer checked the dependency table: it runs the critical quarterly bank reconciliation, and the next run is soon. So its silence is expected. Revoking it would break payments. It's **held**, with a note on when to revisit it."

## 2:30 · The dry run in the sandbox (30 s)

Point at `DRY RUN PASSED`.

> "The sandbox has no network path to the database, by design. So the dry run lints the script (only REVOKE statements, never the held account), simulates it against the live grants, and proves the rollback script restores everything exactly."

## 3:00 · Where it stops (60 s), the most important part

The approval question appears.

> "Here it stops. It tells me what will be removed, what's held, the worst case, and how to undo it. I can revoke the safe changes and hold the risky ones, hold everything, stop, or edit individual roles."

Choose **"Revoke access for 5 roles now …, hold 1 for later"**.

TrueForge's shield prompt appears.

> "And this second prompt isn't the agent asking. It's the **harness**. The revoker tool is shielded, so TrueForge itself blocks every write until a human approves. Even if the model ignored its instructions, it couldn't get past this."

Approve.

## 4:00 · Verify (40 s)

> "Before and after for every role, a production health check confirming both dependent services still have their access, the held account untouched, and a rollback script if we got anything wrong."

## 4:40 · Close (20 s)

> "The agent does the tedious 90%: scanning, cross-checking, writing and testing the SQL. The one irreversible step stays with a human, twice. The pause is the product."

---

## Judge Q&A cheat sheet (everyone should be able to answer these)

- **Where did the code run?** In TrueForge's local sandbox (macOS seatbelt), for the analysis, script writing and dry run. Its network allowlist is only PyPI and GitHub, so it can't reach the database.
- **Why two MCP servers?** The reader runs in `restricted` (read-only) mode for investigation. The revoker can write, but every call is shielded (`require_approval_for_tools: ["@all"]`). The default `@destructive` rule wouldn't have caught it, because postgres-mcp's tools have no annotations.
- **What can the agent never do alone?** Change access on the live database. It also never touches the `postgres` role, the governance data or application data, and never runs anything other than the approved script.
- **What if you deny at the shield?** Nothing changes. We test this in `scripts/test-agent.py`.
- **Blast radius of your own agent?** The revoker is as powerful as a DBA, because removing superuser needs a superuser. That's exactly why it sits behind two human gates. Everything is bound to 127.0.0.1, so nothing is reachable from the venue Wi-Fi.
- **What if it's wrong?** `rollback-plan.sql` restores every change, and the dry run proves it before approval.
- **What's real vs. fake?** The database, MCP servers, sandbox and approvals are real. The company data is fictional.
- **What would production need?** Real IAM/identity sources instead of a seeded usage table, a narrower revoker role where possible, and a PR-based audit trail.
