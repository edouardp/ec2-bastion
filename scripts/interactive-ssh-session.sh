#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
ensure_ec2_running

INSTANCE_ID=$(get_instance_id)
push_ssh_key "$INSTANCE_ID"

ssh -i "$SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o SetEnv="TERM=xterm-256color" \
  -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p" \
  "ec2-user@${INSTANCE_ID}"
