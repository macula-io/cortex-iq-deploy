#!/bin/bash
# Check status of all Macula KinD clusters

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Macula KinD Clusters Status ===${NC}\n"

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}✗${NC} kind is not installed"
    exit 1
fi

# List clusters
echo -e "${CYAN}Clusters:${NC}"
kind get clusters | while read cluster; do
    if [[ "$cluster" == macula-* ]]; then
        echo -e "  ${GREEN}✓${NC} $cluster"
    fi
done

echo ""
echo -e "${CYAN}Hub Cluster (macula-hub):${NC}"
if kind get clusters | grep -q "macula-hub"; then
    echo -e "  ${GREEN}✓${NC} Cluster running"

    # Check pods
    kubectl --context kind-macula-hub get pods -n macula-hub 2>/dev/null && echo -e "  ${GREEN}✓${NC} Pods deployed" || echo -e "  ${YELLOW}⚠${NC} No pods in macula-hub namespace"
else
    echo -e "  ${RED}✗${NC} Cluster not found"
fi

echo ""
echo -e "${CYAN}Edge Clusters:${NC}"
for i in {1..4}; do
    cluster="macula-edge-0${i}"
    if kind get clusters | grep -q "$cluster"; then
        echo -e "  ${GREEN}✓${NC} $cluster"

        # Check if FluxCD is installed
        kubectl --context kind-$cluster get pods -n flux-system 2>/dev/null > /dev/null && \
            echo -e "    ${GREEN}✓${NC} FluxCD installed" || \
            echo -e "    ${YELLOW}⚠${NC} FluxCD not installed"

        # Check payloads
        kubectl --context kind-$cluster get pods -n macula-system 2>/dev/null > /dev/null && \
            echo -e "    ${GREEN}✓${NC} Payloads deployed" || \
            echo -e "    ${YELLOW}⚠${NC} No payloads deployed"
    else
        echo -e "  ${RED}✗${NC} $cluster not found"
    fi
done

echo ""
echo -e "${CYAN}Access Commands:${NC}"
echo "  Hub dashboard:  kubectl --context kind-macula-hub port-forward -n macula-hub svc/dashboard 4000:4000"
echo "  Hub logs:       kubectl --context kind-macula-hub logs -n macula-hub -l app=bondy -f"
echo "  Edge-01 pods:   kubectl --context kind-macula-edge-01 get pods -n macula-system"
