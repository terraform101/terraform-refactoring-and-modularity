# 1. s3 bucket 생성
# 2. vpc 내 pod에서 s3로 직접 연동할 수 있도록 vpc endpoint 생성


resource "aws_s3_bucket" "bucket" {
  #  bucket = var.bucket # bucket naming rule에서 _ 허용 안됨.
  bucket = "s3-${var.env}-${var.pjt}-${var.bucket_serial}" # 전세계 uniq한 값으로 설정

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
  cors_rule { # 해당 버킷에 허용하는 룰. GET, PUT, POST만 넣어줌
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}
# vpc와 s3 연동을 위해 endpoint 설정
resource "aws_vpc_endpoint" "s3" {
  depends_on   = [aws_s3_bucket.bucket]
  service_name = "com.amazonaws.ap-northeast-2.s3"
  vpc_id       = aws_vpc.vpc.id

  tags = {
    Name    = "vpc-${var.env}-${var.pjt}-endpoint",
    Service = "endpoint"
  }
}