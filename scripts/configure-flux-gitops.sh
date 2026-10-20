#!/bin/bash
set -euo pipefail

# Configure FluxCD to watch cortex-iq-deploy repository

REPO_URL="https://github.com/macula-io/cortex-iq-deploy"
REPO_BRANCH="main"

# Colors
GREEN='\033[0;32m'
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
echo "║  Configuring FluxCD GitOps                            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Get all kind clusters
CLUSTERS=$(kind get clusters 2>/dev/null | grep -E "(macula-hub|be-)" || true)

if [ -z "$CLUSTERS" ]; then
  log_error "No KinD clusters found"
  exit 1
fi

echo ""
log_info "Repository: $REPO_URL"
log_info "Branch: $REPO_BRANCH"
echo ""

# Configure each cluster
for cluster in $CLUSTERS; do
  context="kind-${cluster}"

  log_step "Configuring cluster: $cluster"

  # Determine cluster-specific path
  if [[ "$cluster" == "macula-hub" ]]; then
    CLUSTER_PATH="./clusters/macula-hub"
  elif [[ "$cluster" == "be-antwerp" ]]; then
    CLUSTER_PATH="./clusters/be-antwerp"
  elif [[ "$cluster" == "be-brabant" ]]; then
    CLUSTER_PATH="./clusters/be-brabant"
  elif [[ "$cluster" == "be-east-flanders" ]]; then
    CLUSTER_PATH="./clusters/be-east-flanders"
  else
    log_error "Unknown cluster: $cluster"
    continue
  fi

  log_step "Creating GitRepository source..."

  # Create GitRepository resource
  kubectl --context "$context" apply -f - <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: cortex-iq-deploy
  namespace: flux-system
spec:
  interval: 1m
  url: $REPO_URL
  ref:
    branch: $REPO_BRANCH
EOF

  log_step "Creating Kustomization for infrastructure..."

  # Create Kustomization for infrastructure
  kubectl --context "$context" apply -f - <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 1m
  path: $CLUSTER_PATH/infrastructure
  prune: true
  sourceRef:
    kind: GitRepository
    name: cortex-iq-deploy
EOF

  log_step "Creating Kustomization for apps..."

  # Create Kustomization for apps
  kubectl --context "$context" apply -f - <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m
  path: $CLUSTER_PATH/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: cortex-iq-deploy
  dependsOn:
  - name: infrastructure
EOF

  log_info "Cluster $cluster configured"
  echo ""
done

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  FluxCD GitOps Configuration Complete                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

log_info "All clusters are now watching: $REPO_URL"

echo ""
echo "🔍 Check status:"
echo "   flux get sources git --context kind-macula-hub"
echo "   flux get kustomizations --context kind-macula-hub"
echo ""
echo "📦 Force reconciliation:"
echo "   flux reconcile source git cortex-iq-deploy --context kind-macula-hub"
echo "   flux reconcile kustomization apps --context kind-macula-hub"
echo ""
echo "📁 Next: Create manifests in cortex-iq-deploy repository"
echo "   Structure:"
echo "   cortex-iq-deploy/"
echo "   ├── clusters/"
echo "   │   ├── macula-hub/"
echo "   │   │   ├── infrastructure/    # Gateway, PostgreSQL"
echo "   │   │   └── apps/              # Simulation, Projections, Queries, Dashboard"
echo "   │   ├── be-antwerp/apps/       # Homes, Utilities"
echo "   │   ├── be-brabant/apps/"
echo "   │   └── be-east-flanders/apps/"
echo "   └── base/                      # Shared Kustomize bases"
echo ""
