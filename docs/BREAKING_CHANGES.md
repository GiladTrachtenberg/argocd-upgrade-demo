# Breaking Changes Reference

Comprehensive documentation of all breaking changes in the Argo CD upgrade path from v2.10.x to v3.2.1.

---

## Quick Reference Table

| Version | Breaking Change | Impact | Migration Required |
|---------|-----------------|--------|-------------------|
| **v3.0** | Fine-grained RBAC | HIGH | Yes - Add `update/*`, `delete/*` |
| **v3.0** | Redis removed | Medium | Update monitoring |
| **v3.0** | K8s 1.21+ required | Medium | Verify cluster version |
| **v3.1** | Symlink protection | Low | Check for symlinks in repos |
| **v3.1** | Actions API v1 deprecated | Low | Update custom scripts |
| **v3.2** | Hydration paths | Low | Non-root paths only |
| **v3.2** | Progressive sync deletion | Low | Test deletion behavior |

---

## v2.10 → v2.14

### No Critical Breaking Changes

This upgrade is primarily a preparation step for v3.0. No critical breaking changes.

**Minor items to watch:**
- Review server logs for deprecation warnings
- Some config keys may show warnings (non-blocking)

**Official docs:** [v2.10 to v2.11](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.10-2.11/)

---

## v2.14 → v3.0 (MAJOR VERSION)

### 1. Fine-Grained RBAC (CRITICAL)

**Impact:** HIGH - Users may lose ability to manage resources

**What Changed:**

In v2.x, having `update` or `delete` permission on an Application implicitly granted the same permission on all resources managed by that Application.

In v3.0, this is **no longer true**. You must explicitly grant permissions on sub-resources.

**Before v3.0:**
```yaml
# This allowed updating/deleting managed resources
p, role:operator, applications, update, */*, allow
p, role:operator, applications, delete, */*, allow
```

**After v3.0 (required additions):**
```yaml
# Existing permissions
p, role:operator, applications, update, */*, allow
p, role:operator, applications, delete, */*, allow

# NEW: Required for managing resources within applications
p, role:operator, applications, update/*, */*, allow
p, role:operator, applications, delete/*, */*, allow
```

**Migration Steps:**

1. **Identify affected roles** - Any role that needs to:
   - Edit resources via UI (scale replicas, edit configs)
   - Delete resources via UI
   - Restart deployments
   - Perform resource actions

2. **Update RBAC ConfigMap** - Add fine-grained permissions:
   ```bash
   # The migration file is at:
   overlays/v3.0/migrations/argocd-rbac-v3-migration.yaml

   # Apply BEFORE upgrading:
   kubectl apply -f overlays/v3.0/migrations/argocd-rbac-v3-migration.yaml
   ```

3. **Verify permissions:**
   ```bash
   argocd account can-i update applications '*/*'
   # Should return: yes
   ```

**Symptoms if not migrated:**
- "permission denied" errors when editing resources
- Unable to restart deployments from UI
- Unable to scale replicas from UI
- Unable to delete resources from UI

