#!/bin/bash
set -euo pipefail

# Create all Macula KinD clusters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}✓${NC} $1"
}

log_step() {
  echo -e "${CYAN}▸${NC} $1"
}

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed"
    echo "Install with: curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"
    exit 1
fi

# Create hub cluster
log_step "Creating hub cluster (macula-hub)..."
cat <<EOF | kind create cluster --name macula-hub --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  - containerPort: 30081
    hostPort: 30081
    protocol: TCP
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
EOF
log_info "Hub cluster created"

# Create edge clusters
for i in {1..4}; do
  cluster_name="macula-edge-0${i}"
  log_step "Creating edge cluster ($cluster_name)..."

  cat <<EOF | kind create cluster --name "$cluster_name" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
EOF

  log_info "Edge cluster $cluster_name created"
done

echo ""
log_info "All clusters created!"
echo ""
echo "Clusters:"
kind get clusters

echo ""
echo "Contexts:"
kubectl config get-contexts | grep kind-macula

echo ""
echo "Next steps:"
echo "  1. Deploy hub: kubectl --context kind-macula-hub apply -k ../gitops/kind/hub/"
echo "  2. Bootstrap edges: ./bootstrap-flux.sh edge-01"
echo "  3. Check status: ./status.sh"
