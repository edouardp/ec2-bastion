#!/usr/bin/env bash
# Resolve the bastion source security group ID from SSM.
# Prints the sg-xxx ID on success, empty string on failure.
# Warnings go to stderr so callers can capture stdout cleanly.
set -euo pipefail

ENV="${1:?Usage: resolve-bastion-source-sg.sh <environment>}"
SSM_PATH="/${ENV}/network/bastion-source-security-group-id"

# 1. Try to read the SSM parameter
SG_ID=$(aws ssm get-parameter --name "$SSM_PATH" --query Parameter.Value --output text 2>/dev/null) || true

if [[ -z "$SG_ID" ]]; then
    echo "WARNING: SSM parameter $SSM_PATH not found — deploying without bastion source SG" >&2
    echo ""
    exit 0
fi

# 2. Verify the security group actually exists
if ! aws ec2 describe-security-groups --group-ids "$SG_ID" >/dev/null 2>&1; then
    echo "WARNING: SSM parameter $SSM_PATH references $SG_ID but that security group does not exist — deploying without bastion source SG" >&2
    echo ""
    exit 0
fi

echo "$SG_ID"
