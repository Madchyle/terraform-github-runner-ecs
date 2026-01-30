# ==============================================================================
# Runner Service Module - Input Variables
# ==============================================================================
#
# This file defines all input variables for the `runner_service` Terraform module.
# These variables control how a GitHub Actions runner service is deployed on ECS,
# including networking, scaling, logging, and runner registration configuration.
#
# Each variable below includes:
# - A short comment explaining what it is/does (for quick scanning)
# - A Terraform `description` attribute used by `terraform docs` and validation
#
# ==============================================================================

# ECS cluster ID where the service will be created (target cluster for ECS APIs).
variable "cluster_id" {
  description = "ECS cluster ID to deploy the service into."
  type        = string
}

# ECS cluster name used for naming/tagging resources (not used to look up the cluster).
variable "cluster_name" {
  description = "ECS cluster name (used only for naming)."
  type        = string
}

# ECS launch type for the service. Use "EC2" for capacity providers/ASG hosts,
# or "FARGATE" for serverless tasks (some options differ by launch type).
variable "launch_type" {
  description = "Launch type for the ECS service (EC2 or FARGATE)."
  type        = string
  default     = "EC2"
}

# Optional capacity provider name to use for EC2 launch type services.
# If unset, ECS uses the cluster default capacity provider strategy.
variable "capacity_provider_name" {
  description = "Capacity provider name to use for the ECS service (recommended for EC2 launch type). If null/empty, the cluster default capacity provider strategy is used."
  type        = string
  default     = null
}

# AWS region where resources are created and where the service runs.
variable "aws_region" {
  description = "AWS region"
  type        = string
}

# AWS account ID used for constructing ARNs and other account-scoped values.
variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

# VPC ID where the ECS tasks and EFS mount targets will live.
variable "vpc_id" {
  description = "VPC id"
  type        = string
}

# Subnet IDs used for task ENIs (awsvpc) and for EFS mount targets.
# Typically private subnets across at least two AZs for availability.
variable "subnets" {
  description = "List of subnet IDs for the ECS service networking and EFS mount targets."
  type        = list(string)
}

# Additional security group IDs to attach to task ENIs.
# This complements the module-managed security group rules.
variable "security_group_ids" {
  description = "Optional: Additional security group IDs to attach to the ECS tasks."
  type        = list(string)
  default     = []
}

# For Fargate only: whether to assign public IPs to task ENIs.
# Ignored for EC2 launch type tasks.
variable "assign_public_ip" {
  description = "Whether to assign a public IP to the ECS task ENI (only applies to launch_type=FARGATE; ignored for EC2)."
  type        = bool
  default     = false
}

# Optional prefix used when naming resources created by this module.
# If empty, the module derives a prefix from the GitHub org value.
variable "resource_name_prefix" {
  description = "Optional: Prefix used to name AWS resources created by this runner service. If empty, it is derived from github_org."
  type        = string
  default     = ""
}

# GitHub organization name (org-scoped runners) or "OWNER/REPO" for repo-scoped runners.
# Used when registering the runner with GitHub.
variable "github_org" {
  description = "GitHub organization name (or owner/repo for repo-scoped runners)."
  type        = string
}

# SSM Parameter Store name/path that contains the GitHub runner registration token.
# Marked sensitive because it is used to obtain the short-lived registration token.
variable "runner_token_ssm_parameter_name" {
  description = "Name of the SSM parameter storing the GitHub runner token"
  type        = string
  sensitive   = true
}

# Container image to run for the GitHub Actions runner task.
# Should be an ECR (or other registry) image URI compatible with your ECS setup.
variable "runner_image" {
  description = "Docker image for the GitHub runner"
  type        = string
  default     = "github-runner:latest"
}

# Prefix used to name runners as they appear in GitHub (unique suffix is added by runner).
# Helps identify which ECS service a runner belongs to.
variable "runner_name_prefix" {
  description = "Prefix for the GitHub runner name (as it appears in GitHub)."
  type        = string
  default     = "ecs-github-runner"
}

# Comma-separated labels applied to the runner in GitHub.
# Workflows use these in `runs-on` to target this runner pool.
variable "runner_labels" {
  description = "Labels for the GitHub runner"
  type        = string
  default     = "self-hosted,ph-dev,ec2,ecs"
}

# Whether the runner's persistent volume (EFS) should be mounted read-only.
# Useful for hardening, but may break runners that need to write to the volume.
variable "read_only_volume" {
  description = "Whether the runner volume is read-only"
  type        = bool
  default     = false
}

# Desired number of runner tasks for this ECS service.
# Controls parallel job capacity (higher = more concurrent workflows).
variable "desired_count" {
  description = "Desired number of GitHub runner tasks"
  type        = number
  default     = 1
}

# ECS service deployment configuration (rolling update behavior).
variable "deployment_minimum_healthy_percent" {
  description = "ECS service deployment minimum healthy percent (default 100 = no scale-down during deployments)."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "ECS service deployment maximum percent (default 200 = allow 100% surge during deployments)."
  type        = number
  default     = 200
}

# CloudWatch Logs retention for the runner task log group.
# Larger values retain logs longer but can increase costs.
variable "log_retention_in_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}

# ECS task definition network mode. `awsvpc` is required for Fargate and common for EC2.
# Determines how task networking/ENIs are allocated.
variable "network_mode" {
  description = "ECS task network mode"
  type        = string
  default     = "awsvpc"
}

# ECS task definition compatibilities. Typically ["EC2"] or ["FARGATE"] depending on launch type.
# This should align with `launch_type` and task definition settings.
variable "requires_compatibilities" {
  description = "List of launch type compatibilities for the task"
  type        = list(string)
  default     = ["EC2"]
}

# Task CPU value (primarily relevant/required for Fargate). Must match valid Fargate CPU sizes.
# For EC2, this still sets task-level CPU reservations/limits as configured.
variable "task_cpu" {
  description = "Task-level CPU for Fargate (required when launch_type=FARGATE). Example values: 256, 512, 1024, 2048, 4096."
  type        = string
  default     = "2048"
}

# Task memory value (primarily relevant/required for Fargate). Must match valid Fargate memory sizes.
# For EC2, this still sets task-level memory reservations/limits as configured.
variable "task_memory" {
  description = "Task-level memory for Fargate (required when launch_type=FARGATE). Example values: 512, 1024, 2048, 4096, 8192."
  type        = string
  default     = "4096"
}

# Whether to run a privileged Docker-in-Docker (DinD) sidecar container.
# Requires EC2 launch type; Fargate does not support privileged containers.
variable "enable_dind" {
  description = "Enable Docker-in-Docker sidecar (requires EC2 launch type; Fargate does not support privileged containers)."
  type        = bool
  default     = true
}

# ECR resource ARN pattern used when granting pull permissions to the task role.
# Set to a specific repo ARN for least privilege (default "*" is permissive).
variable "ecr_resource_arn" {
  description = "ECR resource ARN for permissions"
  type        = string
  default     = "*"
}