###############################################################################
# Runner Service Module - Outputs
#
# This file defines the outputs exposed by the `runner_service` module. Outputs
# let callers reference important created resources (service name, task family,
# log group, etc.) without needing to know internal resource addresses
# like `aws_ecs_service.github_runner_service`.
###############################################################################

# ECS service name created by this module (useful for `aws ecs describe-services`,
# scaling, or forcing a new deployment).
output "ecs_service_name" {
  description = "The name of the ECS service."                 # Authored in this module's code (not derived from AWS)
  value       = aws_ecs_service.github_runner_service.name      # The ECS service name string; from the `aws_ecs_service.github_runner_service` resource created by this module
}

# ECS task definition family name for the runner task (the stable family identifier
# across task definition revisions).
output "ecs_task_family" {
  description = "ECS task family name."                        # Authored in this module's code (not derived from AWS)
  value       = aws_ecs_task_definition.github_runner.family   # The ECS task definition family (stable family identifier across revisions); from `aws_ecs_task_definition.github_runner`
}

# CloudWatch Logs log group used by the runner containers (useful for log tailing,
# alerts, and retention management).
output "log_group_name" {
  description = "CloudWatch log group name for the runner containers." # Authored in this module's code (not derived from AWS)
  value       = aws_cloudwatch_log_group.github_runner.name            # The CloudWatch Logs log group name string; from `aws_cloudwatch_log_group.github_runner` created by this module
}

# Effective prefix used for naming resources created by this module (derived from
# inputs when no explicit prefix is provided).
output "effective_prefix" {
  description = "Effective prefix used to name this runner service resources." # Authored in this module's code (not derived from AWS)
  value       = local.effective_prefix                                         # The computed naming prefix used by this module for resource names; derived in `locals` from `var.*` inputs
}


