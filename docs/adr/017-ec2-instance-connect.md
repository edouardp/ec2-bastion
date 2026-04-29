# 017: EC2 Instance Connect for SSH Key Management

**Status:** Accepted
**Date:** 2026-04-25

Supersedes [004](004-ed25519-keys-in-ssm-parameter-store.md)
and [005](005-openssh-key-format-in-lambda.md).

## Context

SSH access required managing keys in SSM Parameter Store:
a rotation Lambda generated ed25519 key pairs in OpenSSH
format, stored them as SecureString parameters, and the
instance fetched public keys at boot via user data. This
worked but added significant complexity — a dedicated IAM
role, a Lambda function with custom cryptographic code, an
EventBridge schedule, and SSM parameter cleanup on teardown.

EC2 Instance Connect offers a simpler model: push an
ephemeral public key to instance metadata via the AWS API,
where it's valid for 60 seconds. The instance's sshd
(pre-configured on AL2023) checks metadata for authorized
keys automatically.

## Decision

Replace the custom SSH key rotation system with EC2 Instance
Connect's `send-ssh-public-key` API.

- The scripts generate a temporary ed25519 key pair per
  connection, push the public key, SSH with the private
  key, and delete both on exit
- The key is valid for 60 seconds in instance metadata —
  long enough to establish the SSH handshake
- No keys are stored anywhere — not in AWS, not on disk
- No rotation needed — keys are ephemeral by design
- AL2023 standard AMI has EC2 Instance Connect pre-installed

Removed from CloudFormation:

- `RotateSSHKeyRole`, `RotateSSHKeyFn`,
  `RotateSSHKeySchedule`, `RotateSSHKeyPermission`
- `SSHKeyAccess` policy on the instance role
- SSH key fetching from user data

The caller's IAM identity needs
`ec2-instance-connect:SendSSHPublicKey` permission. This is
a user-side concern, not managed by the stack.

## Consequences

- 5 fewer CloudFormation resources, ~150 fewer lines of
  template
- No secrets stored anywhere — nothing to rotate, leak, or
  clean up on teardown
- No `make rotate-ssh-key` step after first deploy
- No SSH key prerequisites — keys are generated per connection
- Requires the caller to have `ec2-instance-connect:SendSSHPublicKey`
  IAM permission
- The 60-second window means the SSH connection must start
  promptly after the push (the scripts handle this)
