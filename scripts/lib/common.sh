#!/bin/bash
#
# common.sh - Shared functions for Argo CD upgrade demo scripts
#
# This library provides:
# - Colored logging (matching production script style)
# - Dependency checks
# - Kubernetes/Argo CD helpers
# - Backup utilities
#
# Usage: source this file at the top of your script
#   source "$(dirname "$0")/lib/common.sh"
#

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Script directory (for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Argo CD namespace
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Timeouts (in seconds)
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# Backup directory
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"

# ==============================================================================
# LOGGING FUNCTIONS
# Matches production style from argocd-projects-setup.bash
# ==============================================================================

# Main log function with colored output
# Usage: log "message" [level]
# Levels: success (green), warning (yellow), error (red), info (default)
log() {
  local message=$1
  local level=${2:-info}

  case $level in
  success)
    echo -e "\033[0;32m$(date '+%d-%m-%Y-%H:%M:%S') - ✓ $message\033[0m"
    ;;
  warning)
    echo -e "\033[0;33m$(date '+%d-%m-%Y-%H:%M:%S') - ⚠ $message\033[0m"
    ;;
  error)
    echo -e "\033[0;31m$(date '+%d-%m-%Y-%H:%M:%S') - ✗ $message\033[0m"
    ;;
  info)
    echo -e "\033[0;36m$(date '+%d-%m-%Y-%H:%M:%S') - $message\033[0m"
    ;;
  *)
    echo -e "$(date '+%d-%m-%Y-%H:%M:%S') - $message"
    ;;
  esac
}

# Convenience wrappers
log_info() { log "$1" "info"; }
log_success() { log "$1" "success"; }
log_warning() { log "$1" "warning"; }
log_error() { log "$1" "error"; }

# Print a section header
# Usage: log_section "Section Name"
log_section() {
  echo ""
  echo -e "\033[1;35m===============================================================================\033[0m"
  echo -e "\033[1;35m  $1\033[0m"
  echo -e "\033[1;35m===============================================================================\033[0m"
  echo ""
}

# Print a step within a section
# Usage: log_step "1/5" "Step description"
log_step() {
  local step_num=$1
  local description=$2
  echo -e "\033[1;34m[$step_num] $description\033[0m"
}

# ==============================================================================
# DEPENDENCY CHECKS
# ==============================================================================

# Check if a command is available
# Usage: check_dependency "command" "error message"
check_dependency() {
  local command=$1
  local message=${2:-"$command is required but not found. Please install it."}

  if ! command -v "$command" &>/dev/null; then
    log_error "$message"
    exit 1
  fi
}

# Check all required dependencies for the upgrade demo
check_all_dependencies() {
  log_info "Checking required dependencies..."

  check_dependency "minikube" "minikube is required. Install: brew install minikube"
  check_dependency "kubectl" "kubectl is required. Install: brew install kubectl"
  check_dependency "kustomize" "kustomize is required. Install: brew install kustomize"
  check_dependency "argocd" "argocd CLI is required. Install: brew install argocd"
  check_dependency "htpasswd" "htpasswd is required for password hashing. Install: brew install httpd"

  log_success "All dependencies found"
}

# ==============================================================================
# KUBERNETES HELPERS
# ==============================================================================

# Wait for all pods in a namespace to be Running
# Usage: wait_for_pods "namespace" [timeout_seconds]
wait_for_pods() {
  local namespace=$1
  local timeout=${2:-$WAIT_TIMEOUT}
  local start_time=$(date +%s)

  log_info "Waiting for all pods in namespace '$namespace' to be Running (timeout: ${timeout}s)..."

  while true; do
    local elapsed=$(($(date +%s) - start_time))
    if [ $elapsed -ge $timeout ]; then
      log_error "Timeout waiting for pods in namespace '$namespace'"
      kubectl get pods -n "$namespace"
      return 1
    fi

    # Get pods not in Running/Completed state
    local not_ready=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null |
      grep -v -E "Running|Completed" | wc -l | tr -d ' ')

    if [ "$not_ready" -eq 0 ]; then
      # Also check that at least some pods exist
      local pod_count=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [ "$pod_count" -gt 0 ]; then
        log_success "All pods in namespace '$namespace' are Running"
        return 0
      fi
    fi

    sleep $POLL_INTERVAL
  done
}

