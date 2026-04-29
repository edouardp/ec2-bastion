# 002: SSM Session Manager for Access

**Status:** Accepted
**Date:** 2026-04-12

## Context

Need shell access to the instance. Options: SSH with public IP
and security group rules, SSH via bastion host, or SSM Session
Manager.

## Decision

Use SSM Session Manager as the primary access method.

## Consequences

- No inbound security group rules needed — zero network attack
  surface
- No public IP or bastion host required
- No SSH key management needed for basic access
- Session activity is auditable via CloudTrail
- The idle checker can detect active sessions via
  `ssm:DescribeSessions` to prevent premature shutdown
- Requires the SSM agent (pre-installed on AL2023) and either
  internet access or VPC endpoints for SSM
- Session Manager plugin required on the client
  (`brew install --cask session-manager-plugin`)
