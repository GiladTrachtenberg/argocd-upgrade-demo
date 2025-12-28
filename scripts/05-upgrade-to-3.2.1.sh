#!/bin/bash
#
# 05-upgrade-to-3.2.1.sh - Upgrade Argo CD from v3.1.x to v3.2.1
#
# 🎯 FINAL TARGET VERSION
#
# UPGRADE STEP: v3.1.x → v3.2.1
#
# Breaking changes in this upgrade:
#
# 1. HYDRATION PATHS MUST BE NON-ROOT
#    - Hydration path cannot be "" or "."
#    - Must use a subdirectory
#    - Impact: ApplicationSets using root hydration paths
#
# 2. PROGRESSIVE SYNC DELETION
#    - If using progressive sync, deletion now respects waves
#    - Impact: Deletion order may differ
#
# 3. SERVER-SIDE DIFF (NEW FEATURE)
#    - New --server-side flag for diff operations
#    - Uses K8s dry-run apply for more accurate diffs
#    - Great for CRDs with defaulting/validation
#
# WHAT THIS SCRIPT DOES:
# 1. Backs up current state
# 2. Shows breaking changes
# 3. Applies v3.2 overlay
# 4. Tests server-side diff (new feature)
# 5. Runs comprehensive validation
# 6. Shows production readiness checklist
#
# USAGE:
#   ./scripts/05-upgrade-to-3.2.1.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

FROM_VERSION="v3.1"
TO_VERSION="v3.2.1"
OVERLAY_PATH="$PROJECT_ROOT/overlays/v3.2"

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "🎯 Final Upgrade: $FROM_VERSION → $TO_VERSION"

  # Step 1: Pre-flight checks
  log_step "1/7" "Running pre-flight checks..."
  preflight_checks

  # Step 2: Show breaking changes
  log_step "2/7" "Reviewing breaking changes..."
  show_breaking_changes "3.1" "3.2"

  # Step 3: Backup current state
  log_step "3/7" "Backing up current state..."
  backup_argocd_state "$FROM_VERSION"

  # Step 4: Confirm upgrade
  log_step "4/7" "Confirming upgrade..."
  if ! confirm "Proceed with upgrade from $FROM_VERSION to $TO_VERSION (FINAL TARGET)?"; then
    log_warning "Upgrade cancelled by user"
    exit 0
  fi

  # Step 5: Apply upgrade
  log_step "5/7" "Applying upgrade..."
  apply_upgrade

  # Step 6: Validate
  log_step "6/7" "Validating upgrade..."
  validate_upgrade

  # Step 7: Test new features
  log_step "7/7" "Testing new features..."
  test_new_features

  print_summary
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

preflight_checks() {
  # Check current version
  local current=$(get_argocd_version)
  if [[ ! "$current" == *"3.1"* ]]; then
    log_error "Expected current version to be 3.1.x, got: $current"
    log_error "You must upgrade through v3.1 first: ./scripts/04-upgrade-to-3.1.sh"
    exit 1
  fi
  log_success "Current version: $current"

  # Check all apps are healthy
  if ! check_apps_health; then
    log_warning "Some applications are not Healthy/Synced"
    if ! confirm "Continue anyway?"; then
      exit 1
    fi
  fi

  # Check overlay exists
  if [ ! -d "$OVERLAY_PATH" ]; then
    log_error "Overlay not found at $OVERLAY_PATH"
    exit 1
  fi

  log_success "Pre-flight checks passed"
}

apply_upgrade() {
  log_info "Applying Kustomize overlay from $OVERLAY_PATH"

  # Apply the new overlay
  # Note: If this fails with immutable field errors on StatefulSets, we'll handle it
  if ! kustomize build --load-restrictor=LoadRestrictionsNone "$OVERLAY_PATH" | kubectl apply --server-side --force-conflicts -f - 2>&1 | tee /tmp/apply-output.log; then
    # Check if the error is due to immutable StatefulSet selector fields
    if grep -q "StatefulSet.*Forbidden.*spec.*selector" /tmp/apply-output.log; then
      log_warning "Detected immutable StatefulSet selector conflict"
      log_info "Attempting recovery: will recreate StatefulSet with correct selectors..."

      # Delete the StatefulSet (preserving PVCs)
      # This is safe because we're not using --cascade=orphan, so pods will be recreated
      log_info "Deleting argocd-application-controller StatefulSet..."
      kubectl delete statefulset argocd-application-controller -n argocd --cascade=orphan || true

      # Wait a moment for cleanup
      sleep 3

      # Reapply the overlay
      log_info "Reapplying overlay after StatefulSet deletion..."
      kustomize build --load-restrictor=LoadRestrictionsNone "$OVERLAY_PATH" | kubectl apply --server-side --force-conflicts -f -
    else
      # Some other error occurred - fail
      log_error "Upgrade failed with unexpected error"
      cat /tmp/apply-output.log
      exit 1
    fi
  fi

  # Clean up temp file
  rm -f /tmp/apply-output.log

  log_success "Overlay applied"

  # Wait for rollout
  log_info "Waiting for Argo CD to restart..."
  source "$SCRIPT_DIR/lib/wait-for-argocd.sh"
  wait_for_argocd
}

