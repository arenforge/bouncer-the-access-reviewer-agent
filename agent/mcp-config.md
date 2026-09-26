# MCP server setup

Two instances of [crystaldba/postgres-mcp](https://hub.docker.com/r/crystaldba/postgres-mcp) point at the same database with different access modes.

| Name | Port | Access mode | In TrueForge |
| --- | --- | --- | --- |
| `bouncer-reader` | 8000 | `restricted` (read-only) | Default approval (`@destructive`) |
| `bouncer-revoker` | 8001 | `unrestricted` | **Shielded: every tool requires approval (`@all`)** |

## 1. Start the containers

The DB must be up first (`docker compose up -d`, host port **5433**).

```
docker run -d --name bouncer-reader -p 8000:8000 \
  -e DATABASE_URI=postgresql://postgres:postgres@host.docker.internal:5433/company \
  crystaldba/postgres-mcp --access-mode=restricted --transport=sse --sse-host=0.0.0.0

docker run -d --name bouncer-revoker -p 8001:8000 \
  -e DATABASE_URI=postgresql://postgres:postgres@host.docker.internal:5433/company \
  crystaldba/postgres-mcp --access-mode=unrestricted --transport=sse --sse-host=0.0.0.0
```

Gotchas we hit:
- postgres-mcp only supports `stdio` and `sse` (no streamable HTTP), so we use SSE.
- `--sse-host=0.0.0.0` is required. The default binds to `localhost` inside the container, so the port mapping can't reach it.
- Check with `curl -N --max-time 2 http://localhost:8000/sse`, which should print `event: endpoint`.

## 2. Start TrueForge so it can reach localhost

TrueForge's SSRF guard blocks `localhost` URLs by default (`Outbound URL blocked for host "localhost"`). Allow exactly that one host:

```
OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]' npx @truefoundry/trueforge
```

Everything else stays blocked. Standalone TrueForge only listens on localhost.

## 3. Register the servers

UI: **Settings → Connectors → add remote server**. Or with the API:

```
curl -X POST http://localhost:8790/api/v1/settings/mcp-servers -H 'content-type: application/json' \
  -d '{"manifest":{"type":"remote","name":"bouncer-reader","url":"http://localhost:8000/sse","description":"Read-only access to the company Postgres database. Use for all investigation."}}'

curl -X POST http://localhost:8790/api/v1/settings/mcp-servers -H 'content-type: application/json' \
  -d '{"manifest":{"type":"remote","name":"bouncer-revoker","url":"http://localhost:8001/sse","description":"Write access to the company Postgres database. Use ONLY to execute an approved revoke script."}}'
```

## 4. Attach to the agent and shield the revoker

In **Build Agent → MCP Servers → Select MCP Tools**, add both servers. For `bouncer-revoker`, mark **every tool as Shielded**. In the agent API this is:

```json
{ "name": "bouncer-revoker", "require_approval_for_tools": ["@all"] }
```

The default is `["@destructive"]`, which isn't enough: a `REVOKE` sent through `execute_sql` might not be classed as destructive. `@all` guarantees the harness pauses before every revoker call.
