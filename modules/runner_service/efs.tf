###############################################################################
# Runner Service Module - EFS (Persistent storage for the runner task)
#
# This file provisions an Amazon EFS filesystem used by the GitHub Actions runner
# itself (the ECS task/container created by this `runner_service` module).
#
# How this relates to `runner_infra`:
# - `runner_infra` defines the *capacity layer* that runs tasks (either EC2 “ECS container instances”
#   when `launch_type = "EC2"`, or Fargate capacity when `launch_type = "FARGATE"`).
# - `runner_service` defines the *workload layer* (the runner ECS task/service) that is placed onto that
#   capacity. This EFS is mounted by that runner task for persistence across restarts.
###############################################################################

# What it is: an EFS filesystem (regional, multi-AZ NFS) for runner persistence.
# Definition: Amazon EFS is a managed, shared NFS filesystem that can be mounted by multiple clients and persists independently of any single task/instance.
# What it attaches to: mounted by the runner ECS task via EFS mount targets + an access point (see `task_service.tf`).
resource "aws_efs_file_system" "runner" {
  encrypted        = true                 # Encrypt data at rest for this filesystem (AWS-managed encryption, using the CMK below)
  kms_key_id       = aws_kms_key.efs_cmk.arn # KMS key ARN used for EFS at-rest encryption; created in `kms.tf`
  performance_mode = "generalPurpose"     # EFS performance mode (general purpose is recommended for most workloads)
  throughput_mode  = "elastic"            # EFS elastic throughput for bursty/unpredictable workloads
  tags             = { Name = local.effective_prefix } # Resource tags; Name derived from `local.effective_prefix` (see `locals.tf`)
}

# What it is: an EFS mount target (an ENI in a subnet) for AZ/subnet 0.
# Definition: a mount target is the per-subnet/AZ network endpoint (ENI + IPs) that clients connect to when mounting the EFS filesystem.
# What it attaches to: attaches the EFS filesystem to `var.subnets[0]` and associates the EFS security group (from `security-group.tf`).
resource "aws_efs_mount_target" "mt_az1" {
  file_system_id  = aws_efs_file_system.runner.id # The EFS filesystem to expose in this subnet; from `aws_efs_file_system.runner`
  subnet_id       = var.subnets[0]                 # Subnet where this mount target ENI is created; from module input `var.subnets`
  security_groups = [aws_security_group.efs.id]    # SG applied to the mount target ENI; allows NFS from runner tasks (defined in `security-group.tf`)
}

# What it is: an EFS mount target (an ENI in a subnet) for AZ/subnet 1.
# Definition: a mount target is the per-subnet/AZ network endpoint (ENI + IPs) that clients connect to when mounting the EFS filesystem.
# What it attaches to: attaches the same EFS filesystem to `var.subnets[1]` and associates the EFS security group (from `security-group.tf`).
resource "aws_efs_mount_target" "mt_az2" {
  file_system_id  = aws_efs_file_system.runner.id # The EFS filesystem to expose in this subnet; from `aws_efs_file_system.runner`
  subnet_id       = var.subnets[1]                 # Subnet where this mount target ENI is created; from module input `var.subnets`
  security_groups = [aws_security_group.efs.id]    # SG applied to the mount target ENI; allows NFS from runner tasks (defined in `security-group.tf`)
}

# What it is: an EFS access point (a managed entry point) that the runner task mounts.
# Definition: an access point is an EFS “mount handle” that enforces a default POSIX identity and a root directory path for consistent permissions.
# What it attaches to: attaches to the EFS filesystem and defines a fixed POSIX identity + root directory for consistent permissions.
resource "aws_efs_access_point" "runner" {
  file_system_id = aws_efs_file_system.runner.id # The EFS filesystem this access point belongs to; from `aws_efs_file_system.runner`
  posix_user {
    uid = 0 # POSIX user ID enforced for all access via this access point (0 = root)
    gid = 0 # POSIX group ID enforced for all access via this access point (0 = root)
  }
  root_directory {
    path = "/runner" # Path within the EFS filesystem used as the root when mounting via this access point
    creation_info {
      owner_uid   = 0      # Owner UID to set if the directory must be created (0 = root)
      owner_gid   = 0      # Owner GID to set if the directory must be created (0 = root)
      permissions = "0755" # Permissions to set if the directory must be created (rwxr-xr-x)
    }
  }
}


