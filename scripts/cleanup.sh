#!/bin/bash
#
# cleanup.sh - Clean up the Argo CD upgrade demo environment
#
# This script removes Argo CD and optionally the minikube cluster.
#
# USAGE:
#   ./scripts/cleanup.sh [--all]
#
# OPTIONS:
#   --all    Also delete the minikube cluster (default: keep cluster)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

DELETE_CLUSTER=false
if [[ "$1" == "--all" ]]; then
  DELETE_CLUSTER=true
fi

CLUSTER_NAME="${CLUSTER_NAME:-argocd-upgrade-demo}"

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "Argo CD Upgrade Demo - Cleanup"

  echo ""
  echo "This will:"
  echo "  - Delete Argo CD and all applications"
  echo "  - Delete the argocd namespace"
  echo "  - Delete test application namespaces"
  if $DELETE_CLUSTER; then
    echo "  - DELETE THE MINIKUBE CLUSTER '$CLUSTER_NAME'"
  else
    echo "  - Keep the minikube cluster (use --all to delete)"
  fi
  echo ""

  if ! confirm "Proceed with cleanup?"; then
    log_info "Cleanup cancelled"
    exit 0
  fi

  # Step 1: Stop port-forward
  log_step "1/4" "Stopping port-forward..."
  stop_port_forward
  log_success "Port-forward stopped"

  # Step 2: Delete applications
  log_step "2/4" "Deleting Argo CD applications..."
  delete_applications

  # Step 3: Delete Argo CD
  log_step "3/4" "Deleting Argo CD namespace..."
  delete_argocd

  # Step 4: Optionally delete cluster
  if $DELETE_CLUSTER; then
    log_step "4/4" "Deleting minikube cluster..."
    delete_cluster
  else
    log_step "4/4" "Keeping minikube cluster"
    log_info "To delete cluster later: minikube delete -p $CLUSTER_NAME"
  fi

  print_summary
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

delete_applications() {
  # Delete all Argo CD applications first to prevent orphaned resources
  if kubectl get applications.argoproj.io -n argocd &>/dev/null; then
    local apps=$(kubectl get applications.argoproj.io -n argocd -o name 2>/dev/null)
    if [ -n "$apps" ]; then
      log_info "Deleting applications..."
      for app in $apps; do
        log_info "  Deleting $app..."
        kubectl delete "$app" -n argocd --wait=false 2>/dev/null || true
      done

      # Wait for finalizers
      sleep 5
    else
      log_info "No applications found"
    fi
  fi

  # Delete test app namespaces
  for ns in guestbook test-apps; do
    if kubectl get namespace "$ns" &>/dev/null; then
      log_info "  Deleting namespace $ns..."
      kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    fi
  done

  log_success "Applications cleaned up"
}

delete_argocd() {
  if kubectl get namespace argocd &>/dev/null; then
    log_info "Deleting argocd namespace..."

    # Remove finalizers from any stuck resources
    kubectl get applications.argoproj.io -n argocd -o name 2>/dev/null | \
      xargs -I {} kubectl patch {} -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

    # Delete the namespace
    kubectl delete namespace argocd --wait=false 2>/dev/null || true

    # Wait a bit for cleanup
    sleep 5

    # Force delete if still exists
    if kubectl get namespace argocd &>/dev/null; then
      log_warning "Namespace still exists, forcing deletion..."
      kubectl delete namespace argocd --grace-period=0 --force 2>/dev/null || true
    fi

    log_success "Argo CD namespace deleted"
  else
    log_info "argocd namespace does not exist"
  fi
}

delete_cluster() {
  if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
    log_info "Deleting minikube cluster '$CLUSTER_NAME'..."
    minikube delete -p "$CLUSTER_NAME"
    log_success "Minikube cluster deleted"
  else
    log_info "Minikube cluster '$CLUSTER_NAME' does not exist"
  fi
}

print_summary() {
  log_section "Cleanup Complete"

  cat << EOF
The Argo CD upgrade demo environment has been cleaned up.

WHAT WAS REMOVED:
  ✓ Argo CD applications
  ✓ Argo CD namespace
  ✓ Test application namespaces
EOF

  if $DELETE_CLUSTER; then
    cat << EOF
  ✓ Minikube cluster '$CLUSTER_NAME'

TO START FRESH:
  ./scripts/00-setup-minikube.sh
  ./scripts/01-install-argocd-2.10.sh
EOF
  else
    cat << EOF

CLUSTER PRESERVED:
  The minikube cluster '$CLUSTER_NAME' was kept.

  To reinstall Argo CD:
    ./scripts/01-install-argocd-2.10.sh

  To delete the cluster:
    minikube delete -p $CLUSTER_NAME

    Or run:
    ./scripts/cleanup.sh --all
EOF
  fi

  echo ""
}

main "$@"
