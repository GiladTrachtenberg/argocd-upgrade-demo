# Validation Checklist: v3.0.x → v3.1.x

## Pre-Upgrade Checks

- [ ] Current version is v3.0.x
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  ```

- [ ] All applications are Healthy/Synced
  ```bash
  argocd app list
  ```

- [ ] Backup created
  ```bash
  ls backups/
  ```

## Post-Upgrade Checks

### Component Health

- [ ] Version updated to v3.1.x
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  # Expected: quay.io/argoproj/argocd:v3.1.x
  ```

- [ ] All pods are Running
  ```bash
  kubectl get pods -n argocd
  ```

- [ ] **No symlink errors** (new protection in v3.1)
  ```bash
  kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep -i symlink
  # Expected: No symlink-related errors
  ```

- [ ] No 500 errors
  ```bash
  kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep "500"
  # Expected: No 500 errors from symlink protection
  ```

### Application Health

- [ ] All applications remain Healthy/Synced
  ```bash
  argocd app list
  ```

- [ ] Test sync works
  ```bash
  argocd app sync guestbook
  ```

### Actions API

- [ ] Resource actions work via UI
  - Open app in UI
  - Click on a Deployment
  - Try "Restart" action
  - Expected: Action executes successfully

- [ ] Note: v1 Actions API is deprecated
  - Old: `/api/v1/applications/{name}/resource/actions`
  - New: `/api/v1/applications/{name}/resource/actions/v2`

### RBAC (inherited from v3.0)

- [ ] RBAC still working from v3.0 migration
  ```bash
  argocd account can-i sync applications '*/*'
  ```

## Breaking Changes Verification

### 1. Symlink Protection ✓

- [ ] No 500 errors related to symlinks
- [ ] Static assets load correctly in UI

### 2. Actions API v2 ✓

- [ ] UI actions work (uses v2 internally)
- [ ] Note: Update any custom scripts using v1 API

## Rollback Command

If issues are found:
```bash
./scripts/rollback.sh v3.0
```

## Sign-off

- [ ] All checks passed
- [ ] Ready to proceed to v3.2.1 (final target)

**Validated by:** _________________ **Date:** _________________
