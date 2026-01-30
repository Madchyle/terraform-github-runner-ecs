###############################################################################
# Runner Service Module - IAM (roles/policies for the runner ECS task)
#
# This file defines:
# - CloudWatch Logs destination for the runner container(s)
# - The ECS task role assumed by the running task
# - Inline policies enabling:
#   - CloudWatch Logs write
#   - ECR image pulls (if pulling from private ECR)
#   - ECS Exec / SSM Session Manager channels
#   - Optional STS AssumeRole/TagSession behaviors used by GitHub Actions workflows
#   - EFS mount permissions + KMS decrypt (for EFS-at-rest encryption) + runner token SSM read
#
# Key roles:
# - `aws_iam_role.runner_task_role`: IAM role *inside* the container/task (TaskRoleArn)
###############################################################################

# CloudWatch Log Group used by the runner task for container logs.
resource "aws_cloudwatch_log_group" "github_runner" {
  # checkov:skip=CKV_AWS_338:Ensure CloudWatch log groups retains logs for at least 1 year because retention_in_days is configurable by the user.
  # checkov:skip=CKV_AWS_158:Ensure that CloudWatch Log Group is encrypted by KMS because kms_key_id is configurable by the user and not enforced by default.
  name              = local.log_group_name      # Log group name used by the runner task (see task definition logging config)
  retention_in_days = var.log_retention_in_days # Configurable retention period for log events (days)
}

# What it is: IAM role assumed by ECS tasks (the "task role", not the execution role).
# What it attaches to: referenced by the ECS task definition as TaskRoleArn.
resource "aws_iam_role" "runner_task_role" {
  name               = "${local.effective_prefix}-${var.cluster_name}-task-role" # Stable, unique name for the task role
  assume_role_policy = data.aws_iam_policy_document.runner_task_assume.json      # Trust policy allowing ECS tasks to assume it
}

# What it is: trust policy (assume role policy) for the ECS task role.
data "aws_iam_policy_document" "runner_task_assume" {
  # Trust policy statement allowing ECS tasks to assume `runner_task_role`.
  statement {
    actions = ["sts:AssumeRole"] # Allow the ECS tasks service to assume this role
    principals {
      type        = "Service"                   # Service principal type
      identifiers = ["ecs-tasks.amazonaws.com"] # ECS tasks service principal
    }
  }
}

# What it is: attach a managed AWS policy to the task role.
# Why: lets the task read SSM parameters (read-only) without needing to craft a custom policy for common reads.
resource "aws_iam_role_policy_attachment" "runner_task_policy" {
  role       = aws_iam_role.runner_task_role.name                 # Attach to the runner task role
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"  # AWS-managed read-only SSM access
}

resource "aws_iam_role_policy" "ecs_task_logs" {
  # checkov:skip=CKV_AWS_355:Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions because ecr_resource_arn is configurable by the user to be more specific.
  name = "ecs-task-cloudwatch-logs"        # Inline policy name
  role = aws_iam_role.runner_task_role.name # Apply to the runner task role

  # Inline policy granting:
  # - CloudWatch Logs write for this task's log group
  # - ECR pull permissions (if using private ECR)
  policy = jsonencode({
    Version = "2012-10-17" # IAM policy language version
    # Policy statements granting CloudWatch Logs + ECR permissions.
    Statement = [
      {
        Effect = "Allow" # Allow log writes
        # CloudWatch Logs actions needed by the log driver.
        Action = [
          "logs:CreateLogStream", # Create a new stream under the log group for this task/container
          "logs:PutLogEvents"     # Write log events into the stream
        ]
        # Scope to this log group (all streams under it).
        Resource = "${aws_cloudwatch_log_group.github_runner.arn}:*" # Log group ARN + stream wildcard
      },
      {
        Effect = "Allow" # Allow image pull from ECR
        # ECR read/pull actions used by container runtime when pulling images.
        Action = [
          "ecr:GetAuthorizationToken",        # Get an auth token for ECR (often requires Resource = "*")
          "ecr:BatchCheckLayerAvailability", # Check if image layers exist/are accessible
          "ecr:GetDownloadUrlForLayer",      # Get pre-signed layer download URLs
          "ecr:BatchGetImage"                # Retrieve image manifest and layer references
        ]
        Resource = var.ecr_resource_arn # ECR resource scope (configurable; can be "*" or specific repository ARNs)
      }
    ]
  })
}

