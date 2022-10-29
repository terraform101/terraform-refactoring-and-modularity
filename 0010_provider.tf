terraform {
  cloud {
    organization = "LG-uplus"
    hostname     = "app.terraform.io"
    workspaces {
      name = "iac-academy"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags { # 모든 resource에 기본으로 설정되는 Tag
    tags = {
      Environment = var.env
      Project     = var.pjt
      COST_CENTER = "${var.env}_${var.pjt}"
    }
  }
}

provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

provider "aws" {
  alias      = "ucmp_owner"
  region     = var.region
  access_key = var.ucmp-access-key
  secret_key = var.ucmp-access-secret
}