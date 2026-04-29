# 012: uv for Python and Dependency Management

**Status:** Accepted
**Date:** 2026-04-12

## Context

The project uses Python for the Marimo notebook and may add
more Python tooling in future. Need a tool to manage the Python
version, virtual environment, and dependencies.

## Decision

Use uv for Python version management, virtual environments, and
dependency resolution. Use `uvx` to run CLI tools (cfn-lint)
without installing them into the project environment.

## Current usage

- `.python-version` pins Python 3.12
- `pyproject.toml` defines the project and dependencies (marimo,
  boto3)
- `uv.lock` locks dependency versions
- `uvx --python 3.12 cfn-lint` runs cfn-lint in an isolated
  environment via `lint.sh`

## Consequences

- Single tool replaces pyenv + pip + venv
- Fast dependency resolution and installs
- `uvx` avoids polluting the project environment with dev tools
- Consistent Python version across machines via `.python-version`
- Ready to scale if more Python is added (Lambda packaging,
  tests, etc.)
