# Setup Guide

Detailed instructions for setting up the Argo CD upgrade demo environment.

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|------|-----------------|--------------|
| minikube | v1.30+ | `brew install minikube` |
| kubectl | v1.28+ | `brew install kubectl` |
| kustomize | v5.0+ | `brew install kustomize` |
| argocd | v2.10+ | `brew install argocd` |

### System Requirements

- **CPU:** 4 cores (for minikube)
- **RAM:** 8GB available (for minikube)
- **Disk:** 40GB free space
- **Container Runtime:** Docker Desktop (recommended)

### Verify Prerequisites

```bash
# Check all tools
minikube version
kubectl version --client
kustomize version
argocd version --client
```

## Quick Setup

```bash
# 1. Create minikube cluster
./scripts/00-setup-minikube.sh

# 2. Install Argo CD v2.10.x
./scripts/01-install-argocd-2.10.sh

# 3. Access Argo CD UI
# URL: https://localhost:8080
# User: admin
# Pass: admin123 (or check output)
```

## Detailed Setup

### Step 1: Create Minikube Cluster

The setup script creates a minikube cluster with:
- Kubernetes v1.28.0
- 8GB RAM
- 4 CPUs
- 40GB disk
- Ingress and metrics-server addons

```bash
./scripts/00-setup-minikube.sh
```

#### Custom Configuration

```bash
# Use different resources
MEMORY=16384 CPUS=8 ./scripts/00-setup-minikube.sh

# Use different Kubernetes version
KUBERNETES_VERSION=v1.29.0 ./scripts/00-setup-minikube.sh

# Use different cluster name
CLUSTER_NAME=my-argocd-demo ./scripts/00-setup-minikube.sh
```

### Step 2: Install Argo CD v2.10.x

This installs the baseline version matching production:

```bash
./scripts/01-install-argocd-2.10.sh
```

The script will:
1. Apply the v2.10 Kustomize overlay
2. Wait for all components to be ready
3. Set up port-forward for UI access
4. Deploy test applications
5. Run initial validation

### Step 3: Verify Installation

```bash
# Check pods
kubectl get pods -n argocd

# Check version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check applications
argocd app list
```

### Step 4: Access the UI

The install script starts port-forward automatically. If you need to restart it:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Access: https://localhost:8080

**Credentials:**
- Username: `admin`
- Password: `admin123` (or from `./credentials/password`)

## Project Structure

```
.
├── scripts/           # Automation scripts
│   ├── 00-setup-minikube.sh
│   ├── 01-install-argocd-2.10.sh
│   ├── 02-upgrade-to-2.14.sh
│   ├── 03-upgrade-to-3.0.sh
│   ├── 04-upgrade-to-3.1.sh
│   ├── 05-upgrade-to-3.2.1.sh
│   ├── validate.sh
│   ├── rollback.sh
│   ├── cleanup.sh
│   └── lib/           # Shared functions
│
├── base/              # Base Kustomize config
├── overlays/          # Version-specific overlays
│   ├── v2.10/
│   ├── v2.14/
│   ├── v3.0/
│   ├── v3.1/
│   └── v3.2/
│
├── test-apps/         # Test applications
├── validation/        # Checklists
├── docs/              # Documentation
└── backups/           # State backups (created during upgrades)
```

## Common Commands

### Cluster Management

```bash
# Start/stop minikube
minikube start -p argocd-upgrade-demo
minikube stop -p argocd-upgrade-demo

# SSH into node
minikube ssh -p argocd-upgrade-demo

# Open dashboard
minikube dashboard -p argocd-upgrade-demo

# Delete cluster
minikube delete -p argocd-upgrade-demo
```

### Argo CD CLI

```bash
# Login (use current port-forward)
argocd login localhost:8080 --username admin --password admin123 --insecure --grpc-web

# List apps
argocd app list

# Sync an app
argocd app sync guestbook

# Get app details
argocd app get guestbook

# Check RBAC
argocd account can-i sync applications '*/*'
```

### Kubectl

```bash
# Switch context to demo cluster
minikube profile argocd-upgrade-demo

# Check pods
kubectl get pods -n argocd

# View logs
kubectl logs -f deploy/argocd-server -n argocd

# Check events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

## Next Steps

After setup is complete:

1. **Explore the UI:** Open https://localhost:8080 and explore
2. **Check test apps:** Verify guestbook and other apps are synced
3. **Start upgrades:** Run `./scripts/02-upgrade-to-2.14.sh`

See [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) for the upgrade process.

## Troubleshooting

If you encounter issues, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

Common quick fixes:

```bash
# Restart port-forward
pkill -f "port-forward.*argocd"
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Check minikube status
minikube status -p argocd-upgrade-demo

# Check pod issues
kubectl describe pod -l app.kubernetes.io/part-of=argocd -n argocd

# Full validation
./scripts/validate.sh
```
