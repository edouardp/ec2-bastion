# 018: Dynamic AMI Resolution via resolve:ssm

**Status:** Accepted
**Date:** 2026-04-29

## Context

The Launch Template used a CloudFormation parameter of type
`AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` to look up
the latest AL2023 AMI. This resolved the SSM public parameter
at deploy time and baked the resulting AMI ID into the stack.
Subsequent instance launches reused that AMI until the next
`make deploy`.

Because instances are ephemeral (terminated after 5 minutes of
inactivity and recreated on demand), a deploy-time AMI means
instances could run a months-old image if the stack hadn't been
updated — defeating the "always patched" benefit of ephemeral
instances.

## Decision

Replace the `LatestAmiId` parameter with a `resolve:ssm`
dynamic reference in the Launch Template:

```yaml
ImageId: '{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64}}'
```

CloudFormation resolves `resolve:ssm` references when the
resource is created or updated. Since the ASG creates a fresh
instance on every scale-out, each new instance gets the AMI
that is current at launch time.

Removed from the template:

- `LatestAmiId` parameter (`AWS::SSM::Parameter::Value` type)

## Consequences

- Every new instance automatically gets the latest AL2023 AMI
  without redeploying the stack
- One fewer stack parameter to manage
- CloudFormation cannot detect AMI drift — the template always
  contains the same `resolve:ssm` string, so `update-stack`
  won't trigger a Launch Template change based on a new AMI
  alone (this is fine — the ASG already creates fresh instances)
- To switch to Amazon Linux 2, change the SSM path in the
  template rather than overriding a parameter