# Wait for a specific deployment to be ready
# Usage: wait_for_deployment "namespace" "deployment-name" [timeout_seconds]
wait_for_deployment() {
  local namespace=$1
  local deployment=$2
  local timeout=${3:-$WAIT_TIMEOUT}

  log_info "Waiting for deployment '$deployment' in namespace '$namespace'..."

  if kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="${timeout}s"; then
    log_success "Deployment '$deployment' is ready"
    return 0
  else
    log_error "Deployment '$deployment' failed to become ready"
    return 1
  fi
}

# ==============================================================================
# ARGO CD HELPERS
# ==============================================================================

# Get current Argo CD version
# Usage: version=$(get_argocd_version)
get_argocd_version() {
  kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null |
    sed 's/.*://'
}

# Login to Argo CD using admin account
# Usage: argocd_login
argocd_login() {
  local password
  local server

  # Try to get password from credentials file first (set during installation)
  if [ -f "$PROJECT_ROOT/.credentials/password" ]; then
    password=$(cat "$PROJECT_ROOT/.credentials/password")
    log_info "Using password from .credentials/password"
  else
    # Fall back to the known password (matches the bcrypt hash in argocd-secret.yaml)
    password="admin123"
    log_info "Using default password: admin123"
  fi

  if [ -z "$password" ]; then
    log_error "Could not retrieve Argo CD admin password"
    return 1
  fi

  # Get the server URL (using ingress with custom port for Docker driver)
  server="argocd.local:9443"

  log_info "Logging into Argo CD at $server..."
  argocd login "$server" --username admin --password "$password" --insecure --grpc-web --skip-test-tls
}

# Check health of all Argo CD applications
# Usage: check_apps_health
check_apps_health() {
  log_info "Checking Argo CD application health..."

  local apps=$(argocd app list -o name 2>/dev/null)

  if [ -z "$apps" ]; then
    log_warning "No applications found"
    return 0
  fi

  local unhealthy=0
  for app in $apps; do
    local health=$(argocd app get "$app" -o json 2>/dev/null | jq -r '.status.health.status')
    local sync=$(argocd app get "$app" -o json 2>/dev/null | jq -r '.status.sync.status')

    if [ "$health" != "Healthy" ] || [ "$sync" != "Synced" ]; then
      log_warning "App '$app': health=$health, sync=$sync"
      ((unhealthy++))
    else
      log_success "App '$app': Healthy/Synced"
    fi
  done

  if [ $unhealthy -gt 0 ]; then
    log_warning "$unhealthy application(s) are not Healthy/Synced"
    return 1
  fi

  log_success "All applications are Healthy/Synced"
  return 0
}

# Get status of all Argo CD applications as JSON
# Usage: get_all_apps_status
get_all_apps_status() {
  argocd app list -o json 2>/dev/null
}

# ==============================================================================
# BACKUP UTILITIES
# ==============================================================================

# Backup Argo CD state before upgrade
# Usage: backup_argocd_state "v2.10"
backup_argocd_state() {
  local version=$1
  local timestamp=$(date '+%Y%m%d-%H%M%S')
  local backup_path="$BACKUP_DIR/${version}_${timestamp}"

  mkdir -p "$backup_path"

  log_info "Backing up Argo CD state to $backup_path..."

  # Backup ConfigMaps
  kubectl get configmap -n "$ARGOCD_NAMESPACE" -o yaml >"$backup_path/configmaps.yaml" 2>/dev/null

  # Backup Secrets (without decoding)
  kubectl get secrets -n "$ARGOCD_NAMESPACE" -o yaml >"$backup_path/secrets.yaml" 2>/dev/null

  # Backup Applications
  kubectl get applications.argoproj.io -n "$ARGOCD_NAMESPACE" -o yaml >"$backup_path/applications.yaml" 2>/dev/null

  # Backup AppProjects
  kubectl get appprojects.argoproj.io -n "$ARGOCD_NAMESPACE" -o yaml >"$backup_path/appprojects.yaml" 2>/dev/null

  # Backup RBAC policy
  kubectl get configmap argocd-rbac-cm -n "$ARGOCD_NAMESPACE" -o yaml >"$backup_path/argocd-rbac-cm.yaml" 2>/dev/null

  # Save current version info
  echo "version: $version" >"$backup_path/version.txt"
  echo "timestamp: $timestamp" >>"$backup_path/version.txt"
  get_argocd_version >>"$backup_path/version.txt"

  log_success "Backup saved to $backup_path"
  echo "$backup_path"
}

