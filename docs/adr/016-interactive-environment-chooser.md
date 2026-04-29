# 016: Interactive Environment Chooser for Make Targets

**Status:** Accepted
**Date:** 2026-04-24

## Context

Most Make targets existed as `-prod` and `-staging` pairs.
Only `make ssh` and `make ssm` had an interactive chooser
(via `scripts/chooser.py`). All other targets required the
user to remember and type the suffix, or use the umbrella
target that always ran both environments.

## Decision

Add an interactive Textual chooser to every target group.
The bare target name (e.g. `make deploy`, `make status`)
launches the chooser. Targets that can operate on both
environments offer a "both" option via a separate JSON file
(`scripts/environments-with-both.json`). Interactive session
targets (`ssh`, `ssm`, `ensure-ec2`) only offer single
environment selection.

A `choose_and_dispatch` Make macro handles the pattern:
run the chooser, then `$(MAKE)` the appropriate suffixed
target(s).

Explicit `-prod`/`-staging` targets remain for scripting
and CI use.

## Consequences

- `make deploy` is now interactive instead of always deploying
  both — users who relied on the old behaviour should use
  `make deploy-prod deploy-staging` or select "both"
- Every chooser invocation adds ~0.5s for the TUI to render
- The `-prod`/`-staging` targets are unchanged and can be
  called directly to skip the chooser
