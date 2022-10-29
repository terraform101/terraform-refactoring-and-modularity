#############
## TAG
#############
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

#############
## NETWORK
#############
variable "vpc_cidr" {
  type        = string
  default     = "100.64.0.0/16"
  description = "VPC의 CIDR 정의, 16비트 대역을 입력 (e.g. 100.64.0.0/16)"

  validation {
    condition     = contains(split("/", var.vpc_cidr), "16")
    error_message = "CIDR은 16비트"
  }
}

variable "sg_bastion_egress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "Bastion 서버의 Security Group Egress 목록"
}

variable "sg_bastion_ingress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "Bastion 서버의 Security Group Ingress 목록"
}

#############
## AMI
#############
variable "ami_ownerid" {
  default = ""
}

variable "ami_env" {
  default = "prod"
}

#############
## EKS
#############
variable "enable_eks" {
  type    = bool
  default = false
}

variable "sg_eks_cluster_egress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "EKS 클러스터의 Security Group Egress 목록"
}

variable "sg_eks_cluster_ingress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "EKS 클러스터의 Security Group Ingress 목록"
}

variable "sg_eks_node_egress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "EKS 노드의 Security Group Egress 목록"
}

variable "sg_eks_node_ingress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "EKS 노드의 Security Group Ingress 목록"
}

variable "sg_eks_pod_egress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "EKS 파드의 Security Group Egress 목록"
}

variable "sg_eks_pod_ingress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "EKS 파드의 Security Group Ingress 목록"
}

#############
## Elasticache
#############
variable "enable_elasticache" {
  type        = bool
  default     = false
  description = "Elasticache 활성/비활성"
}

variable "sg_elasticache_egress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "Elasticache의 Security Group Egress 목록"
}

variable "sg_elasticache_ingress" {
  type        = map(tuple([string, list(string)]))
  default     = {}
  description = "Elasticache의 Security Group Ingress 목록"
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
}

variable "developer_group_users" {
  description = "Create IAM Developer Group Users"
  type        = list(any)
}

variable "key_pair_name" {
  type        = string
  description = "Key pair 이름 정의"
}