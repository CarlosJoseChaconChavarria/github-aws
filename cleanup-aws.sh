#!/usr/bin/env bash
# =============================================================================
# AWS OIDC Cleanup
# =============================================================================
# Removes all resources created by setup-aws.sh and the workflow.
# Run this when you want to tear down the lab environment.
#
# USAGE:
#   1. Fill in the CONFIGURATION section below (same values as setup-aws.sh)
#   2. chmod +x cleanup-aws.sh && ./cleanup-aws.sh
# =============================================================================

set -uo pipefail  # no -e so we continue past already-deleted resources

# =============================================================================
# CONFIGURATION — use the same values as setup-aws.sh
# =============================================================================

AWS_ACCOUNT_ID="your-12-digit-aws-account-id"
AWS_REGION="us-east-1"
ROLE_NAME="GitHubAction-AssumeRoleWithAction"
POLICY_ARN="arn:aws:iam::aws:policy/AmazonVPCFullAccess"
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo "=== AWS cleanup ==="
echo "Account: $AWS_ACCOUNT_ID"
echo "Region:  $AWS_REGION"
echo ""

# STEP 1 — Detach policy from role before deleting the role
# AWS requires all policies to be detached before a role can be deleted.
echo "[1/5] Detaching policy from IAM role..."
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" 2>/dev/null \
  && echo "      ✓ detached" || echo "      (already detached or role missing)"

# STEP 2 — Delete the IAM Role
echo "[2/5] Deleting IAM role: $ROLE_NAME..."
aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null \
  && echo "      ✓ deleted" || echo "      (already gone)"

# STEP 3 — Delete the OIDC Provider
# NOTE: Only one provider for token.actions.githubusercontent.com exists
# per account. Deleting it affects ALL GitHub Actions OIDC in this account.
# Only delete if this is the only OIDC role you have in this account.
echo "[3/5] Deleting OIDC provider..."
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null \
  && echo "      ✓ deleted" || echo "      (already gone)"

# STEP 4 — Delete subnets created by the workflow
echo "[4/5] Deleting workflow subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=tag:Name,Values=subnet-gh-created" \
  --query "Subnets[].SubnetId" \
  --output text 2>/dev/null)
if [ -n "$SUBNET_IDS" ]; then
  for s in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id "$s" --region "$AWS_REGION" 2>/dev/null \
      && echo "      ✓ deleted $s" || echo "      ✗ could not delete $s"
  done
else
  echo "      (none found)"
fi

# STEP 5 — Delete VPCs created by the workflow
echo "[5/5] Deleting workflow VPCs..."
VPC_IDS=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=tag:Name,Values=vpc-gh-created" \
  --query "Vpcs[].VpcId" \
  --output text 2>/dev/null)
if [ -n "$VPC_IDS" ]; then
  for v in $VPC_IDS; do
    aws ec2 delete-vpc --vpc-id "$v" --region "$AWS_REGION" 2>/dev/null \
      && echo "      ✓ deleted $v" || echo "      ✗ could not delete $v (check for dependencies)"
  done
else
  echo "      (none found)"
fi

echo ""
echo "=== Cleanup complete ==="