# Inline policy enabling ECS Exec (Session Manager channels) for the task role.
resource "aws_iam_role_policy" "ecs_exec" {
  name = "ecs-task-exec"                  # Inline policy name
  role = aws_iam_role.runner_task_role.name # Apply to the runner task role

  # Inline policy enabling ECS Exec:
  # ECS Exec uses SSM Session Manager message channels (ssmmessages.*) to establish the session.
  policy = jsonencode({
    Version = "2012-10-17" # IAM policy language version
    # Policy statement granting SSM Messages channel permissions used by ECS Exec.
    Statement = [
      {
        Sid    = "EcsExecSessionManagerChannels" # Label for ECS Exec permissions
        Effect = "Allow"                         # Allow the following actions
        # SSM Messages channel actions required for Session Manager / ECS Exec.
        Action = [
          "ssmmessages:CreateControlChannel", # Create control channel for session negotiation
          "ssmmessages:CreateDataChannel",    # Create data channel for session traffic
          "ssmmessages:OpenControlChannel",   # Open/attach to control channel
          "ssmmessages:OpenDataChannel"       # Open/attach to data channel
        ]
        Resource = "*" # ssmmessages actions are not resource-scoped
      }
    ]
  })
}

# Inline policy used by workflows that assume roles and pass session tags (testing-focused breadth).
resource "aws_iam_role_policy" "assume_role_with_tags" {
  # checkov:skip=CKV_AWS_290: Need "*" for testing
  # checkov:skip=CKV_AWS_355: Need "*" for testing
  # checkov:skip=CKV_AWS_287: No creds are exposed
  name = "ecs-task-gh-actions-assume-with-tags" # Inline policy name
  role = aws_iam_role.runner_task_role.name      # Apply to the runner task role

  # Inline policy used by workflows that need to assume roles and propagate session tags.
  # NOTE: This is intentionally broad ("sts:*") per the checkov skips above (testing use-case).
  policy = jsonencode({
    Version = "2012-10-17", # IAM policy language version
    Statement = [
      {
        Sid    = "AssumePHGithubActionsRoleWithTags" # Label for assume-role-with-tags capability
        Effect = "Allow"                              # Allow the following actions
        # STS actions used when assuming roles and attaching tags to the session.
        Action = [
          "sts:TagSession", # Allow attaching session tags when assuming roles
          "sts:*"           # Broad STS access (testing); tighten in production if possible
        ],
        Resource = "*" # Applies to all STS resources (testing)
      }
    ]
  })
}

# Inline policy for EFS mount + EFS CMK (KMS) + runner token SSM parameter read.
resource "aws_iam_role_policy" "task_efs_client" {
  name = "ecs-task-efs-client"            # Inline policy name
  role = aws_iam_role.runner_task_role.name # Apply to the runner task role

  # Inline policy enabling the runner task to:
  # - Mount/write to EFS via an access point
  # - Use the EFS CMK (KMS decrypt/grant) when EFS calls KMS on its behalf
  # - Read the runner registration token from SSM Parameter Store
  policy = jsonencode({
    Version = "2012-10-17", # IAM policy language version
    # Policy statements granting EFS client actions, CMK (KMS) usage via EFS, and SSM read.
    Statement = [
      {
        Effect = "Allow" # Allow EFS client operations
        # EFS client permissions needed by the ECS task when mounting EFS.
        Action = [
          "elasticfilesystem:ClientMount",      # Permit mounting the filesystem (via access point)
          "elasticfilesystem:ClientWrite",      # Permit write operations through the mount
          "elasticfilesystem:ClientRootAccess"  # Permit root access through the access point (required by config)
        ]
        # Scope to the filesystem and its access point used by this module.
        Resource = [
          aws_efs_file_system.runner.arn,  # The EFS filesystem ARN (efs.tf)
          aws_efs_access_point.runner.arn  # The EFS access point ARN (efs.tf)
        ]
      },
      {
        Effect = "Allow" # Allow EFS-mediated KMS operations for EFS at-rest encryption
        # KMS permissions EFS needs (via the task role) when using the CMK for encrypted EFS.
        Action = [
          "kms:Decrypt",     # Allow decrypting data keys when EFS reads encrypted content
          "kms:DescribeKey", # Allow reading CMK metadata during KMS operations
          "kms:CreateGrant"  # Allow creating a grant EFS can use for ongoing access
        ]
        Resource = aws_kms_key.efs_cmk.arn # CMK ARN created in `kms.tf`
        # Restrict these KMS permissions to calls that go through the EFS service in this region.
        Condition = {
          StringEquals = {
            "kms:ViaService" = "elasticfilesystem.${var.aws_region}.amazonaws.com" # Only via EFS service endpoint
          }
        }
      },
      {
        Effect = "Allow" # Allow reading the runner token from Parameter Store
        # SSM action used to fetch the runner registration token at runtime.
        Action = ["ssm:GetParameter"] # Read a single parameter value
        # Scope to the specific parameter name provided to this module.
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.runner_token_ssm_parameter_name}" # Runner token parameter ARN
        ]
      }
    ]
  })
}


