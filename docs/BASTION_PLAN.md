# Plan: On-Demand Bastion for Private Resources

## Goal

Extend the on-demand EC2 solution into a bastion host that
provides secure access to private resources (e.g., Aurora
PostgreSQL in a private subnet) via port forwarding — either
through SSM Session Manager or SSH over SSM.

## Use Cases

1. Connect a local SQL client (DataGrip, psql, DBeaver) to
   an Aurora PostgreSQL cluster in a private subnet
2. Access any TCP service in a private subnet (Redis,
   OpenSearch, internal APIs)
3. Temporary access — bastion starts on demand, shuts down
   when idle, no persistent attack surface

## Architecture

```mermaid
graph TB
    User([Local machine<br/>psql / DataGrip])

    subgraph VPC
        subgraph "Public Subnet"
            Bastion[Bastion EC2<br/>t4g.nano<br/>SSM + SSH]
        end

        subgraph "Private Subnet"
            Aurora[(Aurora PostgreSQL<br/>port 5432)]
            Redis[(ElastiCache<br/>port 6379)]
        end
    end

    User -->|"SSM port forward<br/>or SSH -L"| Bastion
    Bastion -->|"TCP 5432"| Aurora
    Bastion -->|"TCP 6379"| Redis
```

## Connection Methods

### Option A: SSM Session Manager Port Forwarding

```bash
aws ssm start-session \
  --target i-xxx \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["aurora-cluster.xxx.rds.amazonaws.com"],"portNumber":["5432"],"localPortNumber":["5432"]}'
```

Then connect locally: `psql -h localhost -p 5432`

Pros:

- No SSH keys needed
- No inbound ports
- AWS-native, auditable via CloudTrail

Cons:

- Requires the Session Manager plugin
- Each port forward is a separate SSM session
- Some tools don't work well with localhost-only binds

### Option B: SSH Port Forwarding over SSM

```bash
ssh -i key.pem \
  -o ProxyCommand="aws ssm start-session --target %h ..." \
  -L 5432:aurora-cluster.xxx.rds.amazonaws.com:5432 \
  ec2-user@i-xxx
```

Pros:

- Multiple port forwards in one session
- Familiar SSH tooling
- Works with all clients

Cons:

- Requires SSH key management (already solved)

### Recommendation

Support both. SSM port forwarding for quick one-off access,
SSH for multi-port or long-running sessions. Add Makefile
targets for common patterns.

## Decisions to Make

### 1. Networking: Where does the bastion live?

The bastion needs to reach private resources. Options:

a) **Public subnet (current setup)** — bastion has internet
   access for SSM. To reach private subnets, the VPC just
   needs routing between subnets (default in most VPCs).
   The bastion's security group is the key control.

b) **Private subnet + VPC endpoints** — bastion has no public
   IP. Needs VPC endpoints for SSM (`ssm`, `ssmmessages`,
   `ec2messages`). More secure but more infrastructure to
   manage and ~$22/month for 3 endpoints.

c) **Private subnet + NAT Gateway** — bastion uses NAT for
   SSM. NAT Gateway costs ~$32/month + data transfer.

**Recommendation:** Stay in a public subnet. The bastion has
no inbound ports (security group has zero ingress rules), so
the attack surface is the same as a private subnet. The only
difference is the public IP, which nothing can connect to.

### 2. Security Groups: How does the bastion access RDS?

Options:

a) **IP-based rules** — RDS security group allows the
   bastion's private IP. Problem: the IP changes every time
   the bastion launches.

b) **Security group reference** — RDS security group allows
   inbound from the bastion's security group. This is the
   standard AWS pattern. The bastion SG ID is stable across
   instance launches.

c) **Tag-based security groups** — RDS security group
   references a "tag" security group (e.g., `bastion-access`)
   that's attached to the bastion. Multiple resources can
   share this tag SG.

