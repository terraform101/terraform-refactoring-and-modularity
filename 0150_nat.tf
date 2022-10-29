# az별 NAT public subnet에 생성
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.eip_nat_puba.id
  subnet_id     = aws_subnet.sbn_puba.id
  depends_on    = [aws_internet_gateway.igw] # igw 생성 이후 가능하기에 의존성 추가함
  tags = {
    Name    = "nat-${var.env}-${var.pjt}-puba",
    Service = "puba"
  }
}

# resource "aws_nat_gateway" "nat_c" {
#   allocation_id = aws_eip.eip_nat_pubc.id
#   subnet_id     = aws_subnet.sbn_pubc.id
#   depends_on    = [aws_internet_gateway.igw] # igw 생성 이후 가능하기에 의존성 추가함
#   tags = {
#     Name    = "nat-${var.env}-${var.pjt}-pubc",
#     Service = "pubc"
#   }
# }