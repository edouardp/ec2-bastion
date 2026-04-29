#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

TIMEOUT=300  # 5 minutes
STARTED=$SECONDS

START_FN=$(_get_output StartFunctionArn)
ASG_NAME=$(_get_output AutoScalingGroupName)

echo "Invoking start Lambda..."
aws lambda invoke --function-name "$START_FN" /dev/null --cli-binary-format raw-in-base64-out >/dev/null 2>&1

echo "Waiting for instance to be InService..."
while true; do
  (( SECONDS - STARTED > TIMEOUT )) && { echo "Timed out waiting for instance" >&2; exit 1; }
  INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'] | [0].InstanceId" \
    --output text)
  [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ] && break
  sleep 5
done

echo "Waiting for SSM agent on $INSTANCE_ID..."
while true; do
  (( SECONDS - STARTED > TIMEOUT )) && { echo "Timed out waiting for SSM agent" >&2; exit 1; }
  READY=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null)
  [ "$READY" = "Online" ] && break
  sleep 5
done

echo "Ready: $INSTANCE_ID"
