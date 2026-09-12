data "aws_caller_identity" "current" {}

variable "instance_profile_role_name" {
  description = "IAM role name attached to the shared Ubuntu EC2 instance."
  type        = string
}

variable "bedrock_model_arns" {
  description = "Bedrock model or inference profile ARNs that users may invoke."
  type        = list(string)
}

data "aws_iam_policy_document" "user_trust" {
  for_each = local.users

  statement {
    sid     = "AllowBrokerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.instance_profile_role_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:SourceIdentity"
      values   = [each.key]
    }
  }
}

resource "aws_iam_role" "bedrock_user" {
  for_each = {
    for username, user in local.users : username => user
    if user.enabled
  }

  name               = "claude-bedrock-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.user_trust[each.key].json

  tags = merge(var.common_tags, {
    User       = each.key
    LinuxUID   = tostring(each.value.uid)
    BedrockTag = each.value.bedrock_tag
  })
}

data "aws_iam_policy_document" "bedrock_user" {
  for_each = aws_iam_role.bedrock_user

  statement {
    sid    = "InvokeApprovedModels"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = var.bedrock_model_arns
  }
}

resource "aws_iam_role_policy" "bedrock_user" {
  for_each = aws_iam_role.bedrock_user

  name   = "bedrock-invoke-approved-models"
  role   = each.value.id
  policy = data.aws_iam_policy_document.bedrock_user[each.key].json
}

data "aws_iam_policy_document" "instance_assume_users" {
  statement {
    sid    = "AssumeEnabledClaudeUsers"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity"
    ]

    resources = [for role in aws_iam_role.bedrock_user : role.arn]
  }
}

resource "aws_iam_role_policy" "instance_assume_users" {
  name   = "claude-assume-user-roles"
  role   = var.instance_profile_role_name
  policy = data.aws_iam_policy_document.instance_assume_users.json
}
