terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws, aws.ucmp_owner]
    }
  }
}

data "aws_region" "current" {}

locals {
  az_a = "${data.aws_region.current.name}a"
  az_c = "${data.aws_region.current.name}c"
  cluster_tags = {
    // eks(managed)가 node 생성되는 서브넷을 찾을 수 있도록 tag 추가
    "kubernetes.io/cluster/eks-${var.env}-${var.pjt}-cluster" = "shared"
  }
  bastion_type = "t2.micro" // 설계 시 정한 값
  developer_group_policy = [
    "arn:aws:iam::aws:policy/PowerUserAccess",
    "arn:aws:iam::aws:policy/IAMUserChangePassword",
    // "arn:aws:iam::**********:policy/MFA_Device"
  ]
}

resource "aws_vpc" "common" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true // VPC WorkerNode와 EKS(Managed) Private Link 통신을 위해 DNS 활성화 필요
  enable_dns_support   = true

  tags = merge(local.cluster_tags, tomap({
    Name    = "vpc-${var.env}-${var.pjt}-vpc"
    Service = "vpc",
  }))
}

// 1. az 별 4개의 Subnet 총 8개의 Subnet 생성함 (sbn_pub, sbn_pri, sbn_pri_pod, sbn_pri_db)
// pub : a)인터넷 
// pri : b)서비스 c)pod(2nd CIDR) d)DB
// 2. db용 subnet_group 생성

// Public subnet 2개
resource "aws_subnet" "puba" {
  availability_zone       = local.az_a
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 0)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = true // 자동 퍼블릭IP 할당 여부

  tags = merge(local.cluster_tags, tomap({
    Name                     = "sbn-${var.env}-${var.pjt}-puba",
    Service                  = "puba"
    "kubernetes.io/role/elb" = "1"
  }))
}

resource "aws_subnet" "pubc" {
  availability_zone       = local.az_c
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 4)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = true

  tags = merge(local.cluster_tags, tomap({
    Name                     = "sbn-${var.env}-${var.pjt}-pubc",
    Service                  = "pubc"
    "kubernetes.io/role/elb" = 1
  }))
}

resource "aws_subnet" "pria" {
  availability_zone       = local.az_a
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 1)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = false
  tags = merge(local.cluster_tags, tomap({
    Name                              = "sbn-${var.env}-${var.pjt}-pria",
    Service                           = "pria",
    "kubernetes.io/role/internal-elb" = 1
  }))
}

resource "aws_subnet" "pric" {
  availability_zone       = local.az_c
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 5)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = false
  tags = merge(local.cluster_tags, tomap({
    Name                              = "sbn-${var.env}-${var.pjt}-pric",
    Service                           = "pric",
    "kubernetes.io/role/internal-elb" = 1
  }))
}

// DB용 Private subnet 2개추가
resource "aws_subnet" "pria_db" {
  availability_zone       = local.az_a
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 2)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = false
  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pria-db",
    Service = "pria-db"
  }
}


resource "aws_subnet" "pric_db" {
  availability_zone       = local.az_c
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 6)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = false
  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pric-db",
    Service = "pric-db"
  }
}

// ElastiCache용 서브넷그룹 설정
resource "aws_elasticache_subnet_group" "elasticache_redis" {
  count      = var.enable_elasticache ? 1 : 0
  name       = "subnetg-${var.env}-${var.pjt}-elasticache-redis"
  subnet_ids = [aws_subnet.pria_db.id, aws_subnet.pric_db.id]
  tags = {
    Name    = "subnetg-${var.env}-${var.pjt}-elasticache-redis",
    Service = "elasticache"
  }
}

// TGW용 Subnet 추가, whatap monitoring을 위한 EC2도 위치할 예정
// 해당 서브넷의 이중화에 대한 고민은 있으나 굳이 2개로 가져가지 않아도 될 것으로 보여, 우선은 단중화 구성되어 있음
resource "aws_subnet" "pria_tgw" {
  availability_zone       = local.az_a
  cidr_block              = cidrsubnet(aws_vpc.common.cidr_block, 4, 3)
  vpc_id                  = aws_vpc.common.id
  map_public_ip_on_launch = false
  tags = {
    Name    = "sbn-${var.env}-${var.pjt}-pria-tgw",
    Service = "pria-tgw"
  }
}

// internet gateway 생성
// 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.common.id

  tags = {
    Name    = "igw-${var.env}-${var.pjt}-internetgw",
    Service = "internetgw"
  }
}

// eip는 계정별 리전 당 5개로 개수 제한됨.
// public ip 설정

