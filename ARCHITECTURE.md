# CortexIQ Deployment Architecture - KinD Clusters

This document describes the deployment architecture for CortexIQ on local KinD (Kubernetes in Docker) clusters using GitOps with FluxCD.

## Overview

CortexIQ is deployed across 4 KinD clusters representing a hub-and-spoke topology:
- **1 Hub Cluster**: `macula-hub` (centralized services: Dashboard, Projections, Queries, Simulation)
- **3 Edge Clusters**: Belgian regions running distributed edge workloads (Homes, Utilities)
  - `be-antwerp` - Antwerp region
  - `be-brabant` - Brabant region
  - `be-east-flanders` - East Flanders region

All clusters use **FluxCD** for GitOps-based continuous deployment from this repository (`cortex-iq-deploy`).

The architecture uses HTTP/3 (QUIC) transport via Macula Gateway. Each cluster has a single gateway process that all applications connect to as clients.

## Cluster Infrastructure

### Local Development Setup (KinD)

**Registry**:
- URL: `registry.macula.local:5000`
- Container: `macula-registry`
- Connected to `kind` Docker network
- Configured as insecure registry in all clusters

**Cluster Contexts**:
```bash
kind-macula-hub            # Hub cluster
kind-be-antwerp            # Antwerp edge cluster
kind-be-brabant            # Brabant edge cluster
kind-be-east-flanders      # East Flanders edge cluster
```

**Port Mappings (macula-hub only)**:
- 30000 → Dashboard web interface
- 30080 → Macula Gateway (QUIC/HTTP3)
- 30081 → Macula Admin API

**Scripts** (in cortex-iq-deploy/scripts/):
- `create-belgian-clusters.sh` - Create all 4 clusters
- `connect-registry.sh` - Configure insecure registry access
- `install-flux.sh` - Install FluxCD on all clusters
- `configure-flux-gitops.sh` - Configure GitOps to watch this repository

## GitOps Workflow

All deployments are managed through this repository using **FluxCD**.

### Repository Structure

```
cortex-iq-deploy/
├── clusters/
│   ├── macula-hub/
│   │   ├── flux-system/          # Flux installation
│   │   ├── infrastructure/       # Gateway, PostgreSQL
│   │   └── apps/                 # Hub applications
│   ├── be-antwerp/
│   │   ├── flux-system/
│   │   ├── infrastructure/
│   │   └── apps/
│   ├── be-brabant/
│   │   ├── flux-system/
│   │   ├── infrastructure/
│   │   └── apps/
│   └── be-east-flanders/
│       ├── flux-system/
│       ├── infrastructure/
│       └── apps/
├── base/                         # Shared Kustomize bases
│   ├── macula-gateway/
│   ├── postgres/
│   ├── cortex-iq-simulation/
│   ├── cortex-iq-homes/
│   ├── cortex-iq-utilities/
│   ├── cortex-iq-projections/
│   ├── cortex-iq-queries/
│   └── cortex-iq-dashboard/
└── ARCHITECTURE.md               # This file
```

### Deployment Process

**GitOps Flow**:
1. Build Docker image: `docker build --build-arg CACHE_BUST=$(date +%s) -t macula/[app]:latest .`
2. Tag for registry: `docker tag macula/[app]:latest registry.macula.local:5000/macula/[app]:latest`
3. Push to registry: `docker push registry.macula.local:5000/macula/[app]:latest`
4. Update manifests in this repo (if needed)
5. Commit and push to Git
6. FluxCD automatically reconciles clusters (every 1 minute by default)

**Manual Reconciliation** (for immediate deployment):
```bash
flux reconcile source git flux-system --context kind-macula-hub
flux reconcile kustomization apps --context kind-macula-hub
```

**Force Pod Restart** (if image tag unchanged):
```bash
kubectl --context kind-macula-hub delete pods -n cortex-iq -l app=cortex-iq-dashboard
```

## Architecture Diagram

### Hub Cluster (macula-hub)

