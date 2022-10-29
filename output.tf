output "ECR_REPOSITORY" {
  value       = aws_ecr_repository.ecr[0].name
  description = "ECR repository"
}

output "private_key" {
  value       = nonsensitive(tls_private_key.key.private_key_pem)
  description = "테라폼으로 생섣된 SSH 접속용 키값"
}

output "kubeconfig" {
  value       = module.eks.kubeconfig
  description = "kube-config 내용"
}