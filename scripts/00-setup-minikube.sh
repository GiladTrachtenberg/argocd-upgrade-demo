#!/bin/bash
#
# 00-setup-minikube.sh - Set up minikube cluster for Argo CD upgrade demo
#
# This script creates a minikube cluster with the resources and addons
# needed to run Argo CD HA installation.
#
# WHAT THIS SCRIPT DOES:
# 1. Checks prerequisites (minikube, kubectl, kustomize, argocd CLI)
# 2. Creates a multi-node minikube cluster for HA Argo CD
# 3. Enables required addons (ingress, metrics-server)
# 4. Verifies cluster is ready
#
# USAGE:
#   ./scripts/00-setup-minikube.sh
#
# PREREQUISITES:
#   - minikube v1.30+
#   - kubectl v1.28+
#   - kustomize v5.0+
#   - argocd CLI v2.10+
#   - Docker Desktop (or other container runtime)
#   - 4GB RAM available (2GB per node x 2 nodes)
#

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Minikube cluster settings
CLUSTER_NAME="${CLUSTER_NAME:-argocd-upgrade-demo}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.28.0}"
NODES="${NODES:-3}"           # 3 nodes for HA
MEMORY="${MEMORY:-2048}"      # 2GB RAM per node
CPUS="${CPUS:-2}"             # 2 CPUs per node
DISK_SIZE="${DISK_SIZE:-10g}" # 10GB disk per node

# Container runtime (docker, containerd, cri-o)
DRIVER="${DRIVER:-docker}"

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

main() {
  log_section "Argo CD Upgrade Demo - Minikube Setup"

  # Step 1: Check prerequisites
  log_step "1/5" "Checking prerequisites..."
  check_all_dependencies

  # Step 2: Check if cluster already exists
  log_step "2/5" "Checking existing clusters..."
  if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
    log_warning "Cluster '$CLUSTER_NAME' already exists"

    if confirm "Delete existing cluster and create new one?"; then
      log_info "Deleting existing cluster..."
      minikube delete -p "$CLUSTER_NAME"
    else
      log_info "Using existing cluster"
      minikube profile "$CLUSTER_NAME"
      verify_cluster
      log_success "Setup complete (using existing cluster)"
      exit 0
    fi
  fi

  # Step 3: Create minikube cluster
  log_step "3/5" "Creating minikube cluster..."
  log_info "Cluster name: $CLUSTER_NAME"
  log_info "Kubernetes version: $KUBERNETES_VERSION"
  log_info "Nodes: $NODES"
  log_info "Memory: ${MEMORY}MB per node"
  log_info "CPUs: $CPUS per node"
  log_info "Disk: $DISK_SIZE per node"
  log_info "Driver: $DRIVER"
  echo ""

  minikube start \
    --profile="$CLUSTER_NAME" \
    --kubernetes-version="$KUBERNETES_VERSION" \
    --nodes="$NODES" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --disk-size="$DISK_SIZE" \
    --driver="$DRIVER" \
    --addons=default-storageclass,storage-provisioner

  log_success "Cluster created"

  # Step 4: Enable addons
  log_step "4/5" "Enabling addons..."

  # Ingress addon for nginx ingress controller (kept for production parity)
  log_info "  Enabling ingress addon..."
  minikube addons enable ingress -p "$CLUSTER_NAME"

  # Ingress-DNS addon for DNS resolution of ingress hosts
  log_info "  Enabling ingress-dns addon..."
  minikube addons enable ingress-dns -p "$CLUSTER_NAME"

  # Metrics server for resource monitoring
  log_info "  Enabling metrics-server addon..."
  minikube addons enable metrics-server -p "$CLUSTER_NAME"

  log_success "Addons enabled"

  # Step 5: Verify cluster
  log_step "5/5" "Verifying cluster..."
  verify_cluster

  # Print summary
  print_summary
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

verify_cluster() {
  log_info "Waiting for cluster to be ready..."

  # Wait for nodes to be ready
  kubectl wait --for=condition=Ready node --all --timeout=120s

  # Wait for core system pods
  kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s

  log_success "Cluster is ready"

  # Show cluster info
  echo ""
  log_info "Cluster information:"
  kubectl cluster-info
  echo ""
  kubectl get nodes -o wide
}

print_summary() {
  log_section "Setup Complete"

  cat <<EOF
Minikube cluster '$CLUSTER_NAME' is ready for Argo CD upgrade demo.

CLUSTER DETAILS:
  Name:       $CLUSTER_NAME
  K8s:        $KUBERNETES_VERSION
  Nodes:      $NODES
  Memory:     ${MEMORY}MB per node
  CPUs:       $CPUS per node
  Driver:     $DRIVER

ENABLED ADDONS:
  - ingress (nginx ingress controller)
  - ingress-dns (DNS resolution for *.local domains)
  - metrics-server (resource monitoring)

NEXT STEPS:
  1. Install Argo CD v2.10.x (initial version):
     ./scripts/01-install-argocd-2.10.sh

  2. Verify installation:
     ./scripts/validate.sh

  3. Proceed with upgrades:
     ./scripts/02-upgrade-to-2.14.sh
     ./scripts/03-upgrade-to-3.0.sh
     ./scripts/04-upgrade-to-3.1.sh
     ./scripts/05-upgrade-to-3.2.1.sh

USEFUL COMMANDS:
  # Switch kubectl context to this cluster
  minikube profile $CLUSTER_NAME

  # Access Argo CD UI (run in separate terminal)
  kubectl port-forward svc/argocd-server -n argocd 8443:443

  # Open Kubernetes dashboard
  minikube dashboard -p $CLUSTER_NAME

  # Get minikube IP
  minikube ip -p $CLUSTER_NAME

  # SSH into minikube node (use -n <node-name> for specific node)
  minikube ssh -p $CLUSTER_NAME

  # Check enabled addons
  minikube addons list -p $CLUSTER_NAME

  # Stop cluster (preserve data)
  minikube stop -p $CLUSTER_NAME

  # Start stopped cluster
  minikube start -p $CLUSTER_NAME

  # Delete cluster completely
  minikube delete -p $CLUSTER_NAME

EOF
}

# ==============================================================================
# RUN
# ==============================================================================

main "$@"
