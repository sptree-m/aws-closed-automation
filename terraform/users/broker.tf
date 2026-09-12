locals {
  broker_users = {
    for username, user in local.users :
    tostring(user.uid) => {
      username = username
      enabled  = user.enabled
      role_arn = try(aws_iam_role.bedrock_user[username].arn, "")
    }
  }

  broker_map_json = jsonencode({
    users = local.broker_users
  })
}

resource "aws_ssm_association" "credential_broker" {
  name             = "AWS-RunShellScript"
  association_name = "claude-credential-broker"
  apply_only_at_cron_interval = false

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }

  parameters = {
    commands = join("\n", [
      "set -euo pipefail",
      "install -d -m 0755 /usr/local/lib/claude-credential-broker",
      "install -d -m 0755 /etc/claude-credential-broker",
      "cat > /etc/claude-credential-broker/users.json <<'BROKERMAP'",
      local.broker_map_json,
      "BROKERMAP",
      "chmod 0600 /etc/claude-credential-broker/users.json",
      "chown root:root /etc/claude-credential-broker/users.json",
      "systemctl restart claude-credential-broker.service"
    ])
  }

  depends_on = [
    aws_iam_role_policy.instance_assume_users,
    aws_iam_role_policy.bedrock_user
  ]
}
