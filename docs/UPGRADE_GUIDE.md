# Argo CD Upgrade Guide

Step-by-step guide for upgrading Argo CD from v2.10.x to v3.2.1.

## Upgrade Path Overview

```
v2.10.x ──► v2.14 ──► v3.0 ──► v3.1 ──► v3.2.1
           (prep)   (MAJOR)  (minor)  (TARGET)
```

**Why this path?**
- **v2.14**: Last v2.x release, preparation for v3.0
- **v3.0**: Major version with breaking RBAC changes
- **v3.1**: Incremental improvements
- **v3.2.1**: Latest stable (our target)

## Prerequisites

Ensure setup is complete before starting upgrades:

```bash
# Verify minikube is running
minikube status -p argocd-upgrade-demo

# Verify Argo CD v2.10 is installed
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: quay.io/argoproj/argocd:v2.10.17

# Verify all apps are healthy
argocd app list
```

---

## Step 1: Upgrade to v2.14

**Risk Level:** Low
**Breaking Changes:** None critical
**Estimated Time:** 5-10 minutes

### Execute

```bash
./scripts/02-upgrade-to-2.14.sh
```

### What the Script Does

1. Creates backup of current state
2. Applies v2.14 Kustomize overlay
3. Waits for all pods to be ready
4. Runs validation checks
5. Displays next steps

### Manual Validation

```bash
# Check version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: quay.io/argoproj/argocd:v2.14.2

# Check pods
kubectl get pods -n argocd

# Check applications
argocd app list
```

### Checklist

See [validation/checklist-2.10-to-2.14.md](../validation/checklist-2.10-to-2.14.md)

### Rollback (if needed)

```bash
./scripts/rollback.sh v2.10
```

---

## Step 2: Upgrade to v3.0 (CRITICAL)

**Risk Level:** HIGH
**Breaking Changes:** RBAC, Redis removal
**Estimated Time:** 15-20 minutes

### ⚠️ READ BEFORE PROCEEDING

This is the **most critical upgrade** in the path. Key changes:

1. **Fine-grained RBAC**: `update`/`delete` on Application no longer implies same on managed resources
2. **Redis removed**: No longer needed for caching
3. **K8s 1.21+ required**: Verify your cluster version

### Execute

```bash
./scripts/03-upgrade-to-3.0.sh
```

### What the Script Does

1. Verifies K8s version ≥ 1.21
2. Creates comprehensive backup
3. **Applies RBAC migration FIRST** (critical)
4. Applies v3.0 Kustomize overlay
5. Waits for all pods (note: Redis will be removed)
6. Runs RBAC validation tests
7. Displays detailed results

### RBAC Migration Details

The script applies `overlays/v3.0/migrations/argocd-rbac-v3-migration.yaml` which adds:

```yaml
# These permissions are NEW in v3.0 and REQUIRED for operators
p, role:operator, applications, update/*, */*, allow
p, role:operator, applications, delete/*, */*, allow
```

**Without this migration**, operators will lose the ability to:
- Edit resources managed by applications
- Delete resources managed by applications
- Restart deployments
- Scale replicas

### Manual Validation

```bash
# Check version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: quay.io/argoproj/argocd:v3.0.4

# Verify Redis is GONE (expected!)
kubectl get deploy -n argocd | grep redis
# Expected: No results

# Check RBAC permissions
argocd account can-i sync applications '*/*'
# Expected: yes

argocd account can-i update applications '*/*'
# Expected: yes (if RBAC migration applied)

# Test actual resource operations
# Go to UI → Select an app → Click a Deployment → Try "Restart"
```

### Checklist

See [validation/checklist-2.14-to-3.0.md](../validation/checklist-2.14-to-3.0.md)

### Rollback (if needed)

```bash
./scripts/rollback.sh v2.14
```

### Production Notes

1. **Apply RBAC migration BEFORE upgrade** in production
2. Update monitoring dashboards to remove Redis metrics
3. Notify all operators about RBAC changes
4. Test with a limited set of applications first

---

## Step 3: Upgrade to v3.1

**Risk Level:** Low
**Breaking Changes:** Symlink protection, API deprecation
**Estimated Time:** 5-10 minutes

### Execute

```bash
./scripts/04-upgrade-to-3.1.sh
```

### What the Script Does

1. Creates backup
2. Applies v3.1 Kustomize overlay
3. Waits for all pods
4. Validates no symlink errors
5. Tests resource actions

