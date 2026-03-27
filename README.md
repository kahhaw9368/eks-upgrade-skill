# EKS Upgrade Readiness Skill for Claude Code

A Claude Code skill that assesses your EKS cluster's readiness for a Kubernetes version upgrade. Connects to your live cluster via AWS CLI and kubectl, runs automated checks, calculates a readiness score (0-100%), and generates a detailed report with pre-filled AWS CLI commands.

Upgrade with confidence. Know exactly what will break before you hit the button — deprecated APIs, incompatible add-ons, node version skew, workload risks. No surprises, no rollbacks, no 2 AM pages. Just a clear, prioritized action plan that turns a stressful upgrade into a routine maintenance window.

## Quick Start

### Step 1: Clone this repo

```bash
git clone https://github.com/kahhaw9368/eks-upgrade-power.git
```

Open the cloned folder as your working directory in Claude Code.

### Step 2: (Optional) Install MCP Servers

This skill works with AWS CLI and kubectl out of the box. For enhanced functionality, you can optionally configure two MCP servers in `.claude/settings.json`:

```json
{
  "mcpServers": {
    "awslabs.eks-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.aws-documentation-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

> **Prerequisites for MCP servers:** Python 3.10+ and uv installed ([Install uv](https://docs.astral.sh/uv/getting-started/installation/))

#### Using a specific AWS profile or region

If your EKS cluster is in a specific account/region, set environment variables before running Claude Code:

```bash
export AWS_PROFILE=your-profile-name
export AWS_REGION=us-west-2
```

Or add to the MCP server's `env` section if using MCP servers.

### Step 3: Verify Prerequisites

Run the permission check script to validate everything is set up correctly:

```bash
# List available clusters and check basic connectivity
./tools/check_permissions.sh

# Check full permissions against a specific cluster
./tools/check_permissions.sh my-cluster-name us-west-2
```

The script checks:
- AWS CLI installed and credentials valid
- EKS API permissions (list, describe clusters/nodegroups/addons/insights)
- EC2 permissions (describe subnets)
- IAM permissions (list role policies)
- Python 3.10+ and uv installed (required for MCP servers, optional otherwise)

### Step 4: Run the Assessment

In Claude Code, invoke the skill:

```
/eks-upgrade
```

Or simply ask:

> "Run an EKS upgrade readiness assessment"

The skill will:
1. Discover your clusters via AWS CLI
2. Ask which cluster and target version
3. Run 8 assessment areas against your live cluster
4. Calculate a readiness score (0-100%)
5. Generate a markdown report with pre-filled CLI commands
6. Optionally convert to HTML via `python3 tools/md_to_html.py <report>.md`

---

## Required AWS Permissions

The IAM principal (user or role) running Claude Code needs these permissions. This is a **read-only** assessment — the skill never modifies your cluster.

### Minimum IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSReadAccess",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "eks:ListAddons",
        "eks:DescribeAddon",
        "eks:DescribeAddonVersions",
        "eks:ListInsights",
        "eks:DescribeInsight",
        "eks:ListAccessEntries",
        "eks:DescribeAccessEntry"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2ReadAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroupRules"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMReadAccess",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

### Kubernetes RBAC

The skill also needs Kubernetes API access to list pods, deployments, services, etc. This is handled through your EKS access configuration:

- **EKS API mode (recommended):** Your IAM principal needs an EKS Access Entry with the `AmazonEKSClusterAdminPolicy` or `AmazonEKSAdminViewPolicy` access policy.
- **ConfigMap mode:** Your IAM principal needs to be mapped in the `aws-auth` ConfigMap with a group that has cluster read access.

To verify your Kubernetes access:

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Test access
kubectl get nodes
kubectl get pods -A
```

---

## What Gets Assessed

| Section | Checks |
|---------|--------|
| Version Validation | Upgrade path validity, version skew policy, support status & cost |
| Breaking Changes | Per-version API removals, behavioral changes, resource impact |
| Deprecated APIs | Live scan of cluster resources + AWS Upgrade Insights |
| Add-on Compatibility | Core EKS add-ons, OSS add-ons (via matrix), Karpenter |
| Node Readiness | AMI type (AL2→AL2023), container runtime, self-managed nodes |
| Workload Risks | Single replicas, missing PDBs, health probes, resource requests |
| AWS Upgrade Insights | Official EKS pre-upgrade checks and recommendations |
| Upgrade Plan | Pre-filled CLI commands with your cluster name and region |

## Readiness Score

| Score | Level | Meaning |
|-------|-------|---------|
| 90-100 | READY | Safe to proceed |
| 80-89 | GOOD | Minor issues, can proceed with caution |
| 70-79 | FAIR | Several issues need attention first |
| 60-69 | RISKY | Significant issues, not recommended yet |
| 0-59 | NOT READY | Critical blockers, must resolve first |

## Report Output

- **Markdown:** `EKS-Upgrade-Assessment-<cluster>-<current>-to-<target>-<date>.md`
- **HTML:** Run `python3 tools/md_to_html.py <report>.md` (zero external dependencies)

Both files are written to the workspace root.

---

## Project Structure

```
eks-upgrade-skill/
├── POWER.md                              # Original Kiro power definition (preserved)
├── README.md                             # This file
├── .gitignore
├── .claude/
│   ├── settings.local.json               # Claude Code permissions
│   └── skills/
│       └── eks-upgrade/                  # Claude Code skill
│           ├── SKILL.md                  # Skill definition & workflow
│           ├── steering/                 # Assessment logic (agent instructions)
│           │   ├── version-validation.md
│           │   ├── breaking-changes.md
│           │   ├── deprecated-apis.md
│           │   ├── addon-compatibility.md
│           │   ├── node-readiness.md
│           │   ├── workload-risks.md
│           │   ├── upgrade-insights.md
│           │   └── report-generation.md
│           ├── data/
│           │   └── oss_addon_matrix.json
│           └── tools/
│               ├── check_permissions.sh
│               └── md_to_html.py
├── steering/                             # Original steering files (preserved)
├── tools/                                # Original tools (preserved)
└── data/                                 # Original data files (preserved)
```

## Troubleshooting

### Cannot list clusters

1. Check credentials: `aws sts get-caller-identity`
2. Check region: `aws eks list-clusters --region <region>`
3. Run permission check: `./tools/check_permissions.sh`

### Permission denied errors

Run the permission check script:
```bash
./tools/check_permissions.sh <cluster-name> <region>
```

It will tell you exactly which permissions are missing.

### No clusters found

- Check your `AWS_REGION` — clusters are regional
- Check your `AWS_PROFILE` — you may be in the wrong account
- Verify: `aws eks list-clusters --region <region>`

### kubectl works but can't access Kubernetes API

Ensure your kubeconfig is up to date:
```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get nodes
```

---

## License

Apache 2.0
