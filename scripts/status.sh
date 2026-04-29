#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "=== Stack ==="
aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query "Stacks[0].{Status:StackStatus,Created:CreationTime,Updated:LastUpdatedTime}" \
  --output table 2>/dev/null || { echo "Stack not found"; exit 0; }

echo ""
echo "=== Outputs ==="
aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}" \
  --output table

echo ""
echo "=== ASG ==="
ASG_NAME=$(_get_output AutoScalingGroupName)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].{Id:InstanceId,State:LifecycleState}}" \
  --output table

INSTANCE_ID=$(get_instance_id)
if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
  echo ""
  echo "=== Instance ==="
  aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].{Id:InstanceId,Type:InstanceType,State:State.Name,AZ:Placement.AvailabilityZone,Launch:LaunchTime,PrivateIP:PrivateIpAddress}" \
    --output table

  echo ""
  echo "=== Active SSM Sessions ==="
  aws ssm describe-sessions --state Active \
    --filters "key=Target,value=$INSTANCE_ID" \
    --query "Sessions[*].{SessionId:SessionId,Owner:Owner,Start:StartDate}" \
    --output table

  echo ""
  echo "=== In-Progress Run Commands ==="
  aws ssm list-commands --instance-id "$INSTANCE_ID" \
    --filters key=Status,value=InProgress \
    --query "Commands[*].{CommandId:CommandId,Requested:RequestedDateTime,Command:Parameters.commands[0]}" \
    --output table
else
  echo ""
  echo "No running instance."
fi

echo ""
echo "=== CloudWatch Alarm ==="
aws cloudwatch describe-alarms --alarm-name-prefix ssm-on-demand \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}" \
  --output table
