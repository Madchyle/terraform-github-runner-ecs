###############################################################################
# Runner Infra Module - ECS (cluster + capacity providers)
#
# This file defines the ECS control-plane resources used by the shared infra layer:
# - The ECS cluster (optionally created, or looked up if you supply an existing one)
# - The cluster capacity provider wiring (EC2 capacity provider when `launch_type = "EC2"`, or Fargate)
#
# How this relates to `runner_service`:
# - `runner_infra` defines the *capacity/host layer* (ECS cluster + capacity providers + EC2 hosts/ASG for EC2 launch type).
# - `runner_service` defines the *workload layer* (ECS service/task definition for the GitHub runner containers) that ECS schedules onto that capacity.
###############################################################################

# What it is: an ECS cluster (the logical scheduler “home” where services/tasks run).
# Definition: an ECS cluster is a regional control-plane construct that tracks where ECS should place tasks (onto EC2 “container instances” or Fargate capacity).
# What it attaches to: capacity providers are attached to the cluster via `aws_ecs_cluster_capacity_providers.this` below.
resource "aws_ecs_cluster" "this" {
  # checkov:skip=CKV_AWS_65:Ensure container insights are enabled on ECS cluster because it is conditionally created and enabled when created.
  count = var.create_cluster ? 1 : 0 # Create a cluster only when `var.create_cluster` is true (otherwise we reference an existing cluster)
  name  = var.cluster_name           # Cluster name; from module input `var.cluster_name`
}

# What it is: a data lookup for an existing ECS cluster.
# Definition: a data source reads an already-existing AWS object instead of creating it.
# What it attaches to: used as the cluster reference when `var.create_cluster = false` (for example by outputs and capacity provider attachment).
data "aws_ecs_cluster" "existing_cluster" {
  count        = var.create_cluster ? 0 : 1 # Only look up an existing cluster when we are not creating one
  cluster_name = var.cluster_name           # Existing cluster name to look up; from module input `var.cluster_name`
}

# What it is: an ECS capacity provider backed by an Auto Scaling Group (ASG).
# Definition: a capacity provider tells ECS *where capacity comes from*; for EC2 it points at an ASG that provides the EC2 hosts (“ECS container instances”).
# What it attaches to: attaches to the ASG via `auto_scaling_group_provider`, and is then attached to the ECS cluster via `aws_ecs_cluster_capacity_providers.this`.
resource "aws_ecs_capacity_provider" "ec2_capacity_provider" {
  count = local.is_ec2_launch_type ? 1 : 0 # Only create an EC2 capacity provider when using EC2 launch type
  name  = "${local.effective_prefix}-ec2-capacity-provider" # Capacity provider name; derived from `local.effective_prefix` (see `locals.tf`)

  # What it is: an Auto Scaling Group provider block for this ECS capacity provider.
  # Definition: this tells ECS which ASG supplies the EC2 hosts (“ECS container instances”) and how ECS should treat instance termination while tasks are running.
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.github_runner_asg[0].arn # The ASG that supplies EC2 hosts; created in `asg.tf`
    managed_termination_protection = "ENABLED" # Tell ECS to avoid terminating instances that are running tasks during scale-in/termination

    # What it is: managed scaling configuration for the ASG capacity provider.
    # Definition: when enabled, ECS adjusts the ASG desired capacity to keep cluster capacity near `target_capacity` utilization for tasks placed via this provider.
    managed_scaling {
      status          = "ENABLED" # Let ECS manage scaling decisions for the ASG via the capacity provider
      target_capacity = 100       # Target utilization (%) ECS aims for when scaling managed capacity (100 = try to keep capacity fully utilized)
    }
  }
}

# What it is: attaches capacity providers to an ECS cluster and sets a default strategy.
# Definition: cluster capacity providers are the set of “capacity sources” ECS is allowed to use for services/tasks in that cluster.
# What it attaches to: attaches capacity provider(s) to the ECS cluster identified by `cluster_name`.
resource "aws_ecs_cluster_capacity_providers" "this" {
  count = var.manage_cluster_capacity_providers ? 1 : 0 # Only manage cluster capacity providers when explicitly enabled
  cluster_name = var.create_cluster ? aws_ecs_cluster.this[0].name : var.cluster_name # Target cluster name: created cluster name if we created it, else the provided existing name
  capacity_providers = local.is_ec2_launch_type ? [aws_ecs_capacity_provider.ec2_capacity_provider[0].name] : ["FARGATE"] # Allowed capacity sources: EC2 capacity provider or Fargate

  # What it is: the default capacity provider strategy block for the ECS cluster.
  # Definition: this sets which capacity provider ECS will use by default for services/tasks when they don't specify one explicitly.
  default_capacity_provider_strategy {
    capacity_provider = local.is_ec2_launch_type ? aws_ecs_capacity_provider.ec2_capacity_provider[0].name : "FARGATE" # Default: place tasks on EC2 hosts or Fargate, depending on launch type
    weight            = 1                                                                                               # Relative weight when multiple capacity providers exist (single provider here, so weight=1)
  }
}


