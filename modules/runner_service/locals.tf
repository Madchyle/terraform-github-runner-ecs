###############################################################################
# Runner Service Module - Locals
#
# This file defines computed values ("locals") used throughout the
# `modules/runner_service` module. Locals are derived from input variables
# (`var.*`) and other locals (`local.*`) to keep naming consistent and to avoid
# repeating conditional logic across multiple files.
#
# Where these locals are used:
# - `task_service.tf`: uses `local.is_ec2_launch_type` to toggle EC2 vs Fargate
#   settings, and uses `local.effective_ecs_service_name` / `local.effective_ecs_task_family`
#   to name the ECS service and task definition family.
# - `iam.tf`: uses `local.log_group_name` (CloudWatch log group name) and
#   `local.effective_prefix` (IAM role naming).
# - `security-group.tf`, `efs.tf`, `kms.tf`: use `local.effective_prefix` to
#   name/tag security groups, EFS resources, and KMS aliases/tags consistently.
# - `outputs.tf`: exposes `local.effective_prefix` to module callers.
###############################################################################

locals {
  # Launch-type switches used for conditional resource arguments (derived from `var.launch_type`; referenced by `task_service.tf`).
  is_ec2_launch_type = var.launch_type == "EC2"                                                                                            # True when `var.launch_type` is "EC2"; drives EC2-vs-Fargate conditionals in `task_service.tf`

  # Normalized identifiers used as stable naming inputs (derived from `var.github_org` / `var.resource_name_prefix`).
  # Terraform doesn't have regexreplace(); replace() supports regex when the pattern is wrapped in /.../.
  org_slug         = substr(replace(lower(var.github_org), "/[^0-9a-z-]/", "-"), 0, 32)                                                    # Lowercased+sanitized slug from `var.github_org` (regex replaces invalid chars), truncated to 32 chars
  effective_prefix = trimspace(var.resource_name_prefix) != "" ? var.resource_name_prefix : "gh-runner-${local.org_slug}"                  # Base prefix for this service: `var.resource_name_prefix` if set, else derived from `local.org_slug`

  # Fully-derived AWS resource names built from `local.effective_prefix` (referenced across multiple resource files).
  log_group_name             = "/ecs/${local.effective_prefix}"                                                                            # CloudWatch log group name string used by `aws_cloudwatch_log_group.github_runner` in `iam.tf`
  effective_ecs_service_name = "${local.effective_prefix}-service"                                                                         # ECS service name string used by `aws_ecs_service.github_runner_service` in `task_service.tf`
  effective_ecs_task_family  = "${local.effective_prefix}-task"                                                                            # ECS task definition family string used by `aws_ecs_task_definition.github_runner` in `task_service.tf`
}
