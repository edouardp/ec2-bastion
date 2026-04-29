# 013: Project Directory Structure

**Status:** Accepted
**Date:** 2026-04-12

## Context

All files were in the repo root — scripts, CloudFormation
template, notebook, and documentation mixed together. As the
project grew to 20+ files, discoverability suffered.

## Decision

Organise into four directories:

```text
cloudformation/     CloudFormation template
notebooks/          Marimo notebook
scripts/            All shell scripts (9 files + common.sh)
docs/               DESIGN.md, TROUBLESHOOTING.md
docs/adr/           Architectural Decision Records
```

Root keeps only entry points and config: `Makefile`, `.envrc`,
`.gitignore`, `.pre-commit-config.yaml`, `.rumdl.toml`,
`.checkmake`, `.python-version`, `pyproject.toml`, `uv.lock`,
`README.md`.

## Consequences

- Clear separation of concerns by file type
- `make help` remains the single entry point — users don't
  need to know the directory structure
- Scripts use `$(dirname "$0")/common.sh` for relative sourcing,
  which works regardless of where they're called from
- `docs/` contains both prose documentation and ADRs, matching
  the convention used in other projects in `~/source`
- cfn-lint pre-commit hook scoped to `cloudformation/*.yaml`
  to avoid false positives on other YAML files
