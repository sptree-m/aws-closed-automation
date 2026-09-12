# Evidence automation design

## Goal
Automatically prove that the closed Claude Code environment is configured as intended and retain machine-readable evidence after deployment.

The pipeline separates:
1. Configuration evidence — actual AWS API state.
2. Behavioral evidence — tests executed from inside the Claude host via SSM.
3. Human-readable report — PASS/FAIL with expected vs actual.

## Initial controls
| Control | Expected |
|---|---|
| NET-001 | No IGW attached to Secure Dev VPC |
| NET-002 | No NAT Gateway in Secure Dev VPC |
| NET-003 | No 0.0.0.0/0 or ::/0 route |
| EC2-001 | Claude host has no public IPv4 |
| VPCE-001 | Bedrock Runtime VPCE exists and is available |
| EFS-001 | At least 10 EFS Access Points exist |
| EXF-001 | Direct github.com access fails from Claude host |
| EXF-002 | Direct pypi.org access fails from Claude host |
| DNS-001 | Bedrock hostname resolves from Claude host |
| ISO-001 | user01 cannot read user02 home |

## Why SSM
Network tests must run inside the isolated VPC. Running curl from CI does not prove the Claude host is isolated. The collector therefore uses SSM Run Command on the target instance.

## Evidence retention
Recommended production bucket settings:
- Versioning enabled
- Object Lock Compliance mode when policy requires immutability
- SSE-KMS
- Block Public Access enabled
- TLS-only bucket policy
- Lifecycle retention aligned to corporate policy
- CloudTrail data events for evidence-bucket writes

Object Lock must be enabled when the bucket is created.

## Security note
Evidence may include AWS account IDs, resource IDs, private IPs, and principal ARNs. Never commit generated evidence to this public repository.

## Production extensions
Before production sign-off, add:
- Rootless Podman container-to-IMDS denial test
- Per-user Bedrock session-tag/identity validation
- EFS IAM authorization assertions
- Security Group least-privilege assertions
- VPCE policy assertions
- CloudTrail and VPC Flow Logs checks
- KMS encryption checks for EBS/EFS/S3
- Internal Git/package mirror positive tests
- Bedrock InvokeModel positive test through PrivateLink
