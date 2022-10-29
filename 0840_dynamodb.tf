resource "aws_dynamodb_table" "dynamodb_table" {
  name         = "dynamodb-${var.env}-${var.pjt}-db"
  billing_mode = "PAY_PER_REQUEST"
  # read_capacity  = 20                 ## if billing mode is PROVISIONED, this field needs to be required
  # write_capacity = 20                 ## if billing mode is PROVISIONED, this field needs to be required
  hash_key  = "RuleSetId"
  range_key = "RuleSetInfo"


  ###########################
  ## Here's the guide for type
  ## S - String
  ## N - Number
  ## B - Binary Data
  ###########################

  attribute {
    name = "RuleSetId"
    type = "S"
  }

  attribute {
    name = "RuleSetInfo"
    type = "S"
  }

  # ttl {
  #   attribute_name = "TimeToExist"
  #   enabled        = false
  # }

  tags = {
    Name        = "dynamodb-${var.env}-${var.pjt}-examle-table",
    Environment = "production"
  }
}


resource "aws_vpc_endpoint" "dynamodb_endpoint" {
  depends_on   = [aws_dynamodb_table.dynamodb_table]
  service_name = "com.amazonaws.ap-northeast-2.dynamodb"
  vpc_id       = aws_vpc.vpc.id

  tags = {
    Name    = "vpc-${var.env}-${var.pjt}-endpoint",
    Service = "endpoint"
  }
}