// NAT 용 eip 생성 (NAT가 2개, eip도 각각 생성)
resource "aws_eip" "nat_puba" {
  vpc        = true                       // EIP가 VPC에 있는지 여부
  depends_on = [aws_internet_gateway.igw] // igw 생성 이후 가능하기에 의존성 추가함
  tags = {
    Name    = "eip-${var.env}-${var.pjt}-nat-puba"
    Service = "nat-puba"
  }
}

// Bastion 용 eip 생성
resource "aws_eip" "bastion" {
  vpc        = true                       // EIP가 VPC에 있는지 여부
  depends_on = [aws_internet_gateway.igw] // igw 생성 이후 가능하기에 의존성 추가함
  tags = {
    Name    = "eip-${var.env}-${var.pjt}-bastion"
    Service = "bastion"
  }
}

// NAT public subnet에 생성
// 
resource "aws_nat_gateway" "puba" {
  allocation_id = aws_eip.nat_puba.id
  subnet_id     = aws_subnet.puba.id
  depends_on    = [aws_internet_gateway.igw] // igw 생성 이후 가능하기에 의존성 추가함
  tags = {
    Name    = "nat-${var.env}-${var.pjt}-puba",
    Service = "puba"
  }
}

// Routing Table 4개 생성 및 각 subnet 연결

// 1. route_pub : pub subnet에서 인터넷으로 (vpc에서 igw로 설정)
// 2. route_pri : pri subnet에서 인터넷으로 (vpc에서 nat로 설정)
// 3. route_pri_pod : pri_pod subnet 내 (선언만)
// 3-1. pri_pod subnet에서 s3으로 : vpc endpoint로 association 설정만 추가


// 1. public에 route table 생성 (igw 1개라 route table 1개)
resource "aws_route_table" "route_pub" {
  vpc_id = aws_vpc.common.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-pub",
    Service = "pub"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id // 모든 IP가 igw로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_sbn_puba" {
  subnet_id      = aws_subnet.puba.id
  route_table_id = aws_route_table.route_pub.id
}

// 2. private에 route table 생성 (nat 2개라 route table 2개)
// 2-1. sub_pria <-> a
resource "aws_route_table" "route_pria" {
  vpc_id = aws_vpc.common.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-pria",
    Service = "pria"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.puba.id // 모든 IP가 NAT로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_sbn_pria" {
  subnet_id      = aws_subnet.pria.id
  route_table_id = aws_route_table.route_pria.id
}

// 3. pod용 private-a에 route table 생성 
// pod 내부 nw으로 별도 라우팅 설정은 없어도 통신 가능하나
// s3를 위한 vpc endpoint routing을 위해 설정
resource "aws_route_table" "route_pri_pod" {
  vpc_id = aws_vpc.common.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-pri-pod",
    Service = "pri-pod"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.puba.id // 모든 IP가 NAT로 가도록 설정
  }
}

// vpc와 s3 연동을 위해 endpoint 설정
// 3-1. private route table 에 s3, dynamodb 등록 

