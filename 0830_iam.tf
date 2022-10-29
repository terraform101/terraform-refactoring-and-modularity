# Administrator 권한을 가진 그룹 생성 및 유저 추가
resource "aws_iam_group" "CloudArchitectureTeam" {
  name = "CloudArchitectureTeam"
}

resource "aws_iam_group_policy_attachment" "policy_attach_to_CloudArchitectureTeam" {
  group      = aws_iam_group.CloudArchitectureTeam.name
  policy_arn = var.CloudArchitectureTeam_policy
}

resource "aws_iam_user" "CloudArchitectureTeam_users" {
  count = length(var.CloudArchitectureTeam_users)
  name  = element(var.CloudArchitectureTeam_users, count.index)

  tags = {
    Name = "CloudArchitectureTeam_user"
  }
}

resource "aws_iam_user_group_membership" "CloudArchitectureTeam_membership" {
  count = length(var.CloudArchitectureTeam_users)
  user  = element(var.CloudArchitectureTeam_users, count.index)
  groups = [
    aws_iam_group.CloudArchitectureTeam.name
  ]
}

# PowerUserAccess, IAMUserChangePassword 권한을 가진 그룹(개발사) 생성 및 유저 추가
resource "aws_iam_group" "developer_group" {
  name = "developer_group"
}

resource "aws_iam_group_policy_attachment" "policy_attach_to_developer_group" {
  group      = aws_iam_group.developer_group.name
  count      = length(var.developer_group_policy)
  policy_arn = var.developer_group_policy[count.index]
}

resource "aws_iam_user" "developer_group_users" {
  count = length(var.developer_group_users)
  name  = element(var.developer_group_users, count.index)

  tags = {
    Name = "developer_group_user"
  }
}

resource "aws_iam_user_group_membership" "developer_group_membership" {
  count = length(var.developer_group_users)
  user  = element(var.developer_group_users, count.index)
  groups = [
    aws_iam_group.developer_group.name
  ]
}

# aws iam console 비밀번호 정책
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 8
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
}