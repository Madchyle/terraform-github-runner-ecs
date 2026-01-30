terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Fixture: minimal `modules/runner_service` instantiation for `terraform test` (Fargate mode).
#
# Notes:
# - This fixture uses placeholder values (subnet/vpc/cluster/etc.).
# - The test file uses Terraform's native provider mocking (`mock_provider "aws" {}`)
#   so no AWS calls are made and no AWS credentials are required.
module "sut" {
  source = "../../../modules/runner_service"

  # Switch the module to Fargate behavior (task CPU/memory become required in the task definition).
  launch_type = "FARGATE"

  cluster_id   = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  cluster_name = "test"

  aws_region     = "us-east-1"
  aws_account_id = "000000000000"

  vpc_id  = "vpc-00000000000000000"
  subnets = ["subnet-00000000000000000", "subnet-11111111111111111"]

  github_org                      = "example"
  runner_token_ssm_parameter_name = "example/runner/token"

  # Ensure CPU/memory are set explicitly for this fixture.
  task_cpu    = "512"
  task_memory = "1024"
}