### Key Changes

1. **Symlink Protection**: New security feature that may cause 500 errors if symlinks exist in repos
2. **Actions API v1 Deprecated**: v2 API is now the default

### Manual Validation

```bash
# Check version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: quay.io/argoproj/argocd:v3.1.1

# Check for symlink errors
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep -i symlink
# Expected: No errors

# Test resource actions via UI
# Open app → Click Deployment → Actions → Restart
```

### Checklist

See [validation/checklist-3.0-to-3.1.md](../validation/checklist-3.0-to-3.1.md)

### Rollback (if needed)

```bash
./scripts/rollback.sh v3.0
```

---

## Step 4: Upgrade to v3.2.1 (FINAL TARGET)

**Risk Level:** Low
**Breaking Changes:** Hydration paths, new features
**Estimated Time:** 5-10 minutes

### Execute

```bash
./scripts/05-upgrade-to-3.2.1.sh
```

### What the Script Does

1. Creates backup
2. Applies v3.2 Kustomize overlay
3. Waits for all pods
4. Tests new server-side diff feature
5. Runs comprehensive validation
6. Displays production readiness summary

### Key Changes

1. **Server-side Diff**: New feature for improved diff accuracy
2. **Hydration Paths**: If using ApplicationSet with hydration, paths cannot be "" or "."

### Manual Validation

```bash
# Check version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: quay.io/argoproj/argocd:v3.2.1

# Test server-side diff (new feature)
argocd app diff guestbook --server-side
# Expected: Diff output (may be empty if synced)

# Test all apps
argocd app list
argocd app sync guestbook
```

### Checklist

See [validation/checklist-3.1-to-3.2.md](../validation/checklist-3.1-to-3.2.md)

### Rollback (if needed)

```bash
./scripts/rollback.sh v3.1
```

---

## Complete Validation

After reaching v3.2.1, run the full validation suite:

```bash
./scripts/validate.sh
```

This checks:
- All component versions
- Pod health
- Application sync status
- RBAC permissions
- UI accessibility
- Resource actions

---

## Rollback Procedure

At any point, you can rollback to a previous version:

```bash
# List available backups
./scripts/rollback.sh

# Rollback to specific version
./scripts/rollback.sh v3.0
./scripts/rollback.sh v2.14
./scripts/rollback.sh v2.10
```

### What Rollback Does

1. Restores ConfigMaps from backup
2. Applies previous version's Kustomize overlay
3. Waits for pods to stabilize
4. Runs validation

### Rollback Limitations

- Application data is NOT rolled back (stored in K8s resources)
- Secrets are NOT rolled back (for security)
- Custom resources may need manual cleanup

---

## Post-Upgrade: Production Planning

Once all validation passes in minikube:

### Documentation

- [ ] Document all breaking changes encountered
- [ ] Update team runbooks
- [ ] Update monitoring dashboards (Redis removal)

### Communication

- [ ] Notify platform team
- [ ] Notify application teams (RBAC changes)
- [ ] Schedule maintenance window

### Production Execution

1. **Pre-production cluster first**: Test on staging/pre-prod
2. **Blue-green if possible**: Deploy alongside existing
3. **Gradual rollout**: One cluster at a time
4. **Monitor closely**: Watch for RBAC-related errors

---

## Timeline Summary

| Step | Version | Risk | Time |
|------|---------|------|------|
| 1 | v2.10 → v2.14 | Low | 5-10 min |
| 2 | v2.14 → v3.0 | **HIGH** | 15-20 min |
| 3 | v3.0 → v3.1 | Low | 5-10 min |
| 4 | v3.1 → v3.2.1 | Low | 5-10 min |
| Validation | - | - | 10 min |
| **Total** | - | - | **~45-60 min** |

---

## Quick Reference Commands

```bash
# Check current version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check all pods
kubectl get pods -n argocd

# Check application status
argocd app list

# Check RBAC
argocd account can-i sync applications '*/*'
argocd account can-i update applications '*/*'

# View logs
kubectl logs -f deploy/argocd-server -n argocd

# Run validation
./scripts/validate.sh

# Rollback
./scripts/rollback.sh <version>
```

---

## Additional Resources

- [BREAKING_CHANGES.md](./BREAKING_CHANGES.md) - Detailed breaking changes by version
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions
- [Official Argo CD Upgrade Docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/)
