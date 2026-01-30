###############################################################################
# Runner Infra Module - Locals
#
# This file defines computed values ("locals") used throughout the
# `modules/runner_infra` module. Locals are derived from input variables (`var.*`)
# and other locals (`local.*`) to keep naming consistent and avoid repeating
# conditional logic across multiple files.
#
# Where these locals are used:
# - `asg.tf`: uses `local.is_ec2_launch_type` to toggle EC2 resources and uses
#   `local.effective_prefix` for launch template / ASG naming.
# - `security-group.tf`: uses `local.effective_prefix` for the instance security
#   group name/description.
# - Other resources/outputs in this module use `local.effective_prefix` to keep
#   tags and names consistent across the shared infra layer.
###############################################################################

locals {
  # Launch-type switch used for conditional resources/arguments (derived from `var.launch_type`; referenced by `asg.tf`).
  # When true, this module creates the EC2 host layer (“ECS container instances”) that runner tasks run on.
  # It’s plural because runner_infra creates an Auto Scaling Group (ASG), which can run 0..N EC2 instances over time (scale out/in, replacements, multiple AZs).
  # It’s not automatically 1 EC2 host per runner:
  #    One EC2 host can run multiple runners (multiple ECS tasks/containers) if the instance has enough CPU/memory and your ECS service desired_count is > 1.
  #    You can end up close to 1:1 if instances are small, tasks are “big”, or you configure scaling/placement such that only one runner fits per host.
  is_ec2_launch_type = var.launch_type == "EC2" # True when `var.launch_type` is "EC2"; drives EC2-vs-Fargate conditionals (resource `count` and related logic)

  # Stable naming prefix used across infra resources (derived from `var.infra_name_prefix` and `var.cluster_name`).
  # Used to name/tag the shared infra resources that *create/manage* the EC2 instances (launch template, ASG, instance security group, capacity provider, etc.).
  effective_prefix = trimspace(var.infra_name_prefix) != "" ? var.infra_name_prefix : "${var.cluster_name}-gh-runner" # Base prefix: explicit `var.infra_name_prefix` if set, else derived from `var.cluster_name`
}


