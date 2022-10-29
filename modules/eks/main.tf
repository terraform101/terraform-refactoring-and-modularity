locals {
  cluster_policy = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy",
  ]
  node_policy = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
  ]
  oidc                = trimprefix("${aws_eks_cluster.cluster.identity[0].oidc[0].issuer}", "https://")
  yaml_crd_path       = "${path.module}/yaml/sencondry_cidr/CustomResourceDefinition.yaml"
  yaml_eni_path       = "${path.module}/yaml/sencondry_cidr/ENIconfig.yaml"
  yaml_sa_path        = "${path.module}/yaml/sencondry_cidr/ServiceAccount.yaml"
  yaml_cert_mgmt_path = "${path.module}/yaml/ingress/cert-manager.yaml"
  yaml_ingress_path   = "${path.module}/yaml/ingress/IngressController.yaml"
}

// 1. EKS Cluster 생성
// 1-1. role 연동
// 1-2. public access는 제한
// 1-3. subnet은 sbn_pri 사용
// 1-4. security group은 cluster 사용
// 2. eks role 생성 후 eks cluster/service policy 연동

// 1-1. EKS 클러스터에 접근하기 위한 Role 생성
resource "aws_iam_role" "cluster" {
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

// 1-2. EKS 클러스터를 위한 Role과 정책 연결
resource "aws_iam_role_policy_attachment" "cluster" {
  for_each   = toset(local.cluster_policy)
  policy_arn = each.key
  role       = aws_iam_role.cluster.name
}

################
// EKS Cluster 생성
resource "aws_eks_cluster" "cluster" {
  name     = "eks-${var.env}-${var.pjt}-cluster"
  role_arn = aws_iam_role.cluster.arn

  vpc_config { // eks에 private access 로 제한함
    endpoint_private_access = true
    endpoint_public_access  = true

    security_group_ids = var.eks_cluster_security_group_ids
    subnet_ids         = var.eks_cluster_subnet_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster
  ]

  tags = {
    Name    = "eks-${var.env}-${var.pjt}-cluster",
    Service = "cluster"
  }
}

##################

data "aws_caller_identity" "current" {}

// OIDC Provider용 CA-thumbprint data 생성
data "tls_certificate" "cluster-tls" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}
// OIDC Provider 생성
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  client_id_list = [
    "sts.amazonaws.com",
  ]
  thumbprint_list = ["${data.tls_certificate.cluster-tls.certificates.0.sha1_fingerprint}"]
}

// 1. eks worker node group 생성
// 1-1. eks cluster 설정
// 1-2. role 연동
// 1-3. subnet 설정
// 1-4. instance type, disk size 설정
// 1-5. auto scailing 설정 : desired/max/min size
// 2. ec2 role 생성 후 EKSWorkerNode/EKS_CNI/EC2ContainerRegistryReadOnly/S3FullAccess policy 연동

// 2-1. worker node를 위한 role 생성
resource "aws_iam_role" "node" {
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

// 2-2. worker node를 위한 role과 정책 연결
resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(local.node_policy)
  policy_arn = each.key
  role       = aws_iam_role.node.name
}

resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.cluster.name // eks-cluster name
  node_group_name = "eks-${var.env}-${var.pjt}-node"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.eks_cluster_subnet_ids

  launch_template {
    name    = aws_launch_template.eks_node.name
    version = "$Default"
  }
  scaling_config {
    desired_size = var.eks_scailing_desired
    max_size     = var.eks_scailing_max
    min_size     = var.eks_scailing_min
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    null_resource.eks-secondary-cidr-1
  ]

  tags = {
    Name    = "eks-${var.env}-${var.pjt}-node",
    Service = "node"
  }
}

###################################################################
// EKS Custom AMI 사용시 launch template을 통해 Node 추가가 필요함
// User Data는 줄바꿈이 민감하므로 아래 포맷을 잘 지킬것
###################################################################
resource "aws_launch_template" "eks_node" {
  name = "${var.env}-${var.pjt}-ucmp-eks-node-template-v0.2"
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 300
      volume_type = "gp3"
      encrypted   = true
    }
  }

  image_id      = var.eks_node_ami_id
  instance_type = var.node_instance_types
  key_name      = var.key_pair_name
  #user_data = filebase64("./custom_script/installsw.sh")
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
sudo /etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.cluster.certificate_authority.0.data}' '${aws_eks_cluster.cluster.name}'

--==MYBOUNDARY==--\
  EOF
  )


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-${var.env}-${var.pjt}-node",
    }
  }
}


// AWS ingress-controller 가이드 참고
// https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-alb-ingress-controller-setup/

// EKS Cluster 정보 확인
data "aws_eks_cluster" "eks_cluster" {
  name = aws_eks_cluster.cluster.name
}

data "aws_eks_cluster_auth" "eks_cluster" {
  depends_on = [aws_eks_cluster.cluster]
  name       = aws_eks_cluster.cluster.name
}
// kubernetes Provider 사용, token을 발급받아 Cluster 접속
// provider "kubernetes" {
//   alias                  = "eks"
//   host                   = data.aws_eks_cluster.cluster.endpoint
//   cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
//   exec {
//     api_version = "client.authentication.k8s.io/v1alpha1"
//     args        = ["eks", "get-token", "--cluster-name", "${aws_eks_cluster.cluster.name}"]
//     command     = "aws"
//   }
// }

