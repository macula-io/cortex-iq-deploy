# cortex-iq-deploy

GitOps Deployment Repository for CortexIQ on Macula Mesh - KinD Clusters

## Overview

This repository contains GitOps deployment configurations for CortexIQ running on the Macula Mesh platform with HTTP/3 (QUIC) transport.

**Deployment Target**: Local KinD (Kubernetes in Docker) clusters
- **Hub Cluster**: `macula-hub` - Centralized services
- **Edge Clusters**: `be-antwerp`, `be-brabant`, `be-east-flanders` - Regional workloads

All deployments are managed via **FluxCD** - changes to this repository automatically sync to clusters.

## Repository Structure

```
cortex-iq-deploy/
├── ARCHITECTURE.md              # Complete architecture documentation
├── README.md                    # This file
├── clusters/                    # Cluster-specific manifests
│   ├── macula-hub/
│   │   ├── flux-system/         # Flux installation (auto-generated)
│   │   ├── infrastructure/      # Gateway, PostgreSQL
│   │   └── apps/                # Hub applications
│   ├── be-antwerp/
│   │   ├── flux-system/
│   │   ├── infrastructure/      # Gateway
│   │   └── apps/                # Edge applications
│   ├── be-brabant/
│   │   ├── flux-system/
│   │   ├── infrastructure/
│   │   └── apps/
│   └── be-east-flanders/
│       ├── flux-system/
│       ├── infrastructure/
│       └── apps/
└── base/                        # Shared Kustomize bases
    ├── macula-gateway/
    ├── postgres/
    ├── cortex-iq-simulation/
    ├── cortex-iq-homes/
    ├── cortex-iq-utilities/
    ├── cortex-iq-projections/
    ├── cortex-iq-queries/
    └── cortex-iq-dashboard/
```

## Quick Start

All infrastructure scripts are in the `scripts/` directory of this repository.

### 1. Create Clusters

```bash
cd scripts/

# Create 4 KinD clusters (macula-hub + 3 Belgian regions)
./create-belgian-clusters.sh

# Configure insecure registry access
./connect-registry.sh

# Install FluxCD on all clusters
./install-flux.sh
```

### 2. Configure GitOps

```bash
# Configure FluxCD to watch this repository
./configure-flux-gitops.sh
```

This creates GitRepository and Kustomization resources in each cluster pointing to this repo.

### 3. Deploy Applications

**Option A: Via GitOps (recommended)**

1. Add Kubernetes manifests to this repository under `clusters/[cluster-name]/`
2. Commit and push to GitHub
3. FluxCD automatically reconciles (within 1 minute)

**Option B: Force immediate reconciliation**

```bash
# After pushing changes
flux reconcile source git cortex-iq-deploy --context kind-macula-hub
flux reconcile kustomization apps --context kind-macula-hub
```

## GitOps Workflow

### Building and Pushing Images

```bash
# From macula-energy-mesh-poc/
cd system/cortex_iq_[app]/

# Build with cache bust
docker build --build-arg CACHE_BUST=$(date +%s) -t macula/cortex-iq-[app]:latest .

# Tag for local registry
docker tag macula/cortex-iq-[app]:latest registry.macula.local:5000/macula/cortex-iq-[app]:latest

# Push to registry
docker push registry.macula.local:5000/macula/cortex-iq-[app]:latest
```

### Deploying Changes

1. **Build and push images** (see above)
2. **Update manifests** in this repo (if needed)
3. **Commit and push** to GitHub
4. **Wait for Flux** to reconcile (1 minute)
5. **Or force reconciliation** with `flux reconcile`

**Important**: Never use `kubectl apply` or `kind load docker-image` directly. All deployments go through GitOps.

## Architecture

See `ARCHITECTURE.md` for complete details.

### Hub Cluster (macula-hub)

```
┌──────────────────────────────────────────┐
│  macula-hub                              │
│                                          │
│  Macula Gateway (port 30080)            │
│              ↕                           │
│  ┌──────┬────┴────┬─────┬─────┐         │
│  │      │         │     │     │         │
│  Sim  Proj    Queries Dash  DB         │
└──────────────────────────────────────────┘
```

**Hub Applications**:
- cortex_iq_simulation - Simulation clock
- cortex_iq_projections - Event processing
- cortex_iq_queries - RPC query handlers
- cortex_iq_dashboard - Phoenix web UI
- postgresql - Database

### Edge Clusters (be-antwerp, be-brabant, be-east-flanders)

```
┌──────────────────────────────┐
│  Edge Cluster                │
│                              │
│  Macula Gateway (port 9443)  │
│              ↕               │
│  ┌───────────┴───────┐       │
│  │                   │       │
│  Homes           Utilities   │
└──────────────────────────────┘
```

**Edge Applications**:
- cortex_iq_homes - Home simulation bots
- cortex_iq_utilities - Provider simulation bots

### Multi-Cluster Connectivity

```
       macula-hub (Hub)
       ┌─────────────┐
       │   Gateway   │
       └──────┬──────┘
              │ Mesh (QUIC)
       ┌──────┼──────┐
       │      │      │
    ┌──▼──┐ ┌▼───┐ ┌▼────┐
    │Ant- │ │Bra-│ │EFL  │
    │werp │ │bant│ │     │
    └─────┘ └────┘ └─────┘
```

## Components

### Infrastructure

