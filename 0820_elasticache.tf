resource "aws_elasticache_replication_group" "cluster" {
  replication_group_description = "elasticache-${var.env}-${var.pjt}-cluster"
  automatic_failover_enabled    = false
  subnet_group_name             = aws_elasticache_subnet_group.subnetg_elasticache_redis.name
  replication_group_id          = "elasticache-${var.env}-${var.pjt}-replica"
  node_type                     = "cache.t3.micro"
  number_cache_clusters         = 1
  parameter_group_name          = "default.redis6.x"
  port                          = 6379
  at_rest_encryption_enabled    = true
  transit_encryption_enabled    = true

  tags = {
    Name    = "elasticache-${var.env}-${var.pjt}-cluster",
    Service = "cluster"
  }
}

resource "aws_elasticache_cluster" "replica" {
  count = 1

  cluster_id           = "elasticache-${var.env}-${var.pjt}-cluster-${count.index}"
  replication_group_id = aws_elasticache_replication_group.cluster.id
}