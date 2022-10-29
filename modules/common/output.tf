output "eks_cluster_security_group_ids" {
  value       = [aws_security_group.eks_cluster[0].id]
  description = "EKS 클러스터 생성에 필요한 보안 그룹 아이디 목록"
}

output "eks_cluster_subnet_ids" {
  value       = [aws_subnet.pria.id, aws_subnet.pric.id]
  description = "EKS 클러스터 생성에 필요한 서브넷 아이디 목록"
}

output "elasticache_redis_name" {
  value       = var.enable_elasticache ? aws_elasticache_subnet_group.elasticache_redis[0].name : ""
  description = "Elasticache 이름"
}