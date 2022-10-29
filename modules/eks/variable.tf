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

#####################
## eks-node
#####################

variable "key_pair_name" {
  type        = string
  description = "Key pair 이름 정의"
}

variable "eks_cluster_security_group_ids" {
  type        = list(string)
  description = "EKS 클러스터 생성에 필요한 보안 그룹 아이디 목록"
}

variable "eks_cluster_subnet_ids" {
  type        = list(string)
  description = "EKS 클러스터 생성에 필요한 서브넷 아이디 목록"
}

variable "eks_scailing_desired" {
  type        = number
  description = "scailing config. initially desired size"
}

variable "eks_scailing_max" {
  type        = number
  description = "scailing config. max size" ##// max size needs to bigger than 0 (>= 1)
}

variable "eks_scailing_min" {
  type        = number
  description = "scailing config. min size"
}

variable "eks_node_ami_id" {
  type        = string
  description = "EKS 노드용 ami id"
}

variable "node_instance_types" {
  type        = string
  description = "EKS 노드 인스턴스 타입 정의"
}