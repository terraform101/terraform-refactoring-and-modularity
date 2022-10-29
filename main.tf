terraform {
  cloud {
    organization = "LG-uplus"
    hostname     = "app.terraform.io"
    workspaces {
      name = "iac-academy"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}

provider "aws" {
  region = var.region

  // test
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY

  default_tags { // 모든 resource에 기본으로 설정되는 Tag
    tags = {
      Environment        = var.env
      Project            = var.pjt
      COST_CENTER        = "${var.env}_${var.pjt}"
      TerraformManaged   = true
      PrivateInformation = var.private_information
    }
  }
}

provider "aws" {
  alias  = "useast1"
  region = "us-east-1"

  // test
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY
}

provider "aws" {
  alias      = "ucmp_owner"
  region     = var.region
  access_key = var.ucmp-access-key
  secret_key = var.ucmp-access-secret
}

// provider "kubernetes" {
//   host                   = aws_eks_cluster.eks_cluster.endpoint                                    // k8s에서 연동할 endpoint
//   cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data) // eks 생성될 떄 k8s와 연동가능한 인증서와 토큰이 발급됨
//   token                  = aws_eks_cluster.eks_cluster.token
//   load_config_file       = false // true면 kubeconfig와 같이 로컬에서 접근하는 인증을 뜻함. 위 cert와 token을 사용하니 false로 셋팅
// }

// ssh 접속 키를 생성
resource "tls_private_key" "key" {
  algorithm = "RSA"

  provisioner "local-exec" {
    command = "echo '${self.private_key_pem}' > ./ec2-${var.env}-${var.pjt}-bastion1.pem"
  }
}

resource "aws_key_pair" "keypair" {
  key_name   = "${var.pjt}-${var.env}-key"
  public_key = tls_private_key.key.public_key_openssh
}

module "common" {
  source = "./modules/common"

  providers = {
    aws            = aws
    aws.ucmp_owner = aws.ucmp_owner
  }

  env      = var.env
  pjt      = var.pjt
  vpc_cidr = "100.64.0.0/16"
  sg_bastion_egress = {
    80   = ["tcp", ["0.0.0.0/0"]] // WEB 포트
    443  = ["tcp", ["0.0.0.0/0"]]
    22   = ["tcp", ["0.0.0.0/0"]] // ternnel 용
    6379 = ["tcp", ["0.0.0.0/0"]] // elasticache 접근용
  }
  sg_bastion_ingress = {
    22 = ["tcp", var.bastion_cidr_block] // ssh 접속 포트
  }

  key_pair_name = aws_key_pair.keypair.key_name
  ami_ownerid   = var.ami_ownerid
  ami_env       = var.ami_env

  CloudArchitectureTeam_users = var.CloudArchitectureTeam_users
  developer_group_users       = var.developer_group_users

  // EKS
  enable_eks = var.enable_eks
  sg_eks_cluster_egress = {
    443   = ["tcp", ["0.0.0.0/0"]] // ssl 포트
    10250 = ["tcp", ["0.0.0.0/0"]] // Kubernetes Control Plane 포트
  }
  sg_eks_cluster_ingress = {
    443   = ["tcp", ["0.0.0.0/0"]]
    10250 = ["tcp", ["0.0.0.0/0"]]
    22    = ["tcp", ["0.0.0.0/0"]]
  }
  sg_eks_node_ingress = {
    22 = ["tcp", ["0.0.0.0/0"]]
  }
  sg_eks_pod_ingress = {
    22 = ["tcp", ["0.0.0.0/0"]]
  }

  // Elasticache
  enable_elasticache = var.enable_elasticache
}

data "aws_ami" "node_ami_id" {
  count       = var.enable_eks ? 1 : 0
  provider    = aws.ucmp_owner
  most_recent = true
  owners      = [var.ami_ownerid]
  filter {
    name   = "name"
    values = ["${var.ami_env}-ucmp-eksnode-*-ami-*"]
  }
}

module "eks" {
  source = "./modules/eks"

  env = var.env
  pjt = var.pjt

  eks_cluster_security_group_ids = module.common.eks_cluster_security_group_ids
  eks_cluster_subnet_ids         = module.common.eks_cluster_subnet_ids

  eks_scailing_desired = var.eks_scailing_desired
  eks_scailing_max     = var.eks_scailing_max
  eks_scailing_min     = var.eks_scailing_min

  key_pair_name       = aws_key_pair.keypair.key_name
  eks_node_ami_id     = data.aws_ami.node_ami_id[0].id
  node_instance_types = var.node_instance_types
}

# 1. container registry용 repository 생성
#   - 이미지 덮어쓰기 가능 여부와 보안취약점 자동 스캔, 암호화 알고리즘 설정
# 2. ecr repository 사용을 위한 policy 생성
#   - 이미지 사용 resource에 attach 후 사용 예정

resource "aws_ecr_repository" "ecr" {
  count = var.enable_ecr ? 1 : 0
  name  = "ecr-${var.env}-${var.pjt}-imagerepository"

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
  count      = var.enable_ecr ? 1 : 0
  repository = aws_ecr_repository.ecr[0].name

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

resource "aws_elasticache_replication_group" "cluster" {
  count                         = var.enable_elasticache ? 1 : 0
  replication_group_description = "elasticache-${var.env}-${var.pjt}-cluster"
  automatic_failover_enabled    = false
  subnet_group_name             = module.common.elasticache_redis_name
  replication_group_id          = "elasticache-${var.env}-${var.pjt}-replica"
  node_type                     = "cache.t3.micro"
  number_cache_clusters         = 1
  parameter_group_name          = "default.redis6.x"
  port                          = 6379
  at_rest_encryption_enabled    = true
  transit_encryption_enabled    = true

  tags = {
    Name    = "elasticache-${var.env}-${var.pjt}-cluster",
    Service = "cluster"
  }
}

resource "aws_elasticache_cluster" "replica" {
  count = var.enable_elasticache ? 1 : 0

  cluster_id           = "elasticache-${var.env}-${var.pjt}-cluster-${count.index}"
  replication_group_id = aws_elasticache_replication_group.cluster[0].id
}

resource "aws_dynamodb_table" "dynamodb" {
  count        = var.enable_dynamodb ? 1 : 0
  name         = "dynamodb-${var.env}-${var.pjt}-db"
  billing_mode = "PAY_PER_REQUEST"
  // read_capacity  = 20                 #// if billing mode is PROVISIONED, this field needs to be required
  // write_capacity = 20                 #// if billing mode is PROVISIONED, this field needs to be required
  hash_key  = "RuleSetId"
  range_key = "RuleSetInfo"


  ###########################
  #// Here's the guide for type
  #// S - String
  #// N - Number
  #// B - Binary Data
  ###########################

  attribute {
    name = "RuleSetId"
    type = "S"
  }

  attribute {
    name = "RuleSetInfo"
    type = "S"
  }

  // ttl {
  //   attribute_name = "TimeToExist"
  //   enabled        = false
  // }

  tags = {
    Name        = "dynamodb-${var.env}-${var.pjt}-examle-table",
    Environment = "production"
  }
}