# 007: CloudFormation for Infrastructure as Code

**Status:** Accepted
**Date:** 2026-04-12

## Context

Need to define and manage AWS infrastructure reproducibly.
Options: CloudFormation, CDK, Terraform, Pulumi.

## Decision

Use a single CloudFormation YAML template. The entire stack
(ASG, Lambdas, IAM roles, EventBridge rules, CloudWatch alarm)
is defined in `ssm-on-demand-instance.yaml`.

## Consequences

- Native AWS service, no external tooling required
- YAML is human-readable and diff-friendly
- Stack updates are atomic with automatic rollback
- Lambda code is inline (`ZipFile`) — no build/package step
- More verbose than CDK, but acceptable for this scope
