#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== CloudFormation Lint ==="
uvx --python 3.12 cfn-lint cloudformation/ssm-on-demand-instance.yaml
echo "✅ cfn-lint passed"

echo ""
echo "=== ShellCheck ==="
shellcheck -x -e SC1091 scripts/*.sh
echo "✅ shellcheck passed"

echo ""
echo "=== Makefile Lint ==="
checkmake --config=.checkmake Makefile
echo "✅ checkmake passed"

echo ""
echo "=== Markdown Lint ==="
if command -v rumdl &>/dev/null; then
  rumdl check .
  echo "✅ rumdl passed"
elif command -v uvx &>/dev/null; then
  uvx rumdl check .
  echo "✅ rumdl passed"
else
  echo "⚠️  rumdl not found, skipping"
fi
