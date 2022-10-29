# internet gateway 생성
# 

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name    = "igw-${var.env}-${var.pjt}-internetgw",
    Service = "internetgw"
  }
}
