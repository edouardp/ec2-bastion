# 008: Pre-commit Hooks for Quality Gates

**Status:** Accepted
**Date:** 2026-04-12

## Context

Multiple linting tools (cfn-lint, shellcheck, checkmake, rumdl)
need to run consistently. Manual execution is easy to forget.

## Decision

Use the pre-commit framework with hooks for:

- trailing-whitespace, end-of-file-fixer, check-yaml, check-toml
- check-added-large-files, check-merge-conflict
- detect-private-key (especially important — this repo handles
  SSH keys)
- cfn-lint (CloudFormation validation)
- shellcheck (shell script linting)
- checkmake (Makefile linting)

## Consequences

- Hooks run automatically on every commit
- Same checks available via `make lint` for ad-hoc use
- `detect-private-key` prevents accidental commits of SSH key
  material
- Adds ~2-5 seconds to commit time (acceptable)
- Can bypass with `--no-verify` in emergencies
