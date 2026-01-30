###############################################################################
# Runner Infra Module - Outputs
#
# This file defines outputs exposed by the `runner_infra` module so callers can
# reference shared infrastructure (ECS cluster, EC2 capacity provider/ASG, etc.)
# without needing to know internal resource addresses.
#
# How this relates to `runner_service`:
# - `runner_infra` describes the shared *host layer* for EC2 launch type: the ECS cluster plus the
#   EC2 “ECS container instances” (hosts) created via Launch Template/ASG/capacity provider.
# - `runner_service` describes the *workload layer*: the ECS service/task definition that runs the
#   GitHub Actions runner containers on those hosts (or on Fargate when `launch_type = "FARGATE"`).
#
# These outputs describe the resources created/read by `runner_infra` (the host layer) as described above.
###############################################################################

# ECS cluster ID (the unique identifier for the cluster). If `create_cluster=false`,
# this is read from the existing cluster data source.
output "ecs_cluster_id" {
  description = "The ID of the ECS cluster." # Authored in this module's code (not derived from AWS)
  value = var.create_cluster ? aws_ecs_cluster.this[0].id : data.aws_ecs_cluster.existing_cluster[0].id # ECS cluster ID; from `aws_ecs_cluster.this[0].id` when created here, else `data.aws_ecs_cluster.existing_cluster[0].id`
}

# ECS cluster ARN (the full Amazon Resource Name). If `create_cluster=false`,
# this is read from the existing cluster data source.
output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster." # Authored in this module's code (not derived from AWS)
  value = var.create_cluster ? aws_ecs_cluster.this[0].arn : data.aws_ecs_cluster.existing_cluster[0].arn # ECS cluster ARN; from `aws_ecs_cluster.this[0].arn` when created here, else `data.aws_ecs_cluster.existing_cluster[0].arn`
}

# ECS cluster name. If `create_cluster=false`, this is read from the existing
# cluster data source.
output "ecs_cluster_name" {
  description = "The name of the ECS cluster." # Authored in this module's code (not derived from AWS)
  value = var.create_cluster ? aws_ecs_cluster.this[0].name : data.aws_ecs_cluster.existing_cluster[0].cluster_name # ECS cluster name; from `aws_ecs_cluster.this[0].name` when created here, else `data.aws_ecs_cluster.existing_cluster[0].cluster_name`
}

# ECS capacity provider name for EC2 capacity (only relevant when `launch_type = "EC2"`).
# When `launch_type != "EC2"`, this output is `null`.
output "ec2_capacity_provider_name" {
  description = "The name of the EC2 capacity provider (if EC2 launch type is used)." # Authored in this module's code (not derived from AWS)
  value       = local.is_ec2_launch_type ? aws_ecs_capacity_provider.ec2_capacity_provider[0].name : null # Capacity provider name; from `aws_ecs_capacity_provider.ec2_capacity_provider[0].name` when EC2 launch type, else null
}

# Auto Scaling Group name backing the ECS container instances (only relevant when `launch_type = "EC2"`).
# When `launch_type != "EC2"`, this output is `null`.
output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group (if EC2 launch type is used)." # Authored in this module's code (not derived from AWS)
  value       = local.is_ec2_launch_type ? aws_autoscaling_group.github_runner_asg[0].name : null # ASG name; from `aws_autoscaling_group.github_runner_asg[0].name` when EC2 launch type, else null
}

# Launch Template ID used by the ASG to create ECS container instances (only relevant when `launch_type = "EC2"`).
# When `launch_type != "EC2"`, this output is `null`.
output "launch_template_id" {
  description = "The ID of the EC2 Launch Template (if EC2 launch type is used)." # Authored in this module's code (not derived from AWS)
  value       = local.is_ec2_launch_type ? aws_launch_template.github_runner_lt[0].id : null # Launch template ID; from `aws_launch_template.github_runner_lt[0].id` when EC2 launch type, else null
}

# Launch Template name used by the ASG to create ECS container instances (only relevant when `launch_type = "EC2"`).
# When `launch_type != "EC2"`, this output is `null`.
output "launch_template_name" {
  description = "The name of the EC2 Launch Template (if EC2 launch type is used)." # Authored in this module's code (not derived from AWS)
  value       = local.is_ec2_launch_type ? aws_launch_template.github_runner_lt[0].name : null # Launch template name; from `aws_launch_template.github_runner_lt[0].name` when EC2 launch type, else null
}

# Security group ID attached to the ECS container instances (EC2 hosts running the ECS agent).
# This SG is created in this module and attached via the EC2 launch template networking configuration.
output "ecs_instances_security_group_id" {
  description = "Security group ID attached to ECS container instances." # Authored in this module's code (not derived from AWS)
  value       = aws_security_group.ecs_instances.id # Security group ID; from `aws_security_group.ecs_instances.id` created by this module
}


