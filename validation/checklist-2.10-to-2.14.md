# Validation Checklist: v2.10.x → v2.14.x

## Pre-Upgrade Checks

- [ ] Current version is v2.10.x
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  ```

- [ ] All applications are Healthy/Synced
  ```bash
  argocd app list
  ```

- [ ] Backup created
  ```bash
  ./scripts/rollback.sh  # Lists available backups
  ```

## Post-Upgrade Checks

### Component Health

- [ ] Version updated to v2.14.x
  ```bash
  kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
  # Expected: quay.io/argoproj/argocd:v2.14.x
  ```

- [ ] All pods are Running
  ```bash
  kubectl get pods -n argocd
  # All should be Running or Completed
  ```

- [ ] No errors in server logs
  ```bash
  kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep -i error
  # Expected: No critical errors
  ```

### Application Health

- [ ] All applications remain Healthy/Synced
  ```bash
  argocd app list
  ```

- [ ] Test sync works
  ```bash
  argocd app sync guestbook --dry-run
  # Expected: No errors
  ```

### UI Access

- [ ] UI is accessible
  ```bash
  # Start port-forward if needed
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &
  # Open https://localhost:8080
  ```

- [ ] Can login with admin credentials
- [ ] Can view applications
- [ ] Can trigger sync from UI

### RBAC

- [ ] Admin can sync all apps
  ```bash
  argocd account can-i sync applications '*/*'
  # Expected: yes
  ```

## Breaking Changes to Monitor

This upgrade has **no critical breaking changes**.

Minor items to check:
- [ ] Review server logs for deprecation warnings
- [ ] Check for config key warnings

## Rollback Command

If issues are found:
```bash
./scripts/rollback.sh v2.10
```

## Sign-off

- [ ] All checks passed
- [ ] Ready to proceed to v3.0

**Validated by:** _________________ **Date:** _________________