**Official docs:** [Fine-grained RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.x-3.0/#fine-grained-rbac)

---

### 2. Redis Removed

**Impact:** Medium - Monitoring/infrastructure changes

**What Changed:**

Redis is no longer used for caching. The application controller now uses an in-memory cache.

**Before v3.0:**
```bash
kubectl get pods -n argocd
# Included: argocd-redis-*
```

**After v3.0:**
```bash
kubectl get pods -n argocd
# No Redis pods (this is expected!)
```

**Migration Steps:**

1. **Update monitoring dashboards** - Remove Redis metrics
2. **Update alerting rules** - Remove Redis-related alerts
3. **Update resource allocation** - Application controller may need more memory

**Infrastructure changes:**
- No Redis PVC needed
- No Redis deployment/service
- Application controller handles caching internally

**Official docs:** [Redis removal](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.x-3.0/#redis-removal)

---

### 3. Kubernetes 1.21+ Required

**Impact:** Medium - May block upgrade

**What Changed:**

Argo CD v3.0 requires Kubernetes 1.21 or newer.

**Verification:**
```bash
kubectl version --short
# Server Version must be >= v1.21
```

**Migration Steps:**

1. **Check cluster version:**
   ```bash
   kubectl version
   ```

2. **Upgrade Kubernetes if needed** before upgrading Argo CD

**Official docs:** [K8s requirements](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.x-3.0/#kubernetes-version)

---

## v3.0 → v3.1

### 1. Symlink Protection

**Impact:** Low - May cause 500 errors with certain repos

**What Changed:**

Static file serving now validates symlinks, preventing path traversal attacks.

**Symptoms if affected:**
- 500 errors when accessing certain static assets
- Errors mentioning "symlink" in server logs

**Check for issues:**
```bash
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=5m | grep -i symlink
```

**Migration Steps:**

1. **Check your repos** for symlinks in UI-served paths
2. **Replace symlinks** with actual files if needed

**Official docs:** [Symlink protection](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/#symlink-protection)

---

### 2. Actions API v1 Deprecated

**Impact:** Low - Only affects custom integrations

**What Changed:**

The v1 Actions API is deprecated in favor of v2.

**Old API:**
```
/api/v1/applications/{name}/resource/actions
```

**New API:**
```
/api/v1/applications/{name}/resource/actions/v2
```

**Migration Steps:**

1. **Audit custom scripts** for Actions API usage
2. **Update to v2 API** if using custom integrations
3. **UI actions work automatically** (use v2 internally)

**Official docs:** [Actions API](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/#actions-api)

---

## v3.1 → v3.2

### 1. Hydration Paths

**Impact:** Low - Only affects ApplicationSet with hydration

**What Changed:**

When using ApplicationSet with the hydrator, the hydration path cannot be an empty string (`""`) or root (`.`).

**Before v3.2:**
```yaml
spec:
  generators:
  - git:
      repoURL: https://...
      path: ""  # This worked
```

**After v3.2:**
```yaml
spec:
  generators:
  - git:
      repoURL: https://...
      path: "manifests"  # Must be non-root
```

**Migration Steps:**

1. **Check ApplicationSets** for hydration path usage
2. **Update paths** to be non-empty, non-root

**Official docs:** [Hydration paths](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/#hydration-paths)

---

### 2. Progressive Sync Deletion Behavior

**Impact:** Low - Only affects progressive sync users

**What Changed:**

Deletions now respect sync waves when using progressive sync.

**Before v3.2:**
- Deletions happened immediately, ignoring sync waves

**After v3.2:**
- Deletions follow sync wave order

**Migration Steps:**

1. **Review sync wave configuration** if using progressive sync
2. **Test deletion behavior** in staging

**Official docs:** [Progressive sync](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/#progressive-sync)

---

### 3. Server-Side Diff (New Feature)

**Impact:** Positive - New capability

**What Changed:**

Server-side diff is now available, providing more accurate diffs by comparing against the server state.

**Usage:**
```bash
argocd app diff <app-name> --server-side
```

**Benefits:**
- More accurate diffs
- Accounts for server-side mutations
- Better handling of defaulted fields

**No migration needed** - This is an opt-in feature.

**Official docs:** [Server-side diff](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/#server-side-diff)

---

## Migration Checklist Summary

### Before Starting

- [ ] Verify Kubernetes version is 1.21+
- [ ] Document current RBAC configuration
- [ ] Create backups of all ConfigMaps
- [ ] Notify affected teams

### v3.0 Migration (Critical)

- [ ] Apply RBAC migration file
- [ ] Verify `update/*` permissions added
- [ ] Verify `delete/*` permissions added
- [ ] Test operator role can manage resources
- [ ] Update monitoring to remove Redis

### v3.1 Migration

- [ ] Check repos for symlinks
- [ ] Update custom scripts using Actions API v1

### v3.2 Migration

- [ ] Check ApplicationSets for hydration paths
- [ ] Test progressive sync deletion behavior
- [ ] Consider enabling server-side diff

### Post-Migration

- [ ] Full validation suite passed
- [ ] All applications healthy
- [ ] All roles can perform expected actions
- [ ] Monitoring dashboards updated

---

## Official Documentation Links

- [Upgrade Overview](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/)
- [v2.10 to v2.11](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.10-2.11/)
- [v2.x to v3.0](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.x-3.0/)
- [v3.0 to v3.1](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/)
- [v3.1 to v3.2](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/)
