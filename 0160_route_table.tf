# Routing Table 4개 생성 및 각 subnet 연결

# 1. route_pub : pub subnet에서 인터넷으로 (vpc에서 igw로 설정)
# 2. route_pri : pri subnet에서 인터넷으로 (vpc에서 nat로 설정)
# 3. route_pri_pod : pri_pod subnet 내 (선언만)
# 3-1. pri_pod subnet에서 s3으로 : vpc endpoint로 association 설정만 추가


# 1. public에 route table 생성 (igw 1개라 route table 1개)
resource "aws_route_table" "route_pub" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-pub",
    Service = "pub"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id # 모든 IP가 igw로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_sbn_puba" {
  subnet_id      = aws_subnet.sbn_puba.id
  route_table_id = aws_route_table.route_pub.id
}

# 2. private에 route table 생성 (nat 2개라 route table 2개)
# 2-1. sub_pria <-> nat_a
resource "aws_route_table" "route_pria" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-pria",
    Service = "pria"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id # 모든 IP가 NAT로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_sbn_pria" {
  subnet_id      = aws_subnet.sbn_pria.id
  route_table_id = aws_route_table.route_pria.id
}

# 3. pod용 private-a에 route table 생성 
# pod 내부 nw으로 별도 라우팅 설정은 없어도 통신 가능하나
# s3를 위한 vpc endpoint routing을 위해 설정
resource "aws_route_table" "route_pri_pod" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-pri-pod",
    Service = "pri-pod"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id # 모든 IP가 NAT로 가도록 설정
  }
}

# 3-1. private route table 에 s3, dynamodb 등록 
resource "aws_vpc_endpoint_route_table_association" "asso_pria_s3" {
  route_table_id  = aws_route_table.route_pria.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint_route_table_association" "asso_pria_dynamodb" {
  route_table_id  = aws_route_table.route_pria.id
  vpc_endpoint_id = aws_vpc_endpoint.dynamodb_endpoint.id
}


# 4. db subnet에 route table 생성
resource "aws_route_table" "route_db" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-db",
    Service = "db"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id # 모든 IP가 NAT로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_db" {
  subnet_id      = aws_subnet.sbn_pria_db.id
  route_table_id = aws_route_table.route_db.id
}

# 5. tgw subnet에 route table 생성
resource "aws_route_table" "route_tgw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "rt-${var.env}-${var.pjt}-tgw",
    Service = "tgw"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id # 모든 IP가 NAT로 가도록 설정
  }
}

resource "aws_route_table_association" "asso_sbn_tgw" {
  subnet_id      = aws_subnet.sbn_pria_tgw.id
  route_table_id = aws_route_table.route_tgw.id
}

# 5-1. tgw route table 에 s3, dynamodb 등록 
resource "aws_vpc_endpoint_route_table_association" "asso_tgw_s3" {
  route_table_id  = aws_route_table.route_tgw.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint_route_table_association" "asso_tgw_dynamodb" {
  route_table_id  = aws_route_table.route_tgw.id
  vpc_endpoint_id = aws_vpc_endpoint.dynamodb_endpoint.id
}