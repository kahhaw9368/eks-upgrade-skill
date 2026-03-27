#!/usr/bin/env bash
#
# EKS Upgrade Power — Pre-flight Permission Check
#
# Validates that the current AWS credentials have the required
# permissions to run the EKS upgrade readiness assessment.
#
# Usage:
#   ./tools/check_permissions.sh [cluster-name] [region]
#
# If cluster-name is omitted, lists available clusters.
# If region is omitted, uses AWS_REGION or AWS_DEFAULT_REGION.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

pass_count=0
fail_count=0
warn_count=0

check_pass() {
    echo -e "  ${GREEN}✅ PASS${NC}  $1"
    ((pass_count++))
}

check_fail() {
    echo -e "  ${RED}❌ FAIL${NC}  $1"
    ((fail_count++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠️  WARN${NC}  $1"
    ((warn_count++))
}

echo ""
echo -e "${BOLD}EKS Upgrade Power — Permission Check${NC}"
echo "======================================"
echo ""

# ── Step 1: Check AWS CLI ──
echo -e "${BOLD}1. AWS CLI & Credentials${NC}"

if ! command -v aws &> /dev/null; then
    check_fail "AWS CLI not installed"
    echo ""
    echo "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi
check_pass "AWS CLI installed ($(aws --version 2>&1 | head -1))"

# Check credentials
CALLER_IDENTITY=$(aws sts get-caller-identity 2>&1) || {
    check_fail "AWS credentials not configured or expired"
    echo ""
    echo "Run: aws configure"
    echo "Or:  export AWS_PROFILE=your-profile"
    exit 1
}

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])" 2>/dev/null || echo "unknown")
ARN=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])" 2>/dev/null || echo "unknown")
check_pass "Authenticated as: $ARN (Account: $ACCOUNT_ID)"

# Determine region
REGION="${2:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
if [ -z "$REGION" ]; then
    REGION=$(aws configure get region 2>/dev/null || echo "")
fi
if [ -z "$REGION" ]; then
    check_fail "No AWS region specified. Set AWS_REGION or pass as second argument."
    exit 1
fi
check_pass "Region: $REGION"

echo ""

# ── Step 2: Check kubectl ──
echo -e "${BOLD}2. kubectl${NC}"

if ! command -v kubectl &> /dev/null; then
    check_warn "kubectl not installed (EKS MCP server handles K8s API calls, but kubectl is useful for verification)"
else
    check_pass "kubectl installed ($(kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -1))"
fi

echo ""

# ── Step 3: Check EKS permissions ──
echo -e "${BOLD}3. EKS Permissions${NC}"

# List clusters
CLUSTERS=$(aws eks list-clusters --region "$REGION" --output json 2>&1) || {
    check_fail "eks:ListClusters — Cannot list EKS clusters"
    echo "    Required: eks:ListClusters permission"
    CLUSTERS=""
}

if [ -n "$CLUSTERS" ]; then
    CLUSTER_COUNT=$(echo "$CLUSTERS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('clusters',[])))" 2>/dev/null || echo "0")
    check_pass "eks:ListClusters — Found $CLUSTER_COUNT cluster(s)"

    if [ "$CLUSTER_COUNT" = "0" ]; then
        echo ""
        echo -e "${YELLOW}No EKS clusters found in $REGION.${NC}"
        echo "Check your region or AWS_PROFILE."
        exit 0
    fi
fi

# If cluster name provided, check specific permissions
CLUSTER="${1:-}"
if [ -z "$CLUSTER" ] && [ -n "$CLUSTERS" ]; then
    echo ""
    echo "Available clusters:"
    echo "$CLUSTERS" | python3 -c "import sys,json; [print(f'  - {c}') for c in json.load(sys.stdin).get('clusters',[])]" 2>/dev/null
    echo ""
    echo "Run again with a cluster name to check full permissions:"
    echo "  ./tools/check_permissions.sh <cluster-name> $REGION"
    echo ""
    exit 0
fi

# Describe cluster
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --output json > /dev/null 2>&1 && \
    check_pass "eks:DescribeCluster — Can describe '$CLUSTER'" || \
    check_fail "eks:DescribeCluster — Cannot describe '$CLUSTER'"

# List node groups
aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --output json > /dev/null 2>&1 && \
    check_pass "eks:ListNodegroups" || \
    check_fail "eks:ListNodegroups"

# Describe node group (first one)
NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --output json 2>/dev/null || echo '{"nodegroups":[]}')
FIRST_NG=$(echo "$NODEGROUPS" | python3 -c "import sys,json; ngs=json.load(sys.stdin).get('nodegroups',[]); print(ngs[0] if ngs else '')" 2>/dev/null || echo "")
if [ -n "$FIRST_NG" ]; then
    aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$FIRST_NG" --region "$REGION" --output json > /dev/null 2>&1 && \
        check_pass "eks:DescribeNodegroup (tested: $FIRST_NG)" || \
        check_fail "eks:DescribeNodegroup"
