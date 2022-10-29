# vpc 생성
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # VPC WorkerNode와 EKS(Managed) Private Link 통신을 위해 DNS 활성화 필요
  enable_dns_support   = true

  tags = {
    Name                                                      = "vpc-${var.env}-${var.pjt}-vpc"
    Service                                                   = "vpc",
    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared" # eks(managed)가 node 생성되는 서브넷을 찾을 수 있도록 tag 추가
  }
}