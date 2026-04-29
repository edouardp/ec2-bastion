# On-Demand EC2 via Auto Scaling Group

A cost-saving setup for an on-demand Graviton instance that automatically
shuts down when you're not using it. Start it when you need it, and it
terminates itself after 5 minutes of inactivity (no SSM sessions or
Run Commands).

See [DESIGN.md](docs/DESIGN.md) for architecture diagrams, design decisions,
and security details.

## Quick start

```bash
# Deploy the stack
make deploy

# Start the instance and open an SSH shell
make ssh

# Or use SSM Session Manager instead
make ssm
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- `ec2-instance-connect:SendSSHPublicKey` IAM permission
- Session Manager plugin
  (`brew install --cask session-manager-plugin`)
- A VPC with at least one subnet (the instance needs internet
  access or VPC endpoints for SSM)
- `direnv` recommended — the `.envrc` sets `AWS_PROFILE` and
  `AWS_REGION`

## Files

| File                          | Description                          |
| ----------------------------- | ------------------------------------ |
| `cloudformation/`             | CloudFormation template              |
| `config/`                     | Per-environment YAML config          |
| `notebooks/`                  | Marimo notebook — start, run, connect    |
| `scripts/`                    | Shell scripts for all operations     |
| `docs/`                       | Design, troubleshooting, ADRs        |
| `Makefile`                    | All common operations                |
| `.pre-commit-config.yaml`     | Pre-commit hooks config              |
| `.rumdl.toml`                 | Markdown linter config               |

## Makefile targets

Run `make help` to see all targets.

| Target                    | Description                               |
| ------------------------- | ----------------------------------------- |
| `make help`               | Show all targets                          |
| `make deploy`             | Deploy/update the CloudFormation stack    |
| `make start-ec2`          | Start an instance                         |
| `make stop-ec2`           | Stop an instance                          |
| `make ensure-ec2`         | Start instance and wait until ready       |
| `make ssh`                | Interactive SSH shell over SSM            |
| `make ssm`                | Interactive SSM Session Manager shell     |
| `make test-ssh CMD="..."` | Run a command via SSH over SSM            |
| `make test-ssm CMD="..."` | Run a command via SSM Run Command         |
| `make status`             | Show system status snapshot               |
| `make lint`               | Run cfn-lint, shellcheck, rumdl           |
| `make teardown`           | Delete stack                              |

All targets present an interactive environment chooser. Targets
that can operate on both environments (deploy, status, teardown,
etc.) include a "both" option. Append `-prod` or `-staging` to
skip the chooser (e.g. `make deploy-prod`).

## Deploy

```bash
# Copy the example config and fill in your values
cp config/prod.yaml.example config/prod.yaml

# Deploy the stack
make deploy
```

Config file (`config/prod.yaml`):

```yaml
stack_name: ssm-on-demand
vpc_id: vpc-xxxxxxxxxxxxxxxxx
subnet_ids: subnet-xxx,subnet-yyy
environment: prod
sns_topic: ""  # optional SNS topic ARN
owner: your-name
```

Stack parameters (set via the config file):

| Parameter                    | Default      | Description                                          |
| ---------------------------- | ------------ | ---------------------------------------------------- |
| `VpcId`                      | —            | VPC for the instance                                 |
| `SubnetIds`                  | —            | Comma-separated subnet IDs                           |
| `Environment`                | `prod`       | Used in SSM parameter paths                          |
| `LatestAmiId`                | AL2023 arm64 | SSM parameter for the AMI                            |
| `BastionSourceSecurityGroupId` | (auto)     | Resolved from SSM; warns and skips if missing        |

## Marimo notebook

```bash
uv run marimo edit notebooks/ssm_on_demand.py
```

The notebook provides a UI to start the instance, run commands,
and manage connections.

## Cost

- **Instance off**: ~$0 (Lambda invocations from EventBridge
  well within free tier)
- **Instance on**: ~$0.0042/hr for `t4g.nano` on-demand.
  About $0.70/month at 8 hrs/day, 5 days/week

## Customisation

- Change `t4g.nano` to `t4g.micro` (1 GB) or `t4g.small` (2 GB)
  in the launch template
- The 5-minute grace period and check interval are in the
  `StopIfIdleFn` Lambda code and the EventBridge
  `rate(5 minutes)` rule
- To use Amazon Linux 2 instead of AL2023, change the
  `LatestAmiId` default to
  `/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-arm64-gp2`

## Monitoring and debugging

Run `make status` for a full snapshot of the system. See
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed debugging
commands and common issues.

## Teardown

```bash
make teardown
```

This deletes the CloudFormation stack.
