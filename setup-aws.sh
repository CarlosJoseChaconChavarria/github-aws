#!/usr/bin/env bash
# =============================================================================
# AWS OIDC Setup for GitHub Actions
# =============================================================================
# Configures AWS to trust GitHub Actions via OIDC.
# Run this ONCE before using the workflow for the first time.
#
# WHAT IS OIDC?
# Instead of storing AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as GitHub
# secrets (long-lived credentials that can leak), OIDC lets GitHub and AWS
# trust each other using short-lived tokens. GitHub generates a JWT per
# workflow run. AWS STS validates it and issues temporary credentials.
# No keys. No secrets. No rotation needed.
#
# PREREQUISITES:
#   - aws CLI installed and configured with admin credentials
#   - Confirm with: aws sts get-caller-identity
#
# USAGE:
#   1. Fill in the CONFIGURATION section below
#   2. chmod +x setup-aws.sh && ./setup-aws.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION — fill in your values here
# =============================================================================

# Your 12-digit AWS Account ID — find it with:
#   aws sts get-caller-identity --query Account --output text
AWS_ACCOUNT_ID="your-12-digit-aws-account-id"

# Your GitHub username or organization name
GH_USER="your-github-username"

# The exact name of the GitHub repo that will run the workflow
GH_REPO="github-aws"

# Name for the IAM Role the workflow will assume — you choose this label
ROLE_NAME="GitHubAction-AssumeRoleWithAction"

# =============================================================================
# SETUP — do not edit below this line
# =============================================================================

echo "=== AWS OIDC setup ==="
echo "Account: $AWS_ACCOUNT_ID"
echo "Role:    $ROLE_NAME"
echo "GitHub:  $GH_USER/$GH_REPO"
echo ""

# STEP 1 — Create the OIDC Identity Provider in AWS IAM
# Tells AWS to trust tokens issued by GitHub's OIDC endpoint.
# AWS equivalent of the GCP Workload Identity Pool + Provider.
#
# --thumbprint-list is GitHub's public TLS certificate fingerprint.
#   Same value for everyone — identifies GitHub's server cert.
#   Since 2023 AWS validates via its own CA store, but param is still required.
#
# --client-id-list "sts.amazonaws.com" means the token audience must be
#   sts.amazonaws.com — matched by the trust policy condition below.
#
# Only one OIDC provider for token.actions.githubusercontent.com can exist
# per AWS account — so we skip gracefully if it already exists.
echo "[1/4] Creating OIDC Identity Provider..."
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com" 2>/dev/null \
  && echo "      ✓ created" \
  || echo "      (already exists — skipping)"

# STEP 2 — Create the trust policy
# Defines WHO can assume the IAM Role — this is the security gate.
# Only GH_USER/GH_REPO can assume this role. No other GitHub repo can.
#
# "Federated" principal = the OIDC provider we just created above.
#
# Conditions:
#   sub (StringLike) = "repo:GH_USER/GH_REPO:*"
#     Restricts to your specific repo. :* allows any branch/tag/PR.
#     Without this, ANY GitHub repo could assume this role.
#
#   aud (StringEquals) = "sts.amazonaws.com"
#     Validates the token was intended for AWS STS specifically.
#     Prevents token reuse across other services.
echo "[2/4] Creating trust policy..."
cat > /tmp/trust-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GH_USER}/${GH_REPO}:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
POLICY
echo "      ✓ trust policy written to /tmp/trust-policy.json"

# STEP 3 — Create the IAM Role
# The identity the workflow assumes. GCP equivalent = Service Account.
# The trust policy (step 2) defines who is allowed to assume it.
echo "[3/4] Creating IAM Role: $ROLE_NAME..."
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  && echo "      ✓ created"

# STEP 4 — Attach the VPC permissions policy to the role
# AmazonVPCFullAccess = permission to create/list/delete VPCs and subnets.
# GCP equivalent = roles/compute.networkAdmin.
# NOTE: In production, always use a least-privilege custom policy.
echo "[4/4] Attaching AmazonVPCFullAccess..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
  && echo "      ✓ attached"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "Now add these as GitHub Actions repository variables:"
echo "Repo -> Settings -> Secrets and variables -> Actions -> Variables tab"
echo ""
echo "  AWS_ACCOUNT_ID   = $AWS_ACCOUNT_ID"
echo "  AWS_REGION       = us-east-1"
echo "  AWS_ROLE_NAME    = $ROLE_NAME"