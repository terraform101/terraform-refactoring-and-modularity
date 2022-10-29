output "cluster_NAME" {
  value       = "eks-${var.env}-${var.pjt}-cluster"
  description = "EKS 클러스터 이름"
}

output "oidc" {
  value       = trimprefix("${aws_eks_cluster.cluster.identity[0].oidc[0].issuer}", "https://")
  description = "EKS OIDC Issuer"
}

output "thumb" {
  value       = data.tls_certificate.cluster-tls.certificates.0.sha1_fingerprint
  description = "EKS fingerprint"
}

output "kubeconfig" {
  value       = local_file.kubeconfig.content
  description = "kube-config 내용"
}