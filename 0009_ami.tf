#ucmp ami 권한 획득
data "aws_caller_identity" "self" {
}

## bastion ami image list
data "aws_ami_ids" "ucmp_ami_ids" {
  provider = aws.ucmp_owner
  owners   = [var.ami_ownerid]
  filter {
    name   = "name"
    values = ["${var.ami_env}-ucmp-*-ami-*"]
  }
}

data "aws_ami" "bastion_ami_id" {
  provider    = aws.ucmp_owner
  most_recent = true
  owners      = [var.ami_ownerid]
  filter {
    name   = "name"
    values = ["${var.ami_env}-ucmp-bastion-ami-*"]
  }
}

data "aws_ami" "node_ami_id" {
  provider    = aws.ucmp_owner
  most_recent = true
  owners      = [var.ami_ownerid]
  filter {
    name   = "name"
    values = ["${var.ami_env}-ucmp-eksnode-*-ami-*"]
  }
}

# ami 리스트에 접근 권한 추가
resource "aws_ami_launch_permission" "bastion_ami" {
  provider   = aws.ucmp_owner
  for_each   = toset(data.aws_ami_ids.ucmp_ami_ids.ids)
  image_id   = each.key
  account_id = data.aws_caller_identity.self.account_id
}
