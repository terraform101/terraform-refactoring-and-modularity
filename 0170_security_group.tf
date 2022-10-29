# Consol 상 Name에는 Tag name이, 보안그룹 이름에는 name이 들어감
# port forwarding을 위해 from_port와 to_port 값을 동일하게 설정

# 1. eks cluster 용 : in/out SSL/KubernetesControlPlane 포트 허용
# 2. workernode 용 : in/out 모든 포트 허용
# 3. pod 용 : in/out 모든 포트 허용
# 4. DB 용 : in DB 리스너 포트만 허용
# 5. EFS 용 : in은 NFS 포트만 허용, out은 모든 포트 허용
# 6. Bastion host 용 : in은 ssh 포트만 허용, out은 WEB/DB 포트만 허용
# 7. Elasticache 용 : in Elasticache 포트만 허용

# 1. eks cluster 용 security_group 
resource "aws_security_group" "sg_cluster" {
  name   = "sg_${var.env}-${var.pjt}-ekscluster" # sg의 naming rule에 맨앞 '-'가 허용 안되서 '_'사용
  vpc_id = aws_vpc.vpc.id

  egress { # all port
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { # ssl 포트
    from_port   = 443
    to_port     = 443
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { # Kubernetes Control Plane 포트
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-ekscluster",
    Service = "ekscluster"
  }
}


# 2. workernode용 security_group
resource "aws_security_group" "sg_node" {
  name   = "sg_${var.env}-${var.pjt}-node"
  vpc_id = aws_vpc.vpc.id

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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-node",
    Service = "node"
  }
}

# 3. pod 용 security_group
resource "aws_security_group" "sg_pod" {
  name   = "sg_${var.env}-${var.pjt}-pod"
  vpc_id = aws_vpc.vpc.id

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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }



  tags = {
    Name    = "sg-${var.env}-${var.pjt}-pod",
    Service = "pod"
  }

}

# 4. db - service 용 security_group
# resource "aws_security_group" "sg_db_service" {
#   name   = "sg_${var.env}-${var.pjt}-db-service"
#   vpc_id = aws_vpc.vpc.id

#   ingress {  # DB 리스너 포트
#     from_port   = var.db_port
#     to_port     = var.db_port
#     protocol    = "tcp"
#     cidr_blocks = [var.pria_cidr, var.pric_cidr]
#   }

#   tags = {
#     Name    = "sg-${var.env}-${var.pjt}-db-service",
#     Service = "db-service"
#   }

# }

# 6. bastion 용 security_group
resource "aws_security_group" "sg_bastion" {
  name   = "sg_${var.env}-${var.pjt}-bastion"
  vpc_id = aws_vpc.vpc.id

  ingress { # ssh 접속 포트
    from_port   = 22
    to_port     = 22
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = var.bastion_cidr_block
  }

  egress { # WEB 포트
    from_port   = 80
    to_port     = 80
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 0322
  egress { # ternnel 용
    from_port   = 22
    to_port     = 22
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = ["0.0.0.0/0"]
  }
  # 0322

  # egress { # db 접근용
  #   from_port   = var.db_port
  #   to_port     = var.db_port
  #   protocol    = "tcp"
  #   cidr_blocks = [var.pria_db_cidr, var.pric_db_cidr]
  # }

  egress { # elasticache 접근용
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.pria_db_cidr, var.pric_db_cidr]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-bastion",
    Service = "bastion"
  }

}


# # 외부 보안 그룹에 추가 할 수 있는 단일 ingress또는 egress그룹 규칙
# resource "aws_security_group_rule" "ingress" {
#   cidr_blocks       = ["0.0.0.0/0"]
#   description       = "Allow all to communicate with the cluster API Server"
#   from_port         = 0
#   protocol          = "-1" # 모든 프로토콜 허용
#   security_group_id = aws_security_group.sg.id
#   to_port           = 0
#   type              = "ingress"
#   }

#############################################################################



# 7. elasticache 용 security_group
resource "aws_security_group" "sg_elasticache" {
  name   = "sg_${var.env}-${var.pjt}-elasticache"
  vpc_id = aws_vpc.vpc.id

  ingress { # Elasticache 포트
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp" # tcp만 허용
    cidr_blocks = [var.pria_db_cidr, var.pric_db_cidr]
  }

  tags = {
    Name    = "sg-${var.env}-${var.pjt}-elasticache",
    Service = "elasticache"
  }

}