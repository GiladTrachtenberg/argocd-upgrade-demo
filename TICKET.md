## Context

We currently run Argo CD **v2.10.x** in our clusters and want to upgrade to **v3.2.1**. This task covers designing and executing a safe migration plan, including a demo upgrade, validation of critical GitOps flows, and a production rollout plan that avoids unscheduled syncs or service disruption.

---

## **Definition of Done (DoD)**

- [ ] **Migration plan approved**
  - [ ] Documented upgrade path from **v2.10.x → 2.14 → 3.0 → 3.1 → 3.2.1**, including required intermediate hops and manifests changes.
  - [ ] Risk assessment completed (breaking changes, deprecated APIs, config changes, RBAC impact).
- [ ] **Non‑prod demo upgrade completed** (e.g., dev / sandbox cluster)
  - [ ] Argo CD upgraded to **3.2.1** in a lower environment using the same method we will use in prod (Helm/manifests, automation, etc.).
  - [ ] All existing Applications are in **Healthy / Synced** state after upgrade.
  - [ ] No unexpected auto‑syncs or mass deletions occurred during the demo (validate with logs and resource history).
- [ ] **Critical GitOps flows validated**
  - [ ] Manual sync, auto‑sync, and rollback flows tested.
  - [ ] App-of-apps / ApplicationSet flows tested.
  - [ ] Kustomize / Helm apps render and diff correctly (including server‑side diff where relevant).[[1]](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/)
  - [ ] Any custom plugins / source hydrators verified to work with v3.x.
- [ ] **RBAC, SSO, and API compatibility validated**
  - [ ] Existing RBAC policies reviewed for **fine‑grained application update/delete sub‑resource** behavior introduced in v3.0 and adjusted if needed.[[2]](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/)
  - [ ] Any clients using the deprecated **v1 Actions API** migrated to the **v2 resource actions endpoint**.[[3]](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/)
  - [ ] SSO/OIDC configuration tested end‑to‑end (CLI and UI login).
- [ ] **Rollout plan for production documented and reviewed**
  - [ ] Step‑by‑step prod rollout, including blast radius, maintenance window (if any), and communication.
  - [ ] Rollback strategy defined and tested in non‑prod (how to revert manifests/images back to 2.10.x/2.14 if needed).
- [ ] **Documentation updated**
  - [ ] Internal runbook: "How to operate Argo CD 3.2.1" updated (commands, dashboards, troubleshooting tips).
  - [ ] Upgrade notes and known issues recorded in this task or linked doc.

---

## Quality Assurance

### 1. Pre‑upgrade checks (current 2.10.x)

- [ ] Export Argo CD configuration and backup critical data (ConfigMaps/Secrets, projects, repos, RBAC, SSO config).
- [ ] Capture baseline:
  - [ ] List of all Applications and their health/sync status.
  - [ ] Controller / API server resource usage (CPU/memory) and error rates.
  - [ ] Any known quirks in current setup (e.g., custom health checks, ignoreDifferences, plugins).

### 2. Demo upgrade flow (non‑prod)

