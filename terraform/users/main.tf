provider "aws" {
  region = var.aws_region
}

locals {
  users_config = yamldecode(file(var.users_file))

  users = {
    for user in local.users_config.users :
    user.username => {
      username     = user.username
      uid          = tonumber(user.uid)
      gid          = tonumber(try(user.gid, user.uid))
      enabled      = try(user.enabled, true)
      display_name = try(user.display_name, user.username)
      bedrock_tag  = try(user.bedrock_tag, user.username)
    }
  }
}

resource "aws_efs_access_point" "user" {
  for_each = local.users

  file_system_id = var.efs_file_system_id

  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }

  root_directory {
    path = "/users/${each.key}"

    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = "0700"
    }
  }

  tags = merge(var.common_tags, {
    Name        = "claude-home-${each.key}"
    User        = each.key
    UserUID     = tostring(each.value.uid)
    BedrockTag  = each.value.bedrock_tag
    UserEnabled = tostring(each.value.enabled)
  })
}

resource "aws_ssm_association" "user_runtime" {
  for_each = local.users

  name             = "AWS-RunShellScript"
  association_name = "claude-user-${each.key}"
  apply_only_at_cron_interval = false

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }

  parameters = {
    commands = join("\n", each.value.enabled ? [
      "set -euo pipefail",
      "USERNAME='${each.key}'",
      "UID_EXPECTED='${each.value.uid}'",
      "GID_EXPECTED='${each.value.gid}'",
      "HOME_PATH='${var.home_root}/${each.key}'",
      "LOCAL_ROOT='${var.local_container_root}/${each.key}'",
      "AP_ID='${aws_efs_access_point.user[each.key].id}'",
      "EFS_ID='${var.efs_file_system_id}'",
      "getent group \"$GID_EXPECTED\" >/dev/null || groupadd --gid \"$GID_EXPECTED\" \"$USERNAME\"",
      "if id \"$USERNAME\" >/dev/null 2>&1; then test \"$(id -u \"$USERNAME\")\" = \"$UID_EXPECTED\"; else useradd --uid \"$UID_EXPECTED\" --gid \"$GID_EXPECTED\" --home-dir \"$HOME_PATH\" --shell /bin/bash \"$USERNAME\"; fi",
      "usermod -U \"$USERNAME\" || true",
      "mkdir -p \"$HOME_PATH\" \"$LOCAL_ROOT/containers\" \"$LOCAL_ROOT/cache\"",
      "chown -R \"$UID_EXPECTED:$GID_EXPECTED\" \"$LOCAL_ROOT\"",
      "chmod 0700 \"$LOCAL_ROOT\"",
      "grep -vE \"[[:space:]]$HOME_PATH[[:space:]]\" /etc/fstab > /etc/fstab.aws-closed.tmp || true",
      "mv /etc/fstab.aws-closed.tmp /etc/fstab",
      "echo \"$EFS_ID:/ $HOME_PATH efs _netdev,tls,iam,accesspoint=$AP_ID 0 0\" >> /etc/fstab",
      "mountpoint -q \"$HOME_PATH\" || mount \"$HOME_PATH\"",
      "install -d -m 0700 -o \"$UID_EXPECTED\" -g \"$GID_EXPECTED\" \"$HOME_PATH/.config/containers\"",
      "printf '%s\\n' '[storage]' 'driver = \"overlay\"' 'graphroot = \"${var.local_container_root}/${each.key}/containers\"' 'runroot = \"/run/user/${each.value.uid}/containers\"' '' '[storage.options.overlay]' 'mount_program = \"/usr/bin/fuse-overlayfs\"' > \"$HOME_PATH/.config/containers/storage.conf\"",
      "chown \"$UID_EXPECTED:$GID_EXPECTED\" \"$HOME_PATH/.config/containers/storage.conf\"",
      "chmod 0600 \"$HOME_PATH/.config/containers/storage.conf\"",
      "loginctl enable-linger \"$USERNAME\" || true"
    ] : [
      "set -euo pipefail",
      "USERNAME='${each.key}'",
      "if id \"$USERNAME\" >/dev/null 2>&1; then",
      "  loginctl disable-linger \"$USERNAME\" || true",
      "  pkill -KILL -u \"$USERNAME\" || true",
      "  usermod -L \"$USERNAME\"",
      "  usermod -s /usr/sbin/nologin \"$USERNAME\"",
      "fi"
    ])
  }

  depends_on = [aws_efs_access_point.user]
}
