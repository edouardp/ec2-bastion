# 011: Rumdl for Markdown Linting

**Status:** Accepted
**Date:** 2026-04-12

## Context

The project has 10 markdown files (README, DESIGN,
TROUBLESHOOTING, 7 ADRs). Formatting consistency matters for
readability.

## Decision

Use rumdl with a 120-character line width limit. Runs via
`make lint` and pre-commit.

## Configuration

`.rumdl.toml` relaxes line length from the default 80 to 120
characters — 80 is too strict for prose documentation.

## Consequences

- Consistent formatting across all documentation
- Catches structural issues (missing blank lines, etc.)
- 120-char limit balances readability with avoiding excessive
  line wrapping
