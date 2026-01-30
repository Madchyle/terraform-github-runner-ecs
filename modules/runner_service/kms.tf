###############################################################################
# Runner Service Module - EFS CMK (KMS key for EFS at-rest encryption)
#
# This file provisions a customer-managed KMS key (CMK) used by the EFS
# filesystem created in `efs.tf`:
# - `aws_efs_file_system.runner.kms_key_id = aws_kms_key.efs_cmk.arn`
#
# Why a CMK:
# - Lets you control key rotation, deletion lifecycle, and key policy.
# - Lets you audit and constrain how EFS uses the key (ViaService + account scoping).
#
# Key concept:
# - EFS encryption-at-rest is performed by the EFS service on your behalf, and EFS
#   creates/uses KMS grants for the filesystem. The key policy must allow those
#   grant operations, otherwise filesystem creation can fail.
###############################################################################

# What it is: identity/region/partition lookups used to build least-privilege ARNs
# and service principals in the CMK policy.
data "aws_caller_identity" "current" {} # Current AWS account context (used for account-scoped conditions/ARNs)
data "aws_region" "current" {}          # Current AWS region context (used for kms:ViaService scoping)
data "aws_partition" "current" {}       # Current AWS partition context (used for service principal DNS suffix)

# What it is: a customer-managed KMS key that EFS uses for at-rest encryption.
# What it attaches to: referenced by the EFS filesystem in `efs.tf`.
resource "aws_kms_key" "efs_cmk" {
  description             = "CMK for EFS at-rest encryption" # Human-readable purpose for the key
  enable_key_rotation     = true                             # Enable annual automatic rotation for symmetric CMK
  deletion_window_in_days = 30                               # Waiting period before CMK deletion after scheduling
  tags                    = { Project = local.effective_prefix } # Tag for cost/ownership tracking (project prefix)

  # Key policy for this CMK (JSON-encoded KMS key policy document).
  policy = jsonencode({
    Version = "2012-10-17" # IAM policy language version for the key policy document
    Statement = [
      # Admin permissions for the account root.
      # - Purpose: ensure the account can administer the key (manage policy, rotation,
      #   schedule deletion, tagging, etc.).
      {
        Sid       = "AllowAccountAdministrators" # Statement ID (label) for account-root administration permissions
        Effect    = "Allow"                      # Allow (vs Deny) the following actions
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" } # Account root principal
        Action = [
          "kms:Create*",             # Create KMS resources (key, alias, grant, etc.)
          "kms:Describe*",           # Read key metadata/configuration
          "kms:Enable*",             # Enable a disabled key (and related features)
          "kms:List*",               # List keys, aliases, grants, and related resources
          "kms:Put*",                # Write key configuration (e.g., put key policy)
          "kms:Update*",             # Update key settings (e.g., description/policy-related updates)
          "kms:Revoke*",             # Revoke grants/permissions previously delegated
          "kms:Disable*",            # Disable the key (and related features)
          "kms:Get*",                # Read key policy/material/status (GET-style operations)
          "kms:Delete*",             # Delete key-related resources (where supported) / schedule deletion helpers
          "kms:TagResource",         # Add tags to the CMK
          "kms:UntagResource",       # Remove tags from the CMK
          "kms:ScheduleKeyDeletion", # Schedule CMK deletion (uses deletion window above)
          "kms:CancelKeyDeletion"    # Cancel scheduled CMK deletion
        ]
        Resource = "*" # KMS key policy uses "*" to refer to the key itself within the policy
      },
      # Allow principals in this account to create the KMS grant that EFS needs
      # at filesystem creation time (scoped to AWS resources only).
      #
      # Why this exists:
      # - The principal that calls `CreateFileSystem` may need to create a grant
      #   for EFS to use the CMK. This statement allows grant creation only when:
      #   - The caller is in this account, and
      #   - The grant is explicitly for an AWS resource (`GrantIsForAWSResource = true`).
      {
        Sid       = "AllowAccountPrincipalsToCreateGrantForAWSResources" # Label for grant-creation permissions (account-scoped)
        Effect    = "Allow"                                             # Allow the following actions
        Principal = { AWS = "*" }                                       # Any principal (further restricted by conditions below)
        # KMS actions allowed by this statement.
        Action = [
          "kms:CreateGrant", # Create a KMS grant (delegates key usage to an AWS resource/service)
          "kms:DescribeKey"  # Read key metadata needed while creating/validating the grant
        ]
        Resource = "*" # Applies to this CMK (KMS key policy convention)
        # Conditions that scope when the above actions are allowed.
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id # Restrict to callers in this AWS account
          }
          Bool = {
            "kms:GrantIsForAWSResource" = true # Only allow grants that are for AWS resources (not arbitrary principals)
          }
        }
      },
      # Allow account principals to use the key *via EFS* in this region/account.
      #
      # What it enables:
      # - The IAM principal applying this Terraform (creating the EFS filesystem)
      #   can request EFS to encrypt/decrypt using this key.
      #
      # Guardrails:
      # - `kms:ViaService` restricts usage to the EFS service endpoint in the current region.
      # - `kms:CallerAccount` restricts usage to this AWS account.
      {
        Sid       = "AllowAccountPrincipalsToUseKeyViaEFS" # Label for key-usage permissions when requests go via EFS
        Effect    = "Allow"                                # Allow the following actions
        Principal = { AWS = "*" }                          # Any principal (restricted by ViaService/CallerAccount conditions)
        Action = [
          "kms:Encrypt",             # Allow EFS to encrypt data keys/metadata for at-rest encryption
          "kms:Decrypt",             # Allow EFS to decrypt data keys/metadata when reading
          "kms:ReEncrypt*",          # Allow re-encryption flows (e.g., key rotation / internal rewrap)
          "kms:GenerateDataKey*",    # Allow generating data keys used to encrypt file content
          "kms:DescribeKey",         # Allow retrieving key metadata during EFS operations
          "kms:CreateGrant"          # Allow creating grants EFS uses for ongoing access
        ]
        Resource = "*" # Applies to this CMK (KMS key policy convention)
        # Conditions that scope usage to EFS (and this account/region).
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "elasticfilesystem.${data.aws_region.current.name}.amazonaws.com" # Only via EFS service in this region
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id                      # Only from this AWS account
          }
        }
      },
      # Allow the EFS service principal to use the key (restricted to this account/region).
      #
      # Notes:
      # - The service principal varies by partition (commercial, govcloud, etc.),
      #   so this uses `${data.aws_partition.current.dns_suffix}`.
      {
        Sid    = "AllowEFSServiceToUseKey" # Label for EFS service principal key-usage permissions
        Effect = "Allow"                   # Allow the following actions
        # Principal (who): the EFS service itself (partition-specific service principal).
        Principal = {
          Service = "elasticfilesystem.${data.aws_partition.current.dns_suffix}" # EFS service principal for this AWS partition
        }
        # KMS actions the EFS service is allowed to perform with this CMK.
        Action = [
          "kms:Encrypt",          # EFS encrypt operations using this CMK
          "kms:Decrypt",          # EFS decrypt operations using this CMK
          "kms:ReEncrypt*",       # EFS re-encrypt operations using this CMK
          "kms:GenerateDataKey*", # EFS generation of data keys for file encryption
          "kms:DescribeKey"       # EFS reads key metadata as part of KMS calls
        ]
        Resource = "*" # Applies to this CMK (KMS key policy convention)
        # Conditions that scope service usage to EFS (and this account/region).
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "elasticfilesystem.${data.aws_region.current.name}.amazonaws.com" # Only via EFS service in this region
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id                      # Only from this AWS account
          }
        }
      },
      # Allow the EFS service to create the grant it needs for the filesystem.
      #
      # Why grants matter:
      # - EFS relies on KMS grants so it can continue using the CMK without needing
      #   the original caller's permissions.
      # - The `GrantIsForAWSResource` condition ensures the grant is only for AWS-managed resources.
      {
        Sid    = "AllowEFSServiceToCreateGrantForAWSResource" # Label for EFS grant-creation permissions
        Effect = "Allow"                                      # Allow the following actions
        # Principal (who): the EFS service itself (partition-specific service principal).
        Principal = {
          Service = "elasticfilesystem.${data.aws_partition.current.dns_suffix}" # EFS service principal for this AWS partition
        }
        # KMS actions the EFS service needs to create a filesystem-scoped grant.
        Action = [
          "kms:CreateGrant" # Let EFS create the AWS-resource grant it needs for the filesystem
        ]
        Resource = "*" # Applies to this CMK (KMS key policy convention)
        # Conditions that scope grant creation to EFS (and this account/region).
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "elasticfilesystem.${data.aws_region.current.name}.amazonaws.com" # Only via EFS service in this region
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id                      # Only from this AWS account
          }
          Bool = {
            "kms:GrantIsForAWSResource" = true # Ensure EFS-created grants are only for AWS resources
          }
        }
      },
      # Allow the ECS task role to use the key *via EFS*.
      #
      # Practical effect:
      # - Runner tasks mounting the EFS filesystem can function even when EFS needs
      #   to call KMS on their behalf.
      #
      # Guardrails:
      # - Restricted to this account and to requests that flow through EFS in-region
      #   (`kms:ViaService` + `kms:CallerAccount`).
      {
        Sid    = "AllowECSTaskRoleToUseKey" # Label for ECS task role key-usage permissions (via EFS)
        Effect = "Allow"                    # Allow the following actions
        # Principal (who): the caller identity; constrained by conditions to EFS in this account/region.
        Principal = {
          AWS = "*" # Any AWS principal (restricted by ViaService/CallerAccount conditions below)
        }
        # KMS actions allowed for the runner task when requests flow through EFS.
        Action = [
          "kms:Decrypt",     # Allow decrypt for EFS-mediated access (e.g., mount/read flows)
          "kms:DescribeKey", # Allow reading key metadata needed for KMS operations
          "kms:CreateGrant"  # Allow grant creation when EFS needs to delegate access
        ]
        Resource = "*" # Applies to this CMK (KMS key policy convention)
        # Conditions that scope task usage to EFS (and this account/region).
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "elasticfilesystem.${data.aws_region.current.name}.amazonaws.com" # Only via EFS service in this region
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id                      # Only from this AWS account
          }
        }
      }
    ]
  })
}

# What it is: a friendly alias for the CMK (useful for visibility and policy tooling).
resource "aws_kms_alias" "efs_cmk_alias" {
  name          = "alias/${local.effective_prefix}/efs" # Friendly alias path for the CMK
  target_key_id = aws_kms_key.efs_cmk.key_id            # The CMK this alias points to
}

