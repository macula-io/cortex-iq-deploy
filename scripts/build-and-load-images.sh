#!/bin/bash
set -euo pipefail

# Build and load container images into KinD clusters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Build MaculaOs sidecar image (needed by all payloads)
log_step "Building macula-os image..."
docker build \
  -f "$PROJECT_ROOT/system/macula_os/Dockerfile" \
  -t macula/macula-os:latest \
  "$PROJECT_ROOT/system"
log_info "MaculaOs image built"

# Build homes image
log_step "Building cortex-iq-homes image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_homes/Dockerfile" \
  -t macula/cortex-iq-homes:latest \
  "$PROJECT_ROOT/system"
log_info "Homes image built"

# Build utilities image
log_step "Building cortex-iq-utilities image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_utilities/Dockerfile" \
  -t macula/cortex-iq-utilities:latest \
  "$PROJECT_ROOT/system"
log_info "Utilities image built"

# Build simulation image
log_step "Building cortex-iq-simulation image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_simulation/Dockerfile" \
  -t macula/cortex-iq-simulation:latest \
  "$PROJECT_ROOT/system"
log_info "Simulation image built"

# Build dashboard image using Dockerfile.hub
log_step "Building cortex-iq-dashboard image..."
docker build \
  -f "$PROJECT_ROOT/Dockerfile.hub" \
  -t macula/cortex-iq-dashboard:latest \
  "$PROJECT_ROOT"
log_info "Dashboard image built"

# Build projections image
log_step "Building cortex-iq-projections image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_projections/Dockerfile" \
  -t macula/cortex-iq-projections:latest \
  "$PROJECT_ROOT/system"
log_info "Projections image built"

# Build queries image
log_step "Building cortex-iq-queries image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_queries/Dockerfile" \
  -t macula/cortex-iq-queries:latest \
  "$PROJECT_ROOT/system"
log_info "Queries image built"

# Load images into KinD clusters
log_step "Loading images into KinD clusters..."

# Load MaculaOs sidecar into ALL edge clusters (needed by all payloads)
log_step "Loading macula-os image into all edge clusters..."
kind load docker-image macula/macula-os:latest --name macula-edge-01
kind load docker-image macula/macula-os:latest --name macula-edge-02
kind load docker-image macula/macula-os:latest --name macula-edge-03
kind load docker-image macula/macula-os:latest --name macula-edge-04
log_info "MaculaOs image loaded into all edge clusters"

# Load simulation into macula-hub (simulation infrastructure)
log_step "Loading simulation image into macula-hub..."
kind load docker-image macula/cortex-iq-simulation:latest --name macula-hub
log_info "Simulation image loaded into hub"

# Load projections into macula-hub (CQRS write-side service)
log_step "Loading projections image into macula-hub..."
kind load docker-image macula/cortex-iq-projections:latest --name macula-hub
log_info "Projections image loaded into hub"

# Load queries into macula-hub (CQRS read-side service)
log_step "Loading queries image into macula-hub..."
kind load docker-image macula/cortex-iq-queries:latest --name macula-hub
log_info "Queries image loaded into hub"

# Load dashboard into macula-hub (where dashboard will run alongside Bondy)
log_step "Loading dashboard image into macula-hub..."
kind load docker-image macula/cortex-iq-dashboard:latest --name macula-hub
log_info "Dashboard image loaded into hub"

# Load homes into edge-01, edge-02, and edge-04
log_step "Loading homes image into macula-edge-01, edge-02, and edge-04..."
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-01
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-02
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-04
log_info "Homes image loaded into edge-01, edge-02, and edge-04"

# Load utilities into edge-02
log_step "Loading utilities image into macula-edge-02..."
kind load docker-image macula/cortex-iq-utilities:latest --name macula-edge-02
log_info "Utilities image loaded into edge-02"

echo ""
log_info "All images built and loaded!"
echo ""
echo "Images:"
echo "  - macula/macula-os:latest (sidecar, loaded into edge-01, edge-02, edge-03, edge-04)"
echo "  - macula/cortex-iq-simulation:latest (loaded into hub)"
echo "  - macula/cortex-iq-projections:latest (loaded into hub)"
echo "  - macula/cortex-iq-dashboard:latest (loaded into hub)"
echo "  - macula/cortex-iq-homes:latest (loaded into edge-01, edge-02, edge-04)"
echo "  - macula/cortex-iq-utilities:latest (loaded into edge-02)"
