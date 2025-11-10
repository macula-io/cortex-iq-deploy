#!/bin/bash
set -euo pipefail

# Create Belgian region KinD clusters for Macula Platform
# Regions: Antwerp, Brabant, East Flanders

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    log_error "kind is not installed"
    echo "Install with: curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"
    exit 1
fi

# Belgian regions configuration
declare -A REGIONS=(
  ["antwerp"]="be-antwerp"
  ["brabant"]="be-brabant"
  ["east-flanders"]="be-east-flanders"
)

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Creating Macula Belgian Region Clusters              ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Create hub cluster first
log_step "Creating hub cluster (macula-hub)..."
if kind get clusters | grep -q "^macula-hub$"; then
  log_info "Hub cluster already exists, skipping..."
else
  cat <<EOF | kind create cluster --name macula-hub --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  # Bondy WAMP WebSocket
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  # Bondy Admin API
  - containerPort: 30081
    hostPort: 30081
    protocol: TCP
  # Dashboard
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
EOF
  log_info "Hub cluster created"
fi

echo ""

# Create regional edge clusters
for region in "${!REGIONS[@]}"; do
  cluster_name="${REGIONS[$region]}"

  log_step "Creating edge cluster for $region ($cluster_name)..."

  if kind get clusters | grep -q "^${cluster_name}$"; then
    log_info "Cluster $cluster_name already exists, skipping..."
    continue
  fi

  cat <<EOF | kind create cluster --name "$cluster_name" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  labels:
    region: $region
    country: belgium
EOF

  log_info "Cluster $cluster_name created"
done

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Cluster Creation Complete                            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Clusters:"
kind get clusters | grep -E "(macula-hub|be-)"

echo ""
echo "🔧 Contexts:"
kubectl config get-contexts | grep -E "(kind-macula-hub|kind-be-)" | awk '{print $2}'

echo ""
echo "📍 Regional Setup:"
echo "  • Hub:            macula-hub"
echo "  • Antwerp:        be-antwerp"
echo "  • Brabant:        be-brabant"
echo "  • East Flanders:  be-east-flanders"

echo ""
echo "🚀 Next Steps:"
echo "  1. Connect clusters to local registry:"
echo "     ./connect-registry.sh"
echo ""
echo "  2. Deploy to hub:"
echo "     kubectl --context kind-macula-hub apply -k ../manifests/hub/"
echo ""
echo "  3. Deploy to regions:"
echo "     kubectl --context kind-be-antwerp apply -k ../manifests/edge/"
echo "     kubectl --context kind-be-brabant apply -k ../manifests/edge/"
echo "     kubectl --context kind-be-east-flanders apply -k ../manifests/edge/"
echo ""