```
┌──────────────────────────────────────────────────────────────┐
│  macula-hub Cluster (KinD)                                   │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Macula Gateway Service                                 │  │
│  │  - Port: 9443 (internal), 30080 (host)                 │  │
│  │  - Realm: be.cortexiq.energy                           │  │
│  │  - Image: registry.macula.local:5000/macula/           │  │
│  │           macula-gateway-service:latest                │  │
│  └─────────────────┬──────────────────────────────────────┘  │
│                    │                                          │
│        ┌───────────┼──────────┬────────────┬──────────┐      │
│        │           │          │            │          │      │
│        ▼           ▼          ▼            ▼          ▼      │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────┐              │
│  │ Simul-  │ │Projec-  │ │Queries  │ │Dash- │              │
│  │ ation   │ │ tions   │ │         │ │board │              │
│  └─────────┘ └─────────┘ └─────────┘ └──────┘              │
│                                          │                    │
│  ┌───────────────────────────────────────┘                   │
│  │                                                            │
│  ▼                                                            │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ PostgreSQL                                               │  │
│  │ - Port: 5432                                            │  │
│  │ - Database: cortex_iq_dashboard                         │  │
│  └─────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Edge Clusters (be-antwerp, be-brabant, be-east-flanders)

```
┌──────────────────────────────────────────────────────────────┐
│  Edge Cluster (KinD)                                         │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Macula Gateway Service                                 │  │
│  │  - Port: 9443                                           │  │
│  │  - Realm: be.cortexiq.energy                           │  │
│  │  - Image: registry.macula.local:5000/macula/           │  │
│  │           macula-gateway-service:latest                │  │
│  │  - Connects to hub gateway for mesh                    │  │
│  └─────────────────┬──────────────────────────────────────┘  │
│                    │                                          │
│        ┌───────────┴──────────┐                               │
│        │                      │                               │
│        ▼                      ▼                               │
│  ┌─────────┐           ┌─────────┐                           │
│  │ Homes   │           │Utilities│                           │
│  │         │           │         │                           │
│  └─────────┘           └─────────┘                           │
└──────────────────────────────────────────────────────────────┘
```

## Components

### Infrastructure Components

#### 1. Macula Gateway Service (Required - All Clusters)

**Image**: `registry.macula.local:5000/macula/macula-gateway-service:latest`

**Purpose**: Gateway that all applications connect to for pub/sub and RPC

**Environment Variables**:
- `MACULA_GATEWAY_PORT=9443` - Port to listen on
- `MACULA_REALM=be.cortexiq.energy` - Realm name
- `HUB_GATEWAY_URL` (edge only) - URL to hub gateway for mesh connectivity

**Deployment**:
- Hub: Standalone gateway, accepts edge connections
- Edge: Gateway that connects to hub for inter-cluster communication

#### 2. PostgreSQL (Hub Only)

**Image**: `postgres:16-alpine`

**Purpose**: Persistent storage for read models (Projections, Queries, Dashboard)

**Database**: `cortex_iq_dashboard`
**Port**: 5432
**Credentials**: Managed via Kubernetes Secret

### Application Components

All applications connect to their local gateway with these common environment variables:
- `MACULA_URL=https://macula-gateway-service:9443` (or local gateway service name)
- `MACULA_REALM=be.cortexiq.energy`

#### Hub Applications (macula-hub)

1. **cortex_iq_simulation** - Simulation clock and control
   - Image: `registry.macula.local:5000/macula/cortex-iq-simulation:latest`
   - Broadcasts simulation time events
   - ENV: `SIMULATION_SPEED`, `SIMULATION_START_DATE`

2. **cortex_iq_projections** - Event processing to read models
   - Image: `registry.macula.local:5000/macula/cortex-iq-projections:latest`
   - Subscribes to all events
   - Updates PostgreSQL read models
   - ENV: `DATABASE_URL`

3. **cortex_iq_queries** - RPC query handlers
   - Image: `registry.macula.local:5000/macula/cortex-iq-queries:latest`
   - Registers RPC procedures
   - Reads from PostgreSQL
   - ENV: `DATABASE_URL`

4. **cortex_iq_dashboard** - Phoenix LiveView web interface
   - Image: `registry.macula.local:5000/macula/cortex-iq-dashboard:latest`
   - Phoenix web server with LiveView
   - Connects to Queries (RPC) and Gateway (events)
   - Port: 4000 (internal), 30000 (host)
   - ENV: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`

#### Edge Applications (be-antwerp, be-brabant, be-east-flanders)

1. **cortex_iq_homes** - Home bots with solar/battery
   - Image: `registry.macula.local:5000/macula/cortex-iq-homes:latest`
   - Simulates homes in region
   - ENV: `HOMES_SOURCES` (JSON config files)

2. **cortex_iq_utilities** - Energy provider bots
   - Image: `registry.macula.local:5000/macula/cortex-iq-utilities:latest`
   - Simulates energy providers
   - ENV: `PROVIDERS_COUNT`, pricing strategy configs

## Environment Variables Reference

### Common (All Apps)
- `MACULA_URL` - Gateway URL (e.g., `https://macula-gateway-service:9443`)
- `MACULA_REALM` - Realm name (e.g., `be.cortexiq.energy`)