- [ ] Apply official **upgrade manifests** for each hop as per Argo CD docs, not just image tags (to ensure all CRDs and configuration are migrated).[[4]](https://argo-cd.readthedocs.io/en/latest/operator-manual/upgrading/overview/)
- [ ] Observe controller / API server logs during upgrade for:
  - [ ] DB migrations or schema errors.
  - [ ] RBAC / permission denials.
  - [ ] Sync or diff failures.
- [ ] Verify:
  - [ ] All Applications reconnect and reconcile successfully.
  - [ ] No unexpected deletions / recreations of resources.
  - [ ] Auto‑sync behavior unchanged for existing apps.

### 3. Functional tests after demo

- [ ] Git flow:
  - [ ] Push a Git change → ensure Argo CD 3.2.1 detects it and syncs as expected.
  - [ ] Verify **server‑side diff** behavior (where enabled) matches expectations.[[1]](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/)
- [ ] Application types:
  - [ ] Helm‑based app syncs and rollbacks.
  - [ ] Kustomize‑based app syncs.
  - [ ] Plain YAML app syncs.
- [ ] ApplicationSet / PR‑preview flows (if used):
  - [ ] Validate any **PR generator** logic, including title‑match filtering in 3.2 where relevant.[[5]](https://www.youtube.com/watch?v=bKroKvraCNE)

### 4. Production rollout dry‑run & verification

- [ ] Run through the full rollout procedure in non‑prod as a rehearsal (timing, commands, observability checks).
- [ ] Validate we can safely roll back Argo CD by:
  - [ ] Re‑applying previous manifests (2.10/2.14) in non‑prod.
  - [ ] Confirming Argo CD comes back healthy and applications continue to reconcile.

---

## Rollout Plan (Prod)

### Phase 0 - Preparation

- [ ] Confirm target version and artifacts:
  - [ ] Argo CD images: **v3.2.1** (API server, repo‑server, controller, dex, redis replacement if applicable).
  - [ ] Updated manifests / Helm chart values committed to the **argocd-control-plane** repo.
- [ ] Validate all breaking‑change mitigations (see "Upgrade highlights" section below) are merged to Git before the window.
- [ ] Announce planned upgrade window in the relevant Slack channels and incident tooling.

### Phase 1 - Read‑only freeze (optional but recommended)

- [ ] Temporarily freeze changes to Git repos managed by Argo CD during the upgrade window (or agree on change‑freeze rules).
- [ ] Disable any automatic tooling that changes Argo CD CRs during the upgrade.

### Phase 2 - Upgrade Argo CD control plane

1. Scale down or cordon any external controllers that might interfere (optional).
2. Apply new Argo CD **3.2.1** manifests/Helm release in the **argocd** namespace.
3. Wait for all Argo CD pods to restart and become Ready.
4. Verify:
   - [ ] `argocd-server`, `argocd-repo-server`, `argocd-application-controller` are healthy.
   - [ ] Argo CD UI is reachable and shows version 3.2.1.

### Phase 3 - Post‑upgrade validation

- [ ] Check global status:
  - [ ] All Applications show **Healthy/Synced** or expected warnings only.
  - [ ] No unexpected OutOfSync spikes.
- [ ] Spot‑check:
  - [ ] At least one app per critical cluster/namespace.
  - [ ] At least one app per app type (Helm / Kustomize / raw YAML / ApplicationSet).
- [ ] Run a small controlled change in Git for a low‑risk app to confirm sync behavior.

### Phase 4 - Rollback plan (if needed)

If a critical issue is detected:

- [ ] Stop Argo CD auto‑sync on high‑risk apps (if necessary) to prevent cascading changes.
- [ ] Re‑apply previous Argo CD manifests / Helm release (2.10/2.14) and wait for pods to roll back.
- [ ] Validate application states and alert stakeholders.

---

## Upgrade highlights: v2.10.x → v3.2.1

This section summarizes the key changes and considerations across the intermediate versions. The dev should refine this list against the official release notes for each minor version.[[4]][https://argo-cd.readthedocs.io/en/latest/operator-manual/upgrading/overview/]([2)][https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/]([3)][https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/]([1)](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/)

### From 2.10.x to 2.14

- Ensure compatibility with the **minimum supported Kubernetes version** for Argo CD 2.14.
- Review any deprecations marked for removal in 3.0 (config keys, APIs, flags) and avoid relying on them in new code.

### From 2.14 to 3.0 (major)

Key breaking changes and behaviors:[[2]][https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/]([6)](https://www.kubeace.com/blog/argocd-3.0-upgrade)

- **Fine‑grained RBAC** for application sub‑resources:
  - Previously, `update`/`delete` permissions on an `Application` also implicitly applied to its managed resources.
  - In v3, `update`/`delete` apply only to the Application object itself.
  - New `update/*` and `delete/*` actions must be granted explicitly if users or automations need to operate on resources through Argo CD.
- **Minimum supported Kubernetes version increased** (3.0 requires K8s 1.21+).
- **Redis dependency removed** in favor of an internal implementation (verify any operational dashboards or alerts that referenced Redis).[[6]](https://www.kubeace.com/blog/argocd-3.0-upgrade)
- Clean‑up of deprecated configuration fields and APIs.

### From 3.0 to 3.1

Important changes:[[3]](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/)

- **Symlink protection** in the API server `--staticassets` directory:
  - Out‑of‑bounds symlinks in `/app/shared` (or configured static assets dir) are now blocked and will return 500 errors.
  - If we serve custom static assets via Argo CD, verify that symlinks do not escape this directory.
- **v1 Actions API deprecated**:
  - Legacy endpoint: `/api/v1/applications/{name}/resource/actions`.
  - Replacement: `/api/v1/applications/{name}/resource/actions/v2` with JSON body.
  - Any automation or scripts using the old endpoint must be updated.
- OIDC / auth flow improvements (including code+PKCE) - verify SSO flows but no major breaking config is expected for standard setups.

### From 3.1 to 3.2.1

Key changes and new capabilities:[[1]][https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/]([5)][https://www.youtube.com/watch?v=bKroKvraCNE]([7)](https://medium.com/@user-cube/argocd-3-2-the-latest-stable-release-is-here-271410ad88e5)

- **Breaking: Hydration paths must be non‑root**
  - Source hydration now requires `.spec.sourceHydrator.syncSource.path` to point to a **subdirectory**.
  - Using the repo root ("" or ".") is no longer supported.
  - Action item: scan our Applications that use hydration and update any root paths to something like `apps/<app-name>`.
- **Progressive Sync Deletion Strategy**
  - New deletion strategy that removes resources in reverse deployment order for safer rollbacks and cleanups.
  - Consider enabling this for higher‑risk apps once we are comfortable with the behavior.
- **Server‑side diff support**
  - Diffs can now leverage Kubernetes dry‑run apply for more accurate previews of changes.
  - Confirm that our clusters' RBAC and admission controllers allow the required dry‑run calls.
- **PR generator improvements (title‑match filter)**
  - ApplicationSet PR generator can now filter PRs by title patterns (useful for preview envs only on specific PRs).
- **Misc improvements**
  - Better authenticated user ID headers for extensions and improved developer documentation.

---

## Notes

- Use this task as the single source of truth for the Argo CD 3.2.1 upgrade.
- The dev should:
  - Refine the upgrade highlights above with specific references to our own manifests, repos, and ApplicationSets.
  - Add links here to:
    - The Git PRs that implement the upgrade.
    - Any internal dashboards used to monitor Argo CD health during and after the upgrade.
    - Incident / post‑mortem docs if we encounter issues during rollout.
- All risky changes (e.g., RBAC adjustments, hydration path changes) must be tested in non‑prod **before** merging to the production control‑plane repo.
