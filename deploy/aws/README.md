# Deploying Bouncer on AWS (safely)

One EC2 instance runs exactly what runs on a laptop: Postgres + the two MCP servers (docker compose) and TrueForge. The **security group has no inbound rules and there is no SSH key.** Nothing is reachable from the internet. You reach TrueForge through an encrypted AWS Systems Manager tunnel, authenticated by your AWS login.

Why so locked down: TrueForge standalone has no login, and the revoker can run SQL as a superuser. On a public port, anyone could approve a revoke.

```
your laptop ──(AWS SSM tunnel, IAM-authenticated)──▶ EC2 (no inbound ports)
  http://localhost:8790                               TrueForge on 127.0.0.1:8790
                                                      db / reader / revoker on 127.0.0.1
```

## Prerequisites (on your laptop)

- AWS CLI v2 and the Session Manager plugin: `brew install awscli && brew install --cask session-manager-plugin`
- AWS credentials with permission to create an EC2 instance, a security group and an IAM role: `aws configure` (or `aws configure sso`)
- Your own Anthropic API key (entered in the TrueForge UI, never in this repo)

## Steps

```bash
./deploy/aws/deploy.sh          # creates the instance (default: m7i-flex.large in ap-south-1; Free Tier eligible)
./deploy/aws/status.sh          # wait until "setup: done" and "trueforge api: up" (about 5–8 min)
./deploy/aws/connect.sh         # keep running; open http://localhost:8790
```

In the TrueForge UI (through the tunnel): **Settings → add a model provider with your own API key.** Then:

```bash
./deploy/aws/update-agent.sh    # registers the MCP servers and creates the bouncer agent
```

Open **Agents → bouncer** and run it as usual.

## Changing the agent after deployment

Edit `agent/instructions.md`, commit and push, then run `./deploy/aws/update-agent.sh`. The next new chat uses the new instructions. No restart is needed.

## Other commands

```bash
./deploy/aws/server.sh "cd ~/bouncer && docker compose down -v && docker compose up -d"   # reset the demo DB
./deploy/aws/server.sh "cd ~/bouncer && ./scripts/check-state.sh untouched"                # check DB state
./deploy/aws/teardown.sh        # delete everything and stop all charges
```