resource "aws_vpc_endpoint" "s3" {
  depends_on   = [aws_s3_bucket.bucket]
  service_name = "com.amazonaws.ap-northeast-2.s3"
  vpc_id       = aws_vpc.common.id

  tags = {
    Name    = "vpc-${var.env}-${var.pjt}-endpoint",
    Service = "endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "asso_pria_s3" {
  route_table_id  = aws_route_table.route_pria.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint" "dynamodb_endpoint" {
  count        = var.enable_dynamodb ? 1 : 0
  service_name = "com.amazonaws.ap-northeast-2.dynamodb"
  vpc_id       = aws_vpc.common.id

  tags = {
    Name    = "vpc-${var.env}-${var.pjt}-endpoint",
    Service = "endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "asso_pria_dynamodb" {
  count           = var.enable_dynamodb ? 1 : 0
  route_table_id  = aws_route_table.route_pria.id
  vpc_endpoint_id = aws_vpc_endpoint.dynamodb_endpoint[0].id
}


// 4. db subnet에 route table 생성
resource "aws_route_table" "route_db" {
  vpc_id = aws_vpc.common.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-db",
    Service = "db"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.puba.id // 모든 IP가 NAT로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_db" {
  subnet_id      = aws_subnet.pria_db.id
  route_table_id = aws_route_table.route_db.id
}

// 5. tgw subnet에 route table 생성
resource "aws_route_table" "route_tgw" {
  vpc_id = aws_vpc.common.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-tgw",
    Service = "tgw"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.puba.id // 모든 IP가 NAT로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_sbn_tgw" {
  subnet_id      = aws_subnet.pria_tgw.id
  route_table_id = aws_route_table.route_tgw.id
}

// 5-1. tgw route table 에 s3, dynamodb 등록 
resource "aws_vpc_endpoint_route_table_association" "asso_tgw_s3" {
  route_table_id  = aws_route_table.route_tgw.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint_route_table_association" "asso_tgw_dynamodb" {
  count           = var.enable_dynamodb ? 1 : 0
  route_table_id  = aws_route_table.route_tgw.id
  vpc_endpoint_id = aws_vpc_endpoint.dynamodb_endpoint[0].id
}

#########
// Consol 상 Name에는 Tag name이, 보안그룹 이름에는 name이 들어감
// port forwarding을 위해 from_port와 to_port 값을 동일하게 설정

// 1. eks cluster 용 : in/out SSL/KubernetesControlPlane 포트 허용
// 2. workernode 용 : in/out 모든 포트 허용
// 3. pod 용 : in/out 모든 포트 허용
// 4. DB 용 : in DB 리스너 포트만 허용
// 5. EFS 용 : in은 NFS 포트만 허용, out은 모든 포트 허용
// 6. Bastion host 용 : in은 ssh 포트만 허용, out은 WEB/DB 포트만 허용
// 7. Elasticache 용 : in Elasticache 포트만 허용

// 1. eks cluster 용 security_group 
resource "aws_security_group" "eks_cluster" {
  count  = var.enable_eks ? 1 : 0
  name   = "sg_${var.env}-${var.pjt}-ekscluster" // sg의 naming rule에 맨앞 '-'가 허용 안되서 '_'사용
  vpc_id = aws_vpc.common.id

  egress { // all port
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-ekscluster",
    Service = "ekscluster"
  }
}

resource "aws_security_group_rule" "eks_cluster_egress" {
  for_each          = var.enable_eks ? var.sg_eks_cluster_egress : {}
  type              = "egress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.eks_cluster[0].id
}

resource "aws_security_group_rule" "eks_cluster_ingress" {
  for_each          = var.enable_eks ? var.sg_eks_cluster_ingress : {}
  type              = "ingress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.eks_cluster[0].id
}


// 2. workernode용 security_group
resource "aws_security_group" "eks_node" {
  count  = var.enable_eks ? 1 : 0
  name   = "sg_${var.env}-${var.pjt}-node"
  vpc_id = aws_vpc.common.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-node",
    Service = "node"
  }
}

resource "aws_security_group_rule" "eks_node_egress" {
  for_each          = var.enable_eks ? var.sg_eks_node_egress : {}
  type              = "egress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.eks_node[0].id
}

resource "aws_security_group_rule" "eks_node_ingress" {
  for_each          = var.enable_eks ? var.sg_eks_node_ingress : {}
  type              = "ingress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.eks_node[0].id
}

// 3. pod 용 security_group
resource "aws_security_group" "eks_pod" {
  count  = var.enable_eks ? 1 : 0
  name   = "sg_${var.env}-${var.pjt}-pod"
  vpc_id = aws_vpc.common.id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-pod",
    Service = "pod"
  }
}

resource "aws_security_group_rule" "eks_pod_egress" {
  for_each          = var.enable_eks ? var.sg_eks_pod_egress : {}
  type              = "egress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.eks_pod[0].id
}

resource "aws_security_group_rule" "eks_pod_ingress" {
  for_each          = var.enable_eks ? var.sg_eks_pod_ingress : {}
  type              = "ingress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.eks_pod[0].id
}

// 6. bastion 용 security_group
resource "aws_security_group" "bastion" {
  name   = "sg_${var.env}-${var.pjt}-bastion"
  vpc_id = aws_vpc.common.id

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-bastion",
    Service = "bastion"
  }
}

resource "aws_security_group_rule" "bastion_egress" {
  for_each          = var.sg_bastion_egress
  type              = "egress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "bastion_ingress" {
  for_each          = var.sg_bastion_ingress
  type              = "ingress"
  from_port         = each.key
  to_port           = each.key
  protocol          = each.value[0]
  cidr_blocks       = each.value[1]
  security_group_id = aws_security_group.bastion.id
}

// 7. elasticache 용 security_group
resource "aws_security_group" "elasticache" {
  count  = var.enable_elasticache ? 1 : 0
  name   = "sg_${var.env}-${var.pjt}-elasticache"
  vpc_id = aws_vpc.common.id

  ingress { // Elasticache 포트
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp" // tcp만 허용
    cidr_blocks = [aws_subnet.pria_db.cidr_block, aws_subnet.pric_db.cidr_block]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-elasticache",
    Service = "elasticache"
  }
}

#ucmp ami 권한 획득
data "aws_caller_identity" "self" {}

#// bastion ami image list
data "aws_ami_ids" "ucmp_ami_ids" {
  provider = aws.ucmp_owner
  owners   = [var.ami_ownerid]
  filter {
    name   = "name"
    values = ["${var.ami_env}-ucmp-*-ami-*"]
  }
}

