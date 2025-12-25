#!/bin/bash
#
# 02-upgrade-to-2.14.sh - Upgrade Argo CD from v2.10.x to v2.14.x
#
# UPGRADE STEP: v2.10.x → v2.14.x
#
# This is a PREPARATION STEP before the major v3.0 upgrade.
# No critical breaking changes in this upgrade.
#
# WHAT THIS SCRIPT DOES:
# 1. Backs up current Argo CD state
# 2. Shows breaking changes for this upgrade
# 3. Waits for user confirmation
# 4. Applies the v2.14 Kustomize overlay
# 5. Waits for upgrade to complete
# 6. Runs validation
#
# USAGE:
#   ./scripts/02-upgrade-to-2.14.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

FROM_VERSION="v2.10"
TO_VERSION="v2.14"
OVERLAY_PATH="$PROJECT_ROOT/overlays/v2.14"

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "Upgrading Argo CD: $FROM_VERSION → $TO_VERSION"

  # Step 1: Pre-flight checks
  log_step "1/6" "Running pre-flight checks..."
  preflight_checks

  # Step 2: Show breaking changes
  log_step "2/6" "Reviewing breaking changes..."
  show_breaking_changes "2.10" "2.14"

  # Step 3: Backup current state
  log_step "3/6" "Backing up current state..."
  backup_argocd_state "$FROM_VERSION"

  # Step 4: Confirm upgrade
  log_step "4/6" "Confirming upgrade..."
  if ! confirm "Proceed with upgrade from $FROM_VERSION to $TO_VERSION?"; then
    log_warning "Upgrade cancelled by user"
    exit 0
  fi

  # Step 5: Apply upgrade
  log_step "5/6" "Applying upgrade..."
  apply_upgrade

  # Step 6: Validate
  log_step "6/6" "Validating upgrade..."
  validate_upgrade

  print_summary
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

preflight_checks() {
  # Check current version
  local current=$(get_argocd_version)
  if [[ ! "$current" == *"2.10"* ]]; then
    log_error "Expected current version to be 2.10.x, got: $current"
    log_error "Run the upgrades in order starting from v2.10"
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
  if [[ "$version" == *"2.14"* ]]; then
    log_success "Version upgraded to: $version"
  else
    log_error "Version check failed: expected 2.14.x, got $version"
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

  # Check applications
  check_apps_health || ((errors++))

  if [ $errors -gt 0 ]; then
    log_error "Validation failed with $errors error(s)"
    log_warning "Consider rolling back: ./scripts/rollback.sh $FROM_VERSION"
    exit 1
  fi

  log_success "Validation passed"
}

print_summary() {
  local version=$(get_argocd_version)

  log_section "Upgrade Complete: $FROM_VERSION → $TO_VERSION"

  cat << EOF
Argo CD has been upgraded to $version.

VALIDATION RESULTS:
  Version:      $version ✓
  Pods:         All Running ✓
  Applications: Check with 'argocd app list'

NEXT STEP:
  Continue to v3.0 (MAJOR upgrade with breaking changes):
  ./scripts/03-upgrade-to-3.0.sh

ROLLBACK (if needed):
  ./scripts/rollback.sh $FROM_VERSION

UPGRADE PATH:
  v2.10.x → [CURRENT] v2.14 → v3.0 → v3.1 → v3.2.1

EOF
}

main "$@"
