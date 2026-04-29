#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Aurora stack naming: aurora-postgres-staging, aurora-postgres-prod
AURORA_STACK="aurora-postgres-${ENVIRONMENT:?Set ENVIRONMENT}"

aurora_output() {
  aws cloudformation describe-stacks \
    --stack-name "$AURORA_STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

LOCAL_PORT="${LOCAL_PORT:-5432}"
AURORA_ENDPOINT=$(aurora_output ClusterEndpoint)
SECRET_ARN=$(aurora_output SecretArn)

echo "Aurora endpoint: $AURORA_ENDPOINT"
echo "Secret: $SECRET_ARN"
echo "Local port: $LOCAL_PORT"
echo ""

# Ensure bastion EC2 is running
ensure_ec2_running
INSTANCE_ID=$(get_instance_id)

echo ""
echo "Opening SSM port-forward tunnel..."
echo "  $AURORA_ENDPOINT:5432 → localhost:$LOCAL_PORT"
echo "  Press Ctrl-C to close"
echo ""

aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$AURORA_ENDPOINT\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
