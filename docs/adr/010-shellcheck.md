# 010: ShellCheck for Shell Script Linting

**Status:** Accepted
**Date:** 2026-04-12

## Context

The project has 9 shell scripts. Shell is easy to get subtly
wrong (unquoted variables, word splitting, portability).

## Decision

Use ShellCheck to lint all `.sh` files. Runs via pre-commit
hook and `make lint`.

## Consequences

- Catches real bugs (unquoted variables, missing error handling)
- `common.sh` uses `# shellcheck shell=bash` directive since
  it has no shebang (it's sourced, not executed)
- All scripts use `set -euo pipefail` as enforced by convention
