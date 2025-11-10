#!/bin/bash
set -euo pipefail

# Complete deployment script for Macula on KinD with FluxCD GitOps
# This script deploys the entire platform from scratch with full GitOps automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}✓${NC} $1"
}

log_step() {
  echo -e "${CYAN}▸${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

log_section() {
  echo ""
  echo -e "${CYAN}========================================${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}========================================${NC}"
}

# Check prerequisites
check_prereqs() {
  log_section "Checking Prerequisites"

  if ! command -v kind &> /dev/null; then
    log_error "kind is not installed"
    exit 1
  fi
  log_info "kind installed"

  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    exit 1
  fi
  log_info "kubectl installed"

  if ! command -v docker &> /dev/null; then
    log_error "docker is not installed"
    exit 1
  fi
  log_info "docker installed"
}

# Step 1: Create clusters
create_clusters() {
  log_section "Step 1: Creating KinD Clusters"

  if kind get clusters | grep -q "macula-hub"; then
    log_info "Clusters already exist, skipping creation"
  else
    log_step "Creating 5 KinD clusters (1 hub + 4 edges)..."
    "$SCRIPT_DIR/create-clusters.sh"
    log_info "All clusters created!"
  fi
}

# Step 1.5: Configure registry access
configure_registry() {
  log_section "Step 1.5: Configuring Local Registry Access"

  REGISTRY_NAME="registry.macula.local"
  REGISTRY_PORT="5000"

  log_step "Configuring containerd for HTTP registry access..."

  for cluster in macula-hub macula-edge-01 macula-edge-02 macula-edge-03 macula-edge-04; do
    log_step "Configuring $cluster..."

    # Create registry directory
    docker exec ${cluster}-control-plane mkdir -p "/etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}"

    # Create hosts.toml for registry
    docker exec ${cluster}-control-plane bash -c "cat > /etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}/hosts.toml << 'EOF'
server = \"http://${REGISTRY_NAME}:${REGISTRY_PORT}\"

[host.\"http://${REGISTRY_NAME}:${REGISTRY_PORT}\"]
  capabilities = [\"pull\", \"resolve\"]
  skip_verify = true
EOF"

    # Add config_path to containerd config
    docker exec ${cluster}-control-plane bash -c "grep -q 'config_path' /etc/containerd/config.toml || sed -i '/\[plugins.\"io.containerd.grpc.v1.cri\".registry\]/a\      config_path = \"/etc/containerd/certs.d\"' /etc/containerd/config.toml"

    # Restart containerd
    docker exec ${cluster}-control-plane systemctl restart containerd

    log_info "✓ $cluster configured for registry access"
  done

  log_info "All clusters configured for local registry!"
}

# Step 2: Setup networking and ingress
setup_networking() {
  log_section "Step 2: Setting Up Networking & Ingress"

  log_step "Installing nginx-ingress on all clusters..."

  # Install nginx-ingress on all clusters
  for cluster in macula-hub macula-edge-02 macula-edge-03 macula-edge-04; do
    log_step "Installing nginx-ingress on $cluster..."
    kubectl --context "kind-$cluster" apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  done

  log_step "Waiting for nginx-ingress to be ready..."
  sleep 10

  for cluster in macula-hub macula-edge-02 macula-edge-03 macula-edge-04; do
    kubectl --context "kind-$cluster" wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s || log_error "nginx-ingress not ready on $cluster"
  done

  log_step "Configuring nginx-ingress to allow snippet annotations..."
  for cluster in macula-hub macula-edge-02 macula-edge-03 macula-edge-04; do
    # Enable snippet annotations for Phoenix LiveView WebSocket support
    kubectl --context "kind-$cluster" patch configmap ingress-nginx-controller -n ingress-nginx \
      --type=merge -p '{"data":{"allow-snippet-annotations":"true"}}'

    # Remove admission webhook that blocks snippets
    kubectl --context "kind-$cluster" delete validatingwebhookconfiguration ingress-nginx-admission \
      --ignore-not-found=true

    log_info "Configured nginx-ingress on $cluster"
  done

  log_info "Networking configured!"
}

# Step 3: Build and load images
build_images() {
  log_section "Step 3: Building & Loading Container Images"

  log_step "This may take 10-15 minutes (building 4 images for 5 clusters)..."
  "$SCRIPT_DIR/build-and-load-images.sh"

  log_info "All images built and loaded!"
}

# Step 4: Install FluxCD
install_flux() {
  log_section "Step 4: Installing FluxCD on All Clusters"

  log_step "Installing FluxCD controllers..."
  "$PROJECT_ROOT/infrastructure/scripts/install-flux.sh"

  log_info "FluxCD installed on all clusters!"
}

# Step 5: Bootstrap GitOps
bootstrap_gitops() {
  log_section "Step 5: Bootstrapping FluxCD GitOps"

  log_step "Creating GitRepository and Kustomization resources..."
  "$PROJECT_ROOT/infrastructure/scripts/bootstrap-flux-gitops.sh"

  log_info "GitOps bootstrapped! FluxCD will now reconcile deployments."
}

# Step 6: Wait for critical deployments
wait_for_deployments() {
  log_section "Step 6: Waiting for Deployments to Reconcile"

  log_step "Waiting for FluxCD to reconcile (this may take 2-3 minutes)..."
  sleep 30

  log_step "Waiting for Bondy (Hub)..."
  kubectl --context kind-macula-hub wait --for=condition=ready pod \
    -l app=bondy -n macula-hub --timeout=180s || log_error "Bondy not ready"

  log_step "Waiting for PostgreSQL (Edge-01)..."
    -l app=postgres -n macula-system --timeout=180s || log_error "PostgreSQL not ready"

  log_step "Waiting for Dashboard (Edge-01)..."
    -l app=cortex-iq-dashboard -n macula-system --timeout=300s || log_error "Dashboard not ready"

  log_step "Waiting for Homes (Edge-01)..."
    -l app=cortex-iq-homes -n macula-system --timeout=180s || log_error "Homes (edge-01) not ready"

  log_step "Waiting for Homes (Edge-02)..."
  kubectl --context kind-macula-edge-02 wait --for=condition=ready pod \
    -l app=cortex-iq-homes -n macula-system --timeout=180s || log_error "Homes (edge-02) not ready"

  log_step "Waiting for Utilities (Edge-03)..."
  kubectl --context kind-macula-edge-03 wait --for=condition=ready pod \
    -l app=cortex-iq-utilities -n macula-system --timeout=180s || log_error "Utilities not ready"

  log_step "Waiting for Homes (Edge-04)..."
  kubectl --context kind-macula-edge-04 wait --for=condition=ready pod \
    -l app=cortex-iq-homes -n macula-system --timeout=180s || log_error "Homes (edge-04) not ready"

  log_info "All pods are ready!"
}

# Step 7: Show status and access info
show_status() {
  log_section "Deployment Complete!"

  echo ""
  log_info "Hub Status (Bondy WAMP Router):"
  kubectl --context kind-macula-hub get pods,svc -n macula-hub

  echo ""
  log_info "Edge-01 Status (Dashboard + PostgreSQL + 13 Homes):"

  echo ""
  log_info "Edge-02 Status (13 Homes):"
  kubectl --context kind-macula-edge-02 get pods -n macula-system

  echo ""
  log_info "Edge-03 Status (5 Providers):"
  kubectl --context kind-macula-edge-03 get pods -n macula-system

  echo ""
  log_info "Edge-04 Status (11 Homes):"
  kubectl --context kind-macula-edge-04 get pods -n macula-system

  echo ""
  log_section "Access Information"
  echo ""
  echo -e "${GREEN}CortexIQ Dashboard:${NC} http://dashboard.cortexiq.local:8080/"
  echo -e "${GREEN}Bondy Admin API:${NC} http://hub.macula.local:8080/admin/"
  echo -e "${GREEN}Bondy Console:${NC} http://console.macula.local:8080/"
  echo ""
  echo -e "${YELLOW}Note:${NC} Make sure /etc/hosts has entries for *.macula.local and *.cortexiq.local"
  echo "Run: sudo ./infrastructure/scripts/setup-hosts.sh"
  echo ""

  log_section "FluxCD Status"
  echo ""
  echo "Check FluxCD resources:"
  echo "  kubectl --context kind-macula-hub get gitrepositories -A"
  echo ""
  echo "Watch FluxCD controller logs:"
  echo ""

  log_info "Macula Platform is running with GitOps! 🚀"
  echo ""
  echo -e "${CYAN}Demo Ready:${NC}"
  echo "  - 37 Homes simulating energy production/consumption"
  echo "  - 5 Providers competing with dynamic pricing strategies"
  echo "  - Real-time Dashboard showing market dynamics"
  echo "  - FluxCD ensuring continuous reconciliation"
}

# Main execution
main() {
  cd "$PROJECT_ROOT"

  echo ""
  echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║   Macula Platform - Complete Deployment          ║${NC}"
  echo -e "${CYAN}║   KinD + FluxCD + GitOps                          ║${NC}"
  echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
  echo ""

  check_prereqs
  create_clusters
  configure_registry
  setup_networking
  build_images
  install_flux
  bootstrap_gitops
  wait_for_deployments
  show_status
}

main "$@"
