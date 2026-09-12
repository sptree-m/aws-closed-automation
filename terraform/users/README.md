# Per-user Terraform layer

This layer manages resources and host configuration that belong to an individual Claude Code user.

## What is per-user

For every entry in `config/users.yaml`:

- EFS Access Point
- EFS root directory and POSIX identity
- Linux user/group on the shared Ubuntu host
- EFS home mount
- EBS-backed Podman graphroot/cache
- rootless Podman storage configuration
- Bedrock audit tag metadata

The shared EC2 instance, VPC, EFS filesystem, and VPC endpoints are inputs and are not recreated by this layer.

## Apply

```bash
cp config/users.example.yaml config/users.yaml
cp terraform/users/terraform.tfvars.example terraform/users/terraform.tfvars

terraform -chdir=terraform/users init
terraform -chdir=terraform/users plan
terraform -chdir=terraform/users apply
```

## Add one user

```bash
bash scripts/user_add.sh user03 10003 "User 03"
terraform -chdir=terraform/users plan
terraform -chdir=terraform/users apply
```

Expected plan: one EFS Access Point plus one SSM association for `user03`.

## Disable one user

```bash
bash scripts/user_remove.sh user03
terraform -chdir=terraform/users plan
terraform -chdir=terraform/users apply
```

The Access Point and EFS data remain. The host association locks the Linux account, disables lingering, kills the user's processes, and changes the shell to `nologin`.

## Purge

```bash
bash scripts/user_remove.sh user03 --purge
terraform -chdir=terraform/users plan
```

Review the destroy plan before apply.

Purging removes the EFS Access Point from Terraform. It does **not** automatically erase the files already stored under the shared EFS filesystem. Data destruction should be a separate, approved operation.

## Host prerequisites

The Ubuntu host must have:

- SSM Agent
- `amazon-efs-utils`
- Podman
- `fuse-overlayfs`
- systemd/logind
- an instance role allowed to mount the EFS filesystem with IAM authorization

The host also needs network access to the EFS mount target (TCP 2049) and SSM VPC endpoints.
