# 004: Ed25519 Keys in SSM Parameter Store

**Status:** Superseded by [017](017-ec2-instance-connect.md)
**Date:** 2026-04-12

## Context

SSH over SSM requires key pairs. Need to decide on key type,
storage, and rotation strategy. Options considered:

- Key type: RSA 2048/4096, ECDSA, Ed25519
- Storage: SSM Parameter Store, Secrets Manager, S3
- Rotation: manual, scheduled Lambda

## Decision

Ed25519 keys stored in SSM Parameter Store with automatic
rotation every 30 days via EventBridge + Lambda. Two slots
(current + previous) for zero-downtime rotation.

## Consequences

- Ed25519: smallest key size (~400 bytes private, ~80 bytes
  public), fits easily in SSM's 4 KB standard parameter limit
- SSM Parameter Store: free (standard tier), `SecureString`
  encrypts private keys with KMS at rest
- Two slots mean rotation never locks out active sessions —
  the instance loads both public keys into `authorized_keys`
- Secrets Manager rejected: $0.40/secret/month for 4 secrets,
  no benefit over SSM for this use case
- SSM parameter names cannot start with "ssm" (case-insensitive)
  — discovered during implementation, prefix is `on-demand-ec2`
