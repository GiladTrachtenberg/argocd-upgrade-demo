# Troubleshooting Guide

Common issues and solutions for the Argo CD upgrade demo environment.

---

## Quick Diagnostics

Run these commands first to gather information:

```bash
# Check minikube status
minikube status -p argocd-upgrade-demo

# Check all pods
kubectl get pods -n argocd

# Check recent events
kubectl get events -n argocd --sort-by='.lastTimestamp' | tail -20

# Check Argo CD version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Run validation
./scripts/validate.sh
```

---

## Setup Issues

### Minikube Won't Start

**Symptoms:**
```
minikube start failed: ...
```

**Solutions:**

1. **Delete and recreate:**
   ```bash
   minikube delete -p argocd-upgrade-demo
   ./scripts/00-setup-minikube.sh
   ```

2. **Check Docker is running:**
   ```bash
   docker ps
   # If error, start Docker Desktop
   ```

3. **Insufficient resources:**
   ```bash
   # Use less resources
   MEMORY=4096 CPUS=2 ./scripts/00-setup-minikube.sh
   ```

4. **Clean Docker state:**
   ```bash
   docker system prune -a
   minikube delete --all --purge
   ./scripts/00-setup-minikube.sh
   ```

---

### Port-Forward Issues

**Symptoms:**
```
Unable to connect to https://localhost:8080
Connection refused
```

**Solutions:**

1. **Restart port-forward:**
   ```bash
   pkill -f "port-forward.*argocd"
   kubectl port-forward svc/argocd-server -n argocd 8080:443 &
   ```

2. **Check server pod is running:**
   ```bash
   kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
   ```

3. **Use a different port:**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8443:443 &
   # Then access https://localhost:8443
   ```

4. **Check for port conflicts:**
   ```bash
   lsof -i :8080
   # Kill conflicting process if needed
   ```

---

### Pods Not Starting

**Symptoms:**
```
kubectl get pods -n argocd
# Shows: Pending, CrashLoopBackOff, ImagePullBackOff
```

**Solutions:**

1. **Check pod events:**
   ```bash
   kubectl describe pod <pod-name> -n argocd
   ```

2. **ImagePullBackOff - Check image:**
   ```bash
   # Verify image exists
   kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

   # Try pulling manually
   docker pull quay.io/argoproj/argocd:v2.10.17
   ```

3. **Pending - Check resources:**
   ```bash
   kubectl describe pod <pod-name> -n argocd | grep -A5 Events
   # Look for: Insufficient cpu/memory

   # Reduce minikube resources or delete other pods
   ```

4. **CrashLoopBackOff - Check logs:**
   ```bash
   kubectl logs <pod-name> -n argocd --previous
   ```

---

## Upgrade Issues

### RBAC Permission Denied (v3.0)

**Symptoms:**
```
permission denied: applications, update, ...
Unable to edit resource from UI
Unable to restart deployment
```

**Cause:** Fine-grained RBAC migration not applied.

**Solution:**

1. **Apply RBAC migration:**
   ```bash
   kubectl apply -f overlays/v3.0/migrations/argocd-rbac-v3-migration.yaml
   ```

2. **Verify permissions:**
   ```bash
   kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep "update/\*"
   # Should see: p, role:operator, applications, update/*, */*, allow
   ```

3. **Test permissions:**
   ```bash
   argocd account can-i update applications '*/*'
   # Expected: yes
   ```

---

### Redis Pod Missing (v3.0)

**Symptoms:**
```
kubectl get pods -n argocd | grep redis
# No results
```

**This is EXPECTED in v3.0+!**

Redis was removed in v3.0. The application controller now uses an in-memory cache.

**No action needed** - This is correct behavior.

---

### Symlink Errors (v3.1)

**Symptoms:**
```
500 Internal Server Error
kubectl logs ... | grep -i symlink
# Shows symlink-related errors
```

**Cause:** Symlink protection introduced in v3.1.

**Solutions:**

1. **Identify problematic symlinks:**
   ```bash
   kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd | grep -i symlink
   ```

2. **Fix in your git repos:**
   - Replace symlinks with actual files
   - Or use relative paths that don't escape the directory

3. **If affecting UI static assets:**
   - Check custom UI extensions
   - Rebuild without symlinks

---

### Application Out of Sync After Upgrade

**Symptoms:**
```
argocd app list
# Shows: OutOfSync
```

**Solutions:**

1. **Check diff:**
   ```bash
   argocd app diff <app-name>
   ```

2. **If diff is expected (version change):**
   ```bash
   argocd app sync <app-name>
   ```

3. **If diff is unexpected:**
   ```bash
   # Check for resource drift
   argocd app get <app-name> --show-diff

   # Check app details
   kubectl get application <app-name> -n argocd -o yaml
   ```

4. **Refresh the app:**
   ```bash
   argocd app get <app-name> --refresh
   ```

---

### Upgrade Script Fails

**Symptoms:**
```
./scripts/02-upgrade-to-2.14.sh
# ERROR: ...
```

**Solutions:**

1. **Check current state:**
   ```bash
   kubectl get pods -n argocd
   kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

