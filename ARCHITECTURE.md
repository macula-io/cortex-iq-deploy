# CortexIQ Deployment Architecture - KinD Clusters

This document describes the deployment architecture for CortexIQ on local KinD (Kubernetes in Docker) clusters using GitOps with FluxCD.

## Documentation Index

**Core Architecture:**
- [ARCHITECTURE.md](./ARCHITECTURE.md) *(this file)* - Overall deployment architecture and mesh topology
- [DNS_STRATEGY.md](./DNS_STRATEGY.md) - DNS resolution strategy for KinD and beam clusters

**Infrastructure Components:**
- [base/observability/README.md](./base/observability/README.md) - Prometheus + Grafana observability stack
- [base/registry/README.md](./base/registry/README.md) - Local Docker registry setup

**Scripts:**
- [scripts/create-belgian-clusters.sh](./scripts/create-belgian-clusters.sh) - Create 4 KinD clusters
- [scripts/configure-flux-gitops.sh](./scripts/configure-flux-gitops.sh) - Configure FluxCD on all clusters
- [scripts/connect-registry.sh](./scripts/connect-registry.sh) - Connect registry to KinD clusters

**Deployment Process:**
- See [README.md](./README.md) - Quick start guide and deployment workflow

## Overview

CortexIQ is deployed across **4 KinD clusters** in a **fully connected mesh topology**:

- **macula-hub** - Centralized services cluster
  - Dashboard (Phoenix LiveView UI)
  - Projections (event processing to read models)
  - Queries (RPC query handlers)
  - Simulation (time clock broadcast)
  - PostgreSQL (read model database)
  - **Macula Gateway** (participates in mesh)

- **be-antwerp** - Antwerp region cluster
  - Homes (regional home simulation bots)
  - Utilities (regional energy provider bots)
  - **Macula Gateway** (participates in mesh)

- **be-brabant** - Brabant region cluster
  - Homes (regional home simulation bots)
  - Utilities (regional energy provider bots)
  - **Macula Gateway** (participates in mesh)

- **be-east-flanders** - East Flanders region cluster
  - Homes (regional home simulation bots)
  - Utilities (regional energy provider bots)
  - **Macula Gateway** (participates in mesh)

### Key Architectural Principles

**Full Mesh Network**:
- All 4 Macula Gateways are connected to each other in a ring topology
- No hub-and-spoke - all gateways are peers
- Messages published in one cluster propagate to all others automatically
- Forms ONE virtual realm (`be.cortexiq.energy`) spanning 4 physical clusters

**Cross-Cluster Communication**:
- A home in Antwerp can see contract offers from providers in Brabant
- Dashboard in macula-hub receives events from homes in all 3 regions
- Simulation clock in macula-hub broadcasts to all homes/utilities across all regions
- All via HTTP/3 (QUIC) transport through the gateway mesh

**Cluster Roles**:
- **macula-hub**: Logical "hub" for centralized services (NOT a gateway hub)
  - Runs shared services: Dashboard, DB, Projections, Queries, Simulation
  - Gateway participates as peer in mesh (not central router)
- **Regional clusters**: Run region-specific workloads
  - Homes and Utilities for that region
  - Gateway participates as peer in mesh

All clusters use **FluxCD** for GitOps-based continuous deployment from this repository (`cortex-iq-deploy`).

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

### Full Mesh Network Topology

```
┌────────────────────────────────────────────────────────────────────────┐
│                     4-Cluster Full Mesh Network                        │
│                     Realm: be.cortexiq.energy                          │
│                                                                         │
│                                                                         │
│                         macula-hub                                     │
│                     ┌──────────────────┐                               │
│                     │  Gateway :9443   │◄─────────┐                    │
│                     │  (mesh peer)     │          │                    │
│                     └────────┬─────────┘          │                    │
│                              │                    │                    │
│                   ┌──────────┼─────────┐          │                    │
│                   │          │         │          │                    │
│                   ▼          ▼         ▼          │                    │
│             ┌──────────┬────────┬──────────┐      │                    │
│             │Dashboard │Proj/Qry│Simulation│      │                    │
│             └──────────┴───┬────┴──────────┘      │                    │
│                            │                      │                    │
│                            ▼                      │                    │
│                       PostgreSQL                  │                    │
│                                                   │                    │
│         ┌─────────────────────────────────────────┘                    │
│         │                                                              │
│         │                                                              │
│    ┌────▼──────────┐                         ┌────────────────┐       │
│    │  be-antwerp   │                         │ be-east-flanders│      │
│    │               │                         │                │      │
│    │ Gateway :9443 │◄───────────────────────►│ Gateway :9443  │      │
│    │ (mesh peer)   │                         │ (mesh peer)    │      │
│    └───────┬───────┘                         └───────┬────────┘       │
│            │                                         │                │
│       ┌────┴─────┐                              ┌────┴─────┐          │
│       │          │                              │          │          │
│       ▼          ▼                              ▼          ▼          │
│    ┌──────┬──────────┐                      ┌──────┬──────────┐      │
│    │Homes │Utilities │                      │Homes │Utilities │      │
│    └──────┴──────────┘                      └──────┴──────────┘      │
│            │                                         │                │
│            │                                         │                │
│            │          ┌─────────────┐                │                │
│            │          │ be-brabant  │                │                │
│            │          │             │                │                │
│            └─────────►│Gateway :9443│◄───────────────┘                │
│                       │(mesh peer)  │                                 │
│                       └──────┬──────┘                                 │
│                              │                                        │
│                         ┌────┴─────┐                                  │
│                         │          │                                  │
│                         ▼          ▼                                  │
│                     ┌──────┬──────────┐                               │
│                     │Homes │Utilities │                               │
│                     └──────┴──────────┘                               │
│                                                                         │
│  All 4 gateways form a RING - fully connected mesh                    │
│  Each gateway connects to all 3 others (6 total connections)          │
│  Any application in any cluster can communicate with any other        │
└────────────────────────────────────────────────────────────────────────┘
```

