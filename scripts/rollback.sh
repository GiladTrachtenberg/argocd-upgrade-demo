#!/bin/bash
#
# rollback.sh - Rollback Argo CD to a previous version
#
# This script rolls back Argo CD to a previous version by applying
# the corresponding Kustomize overlay.
#
# USAGE:
#   ./scripts/rollback.sh <target-version>
#
# EXAMPLES:
#   ./scripts/rollback.sh v2.14    # Rollback to v2.14
#   ./scripts/rollback.sh v3.0     # Rollback to v3.0
#   ./scripts/rollback.sh v2.10    # Rollback to initial v2.10
#
# AVAILABLE VERSIONS:
#   v2.10, v2.14, v3.0, v3.1, v3.2
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

TARGET_VERSION="$1"

# Version to overlay mapping
declare -A VERSION_OVERLAYS
VERSION_OVERLAYS["v2.10"]="$PROJECT_ROOT/overlays/v2.10"
VERSION_OVERLAYS["v2.14"]="$PROJECT_ROOT/overlays/v2.14"
VERSION_OVERLAYS["v3.0"]="$PROJECT_ROOT/overlays/v3.0"
VERSION_OVERLAYS["v3.1"]="$PROJECT_ROOT/overlays/v3.1"
VERSION_OVERLAYS["v3.2"]="$PROJECT_ROOT/overlays/v3.2"

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "Argo CD Rollback"

  # Validate input
  if [ -z "$TARGET_VERSION" ]; then
    show_usage
    exit 1
  fi

  # Normalize version
  if [[ ! "$TARGET_VERSION" == v* ]]; then
    TARGET_VERSION="v$TARGET_VERSION"
  fi

  # Check version is valid
  if [ -z "${VERSION_OVERLAYS[$TARGET_VERSION]}" ]; then
    log_error "Unknown version: $TARGET_VERSION"
    echo ""
    echo "Available versions: ${!VERSION_OVERLAYS[@]}"
    exit 1
  fi

  local overlay_path="${VERSION_OVERLAYS[$TARGET_VERSION]}"
  local current_version=$(get_argocd_version)

  log_info "Current version: $current_version"
  log_info "Target version:  $TARGET_VERSION"
  log_info "Overlay path:    $overlay_path"
  echo ""

  # Confirm rollback
  log_warning "This will rollback Argo CD to $TARGET_VERSION"
  echo ""
  if ! confirm "Proceed with rollback?"; then
    log_info "Rollback cancelled"
    exit 0
  fi

  # Backup current state
  log_step "1/3" "Backing up current state..."
  local backup_path=$(backup_argocd_state "pre-rollback-$current_version")
  log_success "Backup saved to: $backup_path"

  # Apply rollback
  log_step "2/3" "Applying rollback to $TARGET_VERSION..."
  apply_rollback "$overlay_path"

  # Validate
  log_step "3/3" "Validating rollback..."
  validate_rollback

  print_summary
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

show_usage() {
  cat << EOF
Usage: ./scripts/rollback.sh <target-version>

Rollback Argo CD to a previous version.

AVAILABLE VERSIONS:
  v2.10    Initial installation version
  v2.14    Pre-3.0 version
  v3.0     First v3.x version (includes RBAC migration)
  v3.1     Second v3.x version
  v3.2     Target version (v3.2.1)

EXAMPLES:
  ./scripts/rollback.sh v2.14    # Rollback to v2.14
  ./scripts/rollback.sh v3.0     # Rollback to v3.0

NOTE:
  - Backups are created automatically before rollback
  - Check ./backups/ directory for previous states
EOF
}

apply_rollback() {
  local overlay_path=$1

  log_info "Applying Kustomize overlay from $overlay_path"

  # Apply the overlay
  kustomize build --load-restrictor=LoadRestrictionsNone "$overlay_path" | kubectl apply --server-side --force-conflicts -f -

  log_success "Overlay applied"

  # Wait for rollout
  log_info "Waiting for Argo CD to restart..."
  source "$SCRIPT_DIR/lib/wait-for-argocd.sh"
  wait_for_argocd
}

validate_rollback() {
  local errors=0

  # Check version
  local version=$(get_argocd_version)
  log_info "Rolled back to version: $version"

  # Check all pods running
  local not_running=$(kubectl get pods -n argocd --no-headers | grep -v -E "Running|Completed" | wc -l | tr -d ' ')
  if [ "$not_running" -eq 0 ]; then
    log_success "All pods are Running"
  else
    log_error "$not_running pods are not Running"
    ((errors++))
  fi

  # Check applications
  if ! check_apps_health; then
    log_warning "Some applications may need attention"
  fi

  if [ $errors -gt 0 ]; then
    log_error "Rollback validation had issues"
    log_info "Check pod status: kubectl get pods -n argocd"
    log_info "Check logs: kubectl logs -l app.kubernetes.io/part-of=argocd -n argocd"
  else
    log_success "Rollback validation passed"
  fi
}

print_summary() {
  local version=$(get_argocd_version)

  log_section "Rollback Complete"

  cat << EOF
Argo CD has been rolled back.

CURRENT STATE:
  Version: $version

NEXT STEPS:
  1. Verify applications are working: argocd app list
  2. Check for any sync issues
  3. When ready, re-attempt upgrade with fixes

BACKUPS:
  Check ./backups/ for previous states

USEFUL COMMANDS:
  # Full validation
  ./scripts/validate.sh

  # View application status
  argocd app list

  # Check logs for issues
  kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd

EOF
}

main "$@"