2. **Check script prerequisites:**
   ```bash
   # Each script shows prerequisites
   head -50 ./scripts/02-upgrade-to-2.14.sh
   ```

3. **Manually apply and debug:**
   ```bash
   # Apply kustomize directly to see errors
   kubectl apply -k overlays/v2.14/ --dry-run=client
   kubectl apply -k overlays/v2.14/
   ```

4. **Check kustomize output:**
   ```bash
   kustomize build overlays/v2.14/ | head -100
   ```

---

## Rollback Issues

### Rollback Fails

**Symptoms:**
```
./scripts/rollback.sh v2.10
# ERROR: ...
```

**Solutions:**

1. **Check available backups:**
   ```bash
   ls -la backups/
   ```

2. **Manual rollback:**
   ```bash
   # Apply previous version overlay
   kubectl apply -k overlays/v2.10/

   # Wait for rollout
   kubectl rollout status deploy/argocd-server -n argocd

   # Restore ConfigMaps from backup
   kubectl apply -f backups/<timestamp>/argocd-cm.yaml
   kubectl apply -f backups/<timestamp>/argocd-rbac-cm.yaml
   ```

3. **Force pod restart:**
   ```bash
   kubectl rollout restart deploy -n argocd
   ```

---

### State Inconsistent After Rollback

**Symptoms:**
```
# After rollback, some settings don't match expected state
```

**Solutions:**

1. **Verify ConfigMaps:**
   ```bash
   kubectl get configmap argocd-cm -n argocd -o yaml
   kubectl get configmap argocd-rbac-cm -n argocd -o yaml
   ```

2. **Restore from backup manually:**
   ```bash
   ls backups/
   kubectl apply -f backups/<timestamp>/argocd-cm.yaml
   kubectl apply -f backups/<timestamp>/argocd-rbac-cm.yaml
   ```

3. **Restart Argo CD:**
   ```bash
   kubectl rollout restart deploy -n argocd
   ```

---

## Application Issues

### Test Apps Won't Deploy

**Symptoms:**
```
argocd app list
# Shows: Unknown, Missing, Error
```

**Solutions:**

1. **Check app status:**
   ```bash
   argocd app get guestbook
   ```

2. **Check source repo accessibility:**
   ```bash
   # Our test apps use public repos
   curl -I https://github.com/argoproj/argocd-example-apps
   ```

3. **Sync manually:**
   ```bash
   argocd app sync guestbook --force
   ```

4. **Check events:**
   ```bash
   kubectl describe application guestbook -n argocd
   ```

---

### Sync Stuck in Progress

**Symptoms:**
```
argocd app get <app-name>
# Shows: Syncing for extended period
```

**Solutions:**

1. **Check sync status:**
   ```bash
   argocd app get <app-name> --show-operation
   ```

2. **Terminate stuck operation:**
   ```bash
   argocd app terminate-op <app-name>
   ```

3. **Check controller logs:**
   ```bash
   kubectl logs -l app.kubernetes.io/name=argocd-application-controller -n argocd | tail -50
   ```