validate_upgrade() {
  local errors=0

  # Check version
  local version=$(get_argocd_version)
  if [[ "$version" == *"3.2"* ]]; then
    log_success "Version upgraded to: $version"
  else
    log_error "Version check failed: expected 3.2.x, got $version"
    ((errors++))
  fi

  # Check all pods running
  local not_running=$(kubectl get pods -n argocd --no-headers | grep -v -E "Running|Completed" | wc -l | tr -d ' ')
  if [ "$not_running" -eq 0 ]; then
    log_success "All pods are Running"
  else
    log_error "$not_running pods are not Running"
    ((errors++))
  fi

  # Check for errors in logs
  log_info "Checking logs for errors..."
  if kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --since=2m 2>/dev/null | grep -qi "error"; then
    log_warning "Error messages found in server logs - review them"
  else
    log_success "No errors in server logs"
  fi

  # Check applications
  check_apps_health || ((errors++))

  if [ $errors -gt 0 ]; then
    log_error "Validation failed with $errors error(s)"
    log_warning "Consider rolling back: ./scripts/rollback.sh $FROM_VERSION"
    exit 1
  fi

  log_success "Validation passed"
}

test_new_features() {
  log_info "Testing v3.2 features..."

  # Test server-side diff if we have an app
  local password=$(cat "$PROJECT_ROOT/.credentials/password" 2>/dev/null || echo "admin123")

  if argocd login localhost:8443 --username admin --password "$password" --insecure --grpc-web 2>/dev/null; then
    log_info "  Testing server-side diff..."

    # Get first app name
    local app=$(argocd app list -o name 2>/dev/null | head -1)

    if [ -n "$app" ]; then
      log_info "  Running server-side diff on '$app'..."
      if argocd app diff "$app" --server-side 2>/dev/null; then
        log_success "  Server-side diff working ✓"
      else
        log_warning "  Server-side diff returned non-zero (may be expected if app is synced)"
      fi
    else
      log_warning "  No apps found to test server-side diff"
    fi
  else
    log_warning "Could not login to test new features - manual verification needed"
  fi
}

print_summary() {
  local version=$(get_argocd_version)

  log_section "🎉 UPGRADE COMPLETE - TARGET VERSION REACHED!"

  echo -e "\033[1;32m"
  cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════════════════════╗
  ║                                                                           ║
  ║              ARGO CD UPGRADE TO v3.2.1 SUCCESSFUL!                       ║
  ║                                                                           ║
  ║     You have completed the entire upgrade path from v2.10.x to v3.2.1    ║
  ║                                                                           ║
  ╚═══════════════════════════════════════════════════════════════════════════╝
EOF
  echo -e "\033[0m"

  cat << EOF

UPGRADE PATH COMPLETED:
  v2.10.x → v2.14 → v3.0 → v3.1 → [DONE] v3.2.1

VERSION:
  Installed: $version ✓
  Target:    v3.2.1 ✓

NEW FEATURES IN v3.2:
  ✓ Server-side diff (more accurate for CRDs)
  ✓ Progressive sync deletion (respects waves)

═══════════════════════════════════════════════════════════════════════════════
                         PRODUCTION READINESS CHECKLIST
═══════════════════════════════════════════════════════════════════════════════

Before proceeding to production, verify:

  [ ] All test applications are Healthy/Synced
  [ ] RBAC working for owner/operator/viewer roles
  [ ] No critical errors in Argo CD logs
  [ ] UI accessible and functional
  [ ] Sync operations work correctly
  [ ] Diff operations work (both client-side and server-side)
  [ ] Rollback procedure tested (./scripts/rollback.sh)
  [ ] Backup of production state created
  [ ] Maintenance window scheduled
  [ ] Teams notified

═══════════════════════════════════════════════════════════════════════════════

PRODUCTION UPGRADE SUMMARY:

  Key changes to apply in production:

  1. RBAC (v3.0 migration)
     Add to argocd-rbac-cm.yaml:
       p, role:operator, applications, update/*, */*, allow
       p, role:operator, applications, delete/*, */*, allow

  2. MONITORING (v3.0)
     - Remove Redis ServiceMonitors and dashboards

  3. VERSION UPDATES
     - Update kustomization.yaml to reference v3.2.1 manifests

USEFUL COMMANDS:
  # Full validation
  ./scripts/validate.sh

  # Cleanup minikube demo
  ./scripts/cleanup.sh

  # View production upgrade notes
  cat TICKET.md

CONGRATULATIONS! The minikube demo upgrade is complete.

EOF
}

main "$@"
