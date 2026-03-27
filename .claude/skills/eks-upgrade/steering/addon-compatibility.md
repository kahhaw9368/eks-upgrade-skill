# Add-on Compatibility

## Purpose
Assess all EKS managed add-ons, discovered OSS add-ons, and Karpenter for compatibility with the target Kubernetes version.

## Checks to Execute

### 4.1 — Core EKS Managed Add-ons

The 4 core add-ons that MUST be checked:
- `vpc-cni` (Amazon VPC CNI)
- `coredns`
- `kube-proxy`
- `aws-ebs-csi-driver` (if installed)

**How to check:**
1. List all EKS managed add-ons → describe each for version, status, health
2. For each core add-on:
   - Record installed version
   - Check health status and any issues
   - Note if it's self-managed (not in the managed add-on list but running in kube-system)

**Key talking point:** EKS does NOT auto-update add-ons when you upgrade the control plane. This is the #1 thing customers forget. A cluster upgraded to 1.33 can still be running vpc-cni from 1.29.

**Rating per add-on:**
- Compatible + healthy → PASS
- Behind but compatible → WARN (update recommended)
- Incompatible or unhealthy → FAIL
- Self-managed (not EKS managed) → WARN (recommend converting to managed)

### 4.2 — Additional Managed Add-ons

Check any other installed managed add-ons:
- `amazon-cloudwatch-observability`
- `aws-efs-csi-driver`
- `adot` (AWS Distro for OpenTelemetry)
- `eks-pod-identity-agent`
- `aws-guardduty-agent`
- `eks-node-monitoring-agent`
- `snapshot-controller`

**How to check:**
1. List all add-ons → describe each
2. Record version, status, health for each

### 4.3 — OSS Add-on Discovery & Compatibility Verification

Scan workloads to discover non-AWS add-ons running in the cluster, then verify their
compatibility with the target Kubernetes version via web search.

**Step 1: Discover OSS add-ons**
1. List Deployments, DaemonSets, StatefulSets across all namespaces
2. For each workload, extract add-on identity from:
   - Labels: `app.kubernetes.io/name`, `app.kubernetes.io/version`
   - Helm labels: `helm.sh/chart`
   - Container image tags
3. Exclude AWS-managed add-ons (vpc-cni, coredns, kube-proxy, ebs-csi) and Karpenter (checked separately)
4. For each discovered add-on, record: name, version, namespace, identification method

**Common OSS add-ons to look for:**
- cert-manager
- external-dns
- metrics-server
- cluster-autoscaler
- aws-load-balancer-controller
- ingress-nginx (retired March 2026)
- istio / envoy
- prometheus / grafana
- argocd / flux

**Step 2: Web search for compatibility (MANDATORY for each discovered OSS add-on)**

For EACH OSS add-on found in the cluster, you MUST perform a web search to verify
compatibility with the target Kubernetes version. Do NOT rely on LLM training data
for version compatibility — it is likely outdated.

**Search pattern:** Use `remote_web_search` with query:
`"<addon-name> <addon-version> compatibility Kubernetes <target-version>"`

Example searches:
- `"cert-manager 1.14 compatibility Kubernetes 1.31"`
- `"istio 1.20 supported Kubernetes versions"`
- `"aws-load-balancer-controller 2.7 EKS 1.31 compatibility"`

**What to look for in search results:**
1. Official compatibility matrix or supported versions page
2. GitHub issues mentioning the addon + target Kubernetes version
3. Known breaking changes or required minimum versions

**If web search returns no results:** Report the add-on as "compatibility UNKNOWN — manual
verification required" with MEDIUM severity. Do NOT assume it's compatible.

**Output per OSS add-on:**
```
| Add-on | Version | Compatible with target? | Source | Notes |
```

### 4.4 — Karpenter Compatibility

**How to check:**
1. List Deployments in the `karpenter` namespace, or check for NodePool CRDs (`nodepools.karpenter.sh`)
2. If installed, find the Karpenter deployment → extract version from:
   - Labels: `app.kubernetes.io/version` or `helm.sh/chart`
   - Container image tag (e.g., `public.ecr.aws/karpenter/controller:0.37.0`)
3. Check compatibility against the official matrix from https://karpenter.sh/docs/upgrading/compatibility/:

**Official Karpenter Compatibility Matrix (source: karpenter.sh):**

| Kubernetes | 1.29 | 1.30 | 1.31 | 1.32 | 1.33 | 1.34 | 1.35 |
|------------|------|------|------|------|------|------|------|
| Karpenter  | >= 0.34 | >= 0.37 | >= 1.0.5 | >= 1.2 | >= 1.5 | >= 1.6 | >= 1.9 |

**IMPORTANT:** Do NOT rely on the approximate ranges previously listed here. Always use the
matrix above. Note the jump from 0.37 (for 1.30) to 1.0.5 (for 1.31) — this is a major
version boundary that requires API migration (v1beta1 → v1).

**If the target Kubernetes version or installed Karpenter version is NOT in the matrix above:**
You MUST perform a web search to verify compatibility:
1. Search: `"Karpenter compatibility matrix Kubernetes <target-version>"` using `remote_web_search`
2. Fetch the official page: `https://karpenter.sh/docs/upgrading/compatibility/` using `webFetch`
3. Do NOT guess or assume compatibility. Report as UNKNOWN if you can't verify.

**Rating:**
- Compatible version per matrix → PASS
- Installed but version unknown → WARN (manual review)
- Incompatible version per matrix → FAIL (must upgrade Karpenter BEFORE control plane)

**Key talking point:** Karpenter must be upgraded BEFORE the control plane, not after. The order matters. The 0.x → 1.x migration requires migrating from Provisioner to NodePool v1 APIs. See https://karpenter.sh/v1.0/upgrading/v1-migration/

## Score Impact

| Finding | Deduction |
|---------|-----------|
| Critical add-on incompatible (vpc-cni, coredns, kube-proxy) | 5 pts each |
| Optional add-on incompatible | 3 pts each |
| Update recommended | 1 pt each |
| Karpenter incompatible | 10 pts |
| Max category deduction | 15 pts (add-ons) + 10 pts (Karpenter) |
