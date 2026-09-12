locals {
  broker_users = {
    for username, user in local.users :
    tostring(user.uid) => {
      username = username
      enabled  = user.enabled
      role_arn = try(aws_iam_role.bedrock_user[username].arn, "")
    }
  }

  broker_map_json = jsonencode({ users = local.broker_users })

  broker_py_b64      = base64encode(file("${path.module}/../../broker/credential_broker.py"))
  credential_py_b64  = base64encode(file("${path.module}/../../broker/credential_process.py"))
  broker_service_b64 = base64encode(file("${path.module}/../../broker/claude-credential-broker.service"))
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
      "command -v aws >/dev/null",
      "command -v python3 >/dev/null",
      "install -d -m 0755 /usr/local/lib/claude-credential-broker",
      "install -d -m 0755 /etc/claude-credential-broker",
      "echo '${local.broker_py_b64}' | base64 -d > /usr/local/lib/claude-credential-broker/credential_broker.py",
      "echo '${local.credential_py_b64}' | base64 -d > /usr/local/bin/claude-credential-process",
      "echo '${local.broker_service_b64}' | base64 -d > /etc/systemd/system/claude-credential-broker.service",
      "chmod 0755 /usr/local/lib/claude-credential-broker/credential_broker.py /usr/local/bin/claude-credential-process",
      "chmod 0644 /etc/systemd/system/claude-credential-broker.service",
      "cat > /etc/claude-credential-broker/users.json <<'BROKERMAP'",
      local.broker_map_json,
      "BROKERMAP",
      "chmod 0600 /etc/claude-credential-broker/users.json",
      "chown root:root /etc/claude-credential-broker/users.json",
      "systemctl daemon-reload",
      "systemctl enable claude-credential-broker.service",
      "systemctl restart claude-credential-broker.service",
      "nft list table inet claude_guard >/dev/null 2>&1 || nft add table inet claude_guard",
      "nft list chain inet claude_guard output >/dev/null 2>&1 || nft 'add chain inet claude_guard output { type filter hook output priority -10; policy accept; }'",
      "nft list chain inet claude_guard output | grep -q '169.254.169.254' || nft add rule inet claude_guard output ip daddr 169.254.169.254 meta skuid != 0 reject",
      "systemctl is-active --quiet claude-credential-broker.service"
    ])
  }

  depends_on = [
    aws_iam_role_policy.instance_assume_users,
    aws_iam_role_policy.bedrock_user
  ]
}
