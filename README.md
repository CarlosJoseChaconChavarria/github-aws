# GitHub Actions → AWS via OIDC
> Deploy a VPC + Subnet using AWS CLI — no long-lived credentials

## Why OIDC?
Without OIDC you store AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as GitHub secrets — long-lived credentials that can leak. With OIDC, GitHub and AWS trust each other via short-lived tokens. No keys. No rotation.

## How it works
```
GitHub Actions
  │  1. Generates JWT token for this run
  ▼
token.actions.githubusercontent.com
  │  2. Sends token to AWS STS (AssumeRoleWithWebIdentity)
  ▼
AWS STS
  │  3. Validates token + checks trust policy conditions (sub + aud)
  ▼
Temporary credentials (15min–1hr)
  │  4. Workflow runs AWS CLI commands
  ▼
AWS Resources (VPC, Subnet)
```

## Step 1 — Run setup-aws.sh (once)
1. Open `setup-aws.sh`
2. Fill in the **CONFIGURATION** section at the top
3. Run it:
```bash
chmod +x setup-aws.sh && ./setup-aws.sh
```

## Step 2 — Add GitHub Actions repository variables
**Settings → Secrets and variables → Actions → Variables tab**

The script prints these when it finishes:

| Variable | What it is |
|---|---|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS Account ID |
| `AWS_REGION` | e.g. `us-east-1` |
| `AWS_ROLE_NAME` | IAM role name used in setup |

## Step 3 — Run the workflow
Actions tab → **Deploy AWS VPC** → Run workflow → watch **Verify identity** confirm OIDC worked.

## Key concepts
| Concept | What it means |
|---|---|
| `id-token: write` | Lets the workflow request a JWT. Without this, OIDC silently fails |
| `configure-aws-credentials` action | Handles the entire STS token exchange |
| `trust policy sub condition` | Security gate — only your specific repo can assume the role |
| `role-session-name` | Labels the session in CloudTrail logs for auditing |
| `$GITHUB_ENV` | How to pass values (like VPC_ID) between workflow steps |
| `${{ vars.X }}` | Reads a repo variable from Settings → Secrets and variables → Actions |