### Gateway Specific
- `MACULA_GATEWAY_PORT` - Port to listen on (default: 9443)
- `MACULA_REALM` - Realm name
- `HUB_GATEWAY_URL` (edge only) - Hub gateway URL for mesh

### Simulation Specific
- `SIMULATION_SPEED` - Time acceleration (default: 105120 = 1 year in 5 min)
- `SIMULATION_START_DATE` - Start date for simulation

### Homes Specific
- `HOMES_SOURCES` - Comma-separated JSON files with home configs

### Utilities Specific
- `PROVIDERS_COUNT` - Number of provider bots to spawn

### Dashboard/Projections/Queries
- `DATABASE_URL` - PostgreSQL connection (e.g., `ecto://postgres:postgres@postgres:5432/cortex_iq_dashboard`)
- `SECRET_KEY_BASE` - Phoenix secret (dashboard only)
- `PHX_HOST` - Phoenix host (dashboard only, default: `dashboard.cortexiq.local`)

## Deployment Order

### Hub Cluster (macula-hub)

1. **PostgreSQL** - Deploy database (wait for ready)
2. **Macula Gateway** - Deploy gateway service (wait for ready)
3. **Hub Applications** (can deploy in parallel):
   - cortex_iq_simulation
   - cortex_iq_projections
   - cortex_iq_queries
   - cortex_iq_dashboard

### Edge Clusters (be-antwerp, be-brabant, be-east-flanders)

1. **Macula Gateway** - Deploy gateway service connected to hub (wait for ready)
2. **Edge Applications** (can deploy in parallel):
   - cortex_iq_homes
   - cortex_iq_utilities

## FluxCD Configuration

Each cluster has FluxCD configured to watch this repository for changes.

### Flux Installation

```bash
# Install Flux on all clusters (already done via install-flux.sh)
flux check --context kind-macula-hub
flux check --context kind-be-antwerp
flux check --context kind-be-brabant
flux check --context kind-be-east-flanders
```

### GitRepository Source

Each cluster has a GitRepository resource pointing to this repo:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: cortex-iq-deploy
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/macula-io/cortex-iq-deploy
  ref:
    branch: main
```

### Kustomization Resources

Each cluster watches its own directory in this repo:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 1m
  path: ./clusters/macula-hub/infrastructure
  prune: true
  sourceRef:
    kind: GitRepository
    name: cortex-iq-deploy
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m
  path: ./clusters/macula-hub/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: cortex-iq-deploy
  dependsOn:
  - name: infrastructure
```

## Accessing Services

### Dashboard

**Local Development**:
- Via port forward: http://localhost:30000 (macula-hub)
- Via /etc/hosts: http://dashboard.cortexiq.local (mapped to 127.0.0.1:30000)

```bash
# Add to /etc/hosts:
127.0.0.1  dashboard.cortexiq.local

# Or use port-forward:
kubectl --context kind-macula-hub port-forward -n cortex-iq svc/cortex-iq-dashboard 30000:4000
```

### Macula Gateway

**Hub Gateway**:
- Port: 30080 (UDP/QUIC on host)
- URL: `https://localhost:30080` or `https://hub.macula.local:30080`

**Edge Gateways** (internal only):
- Port: 9443 (UDP/QUIC within cluster network)
- Not exposed to host

### PostgreSQL

**Access via port-forward**:
```bash
kubectl --context kind-macula-hub port-forward -n cortex-iq svc/postgres 5432:5432
psql -h localhost -U postgres -d cortex_iq_dashboard
```

## Troubleshooting

### Gateway not starting
- Check QUIC port (UDP 9443) is not blocked
- Verify `MACULA_GATEWAY_PORT` and `MACULA_REALM` are set
- Check container logs: `kubectl logs -n cortex-iq deployment/macula-gateway-service`
- Verify image pulled from registry: `kubectl describe pod -n cortex-iq`