### Message Flow Example

```
Home in Antwerp publishes energy measurement:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. Home (Antwerp) → Gateway (Antwerp)                         │
│     Topic: "be.cortexiq.home.measured"                         │
│     Payload: {home_id: "ant_001", production_w: 3500, ...}     │
│                                                                 │
│  2. Gateway (Antwerp) → All other gateways via mesh            │
│     ├─→ Gateway (Brabant)                                      │
│     ├─→ Gateway (East Flanders)                                │
│     └─→ Gateway (macula-hub)                                   │
│                                                                 │
│  3. Applications subscribed to "be.cortexiq.home.*" receive:   │
│     ├─ Dashboard (macula-hub) ✓                                │
│     ├─ Projections (macula-hub) ✓                              │
│     └─ Any other subscriber in any cluster ✓                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Provider in Brabant publishes contract offer:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. Provider (Brabant) → Gateway (Brabant)                     │
│     Topic: "be.cortexiq.provider.contract.offered"             │
│     Payload: {provider_id: "bra_p01", day_price: 0.15, ...}    │
│                                                                 │
│  2. Gateway (Brabant) → All other gateways via mesh            │
│     ├─→ Gateway (Antwerp)                                      │
│     ├─→ Gateway (East Flanders)                                │
│     └─→ Gateway (macula-hub)                                   │
│                                                                 │
│  3. Homes subscribed to "be.cortexiq.provider.*" receive:      │
│     ├─ Homes in Antwerp ✓ (cross-region!)                     │
│     ├─ Homes in Brabant ✓                                     │
│     ├─ Homes in East Flanders ✓ (cross-region!)               │
│     └─ Dashboard (macula-hub) ✓                                │
│                                                                 │
│  Result: Home in Antwerp can switch to provider in Brabant!    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Individual Cluster Details

#### macula-hub Cluster

```
┌──────────────────────────────────────────────────────────────┐
│  macula-hub (KinD)                                           │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Macula Gateway                                         │  │
│  │  - Port: 9443 (internal), 30080 (host/QUIC)           │  │
│  │  - Realm: be.cortexiq.energy                           │  │
│  │  - Mesh Peers: be-antwerp, be-brabant, be-east-flanders│ │
│  └─────────────────┬──────────────────────────────────────┘  │
│                    │ (local connections)                      │
│        ┌───────────┼──────────┬────────────┬──────────┐      │
│        ▼           ▼          ▼            ▼          ▼      │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────┐              │
│  │ Simul-  │ │Projec-  │ │Queries  │ │Dash- │              │
│  │ ation   │ │ tions   │ │         │ │board │              │
│  └─────────┘ └─────────┘ └─────────┘ └──┬───┘              │
│                   │                      │                   │
│                   ▼                      │                   │
│  ┌─────────────────────────────────┐    │                   │
│  │ PostgreSQL                       │◄───┘                   │
│  │ - Port: 5432                    │                        │
│  │ - Database: cortex_iq_dashboard │                        │
│  └─────────────────────────────────┘                        │
└──────────────────────────────────────────────────────────────┘
```

#### Regional Cluster (be-antwerp, be-brabant, be-east-flanders)

```
┌──────────────────────────────────────────────────────────────┐
│  be-[region] (KinD)                                          │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Macula Gateway                                         │  │
│  │  - Port: 9443 (internal)                               │  │
│  │  - Realm: be.cortexiq.energy                           │  │
│  │  - Mesh Peers: macula-hub, other 2 regions            │  │
│  └─────────────────┬──────────────────────────────────────┘  │
│                    │ (local connections)                      │
│        ┌───────────┴──────────┐                               │
│        ▼                      ▼                               │
│  ┌─────────┐           ┌─────────┐                           │
│  │ Homes   │           │Utilities│                           │
│  │         │           │         │                           │
│  │ Regional│           │ Regional│                           │
│  │ Bots    │           │ Bots    │                           │
│  └─────────┘           └─────────┘                           │
└──────────────────────────────────────────────────────────────┘
```

## Components

### Infrastructure Components

#### 1. Macula Gateway Service (Required - All Clusters)

**Image**: `registry.macula.local:5000/macula/macula-gateway-service:latest`

**Purpose**: Gateway that all local applications connect to for pub/sub and RPC. Forms mesh ring with other gateways.

**Environment Variables**:
- `MACULA_GATEWAY_PORT=9443` - Port to listen on (QUIC/HTTP3)
- `MACULA_REALM=be.cortexiq.energy` - Realm name (all clusters use same realm)
- `MESH_PEERS` - Comma-separated list of other gateway URLs for mesh ring
  - Example: `https://gateway-antwerp:9443,https://gateway-brabant:9443,https://gateway-efl:9443`

