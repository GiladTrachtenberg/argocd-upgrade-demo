# Validation Checklist: v3.1.x → v3.2.1 (FINAL TARGET)

## 🎯 This is the FINAL TARGET VERSION

## Pre-Upgrade Checks

- [ ] Current version is v3.1.x
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

- [ ] Version updated to v3.2.1
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  # Expected: quay.io/argoproj/argocd:v3.2.1
  ```

- [ ] All pods are Running
  ```bash
  kubectl get pods -n argocd
  ```

- [ ] No errors in logs
  ```bash
  kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep -i error
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

### New Features in v3.2

- [ ] **Server-side diff works** (NEW FEATURE)
  ```bash
  argocd app diff guestbook --server-side
  # Expected: Diff output (may be empty if synced)
  ```

- [ ] Client-side diff still works
  ```bash
  argocd app diff guestbook
  ```

### RBAC (inherited from v3.0)

- [ ] All roles working
  ```bash
  argocd account can-i sync applications '*/*'
  argocd account can-i update applications '*/*'
  ```

### UI Validation

- [ ] UI accessible at https://localhost:8080
- [ ] Can login
- [ ] Can view applications
- [ ] Can view diffs
- [ ] Can trigger syncs
- [ ] Can view resource details
- [ ] Can perform resource actions

## Breaking Changes Verification

### 1. Hydration Paths ✓

- [ ] If using ApplicationSet with hydration, verify paths are non-root
- [ ] Note: Hydration path cannot be "" or "."

### 2. Progressive Sync Deletion ✓

- [ ] If using progressive sync, test deletion behavior
- [ ] Deletions now respect sync waves

### 3. Server-side Diff ✓

- [ ] Test server-side diff feature
- [ ] Consider enabling by default if useful

## Rollback Command

If issues are found:
```bash
./scripts/rollback.sh v3.1
```

---

## 🎉 UPGRADE COMPLETE - PRODUCTION READINESS CHECKLIST

Before proceeding to production:

### Technical Validation

- [ ] All component checks passed
- [ ] All applications healthy
- [ ] RBAC working for all roles
- [ ] UI fully functional
- [ ] Sync operations working
- [ ] Diff operations working (both modes)

### Documentation

- [ ] Breaking changes documented for team
- [ ] RBAC migration documented
- [ ] Monitoring updates documented (Redis removal)

### Production Preparation

- [ ] Production backup plan ready
- [ ] Rollback procedure tested in demo
- [ ] Maintenance window scheduled
- [ ] Teams notified
- [ ] On-call prepared

### Sign-off

- [ ] Demo upgrade successful
- [ ] Ready for production upgrade

**Validated by:** _________________ **Date:** _________________

**Production upgrade scheduled for:** _________________

**Notes:**