### Apps can't connect to gateway
- Verify `MACULA_URL` points to correct gateway service
- Check gateway is running and ready: `kubectl get pods -n cortex-iq`
- Verify realm names match exactly
- Check network policies allow UDP traffic
- Test connectivity: `kubectl exec -it <pod> -- nc -zvu macula-gateway-service 9443`

### Dashboard not loading
- Check PostgreSQL is running and accessible: `kubectl get pods -n cortex-iq`
- Verify `DATABASE_URL` is correct in deployment
- Run migrations if needed: `kubectl exec -it <pod> -- mix ecto.migrate`
- Check app logs: `kubectl logs -n cortex-iq deployment/cortex-iq-dashboard`
- Verify service and ingress/NodePort: `kubectl get svc -n cortex-iq`

### FluxCD not reconciling
- Check Flux status: `flux get all --context kind-macula-hub`
- Check GitRepository source: `flux get sources git --context kind-macula-hub`
- Check Kustomization status: `flux get kustomizations --context kind-macula-hub`
- View reconciliation logs: `flux logs --context kind-macula-hub`
- Force reconciliation: `flux reconcile source git flux-system --context kind-macula-hub`

### Images not pulling from registry
- Verify registry is running: `docker ps | grep macula-registry`
- Check registry connectivity: `docker exec be-antwerp-control-plane curl -v http://registry.macula.local:5000/v2/`
- Verify containerd config: `docker exec be-antwerp-control-plane cat /etc/containerd/certs.d/registry.macula.local:5000/hosts.toml`
- Re-run connect-registry.sh if needed

## Differences from Old Architecture

### Removed Components
- ❌ Bondy (WAMP router)
- ❌ MaculaOs sidecar containers
- ❌ API key secrets per app
- ❌ Complex Bondy configuration
- ❌ Realm creation jobs

### New Components
- ✅ Macula Gateway Service (single process per cluster)
- ✅ Simplified client connections (direct to gateway)
- ✅ HTTP/3 (QUIC) transport
- ✅ FluxCD GitOps workflow
- ✅ KinD multi-cluster setup
- ✅ Local insecure Docker registry

### Configuration Changes
- **Before**: `BONDY_URL`, `BONDY_REALM`, `BONDY_ADMIN_URL`
- **After**: `MACULA_URL`, `MACULA_REALM`

## Multi-Region Architecture

The current setup demonstrates a hub-and-spoke multi-region architecture:

```
macula-hub (Hub)                             Registry
┌─────────────────────┐                    ┌──────────────────┐
│ Gateway (port 30080)│◄───────────────────│ macula-registry  │
│ Realm: be.cortexiq  │                    │ :5000            │
│     ↕               │                    └───────┬──────────┘
│ Apps:               │                            │
│ • Simulation        │                            │ Pull images
│ • Projections       │                            │
│ • Queries           │                            ▼
│ • Dashboard         │        ┌────────────────────────────────┐
│ • PostgreSQL        │        │ All clusters configured to pull │
└──────┬──┬──┬────────┘        │ from registry.macula.local:5000│
       │  │  │                 └────────────────────────────────┘
       │  │  │ Mesh connectivity (QUIC)
       │  │  │
   ┌───┘  │  └───┐
   │      │      │
   ▼      ▼      ▼
┌────┐ ┌────┐ ┌────┐
│Ant-│ │Bra-│ │EFL │  (Edge Clusters)
│werp│ │bant│ │    │
│    │ │    │ │    │
│ GW │ │ GW │ │ GW │  (Each has gateway)
│ ↕  │ │ ↕  │ │ ↕  │
│Homes││Homes││Homes│ (Regional workloads)
│Utils││Utils││Utils│
└────┘ └────┘ └────┘
```

**Gateway Bridging**:
- Hub gateway accepts connections from edge gateways
- Edge applications publish/subscribe locally
- Gateway mesh forwards messages between clusters
- Enables cross-region pub/sub and RPC

## References

- **FluxCD**: https://fluxcd.io/
- **KinD**: https://kind.sigs.k8s.io/
- **Kustomize**: https://kustomize.io/
- **Source Code**: https://github.com/macula-io/macula-energy-mesh-poc
- **Infrastructure Scripts**: `scripts/` (in this repo)
