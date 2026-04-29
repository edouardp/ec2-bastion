#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
ensure_ec2_running

INSTANCE_ID=$(get_instance_id)
exec aws ssm start-session --target "$INSTANCE_ID"
