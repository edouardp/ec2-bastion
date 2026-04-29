# 006: Crypto Policy + SELinux Enforcing

**Status:** Superseded
**Date:** 2026-04-12
**Updated:** 2026-04-18

## Context

Amazon Linux 2023 ships with the DEFAULT crypto policy and
SELinux in permissive mode. We can harden both at boot via
user data.

## Decision (original, 2026-04-12)

Set crypto policy to FUTURE and SELinux to enforcing on every
boot.

## Decision (revised, 2026-04-18)

Revert crypto policy to DEFAULT. Keep SELinux enforcing.

The FUTURE policy rejects 2048-bit RSA certificates, which
AWS S3 endpoints use to serve AL2023 dnf repository metadata.
This breaks `dnf install` and `dnf update` — the instance
cannot install packages after boot.

The original design ordered AWS API calls before the policy
change, but dnf is needed throughout the instance lifetime,
not just at boot.

## Consequences

- DEFAULT policy is already strong: TLS 1.2+, no RC4, no
  3DES, no SHA-1 for signatures. Sufficient for this use case.
- SELinux enforcing remains — provides mandatory access
  control with no compatibility issues on AL2023.
- `dnf` works normally for the lifetime of the instance.
- If AWS moves S3 to 3072-bit+ RSA certificates in the
  future, FUTURE policy could be reconsidered.
