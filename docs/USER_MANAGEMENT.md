# User management

Users are managed declaratively in `config/users.yaml`.

Each user definition drives the resources that belong only to that user:

- Linux UID/GID
- EFS Access Point
- EFS home directory
- rootless Podman runtime/config
- per-user workspace/cache path
- Bedrock session tag / audit identity
- optional per-user IAM resources

## Add one user

```bash
cp config/users.example.yaml config/users.yaml   # first time only
bash scripts/user_add.sh user03 10003 "User 03"
```

Then apply the user layer:

```bash
terraform -chdir=terraform/users plan
terraform -chdir=terraform/users apply
```

Only the new user's resources should be created because the Terraform layer uses `for_each` keyed by username.

## Disable one user

Normal offboarding should be two-step.

```bash
bash scripts/user_remove.sh user03
```

This sets `enabled: false`. The implementation should:

- lock the Linux account
- stop/disable the user's Podman services
- revoke Bedrock access/session identity
- leave the EFS Access Point and home data intact

This is the recommended default because it preserves evidence and user data.

## Permanently purge one user

After retention/approval requirements are satisfied:

```bash
bash scripts/user_remove.sh user03 --purge
```

A purge removes the user definition. Terraform may then destroy resources owned by that user.

**Do not automatically delete the user's EFS data on normal disable.** Data deletion must be an explicit separate operation.

## Design rule

User lifecycle must be independent.

Adding or removing one user must not recreate:
- the shared EC2 instance
- the Secure Dev VPC
- shared VPC endpoints
- shared EFS filesystem
- other users' Access Points

Only per-user resources should change.
