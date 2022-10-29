### FOR TEST
variable "AWS_ACCESS_KEY_ID" {}
variable "AWS_SECRET_ACCESS_KEY" {}

#####################################
## ami ids list ucmp 공용 계정용 환경설정
## id , key 는 TFC Variable에 등록됨
#####################################


variable "ami_ownerid" {
  default = ""
}
variable "ucmp-access-key" {
  default = ""
}
variable "ucmp-access-secret" {
  default   = ""
  sensitive = true
}
variable "ami_env" {
  default = "prod"
}

#####################
## default tag
#####################
variable "env" {
  type        = string
  default     = "prd"
  description = "인프라 환경 정의 dev | stg | prd"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.env)
    error_message = "환경 정의는 dev, stg, prd가 가능"
  }
}

variable "pjt" {
  type        = string
  description = "프로젝트 이름"
}

variable "private_information" {
  type        = bool
  default     = false
  description = "개인정보 포함된 자원 여부"
}

#####################
## vpc
#####################
variable "region" {
  type    = string
  default = "ap-northeast-2"
}

#####################
## bastion
#####################
variable "bastion_cidr_block" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "bastion 서버 ingress 허용하는 cidr_block"
}


#####################
## eks-node
#####################
variable "enable_eks" {
  type        = bool
  default     = false
  description = "EKS 활성/비활성"
}

variable "node_instance_types" {
  type        = string
  default     = "t3.small"
  description = "EKS 노드 인스턴스 타입 정의"
}

variable "eks_scailing_desired" {
  type        = number
  default     = 1
  description = "scailing config. initially desired size"
}

variable "eks_scailing_max" {
  type        = number
  default     = 3
  description = "scailing config. max size" ##// max size needs to bigger than 0 (>= 1)
}

variable "eks_scailing_min" {
  type        = number
  default     = 1
  description = "scailing config. min size"
}

#####################
## ecr
#####################
variable "enable_ecr" {
  type        = bool
  default     = false
  description = "ECR 활성/비활성"
}

variable "image_tag_mutability" {
  type        = string
  description = "동일 이미지 태그 덮어쓰기 가능여부, MUTABLE: 가능/ IMMUTABLE: 불가능"
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "MUTABLE: 가능 / IMMUTABLE: 불가능"
  }
}

variable "scan_on_push" {
  type        = bool
  description = "리포지토리에 푸시된 후 각 이미지 보안취약점을 자동으로 스캔 여부"
  default     = false
}

#####################
## elasticache
#####################
variable "enable_elasticache" {
  type        = bool
  default     = false
  description = "Elasticache 활성/비활성"
}

#####################
## dynamodb
#####################
variable "enable_dynamodb" {
  type        = bool
  default     = false
  description = "DynamoDB 활성/비활성"
}

#####################
## iam - users per groups
#####################

variable "CloudArchitectureTeam_users" {
  description = "Create IAM CloudArchitectureTeam Users"
  type        = list(any)
  default = [
    "hello@lguplus.co.kr",
    "lg@lguplus.co.kr",
    "uplus@lguplus.co.kr"
  ]
}

variable "developer_group_users" {
  description = "Create IAM Developer Group Users"
  type        = list(any)
  default = [
    "dev1@lgupluspartners.co.kr",
    "dev2@lgupluspartners.co.kr",
    "dev3@lgupluspartners.co.kr",
  ]
}