**Recommendation:** Option C — create a `bastion-access`
security group with no rules of its own. Attach it to the
bastion EC2 (second SG on the network interface). RDS and
other private resources allow inbound from `bastion-access`.
This decouples the bastion's own SG from the access grants.

```mermaid
graph LR
    subgraph "Bastion EC2"
        SG1[bastion-sg<br/>no ingress]
        SG2[bastion-access<br/>tag SG, no rules]
    end

    subgraph "Aurora"
        RDSSG[aurora-sg<br/>allow 5432 from bastion-access]
    end

    SG2 -.->|referenced by| RDSSG
```

### 3. What changes in the CloudFormation template?

- Add a second security group (`BastionAccessSG`) with no
  rules — this is the "tag" SG
- Attach both SGs to the launch template's network interface
- Export `BastionAccessSG` as a stack output so other stacks
  can reference it
- The RDS stack (separate) adds an ingress rule:
  `allow TCP 5432 from BastionAccessSG`

### 4. Subnet placement: same subnets as RDS?

The bastion doesn't need to be in the same subnet as RDS —
just the same VPC. Security group references work across
subnets. Keep the bastion in public subnets (for SSM
internet access) and RDS in private subnets.

### 5. DNS resolution for RDS endpoints

The bastion needs to resolve the RDS endpoint hostname
(e.g., `my-cluster.cluster-xxx.ap-southeast-2.rds.amazonaws.com`).
This works automatically if the bastion is in the same VPC —
VPC DNS resolution handles it.

### 6. Port forwarding scripts and Makefile targets

New scripts needed:

```text
scripts/port-forward-ssm.sh HOST PORT [LOCAL_PORT]
scripts/port-forward-ssh.sh HOST PORT [LOCAL_PORT]
```

New Makefile targets:

```text
make forward-db     # Forward Aurora PostgreSQL (5432)
make forward-redis  # Forward ElastiCache Redis (6379)
make forward PORT=5432 HOST=aurora.xxx.rds.amazonaws.com
```

These would call `ensure-ec2-running.sh` first, then set up
the tunnel.

### 7. Configuration: how to specify target hosts/ports?

Options:

a) **Hardcoded in Makefile** — simple but inflexible
b) **Stack parameters/outputs** — RDS endpoint exported from
   the database stack, imported here
c) **SSM parameters** — store target endpoints in Parameter
   Store (e.g., `/on-demand-ec2/prod/targets/db`)
d) **Command-line arguments** — `make forward HOST=x PORT=y`

**Recommendation:** Command-line arguments with Makefile
defaults for common targets. The defaults can reference SSM
parameters or be hardcoded. Start simple (hardcoded), move
to SSM parameters if you add more targets.

### 8. Idle detection with port forwarding

Current idle checker looks for SSM sessions and Run Commands.
Port forwarding creates SSM sessions (both methods), so the
bastion stays alive while a tunnel is open. No changes needed
to the Lambda.

However, SSM Session Manager has its own timeouts configured
in the `SSM-SessionManagerRunShell` document or via console
(Session Manager → Preferences):

- **Idle timeout** (default 20 min): terminates sessions with
  no input. This is problematic for port forwarding — a tunnel
  with no active queries looks "idle" to SSM even though it's
  intentionally open. Set this high (60 min) or disable it for
  port-forwarding use cases.
- **Max session duration** (default none, max 1440 min / 24h):
  forcibly terminates sessions after this time regardless of
  activity. Consider setting this as a safety net to prevent
  forgotten tunnels from keeping the bastion alive indefinitely.

The instance-level idle checker we built is separate — it
checks for the *existence* of sessions, not whether they're
active. So even an "idle" SSM session keeps the instance alive.

**Recommendation:** Set max session duration to 8–12 hours as
a safety net. For idle timeout, either disable it or set it to
60 minutes. If a tunnel is killed by idle timeout, the user
just re-runs `make forward-db`.

### 9. Multiple simultaneous tunnels

