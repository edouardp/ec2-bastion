# 003: SSH over SSM

**Status:** Accepted
**Date:** 2026-04-12

## Context

SSM Session Manager provides shell access but lacks port
forwarding, SCP/SFTP, and SSH agent forwarding. These are
needed for development workflows (e.g., VS Code Remote SSH,
file transfer).

## Decision

Support SSH tunnelled over SSM using `ProxyCommand` in addition
to plain SSM sessions.

## Consequences

- Full SSH feature set: port forwarding, SCP, agent forwarding,
  editor integration
- Still no inbound ports — SSH traffic tunnels through SSM
- SSM sessions created by the SSH tunnel count for idle
  detection, so the instance stays alive during SSH use
- Requires SSH key management (see ADR-004)
- Private key is fetched from Parameter Store on demand and
  deleted after the session via `trap`
