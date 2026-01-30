###############################################################################
# Runner Infra Module - IAM for EC2 “ECS container instances”
#
# This file defines the IAM role and instance profile used by the EC2 instances
# when `launch_type = "EC2"`. In AWS, an EC2 instance gets IAM permissions by:
# - These EC2 instances are the “ECS container instances” (hosts) that ECS places
#   the runner ECS tasks/containers (GitHub runner(s)) onto when using EC2 launch type.
# - Assuming an IAM role (trust policy allows EC2 to assume it), and
# - Having that role attached via an Instance Profile, which is then referenced
#   by the EC2 Launch Template (`asg.tf`) so instances launch with the profile.
###############################################################################

# Trust policy for the EC2 instance role.
# What it is: an IAM policy document used as a role *trust policy* (who can assume the role).
# What it attaches to: `aws_iam_role.runner_instance_role.assume_role_policy` (the IAM role EC2 will assume).
# What that target is: an IAM role is an identity with permissions; EC2 instances get those permissions by assuming the role via an instance profile.
data "aws_iam_policy_document" "runner_instance_assume" {
  count = local.is_ec2_launch_type ? 1 : 0 # Only needed when we create EC2 hosts (ECS container instances)
  statement {
    actions = ["sts:AssumeRole"]             # STS action EC2 uses to assume the role
    principals {
      type        = "Service"             # Principal type: AWS service
      identifiers = ["ec2.amazonaws.com"] # EC2 service principal that will assume the instance role
    }
  }
}

# IAM role for the EC2 instances (ECS container instances).
# What it is: an IAM role that grants permissions to the EC2 host (ECS agent, ECR pulls, CloudWatch Logs/metrics, etc.).
# What it attaches to: placed into `aws_iam_instance_profile.runner_instance_profile`, which is then attached to EC2 instances at launch.
# What that target is: an Instance Profile is the wrapper EC2 uses to associate a role with an instance (via the launch template in `asg.tf`).
resource "aws_iam_role" "runner_instance_role" {
  count              = local.is_ec2_launch_type ? 1 : 0                                           # Only created for EC2 launch type
  name               = "${local.effective_prefix}-instance-role"                                   # Role name; derived from `local.effective_prefix`
  assume_role_policy = data.aws_iam_policy_document.runner_instance_assume[0].json                 # Trust policy JSON from the data source above
}

# Attach the AWS-managed ECS-for-EC2 policy to the instance role.
# What it is: a policy attachment that binds a managed IAM policy to an IAM role.
# What it attaches to: `aws_iam_role.runner_instance_role` (the EC2 instance role).
# What that target is: the role assumed by the EC2 hosts running the ECS agent.
resource "aws_iam_role_policy_attachment" "runner_instance_policy" {
  count      = local.is_ec2_launch_type ? 1 : 0                                                    # Only relevant when using EC2 hosts
  role       = aws_iam_role.runner_instance_role[0].name                                            # Role name to attach the policy to
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"           # AWS-managed policy for ECS container instances
}

# Attach the AWS-managed SSM Managed Instance Core policy to the instance role.
# What it is: a policy attachment enabling Systems Manager (SSM) access to the EC2 instances.
# What it attaches to: `aws_iam_role.runner_instance_role` (the EC2 instance role).
# What that target is: the role assumed by the EC2 hosts; SSM uses it for Session Manager / inventory / patching.
resource "aws_iam_role_policy_attachment" "runner_instance_ssm_policy" {
  count      = local.is_ec2_launch_type ? 1 : 0                                                    # Only relevant when using EC2 hosts
  role       = aws_iam_role.runner_instance_role[0].name                                            # Role name to attach the policy to
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"                               # AWS-managed policy for SSM Session Manager / inventory / patching
}

# Instance Profile that is attached to EC2 instances at launch time.
# What it is: an IAM container for a single role that EC2 can be launched with.
# What it attaches to: referenced by the launch template (`aws_launch_template.github_runner_lt.iam_instance_profile`) in `asg.tf`.
# What that target is: the launch template is the EC2 instance “recipe”; using the profile there ensures every instance launched by the ASG gets this role.
resource "aws_iam_instance_profile" "runner_instance_profile" {
  count = local.is_ec2_launch_type ? 1 : 0                                                         # Only created for EC2 launch type
  name  = "${local.effective_prefix}-instance-profile"                                              # Instance profile name; derived from `local.effective_prefix`
  role  = aws_iam_role.runner_instance_role[0].name                                                 # Role contained in this instance profile
}