data "aws_ami" "bastion" {
  provider    = aws.ucmp_owner
  most_recent = true
  owners      = [var.ami_ownerid]
  filter {
    name   = "name"
    values = ["${var.ami_env}-ucmp-bastion-ami-*"]
  }
}

// ami 리스트에 접근 권한 추가
resource "aws_ami_launch_permission" "bastion" {
  provider   = aws.ucmp_owner
  for_each   = toset(data.aws_ami_ids.ucmp_ami_ids.ids)
  image_id   = each.key
  account_id = data.aws_caller_identity.self.account_id
}

#########
// 1. s3 bucket 생성
// 2. vpc 내 pod에서 s3로 직접 연동할 수 있도록 vpc endpoint 생성
resource "random_string" "bucket" {
  keepers = {
    s3_name = "${var.env}-${var.pjt}"
  }
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "aws_s3_bucket" "bucket" {
  bucket = "s3-${var.env}-${var.pjt}-${random_string.bucket.result}" // 전세계 uniq한 값으로 설정

  tags = {
    Name    = "s3-${var.env}-${var.pjt}-original",
    Service = "original"
  }
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "burket_ver" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "cors_rule" {
  bucket = aws_s3_bucket.bucket.id
  cors_rule { // 해당 버킷에 허용하는 룰. GET, PUT, POST만 넣어줌
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

#######
// 1. bastion host용도의 ec2 생성
// 2. 인터넷 연동이 가능하도록 elastic ip 연동
// 3. ssh 연동을 위한 pem key와 key pair 생성

// bastion ec2 instance 생성
resource "aws_instance" "bastion" {
  #ami                         = var.bastion_ami
  ami                         = data.aws_ami.bastion.id
  instance_type               = local.bastion_type
  subnet_id                   = aws_subnet.puba.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  ebs_block_device {
    // device_name = "/dev/sd[f-p]"
    device_name           = "/dev/sdi"
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = false
  }

  tags = {
    Name    = "ec2-${var.env}-${var.pjt}-puba-bastion",
    Service = "puba-bastion"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

#####################
## WAF web ACL 생성
#####################

// lb 용 waf (ingress로 alb만든 후 적용 필요 여부 확인)
resource "aws_wafv2_web_acl" "waf_lb" {
  name  = "waf-${var.env}-${var.pjt}-lb"
  scope = "REGIONAL" // scope 은 CLoudFront일 때만 "CLOURFRONT", 그 외에 ALB, API GW에서 사용하는 ACL은 "REGIONAL"로 설정함
  default_action {
    allow {}
  } // default_action은 rule에 포함되지 않은 요청이 인입될 경우 디폴트 동작. 보안 가이드에 따라야 함 (block or allow)

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf-${var.env}-${var.pjt}-lb"
    sampled_requests_enabled   = true // AWS WAF가 규칙과 일치하는 웹 요청의 샘플링을 저장해야하는지 여부를 나타내는 부울
  }

  tags = {
    Name    = "waf-${var.env}-${var.pjt}-lb",
    Service = "lb"
  }
}

######
// Administrator 권한을 가진 그룹 생성 및 유저 추가
resource "aws_iam_group" "CloudArchitectureTeam" {
  name = "CloudArchitectureTeam"
}

resource "aws_iam_group_policy_attachment" "CloudArchitectureTeam" {
  group      = aws_iam_group.CloudArchitectureTeam.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user" "CloudArchitectureTeam" {
  for_each = toset(var.CloudArchitectureTeam_users)
  name     = each.key

  tags = {
    Name = "CloudArchitectureTeam_user"
  }
}

resource "aws_iam_user_group_membership" "CloudArchitectureTeam" {
  for_each = toset(var.CloudArchitectureTeam_users)
  user     = each.key

  groups = [
    aws_iam_group.CloudArchitectureTeam.name
  ]
}

// PowerUserAccess, IAMUserChangePassword 권한을 가진 그룹(개발사) 생성 및 유저 추가
resource "aws_iam_group" "developer" {
  name = "developer_group"
}

resource "aws_iam_group_policy_attachment" "developer" {
  for_each   = toset(local.developer_group_policy)
  group      = aws_iam_group.developer.name
  policy_arn = each.key
}

resource "aws_iam_user" "developer" {
  for_each = toset(var.developer_group_users)
  name     = each.key

  tags = {
    Name = "developer_group_user"
  }
}

resource "aws_iam_user_group_membership" "developer" {
  for_each = toset(var.developer_group_users)
  user     = each.key
  groups = [
    aws_iam_group.developer.name
  ]
}

// aws iam console 비밀번호 정책
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 8
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
}
