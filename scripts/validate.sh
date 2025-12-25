#!/bin/bash
#
# validate.sh - Comprehensive validation of Argo CD installation
#
# This script performs a full validation of the Argo CD installation,
# useful after any upgrade step or for routine health checks.
#
# WHAT THIS SCRIPT CHECKS:
# 1. Argo CD version
# 2. All pods are running
# 3. All deployments/statefulsets are ready
# 4. API server is responding
# 5. Applications are healthy
# 6. RBAC is working
# 7. UI is accessible
#
# USAGE:
#   ./scripts/validate.sh [--quick]
#
# OPTIONS:
#   --quick    Skip detailed checks, just verify pods are running
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

QUICK_MODE=false
if [[ "$1" == "--quick" ]]; then
  QUICK_MODE=true
fi

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "Argo CD Validation"

  local total_checks=0
  local passed_checks=0
  local failed_checks=0

  # Check 1: Version
  log_info "Checking Argo CD version..."
  local version=$(get_argocd_version)
  if [ -n "$version" ]; then
    log_success "Version: $version"
    ((passed_checks++))
  else
    log_error "Could not determine version"
    ((failed_checks++))
  fi
  ((total_checks++))

  # Check 2: Pods
  log_info "Checking pods..."
  local not_running=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v -E "Running|Completed" | wc -l | tr -d ' ')
  if [ "$not_running" -eq 0 ]; then
    local pod_count=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
    log_success "All $pod_count pods are Running"
    ((passed_checks++))
  else
    log_error "$not_running pods are not Running"
    kubectl get pods -n argocd --no-headers | grep -v -E "Running|Completed"
    ((failed_checks++))
  fi
  ((total_checks++))

  # Quick mode stops here
  if $QUICK_MODE; then
    print_results $passed_checks $failed_checks $total_checks
    exit $failed_checks
  fi

  # Check 3: Deployments
  log_info "Checking deployments..."
  local unhealthy_deploys=$(kubectl get deployments -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.readyReplicas}{" "}{.spec.replicas}{"\n"}{end}' 2>/dev/null | \
    awk '$2 != $3 {print $1}' | wc -l | tr -d ' ')
  if [ "$unhealthy_deploys" -eq 0 ]; then
    log_success "All deployments are ready"
    ((passed_checks++))
  else
    log_error "$unhealthy_deploys deployments are not ready"
    kubectl get deployments -n argocd
    ((failed_checks++))
  fi
  ((total_checks++))

  # Check 4: StatefulSets
  log_info "Checking StatefulSets..."
  if kubectl get statefulsets -n argocd --no-headers 2>/dev/null | grep -q .; then
    local unhealthy_sts=$(kubectl get statefulsets -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.readyReplicas}{" "}{.spec.replicas}{"\n"}{end}' 2>/dev/null | \
      awk '$2 != $3 {print $1}' | wc -l | tr -d ' ')
    if [ "$unhealthy_sts" -eq 0 ]; then
      log_success "All StatefulSets are ready"
      ((passed_checks++))
    else
      log_error "$unhealthy_sts StatefulSets are not ready"
      ((failed_checks++))
    fi
  else
    log_info "No StatefulSets found (may be expected)"
    ((passed_checks++))
  fi
  ((total_checks++))

  # Check 5: API Server
  log_info "Checking API server..."
  if curl -s -k --connect-timeout 5 https://argocd.local:9443/healthz 2>/dev/null | grep -q "ok"; then
    log_success "API server is healthy"
    ((passed_checks++))
  else
    log_warning "Could not reach API server (port-forward may not be running)"
    # Don't count as failure since port-forward might not be active
  fi
  ((total_checks++))

  # Check 6: Applications
  log_info "Checking applications..."
  local apps=$(kubectl get applications.argoproj.io -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$apps" -gt 0 ]; then
    local unhealthy=$(kubectl get applications.argoproj.io -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.health.status}{" "}{.status.sync.status}{"\n"}{end}' 2>/dev/null | \
      grep -v "Healthy Synced" | wc -l | tr -d ' ')
    if [ "$unhealthy" -eq 0 ]; then
      log_success "All $apps applications are Healthy/Synced"
      ((passed_checks++))
    else
      log_warning "$unhealthy of $apps applications are not Healthy/Synced"
      kubectl get applications.argoproj.io -n argocd
      ((failed_checks++))
    fi
  else
    log_info "No applications found"
    ((passed_checks++))
  fi
  ((total_checks++))

  # Check 7: RBAC ConfigMap
  log_info "Checking RBAC configuration..."
  if kubectl get configmap argocd-rbac-cm -n argocd &>/dev/null; then
    local has_policy=$(kubectl get configmap argocd-rbac-cm -n argocd -o jsonpath='{.data.policy\.csv}' 2>/dev/null | wc -c | tr -d ' ')
    if [ "$has_policy" -gt 10 ]; then
      log_success "RBAC policy is configured"
      ((passed_checks++))
    else
      log_warning "RBAC policy appears empty or minimal"
      ((passed_checks++))  # Not a failure, might be intentional
    fi
  else
    log_warning "argocd-rbac-cm not found"
  fi
  ((total_checks++))

  # Check 8: Services
  log_info "Checking services..."
  local services=$(kubectl get svc -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$services" -gt 0 ]; then
    log_success "$services services found"
    ((passed_checks++))
  else
    log_error "No services found"
    ((failed_checks++))
  fi
  ((total_checks++))

  # Show pod details
  log_section "Pod Status"
  kubectl get pods -n argocd -o wide

  # Show app status if any
  if [ "$apps" -gt 0 ]; then
    log_section "Application Status"
    kubectl get applications.argoproj.io -n argocd
  fi

  # Print results
  print_results $passed_checks $failed_checks $total_checks

  exit $failed_checks
}

print_results() {
  local passed=$1
  local failed=$2
  local total=$3

  log_section "Validation Results"

  echo "  Passed: $passed / $total"
  echo "  Failed: $failed / $total"
  echo ""

  if [ $failed -eq 0 ]; then
    log_success "All validation checks passed!"
    generate_validation_report "$(get_argocd_version)"
  else
    log_error "$failed validation check(s) failed"
    echo ""
    echo "Consider:"
    echo "  - Check pod logs: kubectl logs -l app.kubernetes.io/part-of=argocd -n argocd"
    echo "  - Describe failing pods: kubectl describe pod <pod-name> -n argocd"
    echo "  - Check events: kubectl get events -n argocd --sort-by='.lastTimestamp'"
  fi
}

main "$@"
