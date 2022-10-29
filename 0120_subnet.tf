# 1. az 별 4개의 Subnet 총 8개의 Subnet 생성함 (sbn_pub, sbn_pri, sbn_pri_pod, sbn_pri_db)
# pub : a)인터넷 
# pri : b)서비스 c)pod(2nd CIDR) d)DB
# 2. db용 subnet_group 생성

# Public subnet 2개
resource "aws_subnet" "sbn_puba" {
  availability_zone       = var.az_a
  cidr_block              = var.puba_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true # 자동 퍼블릭IP 할당 여부

  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-puba",
    Service = "puba"

    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared",
    "kubernetes.io/role/elb"                                  = "1"
  }
}

resource "aws_subnet" "sbn_pubc" {
  availability_zone       = var.az_c
  cidr_block              = var.pubc_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pubc",
    Service = "pubc"

    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared",
    "kubernetes.io/role/elb"                                  = 1
  }
}

# Private subnet 2개
locals {
  cluster_tags = {
    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared",
    "kubernetes.io/role/elb"                                  = 1
  }
}

resource "aws_subnet" "sbn_pria" {
  availability_zone       = var.az_a
  cidr_block              = var.pria_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags = {
    Name                                                      = "sbn-${var.env}-${var.pjt}-pria",
    Service                                                   = "pria",
    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared" # eks(managed)가 node 생성되는 서브넷을 찾을 수 있도록 tag 추가,
    "kubernetes.io/role/internal-elb"                         = 1
  }
}

resource "aws_subnet" "sbn_pric" {
  availability_zone       = var.az_c
  cidr_block              = var.pric_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags = {
    Name                                                      = "sbn-${var.env}-${var.pjt}-pric",
    Service                                                   = "pric",
    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared" # eks(managed)가 node 생성되는 서브넷을 찾을 수 있도록 tag 추가,
    "kubernetes.io/role/internal-elb"                         = 1
  }
}

# DB용 Private subnet 2개추가
resource "aws_subnet" "sbn_pria_db" {
  availability_zone       = var.az_a
  cidr_block              = var.pria_db_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pria-db",
    Service = "pria-db"
  }
}


resource "aws_subnet" "sbn_pric_db" {
  availability_zone       = var.az_c
  cidr_block              = var.pric_db_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pric-db",
    Service = "pric-db"
  }
}

# ElastiCache용 서브넷그룹 설정
resource "aws_elasticache_subnet_group" "subnetg_elasticache_redis" {
  name       = "subnetg-${var.env}-${var.pjt}-elasticache-redis"
  subnet_ids = [aws_subnet.sbn_pria_db.id, aws_subnet.sbn_pric_db.id]
  #subnet_ids = [aws_subnet.sbn_pria_db.id , aws_subnet.sbn_prib_db.id , aws_subnet.sbn_pric_db.id]
  tags = {
    Name    = "subnetg-${var.env}-${var.pjt}-elasticache-redis",
    Service = "elasticache"
  }
}

# TGW용 Subnet 추가, whatap monitoring을 위한 EC2도 위치할 예정
# 해당 서브넷의 이중화에 대한 고민은 있으나 굳이 2개로 가져가지 않아도 될 것으로 보여, 우선은 단중화 구성되어 있음
resource "aws_subnet" "sbn_pria_tgw" {
  availability_zone       = var.az_a
  cidr_block              = var.pria_tgw_cidr
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pria-tgw",
    Service = "pria-tgw"
  }
}

# resource "aws_subnet" "sbn_pric_tgw" {
#   availability_zone       = var.az_c
#   cidr_block              = var.pric_tgw_cidr
#   vpc_id                  = aws_vpc.vpc.id
#   map_public_ip_on_launch = false
#   tags = {
#     Name    = "sbn-${var.env}-${var.pjt}-pric-tgw",
#     Service = "pric-tgw"
#   }
# }