# List available backups
# Usage: list_backups
list_backups() {
  if [ -d "$BACKUP_DIR" ]; then
    log_info "Available backups:"
    ls -la "$BACKUP_DIR"
  else
    log_warning "No backups found"
  fi
}

# ==============================================================================
# VALIDATION HELPERS
# ==============================================================================

# Run a validation check and track pass/fail
# Usage: run_check "Check name" "command to run"
run_check() {
  local name=$1
  local cmd=$2

  echo -n "  Checking: $name... "
  if eval "$cmd" &>/dev/null; then
    echo -e "\033[0;32mPASS\033[0m"
    return 0
  else
    echo -e "\033[0;31mFAIL\033[0m"
    return 1
  fi
}

# Generate a validation report
# Usage: generate_validation_report "v2.14"
generate_validation_report() {
  local version=$1
  local report_file="$PROJECT_ROOT/validation/report-${version}-$(date '+%Y%m%d-%H%M%S').md"

  log_info "Generating validation report..."

  mkdir -p "$PROJECT_ROOT/validation"

  cat >"$report_file" <<EOF
# Argo CD Upgrade Validation Report

**Version:** $version
**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Cluster:** $(kubectl config current-context)

## Component Status

\`\`\`
$(kubectl get pods -n $ARGOCD_NAMESPACE)
\`\`\`

## Application Status

\`\`\`
$(argocd app list 2>/dev/null || echo "Could not get app list")
\`\`\`

## Version Info

\`\`\`
Argo CD Server: $(get_argocd_version)
\`\`\`

EOF

  log_success "Report saved to $report_file"
}

# ==============================================================================
# MINIKUBE HELPERS
# ==============================================================================

# Configure macOS DNS resolver for ingress access
# For Docker driver: resolves *.local to 127.0.0.1 (Docker port mapping)
# For VM drivers: resolves *.local to minikube IP (direct access)
# Usage: configure_macos_dns_resolver [profile]
#
# NOTE: On macOS with Docker driver, ingress-dns addon does NOT work because
# the minikube IP is not routable from the host. Instead, we use /etc/hosts
# with 127.0.0.1 since Docker maps the ingress ports to localhost.
#
configure_macos_dns_resolver() {
  local profile="${1:-argocd-upgrade-demo}"
  local hosts_entry="127.0.0.1 argocd.local"

  log_info "Configuring /etc/hosts for argocd.local..."

  # Check if entry already exists
  if grep -q "argocd.local" /etc/hosts 2>/dev/null; then
    log_success "/etc/hosts already contains argocd.local entry"
    return 0
  fi

  # Add entry to /etc/hosts
  log_info "Adding argocd.local to /etc/hosts (requires sudo)..."
  echo "$hosts_entry" | sudo tee -a /etc/hosts >/dev/null

  if [ $? -eq 0 ]; then
    log_success "Added to /etc/hosts: $hosts_entry"
  else
    log_warning "Could not update /etc/hosts automatically"
    log_info "Please add this line to /etc/hosts manually:"
    log_info "  $hosts_entry"
    return 1
  fi

  # Flush DNS cache
  log_info "Flushing DNS cache..."
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true

  # Verify resolution works
  sleep 1
  if ping -c 1 -W 2 argocd.local &>/dev/null; then
    log_success "DNS resolution verified: argocd.local resolves correctly"
  else
    log_warning "DNS resolution test inconclusive - may take a moment to propagate"
  fi

  return 0
}

# Remove macOS /etc/hosts entry for argocd.local
# Usage: remove_macos_dns_resolver
remove_macos_dns_resolver() {
  if grep -q "argocd.local" /etc/hosts 2>/dev/null; then
    log_info "Removing argocd.local from /etc/hosts (requires sudo)..."
    sudo sed -i '' '/argocd\.local/d' /etc/hosts
    log_success "Removed argocd.local from /etc/hosts"
  else
    log_info "No argocd.local entry in /etc/hosts to remove"
  fi
}

# Check if minikube is running
# Usage: check_minikube_running
check_minikube_running() {
  if ! minikube status &>/dev/null; then
    log_error "Minikube is not running. Start it with: ./scripts/00-setup-minikube.sh"
    return 1
  fi
  return 0
}

# Start port-forward to Argo CD server
# Usage: start_port_forward
start_port_forward() {
  log_info "Starting port-forward to Argo CD server..."

  # Kill any existing port-forward
  pkill -f "kubectl port-forward.*argocd-server" 2>/dev/null || true

  # Start new port-forward in background
  kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &>/dev/null &
  local pf_pid=$!

  # Wait a moment for it to establish
  sleep 3

  if kill -0 $pf_pid 2>/dev/null; then
    log_success "Port-forward started (PID: $pf_pid). Access Argo CD at https://localhost:8080"
    echo $pf_pid >/tmp/argocd-port-forward.pid
    return 0
  else
    log_error "Failed to start port-forward"
    return 1
  fi
}

# Stop port-forward
# Usage: stop_port_forward
stop_port_forward() {
  if [ -f /tmp/argocd-port-forward.pid ]; then
    kill $(cat /tmp/argocd-port-forward.pid) 2>/dev/null || true
    rm /tmp/argocd-port-forward.pid
  fi
  pkill -f "kubectl port-forward.*argocd-server" 2>/dev/null || true
  log_info "Port-forward stopped"
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Confirm action with user
# Usage: confirm "Are you sure?" && do_thing
confirm() {
  local prompt="${1:-Are you sure?}"
  read -p "$prompt [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

# Wait for user to press Enter
# Usage: pause "Press Enter to continue..."
pause() {
  local prompt="${1:-Press Enter to continue...}"
  read -p "$prompt"
}

# Display breaking changes for a version upgrade
# Usage: show_breaking_changes "2.14" "3.0"
show_breaking_changes() {
  local from=$1
  local to=$2

  log_section "Breaking Changes: v$from → v$to"

  case "${from}_${to}" in
  "2.10"*"_2.14"*)
    cat <<'EOF'
  No critical breaking changes. This is a preparation step.

  Minor changes:
  - Deprecated config keys may show warnings
  - Review release notes for any behavioral changes
EOF
    ;;
  "2.14"*"_3.0"*)
    cat <<'EOF'
  ⚠️  CRITICAL BREAKING CHANGES ⚠️

  1. FINE-GRAINED RBAC (affects operator role!)
     - 'update' on Application no longer implies update on managed resources
     - 'delete' on Application no longer implies delete on managed resources
     - ACTION REQUIRED: Add explicit 'update/*' and 'delete/*' permissions

  2. KUBERNETES VERSION
     - Minimum supported: Kubernetes 1.21+
     - ACTION: Verify cluster version

  Reference: https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/
EOF
    ;;
  "3.0"*"_3.1"*)
    cat <<'EOF'
  Breaking Changes:

  1. SYMLINK PROTECTION
     - Symlinks in /app/shared now blocked if target is outside
     - Impact: 500 errors if using out-of-bounds symlinks

  2. ACTIONS API V1 DEPRECATED
     - v1 endpoint: /api/v1/applications/{name}/resource/actions
     - v2 endpoint: /api/v1/applications/{name}/resource/actions/v2
     - ACTION: Update any API clients using v1

  Reference: https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.0-3.1/
EOF
    ;;
  "3.1"*"_3.2"*)
    cat <<'EOF'
  Breaking Changes:

  1. HYDRATION PATHS
     - Hydration path cannot be root ("" or ".")
     - Must use a subdirectory
     - ACTION: Check ApplicationSet hydration configs

  2. SERVER-SIDE DIFF
     - New feature: uses K8s dry-run apply for diff
     - Enable with: --server-side flag
     - More accurate diffs, especially for CRDs

  Reference: https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.1-3.2/
EOF
    ;;
  *)
    log_warning "No breaking changes documented for v$from → v$to"
    ;;
  esac
  echo ""
}
