resource "aws_security_group" "secgrp_rds" {
  name        = local.secgrp_rds_name
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  ingress {
    description     = "PostgreSQL access from EKS worker nodes"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.aws_base.outputs.eks_nodes_security_group_id]
  }

  tags = {
    Name = local.secgrp_rds_name
  }
}

resource "aws_security_group" "secgrp_cache" {
  name        = local.secgrp_cache_name
  description = "Security group for ElastiCache Valkey replication group"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  ingress {
    description     = "Valkey TLS access from EKS worker nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.aws_base.outputs.eks_nodes_security_group_id]
  }

  tags = {
    Name = local.secgrp_cache_name
  }
}
