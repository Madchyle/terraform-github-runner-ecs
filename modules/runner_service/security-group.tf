###############################################################################
# Runner Service Module - Security Groups
#
# This file defines the network security boundaries for the runner ECS tasks
# and the EFS filesystem they mount. It creates:
# - A security group for runner tasks (egress-only).
# - A security group for EFS, allowing NFS (2049/tcp) from runner tasks only.
###############################################################################

# Security group attached to the ECS tasks (runner containers). This SG is used
# as the source for EFS ingress and to control what the tasks can reach.
resource "aws_security_group" "runner_tasks" {
  name        = "${local.effective_prefix}-tasks-sg" # Name prefix for the runner task SG (stable identifier in AWS console)
  description = "${local.effective_prefix}-tasks-sg" # Human-readable description shown in AWS (kept in sync with name)
  vpc_id      = var.vpc_id                           # VPC where the SG is created (must match the ECS/EFS VPC)
}

# Allow runner tasks to initiate outbound connections to anywhere. Runners need
# outbound access to GitHub, AWS APIs, package registries, etc.
resource "aws_vpc_security_group_egress_rule" "runner_tasks_all" {
  description       = "Allow all egress"                  # Description of this specific rule (visible on the SG rule list)
  security_group_id = aws_security_group.runner_tasks.id  # Target SG that receives this egress rule (runner tasks SG)
  ip_protocol       = "-1"                                # All protocols (-1 means any protocol in AWS SG rules)
  cidr_ipv4         = "0.0.0.0/0"                         # Allow egress to any IPv4 destination
}

# Security group attached to the EFS mount targets. This SG is locked down to
# only allow NFS access from the runner task security group.
resource "aws_security_group" "efs" {
  name        = "${local.effective_prefix}-efs-sg" # Name prefix for the EFS SG (stable identifier in AWS console)
  description = "${local.effective_prefix}-efs-sg" # Human-readable description shown in AWS (kept in sync with name)
  vpc_id      = var.vpc_id                         # VPC where the SG is created (must match the runner tasks SG VPC)
}

# Permit NFS (2049/tcp) from runner tasks to EFS. This is required for the ECS
# tasks to mount the EFS volume.
resource "aws_vpc_security_group_ingress_rule" "efs_from_tasks" {
  description                  = "allow efs ingress from gh-runner tasks" # Description of this specific rule (visible on the SG rule list)
  security_group_id            = aws_security_group.efs.id                # Target SG that receives this ingress rule (EFS SG)
  ip_protocol                  = "tcp"                                    # NFS uses TCP
  from_port                    = 2049                                     # Start of allowed port range (NFS)
  to_port                      = 2049                                     # End of allowed port range (NFS)
  referenced_security_group_id = aws_security_group.runner_tasks.id        # Source SG allowed to connect (runner tasks SG)
}


