#!/bin/bash
#
# wait-for-argocd.sh - Wait for Argo CD to be fully ready
#
# This script waits for all Argo CD components to be running and healthy.
# It's used after installation or upgrade to ensure Argo CD is operational
# before proceeding with validation or further steps.
#
# Usage:
#   ./wait-for-argocd.sh [timeout_seconds]
#
# Exit codes:
#   0 - All components ready
#   1 - Timeout or error
#

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

TIMEOUT=${1:-300}  # Default 5 minutes
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Argo CD components to check (HA installation)
# These are the deployments we expect to see running
CORE_DEPLOYMENTS=(
  "argocd-server"
  "argocd-repo-server"
  "argocd-applicationset-controller"
  "argocd-notifications-controller"
  "argocd-dex-server"
)

# StatefulSets (HA mode)
STATEFULSETS=(
  "argocd-application-controller"
)

# Optional components that may or may not exist
OPTIONAL_DEPLOYMENTS=(
  "argocd-redis"           # Removed in v3.0
  "argocd-redis-ha-haproxy" # HA Redis proxy
)

# ==============================================================================
# MAIN WAIT LOGIC
# ==============================================================================

wait_for_argocd() {
  local start_time=$(date +%s)
  local timeout=$TIMEOUT

  log_section "Waiting for Argo CD Components"
  log_info "Namespace: $NAMESPACE"
  log_info "Timeout: ${timeout}s"
  echo ""

  # First, wait for namespace to exist
  log_step "1/4" "Checking namespace exists..."
  while ! kubectl get namespace "$NAMESPACE" &>/dev/null; do
    local elapsed=$(($(date +%s) - start_time))
    if [ $elapsed -ge $timeout ]; then
      log_error "Timeout waiting for namespace '$NAMESPACE'"
      return 1
    fi
    sleep 2
  done
  log_success "Namespace '$NAMESPACE' exists"

  # Wait for core deployments
  log_step "2/4" "Waiting for core deployments..."
  for deployment in "${CORE_DEPLOYMENTS[@]}"; do
    # Check if deployment exists (some may not in certain versions)
    if ! kubectl get deployment "$deployment" -n "$NAMESPACE" &>/dev/null; then
      log_warning "Deployment '$deployment' not found (may be expected for this version)"
      continue
    fi

    log_info "  Waiting for $deployment..."
    local elapsed=$(($(date +%s) - start_time))
    local remaining=$((timeout - elapsed))

    if [ $remaining -le 0 ]; then
      log_error "Timeout waiting for deployments"
      return 1
    fi

    if ! kubectl rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout="${remaining}s" 2>/dev/null; then
      log_error "Deployment '$deployment' failed to become ready"
      kubectl describe deployment "$deployment" -n "$NAMESPACE" | tail -20
      return 1
    fi
    log_success "  $deployment is ready"
  done

  # Wait for StatefulSets
  log_step "3/4" "Waiting for StatefulSets..."
  for sts in "${STATEFULSETS[@]}"; do
    if ! kubectl get statefulset "$sts" -n "$NAMESPACE" &>/dev/null; then
      log_warning "StatefulSet '$sts' not found (may be expected for this version)"
      continue
    fi

    log_info "  Waiting for $sts..."
    local elapsed=$(($(date +%s) - start_time))
    local remaining=$((timeout - elapsed))

    if [ $remaining -le 0 ]; then
      log_error "Timeout waiting for StatefulSets"
      return 1
    fi

    if ! kubectl rollout status statefulset/"$sts" -n "$NAMESPACE" --timeout="${remaining}s" 2>/dev/null; then
      log_error "StatefulSet '$sts' failed to become ready"
      kubectl describe statefulset "$sts" -n "$NAMESPACE" | tail -20
      return 1
    fi
    log_success "  $sts is ready"
  done

  # Check optional components (don't fail if missing)
  log_step "4/4" "Checking optional components..."
  for deployment in "${OPTIONAL_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" -n "$NAMESPACE" &>/dev/null; then
      local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
      local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
      if [ "$ready" == "$desired" ] && [ -n "$ready" ]; then
        log_success "  $deployment is ready ($ready/$desired)"
      else
        log_warning "  $deployment not fully ready ($ready/$desired)"
      fi
    else
      log_info "  $deployment not present (may be expected)"
    fi
  done

  echo ""
  log_section "Argo CD Status Summary"

  # Show final pod status
  echo "Pods:"
  kubectl get pods -n "$NAMESPACE" -o wide

  echo ""
  echo "Services:"
  kubectl get svc -n "$NAMESPACE"

  echo ""

  # Get version
  local version=$(get_argocd_version)
  log_success "Argo CD $version is ready!"

  return 0
}

# ==============================================================================
# HEALTH CHECK
# ==============================================================================

# Additional health check - verify Argo CD API is responding
check_api_health() {
  log_info "Checking Argo CD API health..."

  # Start port-forward if not already running
  if ! curl -s -k https://localhost:8080/healthz &>/dev/null; then
    log_info "Starting port-forward for health check..."
    kubectl port-forward svc/argocd-server -n "$NAMESPACE" 8080:443 &>/dev/null &
    local pf_pid=$!
    sleep 3

    if ! curl -s -k https://localhost:8080/healthz &>/dev/null; then
      log_warning "Could not reach Argo CD API (this may be fine if not using port-forward)"
      kill $pf_pid 2>/dev/null || true
      return 0
    fi
    kill $pf_pid 2>/dev/null || true
  fi

  log_success "Argo CD API is healthy"
  return 0
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
  log_section "Argo CD Readiness Check"

  if ! wait_for_argocd; then
    log_error "Argo CD failed to become ready within ${TIMEOUT}s"
    echo ""
    echo "Debug information:"
    kubectl get pods -n "$NAMESPACE"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20
    exit 1
  fi

  # Optional: check API health
  # check_api_health

  exit 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
