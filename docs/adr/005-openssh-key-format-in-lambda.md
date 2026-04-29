# 005: OpenSSH Key Format in Lambda

**Status:** Superseded by [017](017-ec2-instance-connect.md)
**Date:** 2026-04-12

## Context

The rotation Lambda generates ed25519 key pairs. The Lambda
runtime has `openssl` but not `ssh-keygen` or the `cryptography`
Python library. OpenSSL outputs ed25519 private keys in PKCS8
PEM format, which macOS OpenSSH (LibreSSL-backed) does not
accept.

Options considered:

1. Store PKCS8 PEM, convert on the client side
2. Add a Lambda layer with `cryptography` or `paramiko`
3. Construct OpenSSH format manually in Python

## Decision

Construct the OpenSSH private key format manually using
`struct`, `base64`, and `secrets` from the Python stdlib.
Use `openssl` to generate the raw key material, then build
the OpenSSH binary format in Python.

## Consequences

- Zero external dependencies — no Lambda layers needed
- Keys work on all OpenSSH clients without conversion
- The OpenSSH format construction is ~30 lines of Python,
  well-understood binary format (openssh-key-v1)
- Public key is also constructed manually in OpenSSH format
  (simpler — just type + raw key base64-encoded)
- If OpenSSH changes its format (unlikely), the Lambda code
  would need updating
