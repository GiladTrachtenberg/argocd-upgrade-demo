# Production Context & Minikube Adaptations

This document explains our production Argo CD setup and how we adapted it for the minikube demo environment.

**Last Updated:** December 2024
**Production Setup Location:** `/Users/giladtrachtenberg/work/git/platform-infra/k8s/argocd/setup/`

---

## Why This Demo Exists

### The Problem

Our production Argo CD (v2.10.0) manages:
- **3 Kubernetes clusters** (hub, development, production)
- **18 AppProjects** spanning multiple teams and environments
- **Critical business applications** that cannot have downtime

We need to upgrade to v3.2.1, but:
1. The upgrade crosses a **major version boundary** (v2 → v3)
2. There are **breaking RBAC changes** that could lock out operators
3. **Redis is removed** in v3.0, affecting monitoring
4. We can't afford to discover issues in production

### The Solution

This minikube environment lets us:
- Test the exact upgrade path safely
- Validate our RBAC policies work after v3.0
- Practice rollback procedures
- Document issues and solutions before production upgrade

---

## Production Setup Summary

### Installation Method

**Kustomize-based** using official HA manifests:

```yaml
# From: /platform-infra/k8s/argocd/setup/manifests/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/ha/install.yaml
```

**Why HA manifests?**
- Production handles 18 projects across 3 clusters
- HA provides redundancy for the control plane
- We keep HA in minikube for configuration parity

### Authentication: Google SSO via Dex

```yaml
# From: argocd-cm.yaml
dex.config: |
  connectors:
    - type: google
      id: google
      name: Google
      config:
        redirectURI: https://argocd.hub.crowncoinscasino.com/api/dex/callback
        hostedDomains:
          - sunfltd.com
          - crowncoinscasino.com
```

**Minikube Adaptation:** SSO disabled. We use local admin account for testing.

### RBAC: Three-Tier Role System

```yaml
# From: argocd-rbac-cm.yaml
scopes: "[groups]"
policy.csv: |
  # Owners - full access (argocd-owners@sunfltd.com)
  p, role:owner, applications, *, */*, allow
  p, role:owner, clusters, *, *, allow
  p, role:owner, repositories, *, *, allow
  p, role:owner, projects, *, *, allow

  # Operators - manage applications (argocd-operators@sunfltd.com)
  p, role:operator, applications, get, */*, allow
  p, role:operator, applications, sync, */*, allow
  p, role:operator, applications, action/*, */*, allow
  # ... plus access to specific project namespaces

  # Viewers - read-only (argocd-viewers@sunfltd.com)
  p, role:viewer, applications, get, *, allow
  p, role:viewer, applications, list, *, allow
```

**Minikube Adaptation:** Same 3-role structure, but mapped to local users instead of Google groups.

### Secrets: External Secrets Operator

```yaml
# From: argocd-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secretsmanager
  target:
    name: argocd-secret
    creationPolicy: Merge
```

**Minikube Adaptation:** Plain Kubernetes Secrets with hardcoded values (not ExternalSecrets).

### Ingress: AWS ALB

```yaml
# From: argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/backend-protocol-version: HTTP2
```

**Minikube Adaptation:** NodePort service + `minikube tunnel` for access.

### Multi-Cluster: 3 EKS Clusters

| Cluster | Purpose | Endpoint |
|---------|---------|----------|
| Hub | Argo CD runs here | `https://kubernetes.default.svc` |
| Development | Dev/staging apps | `https://E5F27...eks.amazonaws.com` |
| Production | Prod apps | `https://7A2DD...eks.amazonaws.com` |

**Minikube Adaptation:** Single in-cluster only (`https://kubernetes.default.svc`).

### Projects: 18 AppProjects

Production has projects for:
- Application teams: blitz, crowncoins-*, c3-*, metagames-*, mini-games-*, icasino-*, aggregators-*
- Infrastructure: core, infra-*, hub
- Shared services: monitoring, n8n, kafka-*, grafana

