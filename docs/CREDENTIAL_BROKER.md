# Per-user Bedrock credential broker

## Purpose

The shared Ubuntu EC2 host must not expose one common instance-profile identity to all Claude Code users.

The broker provides short-lived STS credentials per Linux UID.

```text
user01 process
   |
   | UNIX socket
   v
Credential Broker (root)
   |
   | SO_PEERCRED -> UID 10001
   v
Role claude-user-user01
   |
   v
Bedrock Runtime VPCE
```

The client never supplies the username or role ARN. The broker reads the caller UID from the kernel with `SO_PEERCRED` and looks up the allowed role.

## AWS SDK integration

Each user's `~/.aws/config` uses:

```ini
[default]
region = ap-northeast-1
credential_process = /usr/local/bin/claude-credential-process
```

The client prints the AWS credential-process JSON format. Credentials are short-lived and are not written to disk.

## IAM model

- EC2 instance profile:
  - may call `sts:AssumeRole` only for generated per-user roles.
- Per-user role:
  - trust only the shared EC2 instance-profile role.
  - require `sts:SourceIdentity` equal to that user.
  - allow only approved Bedrock actions/resources.
- Broker:
  - maps host UID -> exactly one role ARN.
  - adds `SourceIdentity` and session tags for audit.

## IMDS

The broker needs the EC2 instance profile, but normal users and containers must not be able to call IMDS directly.

Production host hardening must therefore include both:

1. IMDSv2 required.
2. Host firewall rule denying `169.254.169.254` to non-root user traffic.

Do not rely on container configuration alone for IMDS isolation.

## Audit

CloudTrail STS events contain the assumed-role session and source identity. Bedrock invocation logging/CloudTrail configuration should be enabled according to the organization's logging policy.

The deployment evidence suite should verify:

- user01 receives user01 role credentials.
- user01 cannot request user02 role.
- disabled user receives no credentials.
- normal user cannot reach IMDS.
- root broker can reach STS through the approved route/endpoint.
