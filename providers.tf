# Terraform configuration block: defines which providers (plugins) are needed
# and where to store Terraform's state file (which tracks what resources exist)

terraform {
  # Required providers: tells Terraform which plugins to download and use
  required_providers {
    # The AWS provider lets Terraform create and manage AWS resources (EC2, ECS, etc.)
    aws = {
      source  = "hashicorp/aws"  # Official AWS provider from HashiCorp
      version = "~> 5.0"         # Use version 5.x (allows 5.0, 5.1, 5.2, etc., but not 6.0)
    }
  }
  # Backend configuration: the "s3" backend tells Terraform to store its state file in an S3 bucket
  # The region specifies the AWS region where the S3 bucket containing the state file is located.
  # Backend config (bucket/key/region/etc.) is supplied at `terraform init` time,
  # e.g. via CI: terraform init -backend-config="region=..." ...
  backend "s3" {}
}

# AWS provider configuration: tells Terraform which AWS region to use for resources
# This uses a variable so you can deploy to different regions (us-east-1, us-west-2, etc.)
provider "aws" {
  region = var.aws_region  # Set via TF_VAR_aws_region in the deployment workflow
}