---

## CLI Issues

### argocd login fails

**Symptoms:**
```
argocd login localhost:8080
# FATA[0000] rpc error: ...
```

**Solutions:**

1. **Use correct flags:**
   ```bash
   argocd login localhost:8080 --insecure --grpc-web --username admin --password admin123
   ```

2. **Check port-forward is running:**
   ```bash
   ps aux | grep port-forward
   # If not running:
   kubectl port-forward svc/argocd-server -n argocd 8080:443 &
   ```

3. **Verify server is healthy:**
   ```bash
   kubectl get pods -l app.kubernetes.io/name=argocd-server -n argocd
   ```

---

### Wrong Password

**Symptoms:**
```
FATA[0001] rpc error: code = Unauthenticated
```

**Solutions:**

1. **Use the demo password:**
   ```bash
   # Default: admin123
   argocd login localhost:8080 --insecure --grpc-web --username admin --password admin123
   ```

2. **Check credentials file:**
   ```bash
   cat credentials/password 2>/dev/null || echo "admin123"
   ```

3. **Reset password (if needed):**
   ```bash
   # Get current bcrypt hash
   kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.admin\.password}' | base64 -d

   # Reset to admin123
   kubectl patch secret argocd-secret -n argocd -p '{"stringData": {"admin.password": "$2a$10$mivhwttXM0U5eBrZGtAG8.VSRL1l9cZNAmaSaqotIzXRBRwID1NT."}}'
   kubectl rollout restart deploy/argocd-server -n argocd
   ```

---

## Resource Issues

### Minikube Running Slow

**Symptoms:**
- Pods take forever to start
- kubectl commands are slow
- UI is unresponsive

**Solutions:**

1. **Check resource usage:**
   ```bash
   minikube ssh -p argocd-upgrade-demo -- top -bn1 | head -20
   ```

2. **Allocate more resources:**
   ```bash
   minikube stop -p argocd-upgrade-demo
   minikube config set memory 12288 -p argocd-upgrade-demo
   minikube config set cpus 6 -p argocd-upgrade-demo
   minikube start -p argocd-upgrade-demo
   ```

3. **Clean up unused resources:**
   ```bash
   # Delete old pods/deployments
   kubectl delete pods --field-selector=status.phase=Failed -A
   ```

---

### Disk Space Issues

**Symptoms:**
```
No space left on device
```

**Solutions:**

1. **Clean Docker:**
   ```bash
   docker system prune -a
   ```

2. **Clean minikube:**
   ```bash
   minikube ssh -p argocd-upgrade-demo -- sudo docker system prune -a
   ```

3. **Recreate cluster:**
   ```bash
   ./scripts/cleanup.sh
   ./scripts/00-setup-minikube.sh
   ```

---

## Getting More Help

### Collect Diagnostic Info

```bash
# Create diagnostic bundle
mkdir -p diagnostics
kubectl get pods -n argocd -o wide > diagnostics/pods.txt
kubectl get events -n argocd --sort-by='.lastTimestamp' > diagnostics/events.txt
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --tail=100 > diagnostics/server.log
kubectl logs -l app.kubernetes.io/name=argocd-application-controller -n argocd --tail=100 > diagnostics/controller.log
kubectl get configmap argocd-cm -n argocd -o yaml > diagnostics/argocd-cm.yaml
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > diagnostics/argocd-rbac-cm.yaml
./scripts/validate.sh > diagnostics/validation.txt 2>&1
```

### Official Resources

- [Argo CD Docs](https://argo-cd.readthedocs.io/)
- [Argo CD FAQ](https://argo-cd.readthedocs.io/en/stable/faq/)
- [Argo CD GitHub Issues](https://github.com/argoproj/argo-cd/issues)
- [Argo CD Slack](https://argoproj.github.io/community/join-slack/)

### Project-Specific

- Check `./scripts/validate.sh` output
- Review upgrade checklist in `validation/`
- See breaking changes in `docs/BREAKING_CHANGES.md`
