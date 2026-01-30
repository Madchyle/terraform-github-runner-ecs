# ============================================================================
# Infrastructure Configuration File
# ============================================================================
#
# This file contains infrastructure-level settings for the GitHub Actions
# runner deployment on AWS ECS. These settings control the underlying
# infrastructure (ECS cluster, EC2 instances, Auto Scaling Groups) that
# hosts your runner containers.
#
# IMPORTANT: This file only contains infrastructure settings. Runner service
# configuration (GitHub organization, runner labels, image, count, etc.) is
# provided via GitHub Actions workflow environment variables (TF_VAR_*) when
# using the automated deployment workflow (.github/workflows/deployment.yml).
#
# When deploying manually with Terraform CLI, you would provide runner service
# configuration either via:
#   - Additional .tfvars files
#   - Command-line flags (-var)
#   - Environment variables (TF_VAR_*)
#
# ============================================================================
# ECS Cluster Configuration
# ============================================================================

# Name of the ECS cluster where your GitHub runners will run. This cluster manages all your runner containers and EC2 instances. If create_cluster is false, this must match an existing cluster name.
cluster_name   = "nexus-repo"

# Whether to create a new ECS cluster (true) or use an existing one (false). Set to false if you already have an ECS cluster you want to use.
create_cluster = false

# ============================================================================
# Launch Type Configuration
# ============================================================================

# Type of compute for running your runners: "EC2" or "FARGATE". EC2: You manage EC2 instances (more control, can be cheaper at scale). FARGATE: AWS manages the servers (simpler, no instance management). Note: The rest of this file's settings are primarily for EC2 launch type.
launch_type = "EC2"

# ============================================================================
# EC2 Instance Configuration (for launch_type = "EC2")
# ============================================================================

# EC2 instance type/size for your runner hosts. Common options: t3.medium, t3.large, t3.xlarge. Bigger instances = more CPU/memory but higher cost. See AWS documentation for available instance types in your region.
instance_type        = "t3.medium"

# Minimum number of EC2 instances that will always be running. Set to 0 to allow scaling down to zero when idle (saves money). Set to 1 or higher if you want instances always available (faster startup).
asg_min_size         = 0

# Maximum number of EC2 instances that can be created. Prevents runaway scaling and controls maximum costs. Increase if you need more parallel runner capacity.
asg_max_size         = 5

# Initial/desired number of EC2 instances to start with. The Auto Scaling Group will try to maintain this many instances. Should be between asg_min_size and asg_max_size.
asg_desired_capacity = 1

# ============================================================================
# Docker Cleanup Configuration
# ============================================================================

# Whether to automatically clean up old Docker containers, images, networks, and volumes on a schedule. This prevents disk space issues over time. Recommended: true (keeps your instances from running out of disk space)
enable_docker_prune_cron = true

# Cron schedule for when to run the Docker cleanup job. Format: "minute hour day-of-month month day-of-week". Examples: "0 * * * *" = Every hour at minute 0, "0 */6 * * *" = Every 6 hours, "0 2 * * *" = Every day at 2:00 AM, "0 0 * * 0" = Every Sunday at midnight
docker_prune_cron_schedule = "0 * * * *"

# How old Docker resources must be before they get cleaned up. Only resources unused for at least this duration will be pruned. Examples: "3h" = 3 hours, "24h" = 1 day, "168h" = 1 week
docker_prune_until = "3h"

# Size in gigabytes of the additional EBS volume used for Docker data. Docker images and containers can use significant disk space. Recommended: 100GB or more if you build large Docker images. This volume stores /var/lib/docker data separately from the root volume.
docker_volume_size = 100

# ============================================================================
# Runner Service Configuration
# ============================================================================
#
# NOTE: Runner service configuration (GitHub organization, runner labels,
# image, desired count, etc.) is NOT set in this file when using the
# automated GitHub Actions deployment workflow.
#
# The deployment workflow (.github/workflows/deployment.yml) provides runner
# service configuration via GitHub repository secrets and variables, which
# are passed to Terraform as TF_VAR_* environment variables.
#
# If deploying manually with Terraform CLI, you would configure runner
# services via the runner_services variable or top-level runner variables.
#
# ============================================================================