**Minikube Adaptation:** Single `test-apps` project for demo purposes.

### Monitoring: Prometheus ServiceMonitors

```yaml
# From: service-monitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    release: prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
```

**Minikube Adaptation:** Omitted (not needed for upgrade testing).

---

## Minikube Adaptations Summary

| Production Feature | Minikube Adaptation | Why |
|-------------------|---------------------|-----|
| AWS ALB Ingress | NodePort + tunnel | No AWS in local |
| External Secrets (AWS) | Local K8s Secrets | No AWS Secrets Manager |
| Google SSO via Dex | Disabled, local admin | Simpler for testing |
| 3 EKS clusters | Single minikube | Testing upgrade, not multi-cluster |
| 18 AppProjects | 1 test-apps project | Validate project functionality |
| HA manifests | **Kept as-is** | Configuration parity |
| 3-role RBAC | **Kept as-is** | Testing RBAC upgrade |
| Prometheus ServiceMonitors | Omitted | Not testing monitoring |
| Webhook ingress | Omitted | Not testing webhooks |
| gRPC service | Omitted | Not needed without ALB |

---

## Critical Production Files Reference

When preparing the production upgrade, refer to these files:

| File | Purpose | Upgrade Impact |
|------|---------|----------------|
| `manifests/kustomization.yaml` | Main orchestration | Update HA manifest URL |
| `manifests/argocd-rbac-cm.yaml` | RBAC policies | **Must update for v3.0** |
| `manifests/argocd-cm.yaml` | Core configuration | Check for deprecated keys |
| `manifests/argocd-secret.yaml` | External secrets | No change expected |
| `manifests/service-monitors.yaml` | Prometheus integration | Remove Redis monitors in v3.0 |
| `scripts/argocd-projects-setup.bash` | Project automation | May need API updates |

---

## RBAC Migration Notes for v3.0

**This is the most critical change.**

In v3.0, fine-grained RBAC means:
- `update` on Application no longer implies `update` on managed resources
- `delete` on Application no longer implies `delete` on managed resources

**Current production RBAC (v2.10):**
```yaml
p, role:operator, applications, sync, */*, allow
p, role:operator, applications, action/*, */*, allow
```

**Required for v3.0:**
```yaml
p, role:operator, applications, sync, */*, allow
p, role:operator, applications, action/*, */*, allow
p, role:operator, applications, update/*, */*, allow  # NEW
p, role:operator, applications, delete/*, */*, allow  # NEW (if needed)
```

The minikube demo tests this exact change in `overlays/v3.0/patches/argocd-rbac-patch.yaml`.

---

## Production Upgrade Checklist

After validating in minikube, the production upgrade will need:

1. **Pre-upgrade:**
   - [ ] Backup all ConfigMaps and Secrets
   - [ ] Export current RBAC policies
   - [ ] Notify teams of maintenance window
   - [ ] Verify all apps are Healthy/Synced

2. **RBAC Migration (before v3.0):**
   - [ ] Apply fine-grained RBAC additions
   - [ ] Test operator access still works
   - [ ] Verify viewer access unchanged

3. **Post-upgrade validation:**
   - [ ] All pods Running
   - [ ] All apps still Healthy/Synced
   - [ ] RBAC working for all roles
   - [ ] UI accessible via SSO
   - [ ] Webhook endpoint responding

4. **Monitoring updates (after v3.0):**
   - [ ] Remove Redis ServiceMonitor
   - [ ] Update Grafana dashboards
   - [ ] Verify remaining metrics flowing

---

## Questions to Answer in Demo

1. **RBAC:** Do operators retain access after v3.0 with our updated policies?
2. **Sync behavior:** Do apps auto-sync correctly after each upgrade?
3. **Health checks:** Are health assessments still accurate?
4. **UI:** Does the web interface work without issues?
5. **CLI:** Does `argocd` CLI work with updated API versions?
6. **Rollback:** Can we rollback cleanly if issues arise?

Each question should be answered with "Yes, verified in minikube demo" before production upgrade.
