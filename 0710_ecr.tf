# 1. container registry용 repository 생성
#   - 이미지 덮어쓰기 가능 여부와 보안취약점 자동 스캔, 암호화 알고리즘 설정
# 2. ecr repository 사용을 위한 policy 생성
#   - 이미지 사용 resource에 attach 후 사용 예정

resource "aws_ecr_repository" "ecr" {
  name = "ecr-${var.env}-${var.pjt}-imagerepository"

  image_tag_mutability = var.image_tag_mutability # MUTABLE : 동일 이미지 태그 덮어쓰기 가능, IMMUTABLE: 불가능

  image_scanning_configuration { //리포지토리에 푸시된 후 각 이미지를 자동으로 보안취약점 스캔. 
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = "AES256" # KMS or AES256,, default AES-256, KMS 선택 시 kms_key 입력필수 
    # kms_key = 
  }

  tags = {
    Name    = "ecr-${var.env}-${var.pjt}-imagerepository",
    Service = "imagerepository"
  }
}


# ecr를 사용할 resource(code deploy? sagemaker? 등)의 role에 추가 예정

resource "aws_ecr_repository_policy" "ecr_policy" {
  repository = aws_ecr_repository.ecr.name

  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "new policy",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:GetRepositoryPolicy",
                "ecr:ListImages",
                "ecr:DeleteRepository",
                "ecr:BatchDeleteImage",
                "ecr:SetRepositoryPolicy",
                "ecr:DeleteRepositoryPolicy"
            ]
        }
    ]
}
EOF

}

output "ECR_REPOSITORY" {
  value = "ecr-${var.env}-${var.pjt}-imagerepository"
}
