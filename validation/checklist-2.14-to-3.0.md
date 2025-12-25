# Validation Checklist: v2.14.x → v3.0.x

## ⚠️ CRITICAL: MAJOR VERSION UPGRADE

This is the **most critical upgrade step** with significant breaking changes.

## Pre-Upgrade Checks

- [ ] Current version is v2.14.x
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  ```

- [ ] Kubernetes version is 1.21+
  ```bash
  kubectl version --short
  # Server Version must be >= v1.21
  ```

- [ ] All applications are Healthy/Synced
  ```bash
  argocd app list
  ```

- [ ] RBAC migration file exists
  ```bash
  ls overlays/v3.0/migrations/argocd-rbac-v3-migration.yaml
  ```

- [ ] Backup created
  ```bash
  # Backup is created automatically by upgrade script
  ls backups/
  ```

## Post-Upgrade Checks

### Component Health

- [ ] Version updated to v3.0.x
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  # Expected: quay.io/argoproj/argocd:v3.0.x
  ```

- [ ] **Redis is REMOVED** (expected in v3.0)
  ```bash
  kubectl get deploy -n argocd | grep redis
  # Expected: No results (Redis removed in v3.0)
  ```

- [ ] All pods are Running
  ```bash
  kubectl get pods -n argocd
  ```

- [ ] No errors in logs
  ```bash
  kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep -i error
  kubectl logs -l app.kubernetes.io/name=argocd-application-controller -n argocd --since=5m | grep -i error
  ```

### RBAC - CRITICAL CHECKS

The fine-grained RBAC changes are the most important thing to validate.

- [ ] RBAC migration was applied
  ```bash
  kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep "update/\*"
  # Expected: Should see 'update/*' permissions
  ```

- [ ] Owner role works
  ```bash
  argocd account can-i sync applications '*/*'
  # Expected: yes
  ```

- [ ] Operator can sync apps
  ```bash
  argocd account can-i sync applications 'test-apps/*'
  # Expected: yes
  ```

- [ ] **Operator can UPDATE managed resources** (NEW in v3.0)
  ```bash
  argocd account can-i update applications '*/*'
  # Expected: yes (if update/* permission added)
  ```

- [ ] Viewer has read-only access
  ```bash
  argocd account can-i get applications '*/*'
  # Expected: yes
  argocd account can-i sync applications '*/*'
  # Expected: no (for viewer role)
  ```

### Application Health

- [ ] All applications remain Healthy/Synced
  ```bash
  argocd app list
  ```

- [ ] Test sync works
  ```bash
  argocd app sync guestbook
  # Expected: Synced successfully
  ```

- [ ] Test resource update (v3.0 fine-grained test)
  ```bash
  # Try to edit a resource via UI or CLI
  # This should work if RBAC migration was applied correctly
  ```

### UI Access

- [ ] UI is accessible at https://localhost:8080
- [ ] Can login with admin credentials
- [ ] Can view applications
- [ ] Can trigger sync
- [ ] Can view resource details
- [ ] Can perform resource actions (restart, etc.)

## Breaking Changes Verification

### 1. Fine-Grained RBAC ✓

- [ ] Verified `update/*` permissions exist
- [ ] Verified `delete/*` permissions exist (if needed)
- [ ] Tested operator can still manage resources

### 2. Redis Removed ✓

- [ ] Confirmed no Redis pods
- [ ] Note: Update monitoring dashboards in production

### 3. Kubernetes 1.21+ ✓

- [ ] Verified K8s version requirement met

## Production Notes

When applying this upgrade in production:

1. **RBAC Migration**: Apply the RBAC migration BEFORE upgrading
   ```bash
   kubectl apply -f overlays/v3.0/migrations/argocd-rbac-v3-migration.yaml
   ```

2. **Monitoring**: Update dashboards to remove Redis metrics

3. **Notify Teams**: Inform operators about RBAC changes

## Rollback Command

If issues are found:
```bash
./scripts/rollback.sh v2.14
```

## Sign-off

- [ ] All component checks passed
- [ ] RBAC working for all roles
- [ ] Applications healthy
- [ ] Ready to proceed to v3.1

**Validated by:** _________________ **Date:** _________________

**Notes:**
