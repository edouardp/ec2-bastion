# 009: AWS Resource Tagging Strategy

**Status:** Accepted
**Date:** 2026-04-12

## Context

AWS resources need tags for cost allocation, ownership tracking,
and operational visibility.

## Decision

Three tags on every resource, applied via `--tags` on
`aws cloudformation deploy`:

| Tag | Value |
|-----|-------|
| `Project` | `on-demand-ec2` |
| `Environment` | `prod` |
| `Owner` | `edouard` |

Stack-level tags propagate to all supported resources
automatically.

## Consequences

- Cost Explorer can filter by Project and Environment
- Consistent with tagging strategy used across other projects
  in `~/source`
- No `Version` tag (unlike hello_world_api) because there's no
  CI/CD pipeline or versioned releases — the stack is deployed
  manually
