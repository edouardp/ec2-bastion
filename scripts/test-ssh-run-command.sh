#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
ensure_ec2_running

CMD="${1:-uname -a}"
INSTANCE_ID=$(get_instance_id)
push_ssh_key "$INSTANCE_ID"

echo "Running on $INSTANCE_ID via SSH over SSM: $CMD"
ssh -i "$SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o SetEnv="TERM=xterm-256color" \
  -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p" \
  "ec2-user@${INSTANCE_ID}" "$CMD"