- **Macula Gateway Service** - HTTP/3 (QUIC) gateway (one per cluster)
  - Image: `registry.macula.local:5000/macula/macula-gateway-service:latest`
  - Port: 9443 (internal), 30080 (hub host)
  - Realm: `be.cortexiq.energy`

- **PostgreSQL** (hub only) - Database for read models
  - Image: `postgres:16-alpine`
  - Port: 5432
  - Database: `cortex_iq_dashboard`

### Applications

All apps connect to local gateway via `MACULA_URL` and `MACULA_REALM` environment variables.

**Hub Apps**:
- **cortex_iq_simulation** - Broadcasts simulation time
- **cortex_iq_projections** - Subscribes to events, updates DB
- **cortex_iq_queries** - RPC procedures for read models
- **cortex_iq_dashboard** - Phoenix LiveView web interface

**Edge Apps**:
- **cortex_iq_homes** - Home bots with solar/battery/contracts
- **cortex_iq_utilities** - Provider bots with pricing strategies

## Accessing Services

### Dashboard

```bash
# Via host port mapping (macula-hub)
http://localhost:30000

# Or via /etc/hosts (add: 127.0.0.1  dashboard.cortexiq.local)
http://dashboard.cortexiq.local
```

### Macula Gateway (Hub)

```bash
# QUIC on UDP port 30080
https://localhost:30080
```

### PostgreSQL

```bash
# Via port-forward
kubectl --context kind-macula-hub port-forward -n cortex-iq svc/postgres 5432:5432
psql -h localhost -U postgres -d cortex_iq_dashboard
```

## FluxCD Commands

### Check Status

```bash
# Overall status
flux check --context kind-macula-hub

# Git sources
flux get sources git --context kind-macula-hub

# Kustomizations
flux get kustomizations --context kind-macula-hub

# Logs
flux logs --context kind-macula-hub
```

### Force Reconciliation

```bash
# Reconcile Git source
flux reconcile source git cortex-iq-deploy --context kind-macula-hub

# Reconcile infrastructure
flux reconcile kustomization infrastructure --context kind-macula-hub

# Reconcile apps
flux reconcile kustomization apps --context kind-macula-hub
```

### Suspend/Resume

```bash
# Suspend automatic reconciliation
flux suspend kustomization apps --context kind-macula-hub

# Resume
flux resume kustomization apps --context kind-macula-hub
```

## Troubleshooting

### Flux Not Reconciling

```bash
# Check Git source status
flux get sources git cortex-iq-deploy --context kind-macula-hub

# Check Kustomization status
flux get kustomizations --context kind-macula-hub

# View logs
flux logs --context kind-macula-hub --follow

# Force reconciliation
flux reconcile source git cortex-iq-deploy --context kind-macula-hub
```

### Pods Not Starting

```bash
# Check pod status
kubectl --context kind-macula-hub get pods -n cortex-iq

# Describe pod
kubectl --context kind-macula-hub describe pod <pod-name> -n cortex-iq

# View logs
kubectl --context kind-macula-hub logs <pod-name> -n cortex-iq

# Check events
kubectl --context kind-macula-hub get events -n cortex-iq --sort-by='.lastTimestamp'
```

### Images Not Pulling

```bash
# Check registry connectivity
docker exec macula-hub-control-plane curl -v http://registry.macula.local:5000/v2/

# Check containerd config
docker exec macula-hub-control-plane cat /etc/containerd/certs.d/registry.macula.local:5000/hosts.toml

# Re-run registry connection script
cd macula-energy-mesh-poc/infrastructure/kind/
./connect-registry.sh
```

## Key Differences from Old Architecture

**Removed**:
- ❌ Bondy (WAMP router)
- ❌ MaculaOs sidecar containers
- ❌ API key secrets per app
- ❌ Complex Bondy configuration
- ❌ Manual kubectl deployments

**Added**:
- ✅ Macula Gateway (HTTP/3/QUIC)
- ✅ Simplified client connections
- ✅ FluxCD GitOps workflow
- ✅ KinD multi-cluster setup
- ✅ Local insecure Docker registry
- ✅ Automatic reconciliation from Git

**Configuration Changes**:
- **Before**: `BONDY_URL`, `BONDY_REALM`, `BONDY_ADMIN_URL`
- **After**: `MACULA_URL`, `MACULA_REALM`

## Documentation

**Project Documentation:**
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Complete architecture and mesh topology
- [DNS_STRATEGY.md](./DNS_STRATEGY.md) - DNS resolution strategy for KinD and beam clusters
- [base/observability/README.md](./base/observability/README.md) - Prometheus + Grafana monitoring
- [base/registry/README.md](./base/registry/README.md) - Local Docker registry setup

**External References:**
- **FluxCD**: https://fluxcd.io/
- **KinD**: https://kind.sigs.k8s.io/
- **Kustomize**: https://kustomize.io/
- **Source Code**: https://github.com/macula-io/macula-energy-mesh-poc
- **Infrastructure Scripts**: `scripts/` (in this repo)

## Next Steps

1. ✅ Create KinD clusters - **DONE**
2. ✅ Configure insecure registry - **DONE**
3. ✅ Install FluxCD - **DONE**
4. ✅ Configure GitOps - **DONE**
5. 🔄 Create Kubernetes manifests in this repo
6. ⏳ Build and push Docker images
7. ⏳ Test deployment via GitOps
8. ⏳ Access dashboard and verify functionality