**Deployment**:
- **All clusters are peers** - no hub/spoke hierarchy
- Each gateway connects to ALL other gateways (full mesh)
- Messages published to one gateway propagate to all others automatically
- Gateway mesh forms ONE virtual realm spanning all physical clusters

**Network Configuration**:
- **macula-hub**: Port 30080 exposed to host (for external testing)
- **Regional clusters**: Port 9443 internal only (cluster-to-cluster via Kubernetes service mesh)

**Mesh Ring Topology**:
```
Gateway connections (6 total for 4 gateways):
1. macula-hub ↔ be-antwerp
2. macula-hub ↔ be-brabant
3. macula-hub ↔ be-east-flanders
4. be-antwerp ↔ be-brabant
5. be-antwerp ↔ be-east-flanders
6. be-brabant ↔ be-east-flanders
```

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

## Multi-Region Full Mesh Architecture

The deployment demonstrates a **fully connected mesh** multi-region architecture:

```
Container Registry                    4-Cluster Full Mesh Network
┌──────────────────┐
│ macula-registry  │                  All clusters pull images
│ :5000            │◄─────────────────from registry
└──────────────────┘
                                      ┌─────────────────────────┐
                                      │ Realm: be.cortexiq.energy│
                                      │ (ONE virtual realm)      │
                                      └─────────────────────────┘

     macula-hub
   ┌─────────────┐                         MESH RING
   │  Gateway    │──────────┐              (HTTP/3/QUIC)
   │  :9443      │          │
   └──────┬──────┘          │              All gateways
          │                 │              connected to
          ▼                 │              all others
    ┌──────────┐            │
    │Dashboard │            │              Messages published
    │Proj/Query│            │              in ANY cluster
    │Simulation│            │              propagate to
    │PostgreSQL│            │              ALL clusters
    └──────────┘            │
                            │
         ┌──────────────────┼───────────────────┐
         │                  │                   │
         ▼                  ▼                   ▼
    be-antwerp         be-brabant      be-east-flanders
   ┌──────────┐       ┌──────────┐     ┌──────────┐
   │ Gateway  │◄─────►│ Gateway  │◄───►│ Gateway  │
   │ :9443    │       │ :9443    │     │ :9443    │
   └────┬─────┘       └────┬─────┘     └────┬─────┘
        │                  │                 │
        ▼                  ▼                 ▼
   ┌─────────┐        ┌─────────┐      ┌─────────┐
   │  Homes  │        │  Homes  │      │  Homes  │
   │Utilities│        │Utilities│      │Utilities│
   └─────────┘        └─────────┘      └─────────┘
```

**Mesh Network Properties**:
- **No central hub** - all gateways are equal peers
- **Full connectivity** - each gateway connects to all 3 others (6 total connections)
- **Automatic propagation** - messages published anywhere reach all subscribers everywhere
- **Realm unification** - ONE virtual realm `be.cortexiq.energy` spanning 4 physical clusters
- **HTTP/3 (QUIC)** - NAT-friendly, firewall-friendly transport between gateways

**Cross-Region Communication Examples**:
1. **Provider in Brabant → Home in Antwerp**:
   - Provider publishes contract offer to local gateway (Brabant)
   - Gateway mesh propagates to all clusters
   - Home in Antwerp receives offer and can switch providers

2. **Home in any region → Dashboard in macula-hub**:
   - Home publishes measurement to local gateway
   - Gateway mesh propagates to macula-hub
   - Dashboard receives and displays real-time data

3. **Simulation in macula-hub → All homes in all regions**:
   - Simulation publishes time tick to local gateway
   - Gateway mesh propagates to all regional clusters
   - All homes advance simulation time synchronously

**Why "macula-hub" if it's not a hub?**
- **Logical role**, not architectural role
- Hosts **shared services**: Dashboard, Projections, Queries, Simulation, PostgreSQL
- Gateway participates in mesh **as a peer**, not as a central router
- Could be renamed to "macula-services" for clarity, but "hub" reflects its logical purpose

## References

- **FluxCD**: https://fluxcd.io/
- **KinD**: https://kind.sigs.k8s.io/
- **Kustomize**: https://kustomize.io/
- **Source Code**: https://github.com/macula-io/macula-energy-mesh-poc
- **Infrastructure Scripts**: `scripts/` (in this repo)
