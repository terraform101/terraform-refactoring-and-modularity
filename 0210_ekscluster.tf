# 1. EKS Cluster 생성
# 1-1. role 연동
# 1-2. public access는 제한
# 1-3. subnet은 sbn_pri 사용
# 1-4. security group은 sg_cluster 사용
# 2. eks role 생성 후 eks cluster/service policy 연동

# 1-1. EKS 클러스터에 접근하기 위한 Role 생성
resource "aws_iam_role" "role_eks" {
  name = "iam-${var.env}-${var.pjt}-role-eks"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = {
    Name    = "iam-${var.env}-${var.pjt}-role-eks",
    Service = "role-eks"
  }
}

# 1-2. EKS 클러스터를 위한 Role과 정책 연결
resource "aws_iam_role_policy_attachment" "att_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.role_eks.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.role_eks.name
}


################
# EKS Cluster 생성
resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks-${var.env}-${var.pjt}-cluster"
  role_arn = aws_iam_role.role_eks.arn

  vpc_config { # eks에 private access 로 제한함
    endpoint_private_access = true
    endpoint_public_access  = true

    security_group_ids = [aws_security_group.sg_cluster.id]
    subnet_ids         = [aws_subnet.sbn_pria.id, aws_subnet.sbn_pric.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.att_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.att_AmazonEKSServicePolicy
  ]

  tags = {
    Name    = "eks-${var.env}-${var.pjt}-cluster",
    Service = "cluster"
  }
}

##################

data "aws_caller_identity" "current" {}

# OIDC Provider용 CA-thumbprint data 생성
data "tls_certificate" "cluster-tls" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}
# OIDC Provider 생성
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = [
    "sts.amazonaws.com",
  ]
  thumbprint_list = ["${data.tls_certificate.cluster-tls.certificates.0.sha1_fingerprint}"]
}

output "EKS_CLUSTER_NAME" {
  value = "eks-${var.env}-${var.pjt}-cluster"
}

output "oidc" {
  value = trimprefix("${aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer}", "https://")
}
output "thumb" {
  value = data.tls_certificate.cluster-tls.certificates.0.sha1_fingerprint
}

