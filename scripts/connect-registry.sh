#!/bin/bash
set -euo pipefail

# Connect KinD clusters to local insecure Docker registry
# Registry: registry.macula.local:5000

REGISTRY_NAME="registry.macula.local"
REGISTRY_PORT="5000"
REGISTRY_CONTAINER="macula-registry"

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

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Connecting Clusters to Local Registry                ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Check if registry is running
if ! docker ps | grep -q "$REGISTRY_CONTAINER"; then
  log_error "Registry container '$REGISTRY_CONTAINER' is not running"
  echo "Start it with: docker start $REGISTRY_CONTAINER"
  exit 1
fi

log_info "Registry is running at $REGISTRY_NAME:$REGISTRY_PORT"

# Get all kind clusters
CLUSTERS=$(kind get clusters 2>/dev/null | grep -E "(macula-hub|be-)" || true)

if [ -z "$CLUSTERS" ]; then
  log_error "No KinD clusters found"
  exit 1
fi

echo ""
log_step "Connecting clusters to Docker network..."

# Connect registry to kind network if not already connected
if ! docker network inspect kind | grep -q "$REGISTRY_CONTAINER"; then
  docker network connect kind "$REGISTRY_CONTAINER" 2>/dev/null || true
  log_info "Registry connected to 'kind' network"
else
  log_info "Registry already connected to 'kind' network"
fi

echo ""
log_step "Configuring clusters to use insecure registry..."

# Configure each cluster
for cluster in $CLUSTERS; do
  echo ""
  log_step "Configuring cluster: $cluster"

  # Get the node name
  node_name="${cluster}-control-plane"

  # Create the directory if it doesn't exist
  docker exec "$node_name" mkdir -p "/etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}"

  # Add insecure registry configuration to containerd
  docker exec "$node_name" sh -c "cat > /etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}/hosts.toml <<EOF
server = \"http://${REGISTRY_NAME}:${REGISTRY_PORT}\"

[host.\"http://${REGISTRY_NAME}:${REGISTRY_PORT}\"]
  capabilities = [\"pull\", \"resolve\"]
  skip_verify = true
EOF"

  # Restart containerd to pick up the changes
  docker exec "$node_name" systemctl restart containerd

  log_info "Cluster $cluster configured"
done

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Registry Connection Complete                         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

log_info "All clusters can now pull from $REGISTRY_NAME:$REGISTRY_PORT"

echo ""
echo "🧪 Test with:"
echo "   kubectl --context kind-macula-hub run test --image=$REGISTRY_NAME:$REGISTRY_PORT/macula/cortex-iq-simulation:latest --rm -it -- sh"
echo ""
