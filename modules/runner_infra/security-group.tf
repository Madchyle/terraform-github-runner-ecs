###############################################################################
# Runner Infra Module - Security Group for ECS Container Instances
#
# What is a security group?
# - In AWS, a security group is a stateful, virtual firewall attached to network
#   interfaces (ENIs). You explicitly allow inbound and/or outbound traffic; any
#   traffic not allowed is implicitly denied.
#
# This file defines the security group used by the ECS *container instances*.
#
# Important terminology in this repo:
# - The ECS container instance is the EC2 host (VM) running the ECS agent. It provides the CPU/RAM/network where containers can run
# - Runner: the GitHub Actions runner process running inside an ECS *task/container* placed onto the container instance
#   when `launch_type = "EC2"`.
# - The runner is an ecs task running on the ECS container instance (EC2 host)
#
# What this file creates:
# - A security group intended to be attached to the EC2 instances (via their ENI(s)).
# - A permissive egress rule so those instances can make outbound calls to AWS APIs, GitHub,
#   and package registries (often through a NAT when using private subnets).
#
###############################################################################

# Security group for the EC2 instances that run the ECS agent (“ECS container instances”).
#
# What it is:
# - A Security Group (SG): a stateful, virtual firewall. Rules are evaluated on an ENI.
#
# What it attaches to:
# - ENI (Elastic Network Interface): an EC2 instance’s virtual network card with an IP in your VPC.
# - The ENI is attached to an EC2 instance (a virtual machine).
resource "aws_security_group" "ecs_instances" {
  name        = "${local.effective_prefix}-ecs-instances-sg" # Instance SG name; prefixed by `local.effective_prefix` derived from `var.infra_name_prefix`/`var.cluster_name`
  description = "${local.effective_prefix}-ecs-instances-sg" # Instance SG description; set to match name for easy identification in AWS
  vpc_id      = var.vpc_id                                   # VPC where the SG is created; comes from the module input `var.vpc_id`
}

# Security goroup rule that allows ECS container instances to initiate outbound connections to anywhere.
# The hosts need outbound access for ECS agent registration, pulling images, SSM,
# GitHub access + dependency registries (often via NAT) for runner workloads, OS/package updates, etc.
#
# What is this rule attached to?
# - SG rules attach to a security group (here: `aws_security_group.ecs_instances`).
# - Because that SG is attached to the instance ENI(s), the rule effectively applies to the instances.
resource "aws_vpc_security_group_egress_rule" "ecs_instances_all" {
  description       = "Allow all egress"                     # Rule description shown in AWS for this SG rule. An SG egress rule: a rule that allows outbound traffic *leaving* an ENI.
  security_group_id = aws_security_group.ecs_instances.id     # Attach this egress rule to the instance SG created above
  ip_protocol       = "-1"                                   # All protocols (-1 means any protocol in AWS SG rules)
  cidr_ipv4         = "0.0.0.0/0"                            # Allow egress to any IPv4 destination
}


