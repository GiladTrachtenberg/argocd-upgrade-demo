# Argo CD Upgrade Demo Environment

A minikube-based environment for testing the Argo CD upgrade path from **v2.10.x → v3.2.1**.

## Why This Exists

Our production Argo CD (v2.10.0) needs to be upgraded to v3.2.1. This upgrade:
- Crosses a **major version boundary** (v2 → v3)
- Involves **breaking changes** (RBAC, Redis removal, API deprecations)
- Requires a **multi-step upgrade path** (can't jump directly)

This demo environment lets us:
1. Test each upgrade step safely
2. Validate our GitOps workflows survive the upgrade
3. Document issues before touching production
4. Practice rollback procedures

## Quick Start

```bash
# 1. Set up minikube cluster
./scripts/00-setup-minikube.sh

# 2. Install Argo CD v2.10.x (baseline)
./scripts/01-install-argocd-2.10.sh

# 3. Run upgrade steps one at a time
./scripts/02-upgrade-to-2.14.sh
./scripts/03-upgrade-to-3.0.sh    # Critical - has RBAC breaking changes
./scripts/04-upgrade-to-3.1.sh
./scripts/05-upgrade-to-3.2.1.sh

# After each step, validate
./scripts/validate.sh

# If something breaks, rollback
./scripts/rollback.sh v2.14  # Rollback to specific version

# Clean up when done
./scripts/cleanup.sh
```

## Upgrade Path

```
v2.10.17 → v2.14.x → v3.0.x → v3.1.x → v3.2.1
    │         │         │         │         │
    │         │         │         │         └─ Server-side diff, hydration path changes
    │         │         │         └─ Symlink protection, Actions API v2
    │         │         └─ MAJOR: Fine-grained RBAC, Redis removed, K8s 1.21+
    │         └─ Preparation step
    └─ Current production version
```

## Directory Structure

```
.
├── scripts/          # Automation scripts for setup, upgrade, validation
├── base/             # Base Kustomize configuration (version-agnostic)
├── overlays/         # Version-specific Kustomize overlays
│   ├── v2.10/
│   ├── v2.14/
│   ├── v3.0/         # Includes RBAC migration
│   ├── v3.1/
│   └── v3.2/
├── test-apps/        # Sample apps to validate GitOps flows
├── validation/       # Checklists and smoke tests
└── docs/             # Detailed documentation
```

## Key Breaking Changes

| Upgrade Step | What Breaks | How We Handle It |
|-------------|-------------|------------------|
| **2.14 → 3.0** | RBAC: `update`/`delete` no longer implies sub-resource access | Add explicit `update/*`, `delete/*` permissions |
| **2.14 → 3.0** | Redis removed | Update monitoring (no Redis metrics) |
| **3.0 → 3.1** | Symlinks blocked in static assets | Check `/app/shared` access patterns |
| **3.0 → 3.1** | Actions API v1 deprecated | Migrate to `/api/v1/.../actions/v2` |
| **3.1 → 3.2** | Hydration paths must be non-root | Use subdirectories, not `""` or `"."` |

## Test Applications

The demo includes sample apps to verify GitOps flows after each upgrade:

| App | Type | Tests |
|-----|------|-------|
| `guestbook` | Kustomize | Kustomize rendering, sync, health |
| `helm-nginx` | Helm | Helm chart rendering, upgrades |
| `plain-yaml` | Plain YAML | Basic manifest application |
| `app-of-apps` | App of Apps | Parent/child application pattern |

## Production Reference

This demo mirrors our production setup at:
```
/Users/giladtrachtenberg/work/git/platform-infra/k8s/argocd/setup/
```

See [CONTEXT.md](./CONTEXT.md) for details on how production is configured and what we adapted for minikube.

## Documentation

- [CONTEXT.md](./CONTEXT.md) - Production setup context and adaptations
- [docs/SETUP.md](./docs/SETUP.md) - Detailed setup instructions
- [docs/UPGRADE_GUIDE.md](./docs/UPGRADE_GUIDE.md) - Step-by-step upgrade guide
- [docs/BREAKING_CHANGES.md](./docs/BREAKING_CHANGES.md) - All breaking changes by version
- [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) - Common issues and solutions

## Prerequisites

- `minikube` v1.30+
- `kubectl` v1.28+
- `kustomize` v5.0+
- `argocd` CLI v2.10+
- 8GB RAM available for minikube

## Official Argo CD Upgrade Docs

- [Upgrade Overview](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/)
- [v2.10 → v2.11](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.10-2.11/)
- [v2.x → v3.0](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.x-3.0/)
- [v3.0 → v3.1](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/)
- [v3.1 → v3.2](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/)
