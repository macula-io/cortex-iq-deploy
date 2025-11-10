#!/bin/bash
set -euo pipefail

# Install FluxCD on KinD clusters

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

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Installing FluxCD on Clusters                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    log_error "flux CLI is not installed"
    echo ""
    echo "Install with:"
    echo "  curl -s https://fluxcd.io/install.sh | sudo bash"
    echo ""
    exit 1
fi

log_info "flux CLI is installed: $(flux --version | head -1)"

# Get all kind clusters
CLUSTERS=$(kind get clusters 2>/dev/null | grep -E "(macula-hub|be-)" || true)

if [ -z "$CLUSTERS" ]; then
  log_error "No KinD clusters found"
  exit 1
fi

echo ""

# Install Flux on each cluster
for cluster in $CLUSTERS; do
  context="kind-${cluster}"

  log_step "Installing Flux on cluster: $cluster"

  # Check if already installed
  if kubectl --context "$context" get ns flux-system &>/dev/null; then
    log_warning "Flux already installed on $cluster, skipping..."
    continue
  fi

  # Pre-check
  log_step "Running pre-installation checks..."
  if ! flux check --context "$context" --pre; then
    log_error "Pre-installation checks failed for $cluster"
    continue
  fi

  # Install Flux
  log_step "Installing Flux components..."
  flux install --context "$context" \
    --components=source-controller,kustomize-controller,helm-controller,notification-controller \
    --network-policy=false \
    --toleration-keys=node-role.kubernetes.io/control-plane

  log_info "Flux installed on $cluster"

  # Wait for Flux to be ready
  log_step "Waiting for Flux to be ready..."
  kubectl --context "$context" -n flux-system wait --for=condition=ready pod --all --timeout=2m

  log_info "Flux is ready on $cluster"
  echo ""
done

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  FluxCD Installation Complete                         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Installed on:"
for cluster in $CLUSTERS; do
  context="kind-${cluster}"
  echo "  • $cluster"
done

echo ""
echo "🔍 Check status:"
echo "   flux check --context kind-macula-hub"
echo "   flux check --context kind-be-antwerp"
echo ""
echo "📦 Next: Create GitRepository and Kustomization resources to deploy apps"
echo ""