else
    check_warn "eks:DescribeNodegroup — No node groups to test (Fargate or Karpenter?)"
fi

# List addons
aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION" --output json > /dev/null 2>&1 && \
    check_pass "eks:ListAddons" || \
    check_fail "eks:ListAddons"

# Describe addon (first one)
ADDONS=$(aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION" --output json 2>/dev/null || echo '{"addons":[]}')
FIRST_ADDON=$(echo "$ADDONS" | python3 -c "import sys,json; addons=json.load(sys.stdin).get('addons',[]); print(addons[0] if addons else '')" 2>/dev/null || echo "")
if [ -n "$FIRST_ADDON" ]; then
    aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$FIRST_ADDON" --region "$REGION" --output json > /dev/null 2>&1 && \
        check_pass "eks:DescribeAddon (tested: $FIRST_ADDON)" || \
        check_fail "eks:DescribeAddon"
else
    check_warn "eks:DescribeAddon — No addons to test"
fi

# List insights
aws eks list-insights --cluster-name "$CLUSTER" --region "$REGION" --output json > /dev/null 2>&1 && \
    check_pass "eks:ListInsights" || \
    check_fail "eks:ListInsights"

echo ""

# ── Step 4: Check EC2 permissions ──
echo -e "${BOLD}4. EC2 Permissions${NC}"

aws ec2 describe-subnets --region "$REGION" --max-results 5 --output json > /dev/null 2>&1 && \
    check_pass "ec2:DescribeSubnets" || \
    check_fail "ec2:DescribeSubnets"

echo ""

# ── Step 5: Check IAM permissions ──
echo -e "${BOLD}5. IAM Permissions${NC}"

# Get the cluster's node role to test IAM access
CLUSTER_DESC=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --output json 2>/dev/null || echo "{}")
CLUSTER_ROLE=$(echo "$CLUSTER_DESC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster',{}).get('roleArn','').split('/')[-1])" 2>/dev/null || echo "")

if [ -n "$CLUSTER_ROLE" ]; then
    aws iam list-attached-role-policies --role-name "$CLUSTER_ROLE" --output json > /dev/null 2>&1 && \
        check_pass "iam:ListAttachedRolePolicies (tested: $CLUSTER_ROLE)" || \
        check_fail "iam:ListAttachedRolePolicies"

    aws iam list-role-policies --role-name "$CLUSTER_ROLE" --output json > /dev/null 2>&1 && \
        check_pass "iam:ListRolePolicies" || \
        check_fail "iam:ListRolePolicies"
else
    check_warn "Could not determine cluster role — skipping IAM checks"
fi

echo ""

# ── Step 6: Check Python & uv (for MCP server) ──
echo -e "${BOLD}6. MCP Server Prerequisites${NC}"

if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 --version 2>&1)
    check_pass "Python installed ($PY_VERSION)"
else
    check_fail "Python 3 not installed"
fi

if command -v uv &> /dev/null; then
    check_pass "uv installed ($(uv --version 2>&1))"
elif command -v uvx &> /dev/null; then
    check_pass "uvx available"
else
    check_fail "uv/uvx not installed — required to run EKS MCP server"
    echo "    Install: https://docs.astral.sh/uv/getting-started/installation/"
fi

echo ""

# ── Summary ──
echo "======================================"
echo -e "${BOLD}Summary${NC}"
echo "======================================"
echo -e "  ${GREEN}Passed:${NC}  $pass_count"
echo -e "  ${RED}Failed:${NC}  $fail_count"
echo -e "  ${YELLOW}Warnings:${NC} $warn_count"
echo ""

if [ "$fail_count" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All required permissions verified. Ready to run the assessment.${NC}"
    echo ""
    echo "Open Kiro and ask: \"Run an EKS upgrade readiness assessment\""
else
    echo -e "${RED}${BOLD}$fail_count permission check(s) failed.${NC}"
    echo ""
    echo "Ask your AWS administrator to attach a policy with these permissions:"
    echo ""
    echo "  eks:DescribeCluster, eks:ListClusters, eks:ListNodegroups,"
    echo "  eks:DescribeNodegroup, eks:ListAddons, eks:DescribeAddon,"
    echo "  eks:ListInsights, eks:DescribeInsight,"
    echo "  ec2:DescribeSubnets,"
    echo "  iam:GetRole, iam:ListAttachedRolePolicies, iam:ListRolePolicies,"
    echo "  iam:GetRolePolicy"
    echo ""
    echo "Or use the sample IAM policy in the README."
fi
echo ""
