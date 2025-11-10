#!/bin/bash
set -euo pipefail

# Complete deployment script for Macula on KinD
# This script deploys the entire platform from scratch

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
    log_step "Creating 5 KinD clusters..."
    "$SCRIPT_DIR/create-clusters.sh"
  fi
}

# Step 2: Deploy hub
deploy_hub() {
  log_section "Step 2: Deploying Hub (Bondy WAMP Router)"

  log_step "Applying Bondy manifests to hub cluster..."
  kubectl --context kind-macula-hub apply -k "$PROJECT_ROOT/infrastructure/gitops/kind/clusters/hub-01/bondy/"

  log_step "Waiting for Bondy to be ready..."
  kubectl --context kind-macula-hub wait --for=condition=ready pod \
    -l app=bondy -n macula-hub --timeout=120s

  log_info "Bondy is running!"
}

# Step 3: Build and load images
build_images() {
  log_section "Step 3: Building Container Images"

  log_step "This may take 10-15 minutes..."
  "$SCRIPT_DIR/build-and-load-images.sh"

  log_info "All images built and loaded!"
}

# Step 4: Deploy edge payloads
deploy_edges() {
  log_section "Step 4: Deploying Edge Payloads"

  # Edge-01: Dashboard + Postgres + Homes
  log_step "Deploying to edge-01 (Dashboard + 13 Homes)..."
  kubectl --context kind-macula-edge-01 apply -k "$PROJECT_ROOT/infrastructure/gitops/kind/clusters/edge-01/"

  # Edge-02: Homes
  log_step "Deploying to edge-02 (13 Homes)..."
  kubectl --context kind-macula-edge-02 apply -k "$PROJECT_ROOT/infrastructure/gitops/kind/clusters/edge-02/"

  # Edge-03: Utilities
  log_step "Deploying to edge-03 (5 Providers)..."
  kubectl --context kind-macula-edge-03 apply -k "$PROJECT_ROOT/infrastructure/gitops/kind/clusters/edge-03/"

  # Edge-04: Homes
  log_step "Deploying to edge-04 (11 Homes)..."
  kubectl --context kind-macula-edge-04 apply -k "$PROJECT_ROOT/infrastructure/gitops/kind/clusters/edge-04/"

  log_info "All edge payloads deployed!"
}

# Step 5: Wait for deployments
wait_for_deployments() {
  log_section "Step 5: Waiting for Pods to be Ready"

  log_step "Waiting for PostgreSQL..."
  kubectl --context kind-macula-edge-01 wait --for=condition=ready pod \
    -l app=postgres -n macula-system --timeout=120s || log_error "PostgreSQL not ready"

  log_step "Waiting for Dashboard..."
  kubectl --context kind-macula-edge-01 wait --for=condition=ready pod \
    -l app=cortex-iq-dashboard -n macula-system --timeout=180s || log_error "Dashboard not ready"

  log_step "Waiting for Homes (edge-01)..."
  kubectl --context kind-macula-edge-01 wait --for=condition=ready pod \
    -l app=cortex-iq-homes -n macula-system --timeout=120s || log_error "Homes (edge-01) not ready"

  log_step "Waiting for Homes (edge-02)..."
  kubectl --context kind-macula-edge-02 wait --for=condition=ready pod \
    -l app=cortex-iq-homes -n macula-system --timeout=120s || log_error "Homes (edge-02) not ready"

  log_step "Waiting for Utilities (edge-03)..."
  kubectl --context kind-macula-edge-03 wait --for=condition=ready pod \
    -l app=cortex-iq-utilities -n macula-system --timeout=120s || log_error "Utilities not ready"

  log_step "Waiting for Homes (edge-04)..."
  kubectl --context kind-macula-edge-04 wait --for=condition=ready pod \
    -l app=cortex-iq-homes -n macula-system --timeout=120s || log_error "Homes (edge-04) not ready"

  log_info "All pods are ready!"
}

# Step 6: Show status
show_status() {
  log_section "Deployment Complete!"

  echo ""
  log_info "Hub Status:"
  kubectl --context kind-macula-hub get pods,svc -n macula-hub

  echo ""
  log_info "Edge-01 Status (Dashboard + Homes):"
  kubectl --context kind-macula-edge-01 get pods -n macula-system

  echo ""
  log_info "Edge-02 Status (Homes):"
  kubectl --context kind-macula-edge-02 get pods -n macula-system

  echo ""
  log_info "Edge-03 Status (Utilities):"
  kubectl --context kind-macula-edge-03 get pods -n macula-system

  echo ""
  log_info "Edge-04 Status (Homes):"
  kubectl --context kind-macula-edge-04 get pods -n macula-system

  echo ""
  log_section "Access Information"
  echo ""
  echo "Dashboard URL: http://localhost:30000"
  echo "  (Port forwarding from edge-01)"
  echo ""
  echo "To access dashboard:"
  echo "  kubectl --context kind-macula-edge-01 port-forward \\"
  echo "    -n macula-system svc/cortex-iq-dashboard 4000:4000"
  echo ""
  echo "Or access via NodePort on docker network:"
  echo "  docker inspect macula-edge-01-control-plane | grep IPAddress"
  echo "  Then: http://<IP>:30000"
  echo ""
  log_info "Macula Platform is running!"
}

# Main execution
main() {
  cd "$PROJECT_ROOT"

  check_prereqs
  create_clusters
  deploy_hub
  build_images
  deploy_edges
  wait_for_deployments
  show_status
}

# Parse arguments
SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --skip-build    Skip image building (use existing images)"
      echo "  --help          Show this help message"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$SKIP_BUILD" = true ]; then
  main() {
    cd "$PROJECT_ROOT"
    check_prereqs
    create_clusters
    deploy_hub
    deploy_edges
    wait_for_deployments
    show_status
  }
fi

main
