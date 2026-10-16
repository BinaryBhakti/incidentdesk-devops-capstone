variable "aws_region" {
  description = "AWS region (LocalStack honours it for ARNs and AZ names)."
  type        = string
  default     = "ap-south-1"
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint."
  type        = string
  default     = "http://localhost:4566"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "incidentdesk"
}

variable "environment" {
  description = "dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "VPC address space."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Two availability zones: one public + one private subnet in each."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "backup_retention_days" {
  description = "Days before database backups are deleted."
  type        = number
  default     = 90
}

variable "use_localstack" {
  description = "true: send every AWS call to LocalStack (CI / no AWS account). false: real AWS."
  type        = bool
  default     = false
}

variable "enable_eks" {
  description = "Create the EKS cluster + managed node group. LocalStack community has no EKS API, so CI plans with true and applies with false."
  type        = bool
  default     = true
}

variable "eks_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.33"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Worker nodes in the managed node group (min 1, max desired+2)."
  type        = number
  default     = 2
}
