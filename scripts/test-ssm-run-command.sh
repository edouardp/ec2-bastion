#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
ensure_ec2_running

CMD="${1:-uname -a}"
INSTANCE_ID=$(get_instance_id)

echo "Running on $INSTANCE_ID: $CMD"
CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters '{"commands":["'"$CMD"'"]}' \
  --query Command.CommandId \
  --output text)

aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" 2>/dev/null || true
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query '[StatusDetails, StandardOutputContent, StandardErrorContent]' --output text
