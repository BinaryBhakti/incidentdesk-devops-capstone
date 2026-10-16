# EKS: a managed control plane + one managed node group of worker nodes.
#   control plane ENIs -> private AND public subnets (so the API endpoint and LBs work)
#   worker nodes       -> private subnets only (outbound via the NAT gateway, no public IPs)
#
# Plain resources rather than the terraform-aws-modules/eks module: every object is visible
# here, and `terraform plan` runs offline against LocalStack (no module-side API lookups).

locals {
  eks_count    = var.enable_eks ? 1 : 0
  cluster_name = "${local.name}-eks"
}

# ---- IAM: the role the EKS control plane assumes
data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count              = local.eks_count
  name               = "${local.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  count      = local.eks_count
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---- IAM: the role the worker nodes (EC2) assume
data "aws_iam_policy_document" "eks_node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  count              = local.eks_count
  name               = "${local.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = var.enable_eks ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # pull images (ECR); GHCR is public
  ]) : toset([])
  role       = aws_iam_role.eks_node[0].name
  policy_arn = each.value
}

# ---- the cluster
resource "aws_eks_cluster" "main" {
  count    = local.eks_count
  name     = local.cluster_name
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true # kubectl from a laptop / CI; restrict public_access_cidrs in prod
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true # whoever runs apply gets cluster-admin
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# ---- worker nodes: a managed node group in the private subnets
resource "aws_eks_node_group" "default" {
  count           = local.eks_count
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${local.cluster_name}-default"
  node_role_arn   = aws_iam_role.eks_node[0].arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = var.node_desired_size + 2 # headroom for the HPA to schedule extra pods
  }

  update_config {
    max_unavailable = 1
  }

  labels = { workload = "general" }

  # nodes need their IAM permissions before they can join; deleting them first strands the nodes
  depends_on = [aws_iam_role_policy_attachment.eks_node]
}
