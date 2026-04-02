# EKS Upgrade Readiness Skill

[![License](https://img.shields.io/badge/License-Apache%202.0-brightgreen.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue.svg)](https://www.python.org/)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-7C3AED.svg)](https://claude.ai/claude-code)

A [Claude Code](https://claude.ai/claude-code) skill that performs automated EKS upgrade readiness assessments. It connects to a live EKS cluster, runs checks across 8 assessment areas, calculates a readiness score (0–100%), and generates a detailed report with pre-filled AWS CLI commands.

Checks are informed by the [EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/) and [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/). All operations are **read-only** — the skill does not modify your cluster.

![Sample EKS Upgrade Readiness Report](docs/sample-report-summary.png)

## Table of Contents

- [Getting Started](#getting-started)
- [What Gets Assessed](#what-gets-assessed)
- [Readiness Score](#readiness-score)
- [Output](#output)
- [MCP Server Setup](#mcp-server-setup)
- [Required Permissions](#required-permissions)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Getting Started

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Python 3.10+](https://www.python.org/) and [uv](https://docs.astral.sh/uv/getting-started/installation/)
- AWS credentials configured — `aws sts get-caller-identity` should succeed

### Quick Start

```bash
git clone https://github.com/kahhaw9368/eks-upgrade-skill.git
cd eks-upgrade-skill
claude
```

Then run:

```
/eks-upgrade
```

The skill discovers your EKS clusters, asks which cluster and target version, and walks you through the assessment.

### Verify Prerequisites

Run the permission check script to validate everything is set up correctly:

```bash
# List available clusters and check basic connectivity
./tools/check_permissions.sh

# Check full permissions against a specific cluster
./tools/check_permissions.sh my-cluster-name us-west-2
```

## What Gets Assessed

| # | Area | Examples |
|---|------|----------|
| 01 | Version Validation | Upgrade path validity, version skew policy, support status & cost |
| 02 | Breaking Changes | Per-version API removals, behavioral changes, resource impact |
| 03 | Deprecated APIs | Live scan of cluster resources + AWS Upgrade Insights |
| 04 | Add-on Compatibility | Core EKS add-ons, OSS add-ons (via matrix), Karpenter |
| 05 | Node Readiness | AMI type (AL2→AL2023), container runtime, self-managed nodes |
| 06 | Workload Risks | Single replicas, missing PDBs, health probes, resource requests |
| 07 | AWS Upgrade Insights | Official EKS pre-upgrade checks and recommendations |
| 08 | Upgrade Plan | Pre-filled CLI commands with your cluster name and region |

**Sample findings detail**

![Detailed Findings by Section](docs/sample-report-findings.png)

## Readiness Score

| Score | Level | Meaning |
|-------|-------|---------|
| 90–100 | READY | Safe to proceed |
| 80–89 | GOOD | Minor issues, can proceed with caution |
| 70–79 | FAIR | Several issues need attention first |
| 60–69 | RISKY | Significant issues, not recommended yet |
| 0–59 | NOT READY | Critical blockers, must resolve first |

## Output

Reports are generated in the workspace root:

| Format | Filename |
|--------|----------|
| Markdown | `EKS-Upgrade-Assessment-<cluster>-<current>-to-<target>-<date>.md` |
| HTML (optional) | `EKS-Upgrade-Assessment-<cluster>-<current>-to-<target>-<date>.html` |

Each report includes a readiness score, score breakdown, blockers & critical actions, per-section findings, and a step-by-step upgrade plan with pre-filled CLI commands.

To convert to HTML: `python3 tools/md_to_html.py <report>.md` (zero external dependencies).

**Sample upgrade plan**

![Sample Upgrade Plan](docs/sample-report-upgrade-plan.png)

## MCP Server Setup

This skill uses MCP servers to interact with your cluster. Configure them in `.mcp.json` at the project root.

### EKS MCP Server

**Option A: AWS-Managed EKS MCP Server (Recommended)**

The [AWS-managed EKS MCP server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) is a hosted service with automatic updates, CloudTrail audit logging, and a built-in troubleshooting knowledge base.

1. Attach the `AmazonEKSMCPReadOnlyAccess` managed policy to your IAM user/role.
2. Update `.mcp.json` (replace `{region}` with your AWS region):

```json
{
  "mcpServers": {
    "eks-mcp": {
      "command": "uvx",
      "args": [
        "mcp-proxy-for-aws@latest",
        "https://eks-mcp.{region}.api.aws/mcp",
        "--service", "eks-mcp",
        "--profile", "default",
        "--region", "{region}",
        "--read-only"
      ]
    }
  }
}
```

See the [Getting Started guide](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-getting-started.html) for full setup instructions.

**Option B: Open-Source EKS MCP Server**

The [awslabs.eks-mcp-server](https://github.com/awslabs/mcp) works out of the box with no additional IAM setup.

```json
{
  "mcpServers": {
    "awslabs.eks-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

### AWS Documentation MCP Server

Used during assessment to look up documentation:

```json
{
  "mcpServers": {
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

### Customization

To use a specific AWS profile or region, update the `env` block:

```json
"env": {
  "AWS_PROFILE": "your-profile",
  "AWS_REGION": "us-west-2",
  "FASTMCP_LOG_LEVEL": "ERROR"
}
```

> **Already have these MCP servers?** If you already have them configured globally or in another project, you can skip this step. Project-level configs in `.mcp.json` are additive — they won't overwrite your existing servers.

## Required Permissions

### AWS IAM

Minimum IAM permissions:

```
eks:ListClusters, eks:DescribeCluster, eks:ListNodegroups,
eks:DescribeNodegroup, eks:ListAddons, eks:DescribeAddon,
eks:DescribeAddonVersions, eks:ListInsights, eks:DescribeInsight,
eks:ListAccessEntries, eks:DescribeAccessEntry
ec2:DescribeSubnets, ec2:DescribeSecurityGroupRules
iam:GetRole, iam:ListAttachedRolePolicies,
iam:ListRolePolicies, iam:GetRolePolicy
```

### Kubernetes RBAC

Your IAM identity needs read access to Kubernetes resources (Nodes, Pods, Deployments, Services, etc.) via an [EKS access entry](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html) or `aws-auth` ConfigMap.

## Limitations

- **One cluster at a time** — run the skill again for additional clusters.
- **Point-in-time snapshot** — reflects cluster state at the time of the run; does not monitor ongoing changes.
- **Requires cluster access** — your IAM identity must have both AWS API permissions and Kubernetes RBAC access.

## Troubleshooting

**MCP server not responding**

1. Check Python and uv are installed: `uv --version`
2. Check AWS credentials: `aws sts get-caller-identity`
3. Test the MCP server directly: `uvx awslabs.eks-mcp-server@latest`
4. Check `.mcp.json` — ensure `AWS_PROFILE` and `AWS_REGION` match your environment

**No clusters found**

The skill lists clusters in the region configured in your AWS credentials. To target a different region, set `AWS_REGION` in the MCP server's `env` config or your environment.

**Permission denied errors**

Run the permission check script:

```bash
./tools/check_permissions.sh <cluster-name> <region>
```

It will tell you exactly which permissions are missing.

**kubectl works but MCP server can't access Kubernetes API**

The MCP server runs in its own process and doesn't inherit your shell environment. Ensure `AWS_PROFILE` and `AWS_REGION` are set in the MCP server's `env` config in `.mcp.json`.

## Project Structure

```
eks-upgrade-skill/
├── README.md                         # This file
├── .claude/
│   └── skills/
│       └── eks-upgrade/
│           ├── SKILL.md              # Skill definition & agent workflow
│           ├── steering/             # Assessment logic (agent instructions)
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
├── tools/
│   ├── md_to_html.py                 # Markdown → HTML converter
│   └── check_permissions.sh          # Pre-flight permission validator
└── data/
    └── oss_addon_matrix.json         # OSS add-on compatibility matrix
```

## Contributing

Contributions are welcome. Please [open an issue](https://github.com/kahhaw9368/eks-upgrade-skill/issues) first to discuss what you'd like to change.

## Security

This skill is **read-only** and does not create, modify, or delete any AWS or Kubernetes resources. All operations are describe, list, and get calls.

If you discover a security issue, please report it via [GitHub Issues](https://github.com/kahhaw9368/eks-upgrade-skill/issues) rather than a public comment.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).