SSH supports multiple `-L` flags in one session. SSM port
forwarding is one tunnel per session. For multi-port access,
SSH is better. The script could accept multiple HOST:PORT
pairs.

### 10. Client-side tooling

For PostgreSQL specifically, the user needs:

- `psql` or a GUI client
- Connection string: `postgresql://user:pass@localhost:5432/dbname`
- Credentials: from Secrets Manager, SSM, or IAM auth

Consider a `make db-shell` target that sets up the tunnel
AND runs psql in one command.

## Implementation Order

1. Add `BastionAccessSG` to the CloudFormation template
2. Export it as a stack output
3. Attach it to the launch template (second SG)
4. Create `port-forward-ssm.sh` and `port-forward-ssh.sh`
5. Add Makefile targets (`forward`, `forward-db`)
6. Update the RDS stack to allow inbound from
   `BastionAccessSG` (separate repo/stack)
7. Test end-to-end: `make forward-db` → `psql -h localhost`
8. Document in README and DESIGN.md
9. ADR for the bastion-access security group pattern

## What NOT to Change

- Instance type (t4g.nano is fine — port forwarding is
  just TCP proxying, minimal CPU/memory)
- Idle detection (SSM sessions already cover tunnels)
- SSH key rotation (unchanged)
- Boot hardening (unchanged)

## Cost Impact

Zero additional cost. The `BastionAccessSG` is a free
resource. The bastion instance cost is unchanged. The only
new cost would be data transfer through the tunnel, which
is negligible for database queries.

## Hardening: Tunnel-Only SSH User

If the bastion is primarily used for port forwarding, we can
reduce the attack surface by creating a dedicated user with
no shell access.

### Setup (in user data)

```bash
# Create tunnel user with no shell
useradd -m -s /usr/sbin/nologin tunnel

# Restrict to port forwarding only in sshd_config
cat >> /etc/ssh/sshd_config <<'EOF'
Match User tunnel
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
    PermitTTY no
EOF
systemctl restart sshd

# Load SSH public keys for tunnel user too
TUNNEL_SSH_DIR=/home/tunnel/.ssh
mkdir -p "$TUNNEL_SSH_DIR"
cp /home/ec2-user/.ssh/authorized_keys "$TUNNEL_SSH_DIR/"
chmod 600 "$TUNNEL_SSH_DIR/authorized_keys"
chown -R tunnel:tunnel "$TUNNEL_SSH_DIR"
```

### Client usage

```bash
ssh -N -L 5432:aurora.xxx.rds.amazonaws.com:5432 \
  -i key.pem \
  -o ProxyCommand="aws ssm start-session ..." \
  tunnel@i-xxx
```

`-N` means no remote command — just port forwarding. Combined
with `ForceCommand /bin/false` and `PermitTTY no` on the
server, the user literally cannot get a shell even if they
try.

### Two-user model

| User | Shell | Purpose |
|------|-------|---------|
| `ec2-user` | `/bin/bash` | Full shell access (admin) |
| `tunnel` | `/usr/sbin/nologin` | Port forwarding only |

Both users share the same SSH public keys (from Parameter
Store). The Makefile targets would use the appropriate user:

- `make ssh` → `ec2-user` (full shell)
- `make forward-db` → `tunnel` (port forward only)

### Why this matters

- If the `tunnel` user's key is compromised, the attacker
  can only forward ports — no shell, no command execution
- `ForceCommand /bin/false` ensures even `ssh tunnel@host
  'cat /etc/passwd'` is rejected
- The `ec2-user` remains available for admin/debug access
- Same key pair for both users keeps rotation simple

## Security Considerations

- The bastion never stores database credentials — it's
  just a TCP tunnel
- RDS credentials should come from Secrets Manager or
  IAM database authentication, not hardcoded
- The `bastion-access` SG pattern means revoking bastion
  access to all resources is a single SG detach
- CloudTrail logs all SSM sessions including port forwards
- The bastion is still ephemeral — no persistent state,
  no risk of credential accumulation
