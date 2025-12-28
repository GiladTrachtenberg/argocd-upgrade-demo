#!/bin/bash
#
# 01-install-argocd-2.10.sh - Install Argo CD v2.10.x (initial version)
#
# This script installs Argo CD v2.10.17 (latest 2.10.x patch) as the baseline
# for the upgrade demo. This mirrors the production version (v2.10.0).
#
# WHAT THIS SCRIPT DOES:
# 1. Verifies minikube cluster is running
# 2. Applies the v2.10 Kustomize overlay
# 3. Waits for all Argo CD components to be ready
# 4. Sets up port-forward for UI access
# 5. Retrieves admin credentials
# 6. Deploys test applications
# 7. Runs initial validation
#
# USAGE:
#   ./scripts/01-install-argocd-2.10.sh
#
# AFTER RUNNING:
#   - Ensure minikube tunnel is running: minikube tunnel -p argocd-upgrade-demo
#   - Access Argo CD UI: https://argocd.local
#   - Username: admin
#   - Password: admin123 (or generated password shown in output)
#

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

VERSION="v2.10"
OVERLAY_PATH="$PROJECT_ROOT/overlays/v2.10"
TEST_APPS_PATH="$PROJECT_ROOT/test-apps"

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "Installing Argo CD $VERSION"

  # Step 1: Check prerequisites
  log_step "1/8" "Checking prerequisites..."
  check_prerequisites

  # Step 2: Apply Kustomize overlay
  log_step "2/8" "Applying Kustomize overlay..."
  apply_overlay

  # Step 3: Wait for Argo CD to be ready
  log_step "3/8" "Waiting for Argo CD to be ready..."
  source "$SCRIPT_DIR/lib/wait-for-argocd.sh"
  wait_for_argocd

  # Step 4: Configure macOS DNS resolver for ingress-dns
  log_step "4/8" "Configuring macOS DNS resolver..."
  configure_macos_dns_resolver "argocd-upgrade-demo"

  # Step 5: Get admin credentials (password is pre-configured in argocd-secret)
  log_step "5/8" "Retrieving admin credentials..."
  get_credentials

  # Step 6: Wait for ingress to be ready
  log_step "6/8" "Waiting for ingress to be ready..."
  wait_for_ingress

  # Step 7: Deploy test applications
  log_step "7/8" "Deploying test applications..."
  deploy_test_apps

  # Step 8: Run validation
  log_step "8/8" "Running validation..."
  run_validation

  # Print summary
  print_summary
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check_prerequisites() {
  # Check dependencies
  check_all_dependencies

  # Check minikube is running
  if ! check_minikube_running; then
    log_error "Minikube is not running. Run ./scripts/00-setup-minikube.sh first."
    exit 1
  fi

  # Check overlay exists
  if [ ! -d "$OVERLAY_PATH" ]; then
    log_error "Overlay not found at $OVERLAY_PATH"
    exit 1
  fi

  log_success "Prerequisites check passed"
}

apply_overlay() {
  log_info "Applying overlay from $OVERLAY_PATH"

  # Build and apply kustomize
  kustomize build --load-restrictor=LoadRestrictionsNone "$OVERLAY_PATH" | kubectl apply --server-side --force-conflicts -f -

  log_success "Overlay applied"
}

