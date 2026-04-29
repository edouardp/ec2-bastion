# 015: YAML Config Files for Environment Parameters

**Status:** Accepted
**Date:** 2026-04-24

## Context

The Makefile contained hardcoded AWS account IDs, VPC IDs,
subnet IDs, SNS topic ARNs, and owner names. This prevented
the repo from being made public without leaking infrastructure
details and personal identity.

## Decision

Move all per-environment parameters into `config/*.yaml` files
parsed by a Python script (`scripts/load_config.py`) that emits
Make-compatible `KEY=VALUE` lines. The Makefile loads these via
`$(foreach $(eval))`.

- `config/prod.yaml` and `config/staging.yaml` hold real values
  and are gitignored
- `config/prod.yaml.example` is committed with placeholders
- `pyyaml` is added as a project dependency (already using `uv`
  and Python for the chooser and notebooks)
- Staging VPC/subnet values fall back to CloudFormation stack
  outputs when left blank in the YAML

## Consequences

- No sensitive values in version control
- New users copy the example, fill in their values, and deploy
- Adds a Python invocation to every `make` call (negligible
  with `uv run` caching)
- All existing `-prod`/`-staging` targets continue to work
  unchanged
