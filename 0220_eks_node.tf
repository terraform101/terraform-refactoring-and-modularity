# 1. eks worker node group 생성
# 1-1. eks cluster 설정
# 1-2. role 연동
# 1-3. subnet 설정
# 1-4. instance type, disk size 설정
# 1-5. auto scailing 설정 : desired/max/min size
# 2. ec2 role 생성 후 EKSWorkerNode/EKS_CNI/EC2ContainerRegistryReadOnly/S3FullAccess policy 연동

# 2-1. worker node를 위한 role 생성
resource "aws_iam_role" "role_node" {
  name = "iam-${var.env}-${var.pjt}-role-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = {
    Name    = "iam-${var.env}-${var.pjt}-role-node",
    Service = "role-node"
  }
}

# 2-2. worker node를 위한 role과 정책 연결
resource "aws_iam_role_policy_attachment" "att_AmazonEKSWorkerNodePolicy" { # AWS EKS Worker Node Policy
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.role_node.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonEKS_CNI_Policy" { # AWS CNI가 VPC CIDR을 가지고 IP 할당하기에 필요
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.role_node.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonEC2ContainerRegistryReadOnly" { # EC2 Container Registry에 대한 읽기전용 권한 부여
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.role_node.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonS3FullAccess" { # S3 Access 권한 부여
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.role_node.name
}


resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.eks_cluster.name # eks-cluster name
  node_group_name = "eks-${var.env}-${var.pjt}-node"
  node_role_arn   = aws_iam_role.role_node.arn
  subnet_ids      = [aws_subnet.sbn_pria.id]

  launch_template {
    name    = aws_launch_template.eks-node.name
    version = "$Default"
  }
  scaling_config {
    desired_size = var.scailing_desired
    max_size     = var.scailing_max
    min_size     = var.scailing_min
  }

  depends_on = [
    aws_iam_role_policy_attachment.att_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.att_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.att_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.att_AmazonS3FullAccess,
    null_resource.eks-secondary-cidr-1
  ]

  tags = {
    Name    = "eks-${var.env}-${var.pjt}-node",
    Service = "node"
  }

}


