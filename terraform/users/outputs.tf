output "users" {
  description = "Resolved per-user lifecycle state and EFS/IAM resources."
  value = {
    for username, user in local.users :
    username => {
      uid              = user.uid
      gid              = user.gid
      enabled          = user.enabled
      bedrock_tag      = user.bedrock_tag
      efs_access_point = aws_efs_access_point.user[username].id
      bedrock_role_arn = try(aws_iam_role.bedrock_user[username].arn, null)
      home_path        = "${var.home_root}/${username}"
      container_root   = "${var.local_container_root}/${username}"
    }
  }
}
