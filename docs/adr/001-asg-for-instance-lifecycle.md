# 001: ASG for Instance Lifecycle

**Status:** Accepted
**Date:** 2026-04-12

## Context

We need an on-demand EC2 instance that starts quickly and shuts
down automatically when idle. Options: direct EC2 start/stop,
ASG with min=0/max=1, or Fargate/ECS.

## Decision

Use an Auto Scaling Group with min=0, max=1, desired=0.

## Consequences

- Scaling to 0 terminates the instance — no EBS charges for
  stopped volumes
- Every launch gets a fresh AMI (latest AL2023 via SSM
  parameter), so the instance is always fully patched
- No state to manage — the instance is truly ephemeral
- ASG handles replacement if the instance becomes unhealthy
- Slightly slower start (~60s) vs resuming a stopped instance
  (~30s), but acceptable for on-demand use
