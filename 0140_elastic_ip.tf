# eip는 계정별 리전 당 5개로 개수 제한됨.
# public ip 설정

# NAT 용 eip 생성 (NAT가 2개, eip도 각각 생성)
resource "aws_eip" "eip_nat_puba" {
  vpc        = true                       # EIP가 VPC에 있는지 여부
  depends_on = [aws_internet_gateway.igw] # igw 생성 이후 가능하기에 의존성 추가함
  tags = {
    Name    = "eip-${var.env}-${var.pjt}-nat-puba"
    Service = "nat-puba"
  }
}

# resource "aws_eip" "eip_nat_pubc" {
#   vpc        = true                       # EIP가 VPC에 있는지 여부
#   depends_on = [aws_internet_gateway.igw] # igw 생성 이후 가능하기에 의존성 추가함
#   tags = {
#     Name = "eip-${var.env}-${var.pjt}-nat-pubc"
#     Service = "nat-pubc"
#   }
# }

# Bastion 용 eip 생성
resource "aws_eip" "eip_bastion" {
  vpc        = true                       # EIP가 VPC에 있는지 여부
  depends_on = [aws_internet_gateway.igw] # igw 생성 이후 가능하기에 의존성 추가함
  tags = {
    Name    = "eip-${var.env}-${var.pjt}-bastion"
    Service = "bastion"
  }
}