// ingress-contoller 동작에 필요한 IAM Policy 생성
resource "aws_iam_policy" "load_balancer_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.env}-${var.pjt}"
  path        = "/"
  description = "AWS LoadBalancer Controller IAM Policy"
  policy      = file("${path.module}/iam-policy.json")
}

// ingress-contoller 동작에 필요한 IAM Role 생성
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  name = "aws-load-balancer-controller-${var.env}-${var.pjt}"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${local.oidc}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

// Load Balancer controller 동작에 필요한 IAM Policy-Role Attachment
resource "aws_iam_role_policy_attachment" "alb_controller_attachment" {
  role       = aws_iam_role.aws_load_balancer_controller_role.name
  policy_arn = aws_iam_policy.load_balancer_policy.arn
}

resource "local_file" "kubeconfig" {
  content = templatefile("${path.module}/template/kubeconfig.tpl", {
    endpoint    = aws_eks_cluster.cluster.endpoint,
    authority   = aws_eks_cluster.cluster.certificate_authority.0.data,
    clustername = aws_eks_cluster.cluster.name
  })
  filename = pathexpand("~/.kube/config")
}

resource "local_file" "crd" {
  content  = templatefile("${path.module}/template/crd.tpl", {})
  filename = local.yaml_crd_path
}

resource "local_file" "eniconfig" {
  content = templatefile("${path.module}/template/eniconfig.tpl", {
    subnet_a_id       = var.eks_cluster_subnet_ids[0],
    subnet_c_id       = var.eks_cluster_subnet_ids[1],
    security_group_id = var.eks_cluster_security_group_ids[0]
  })
  filename = local.yaml_eni_path
}

resource "local_file" "sa" {
  content = templatefile("${path.module}/template/sa.tpl", {
    arn = aws_iam_role.aws_load_balancer_controller_role.arn
  })
  filename = local.yaml_sa_path
}

// EKS Pod의 Secondary CIDR 구성& Load Balancer controller 동작에 필요한 ServiceAccount 생성
resource "null_resource" "eks-secondary-cidr-1" {
  depends_on = [
    local_file.kubeconfig,
    local_file.crd,
    local_file.eniconfig,
    local_file.sa,
    aws_eks_cluster.cluster,
    aws_iam_role_policy_attachment.alb_controller_attachment
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOF
ls -al ./
ls -al ${path.module}
cd ${path.module}
chmod +x ./kubectl
chmod +x ./aws-iam-authenticator
export PATH=$PATH:$(pwd)
cd -

kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
sleep 20
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone
kubectl apply -f ${local.yaml_crd_path}
kubectl apply -f ${local.yaml_eni_path}
kubectl apply -f ${local.yaml_sa_path}
    EOF
  }
}

resource "local_file" "cert_manager" {
  content = templatefile("${path.module}/template/cert-manager.tpl", {
    cluster_name = aws_eks_cluster.cluster.name
  })
  filename = local.yaml_cert_mgmt_path
}

resource "local_file" "ingress" {
  content = templatefile("${path.module}/template/ingress.tpl", {
    cluster_name = aws_eks_cluster.cluster.name
  })
  filename = local.yaml_ingress_path
}

resource "null_resource" "kubectl" {
  depends_on = [
    local_file.kubeconfig,
    local_file.cert_manager,
    local_file.ingress,
    null_resource.eks-secondary-cidr-1,
    aws_eks_node_group.node
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    // Load credentials to local environment so subsequent kubectl commands can be run
    command = <<EOF
ls -al ./
ls -al ${path.module}
cd ${path.module}
chmod +x ./kubectl
chmod +x ./aws-iam-authenticator
export PATH=$PATH:$(pwd)
cd -

kubectl version --client
kubectl version
kubectl apply -f ${local.yaml_cert_mgmt_path}
kubectl rollout status deployment cert-manager-webhook -n cert-manager
kubectl apply -f ${local.yaml_ingress_path}
kubectl rollout status deployment aws-load-balancer-controller -n kube-system
    EOF
  }
}

// kubectl-destroy
resource "null_resource" "kubectl-destroy" {
  depends_on = [
    aws_eks_node_group.node,
    aws_iam_openid_connect_provider.eks_oidc_provider,
    aws_iam_policy.load_balancer_policy,
    aws_iam_role.aws_load_balancer_controller_role,
    aws_iam_role_policy_attachment.alb_controller_attachment,
    local_file.kubeconfig
  ]
  triggers = {
    kube = local_file.kubeconfig.content
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
ls -al ./
ls -al ${path.module}
cd ${path.module}
chmod +x ./kubectl
chmod +x ./aws-iam-authenticator
export PATH=$PATH:$(pwd)
cd -

kubectl version --client
kubectl version
kubectl get all --all-namespaces
KUBECTL_GET_ING=`./kubectl get ingress --all-namespaces`
if [[ -z $KUBECTL_GET_ING ]]
then
  echo "No Ingress Resources Found."
else
  kubectl get ingress --all-namespaces | grep -v NAMESPACE | awk '{ print "kubectl delete ingress "$2" -n "$1 }' | sh -v
fi
kubectl get all --all-namespaces
    EOF
  }
}





