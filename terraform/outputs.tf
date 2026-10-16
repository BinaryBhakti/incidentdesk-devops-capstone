output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnets (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets (one per AZ)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "security_group_ids" {
  value = { web = aws_security_group.web.id, db = aws_security_group.db.id }
}

output "backup_bucket" {
  description = "Bucket for PostgreSQL backups"
  value       = aws_s3_bucket.backups.bucket
}

output "backup_role_arn" {
  value = aws_iam_role.backup.arn
}

output "tf_lock_table" {
  value = aws_dynamodb_table.tf_lock.name
}

output "eks_cluster_name" {
  description = "EKS cluster name (null when enable_eks = false)"
  value       = one(aws_eks_cluster.main[*].name)
}

output "eks_cluster_endpoint" {
  value = one(aws_eks_cluster.main[*].endpoint)
}

output "kubeconfig_command" {
  description = "Run this after apply to point kubectl at the new cluster"
  value       = var.enable_eks ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}" : null
}