wait_for_ingress() {
  log_info "Waiting for ingress controller to be ready..."

  # Wait for ingress-nginx controller
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s 2>/dev/null || log_warning "Ingress controller wait timed out"

  # Wait for ArgoCD ingress to get an address
  log_info "Waiting for ArgoCD ingress to be ready..."
  local retries=0
  local max_retries=30

  while [ $retries -lt $max_retries ]; do
    local ingress_addr=$(kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$ingress_addr" ]; then
      log_success "Ingress is ready at $ingress_addr"
      break
    fi
    sleep 2
    ((retries++))
  done

  if [ $retries -eq $max_retries ]; then
    log_warning "Ingress address not assigned yet - this is OK for minikube"
  fi

  # Test connectivity via ingress (requires minikube tunnel running)
  sleep 3
  if curl -s -k --connect-timeout 5 https://argocd.local/healthz &>/dev/null; then
    log_success "ArgoCD is accessible via https://argocd.local"
  else
    log_warning "Could not reach ArgoCD via ingress - ensure 'minikube tunnel' is running"
  fi
}

get_credentials() {
  local password="admin123"  # This matches the bcrypt hash in argocd-secret.yaml

  log_info "Admin password is set to: admin123"
  log_info "(This password is pre-configured in base/argocd-secret.yaml)"

  # NOTE: When argocd-secret is pre-configured with a password hash,
  # ArgoCD does NOT generate argocd-initial-admin-secret.
  # We skip waiting for it since we already know our password.

  # Store credentials for reference
  mkdir -p "$PROJECT_ROOT/.credentials"
  echo "admin" > "$PROJECT_ROOT/.credentials/username"
  echo "$password" > "$PROJECT_ROOT/.credentials/password"
  chmod 600 "$PROJECT_ROOT/.credentials/password"

  log_success "Credentials stored in $PROJECT_ROOT/.credentials/"
}

deploy_test_apps() {
  # Check if test-apps exist
  if [ ! -d "$TEST_APPS_PATH" ]; then
    log_warning "Test apps not found at $TEST_APPS_PATH - skipping"
    return 0
  fi

  # Check if project.yaml exists
  if [ ! -f "$TEST_APPS_PATH/project.yaml" ]; then
    log_warning "test-apps/project.yaml not found - creating basic project"
    create_test_project
  fi

  # Login to Argo CD via ingress
  log_info "Logging into Argo CD..."
  local password=$(cat "$PROJECT_ROOT/.credentials/password" 2>/dev/null || echo "admin123")

  if argocd login argocd.local --username admin --password "$password" --insecure --grpc-web --skip-test-tls 2>/dev/null; then
    log_success "Logged into Argo CD"
  else
    log_warning "Could not login to Argo CD CLI - will use kubectl instead"
  fi

  # Apply test apps project
  if [ -f "$TEST_APPS_PATH/project.yaml" ]; then
    kubectl apply -f "$TEST_APPS_PATH/project.yaml"
    log_success "Test apps project created"
  fi

  # Deploy guestbook app if it exists
  if [ -f "$TEST_APPS_PATH/guestbook/application.yaml" ]; then
    kubectl apply -f "$TEST_APPS_PATH/guestbook/application.yaml"
    log_success "Guestbook application created"
  else
    # Create guestbook app via kubectl
    create_guestbook_app_kubectl
  fi

  log_success "Test applications deployed"
}

create_test_project() {
  cat << 'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: test-apps
  namespace: argocd
spec:
  description: Test applications for upgrade validation
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
EOF
}

create_guestbook_app_kubectl() {
  log_info "Creating guestbook application via kubectl..."

  # Create namespace if needed
  kubectl create namespace guestbook --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

  # Create the Application resource directly
  cat << 'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: test-apps
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
}

run_validation() {
  log_info "Running initial validation..."

  local errors=0

  # Check Argo CD version
  local version=$(get_argocd_version)
  if [[ "$version" == *"2.10"* ]]; then
    log_success "Version check: $version"
  else
    log_error "Version check failed: expected 2.10.x, got $version"
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

  # Check server is responding via ingress (requires minikube tunnel)
  if curl -s -k https://argocd.local/healthz &>/dev/null; then
    log_success "Argo CD server is responding via ingress"
  else
    log_warning "Could not reach Argo CD server via ingress - ensure 'minikube tunnel' is running"
  fi

  # Check ingress is configured
  if kubectl get ingress argocd-server-ingress -n argocd &>/dev/null; then
    log_success "Ingress is configured"
  else
    log_error "Ingress is not configured"
    ((errors++))
  fi

  if [ $errors -gt 0 ]; then
    log_warning "Validation completed with $errors error(s)"
  else
    log_success "Validation passed"
  fi
}

print_summary() {
  log_section "Installation Complete"

  local password=$(cat "$PROJECT_ROOT/.credentials/password" 2>/dev/null || echo "admin123")
  local version=$(get_argocd_version)

  cat << EOF
Argo CD $VERSION has been installed successfully.

IMPORTANT:
  Run 'minikube tunnel -p argocd-upgrade-demo' in a separate terminal
  to enable ingress access.

ARGO CD ACCESS:
  URL:      https://argocd.local
  Username: admin
  Password: $password

VERSION:
  Installed: $version
  Target:    v3.2.1

NEXT STEPS:
  1. Ensure minikube tunnel is running
  2. Open the Argo CD UI: https://argocd.local
  3. Verify test applications are Healthy/Synced
  4. Proceed to first upgrade:
     ./scripts/02-upgrade-to-2.14.sh

USEFUL COMMANDS:
  # Check Argo CD status
  kubectl get pods -n argocd

  # Check ingress
  kubectl get ingress -n argocd

  # View applications
  argocd app list

  # Check application health
  argocd app get guestbook

  # View Argo CD server logs
  kubectl logs -f deploy/argocd-server -n argocd

UPGRADE PATH:
  [CURRENT] v2.10.x → v2.14 → v3.0 → v3.1 → v3.2.1

EOF
}

# ==============================================================================
# RUN
# ==============================================================================

main "$@"
