# 014: Bastion Source Security Group for Database Access

**Status:** Accepted
**Date:** 2026-04-20

## Context

RDS databases need to allow inbound access from bastion hosts.
A shared "source" security group pattern was introduced in
`platform/bastion-source-sg/` — an empty security group that
acts as an identity marker. Backend resources allow ingress
from this group ID, published to SSM at
`/{env}/network/bastion-source-security-group-id`.

This instance needs to be recognised as a bastion so it can
connect to Postgres databases.

## Decision

Attach the bastion source security group as a second group on
the launch template, resolved from SSM at deploy time.

The parameter is optional — if the SSM path is missing or the
referenced security group no longer exists, the deploy script
warns and continues without it. This is handled by
`scripts/resolve-bastion-source-sg.sh`, which checks both
conditions and outputs an empty string on failure. The
CloudFormation template uses a `HasBastionSourceSG` condition
to conditionally include the group.

We resolve at deploy time (in the Makefile) rather than using
`AWS::SSM::Parameter::Value` because the latter fails the
entire deploy if the parameter doesn't exist.

## Consequences

- Instances are recognised as bastions by RDS security group
  rules — no IP or subnet-based rules needed
- Adding or replacing instances requires no changes to RDS
  ingress rules
- Deploy succeeds even if the bastion source SG stack hasn't
  been deployed yet, with a clear warning
- Invalid SG references (deleted group) are caught before
  deploy, not at instance launch time
