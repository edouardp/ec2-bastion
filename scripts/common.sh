# shellcheck shell=bash
# Shared helpers — source this, don't execute it
STACK_NAME="${STACK_NAME:-ssm-on-demand}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_KEY_DIR=$(mktemp -d)
SSH_PRIVATE_KEY="$SSH_KEY_DIR/key"
SSH_PUBLIC_KEY="$SSH_KEY_DIR/key.pub"
trap 'rm -rf "$SSH_KEY_DIR"' EXIT

_get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

get_instance_id() {
  local asg_name
  asg_name=$(_get_output AutoScalingGroupName)
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$asg_name" \
    --query "AutoScalingGroups[0].Instances[0].InstanceId" \
    --output text
}

get_instance_az() {
  aws ec2 describe-instances \
    --instance-ids "$1" \
    --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
    --output text
}

push_ssh_key() {
  local instance_id="$1"
  echo "Generating ephemeral SSH key pair..."
  ssh-keygen -t ed25519 -f "$SSH_PRIVATE_KEY" -N "" -q
  local az
  az=$(get_instance_az "$instance_id")
  echo "Pushing public key to $instance_id ($az) via EC2 Instance Connect..."
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$instance_id" \
    --instance-os-user ec2-user \
    --availability-zone "$az" \
    --ssh-public-key "file://$SSH_PUBLIC_KEY" >/dev/null
  echo "Key valid for 60s. Connecting..."
}

ensure_ec2_running() {
  "$SCRIPT_DIR/ensure-ec2-running.sh"
}
