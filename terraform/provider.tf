# One provider block, two targets:
#   use_localstack = false (default) -> real AWS, credentials from env vars / SSO profile
#   use_localstack = true            -> LocalStack on localhost:4566 (what CI uses; no AWS account needed)
provider "aws" {
  region = var.aws_region

  # LocalStack accepts any credentials; "test" is its documented dummy. null = normal AWS chain.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      dynamodb = var.localstack_endpoint
      ec2      = var.localstack_endpoint
      eks      = var.localstack_endpoint
      iam      = var.localstack_endpoint
      s3       = var.localstack_endpoint
      sts      = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Session     = "21"
    }
  }
}

provider "random" {}
