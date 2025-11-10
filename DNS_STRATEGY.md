# DNS Strategy for CortexIQ Deployment

## Overview

DNS requirements differ significantly between local KinD development and production beam cluster deployments.

## Local KinD Development (Current Setup)

### Built-in Kubernetes DNS (CoreDNS)

Each KinD cluster has CoreDNS automatically configured, providing:

**Service DNS Format:**
```
<service-name>.<namespace>.svc.cluster.local
```

**Examples:**
- `prometheus.observability.svc.cluster.local`
- `grafana.observability.svc.cluster.local`
- `gateway.macula-hub.svc.cluster.local`

**Cross-Cluster Communication:**

Since each KinD cluster is isolated, gateway mesh peers are configured using Docker network hostnames:

```yaml
env:
  - name: MESH_PEERS
    value: "https://macula-hub-gateway:9443,https://macula-antwerp-gateway:9443,https://macula-brabant-gateway:9443"
```

These resolve via Docker's embedded DNS server (Docker network `cortexiq-mesh`).

**No ExternalDNS Required** - All DNS resolution happens via:
1. CoreDNS (within cluster)
2. Docker embedded DNS (cross-cluster via Docker network)

---

## Production Beam Cluster Deployment

### Architecture

4 physical nodes running k3s:
- beam00.lab (192.168.1.10) - macula-hub
- beam01.lab (192.168.1.11) - macula-antwerp
- beam02.lab (192.168.1.12) - macula-brabant
- beam03.lab (192.168.1.13) - macula-efl

### DNS Requirements

**Intra-Cluster DNS** (within each k3s cluster):
- ✅ Handled by CoreDNS (built into k3s)
- Services resolve via `<service>.cortex-iq.svc.cluster.local`

**Inter-Cluster DNS** (gateway mesh communication):
- ❌ CoreDNS does NOT span clusters
- Need cross-cluster service discovery for gateway mesh

### Option 1: Static /etc/hosts (Simplest)

Configure on each beam node:

```bash
# /etc/hosts on all beam nodes
192.168.1.10 macula-hub.lab gateway-hub.macula.local
192.168.1.11 macula-antwerp.lab gateway-antwerp.macula.local
192.168.1.12 macula-brabant.lab gateway-brabant.macula.local
192.168.1.13 macula-efl.lab gateway-efl.macula.local
```

**Gateway Configuration:**
```yaml
env:
  - name: MESH_PEERS
    value: "https://gateway-hub.macula.local:9443,https://gateway-antwerp.macula.local:9443,https://gateway-brabant.macula.local:9443"
```

**Pros:**
- Simple, no additional infrastructure
- Works immediately
- No dynamic DNS complexity

**Cons:**
- Manual updates if IPs change
- Not dynamic

---

### Option 2: PowerDNS (Already Deployed on beam00)

Per parent CLAUDE.md, PowerDNS is running on beam00 via Docker.

**Zone Configuration:**

Create zone `macula.local` with records:
```
gateway-hub.macula.local.     A  192.168.1.10
gateway-antwerp.macula.local. A  192.168.1.11
gateway-brabant.macula.local. A  192.168.1.12
gateway-efl.macula.local.     A  192.168.1.13
```

**DNS Resolver Configuration** on each beam node:

```bash
# /etc/systemd/resolved.conf
[Resolve]
DNS=192.168.1.10
Domains=~macula.local
```

**Gateway Configuration:**
```yaml
env:
  - name: MESH_PEERS
    value: "https://gateway-hub.macula.local:9443,https://gateway-antwerp.macula.local:9443,https://gateway-brabant.macula.local:9443"
```

**Pros:**
- Centralized DNS management
- Can add additional records easily
- Authoritative for `.macula.local` domain

**Cons:**
- PowerDNS must be highly available (single point of failure)
- Requires additional configuration steps

---

### Option 3: ExternalDNS with PowerDNS Backend

Deploy ExternalDNS in each k3s cluster to automatically manage PowerDNS records.

**How It Works:**
1. Deploy gateway Service with annotation:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: gateway
     namespace: cortex-iq
     annotations:
       external-dns.alpha.kubernetes.io/hostname: gateway-hub.macula.local
   spec:
     type: LoadBalancer
     externalIPs:
       - 192.168.1.10
   ```

2. ExternalDNS watches Service resources
3. Automatically creates/updates PowerDNS records

**ExternalDNS Configuration:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  template:
    spec:
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.14.0
          args:
            - --source=service
            - --provider=pdns
            - --pdns-server=http://192.168.1.10:8081
            - --pdns-api-key=<secret>
            - --domain-filter=macula.local
            - --txt-owner-id=beam00
```

**Pros:**
- Fully automated DNS management
- GitOps-friendly (DNS via Kubernetes manifests)
- Automatic cleanup when services deleted

**Cons:**
- Most complex option
- Requires PowerDNS API key management
- Additional moving parts

---

### Option 4: Static IP LoadBalancer Services (Recommended for Beam Clusters)

Since beam clusters are bare metal with fixed IPs, use k3s built-in ServiceLB (Klipper) with static IPs.

**Gateway Service Configuration:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: gateway
  namespace: cortex-iq
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.1.10  # Static IP for this node
  ports:
    - name: quic
      port: 9443
      targetPort: 9443
      protocol: UDP
```

**Gateway Mesh Configuration:**
```yaml
env:
  - name: MESH_PEERS
    value: "https://192.168.1.10:9443,https://192.168.1.11:9443,https://192.168.1.12:9443,https://192.168.1.13:9443"
```

**Use /etc/hosts for friendly names** (optional):
```bash
192.168.1.10 gateway-hub.macula.local
192.168.1.11 gateway-antwerp.macula.local
192.168.1.12 gateway-brabant.macula.local
192.168.1.13 gateway-efl.macula.local
```

**Pros:**
- Simple and reliable
- No DNS infrastructure required
- IPs are static (beam nodes don't move)

**Cons:**
- IPs in configuration instead of hostnames
- Less human-readable

---

## Recommendation

### For Local KinD Development (Current)
✅ **No action required** - Use built-in CoreDNS + Docker network DNS

### For Beam Cluster Production

**Phase 1 (Immediate):**
- Use **Option 4** (Static IPs) - simplest and most reliable
- Configure gateway mesh with `192.168.1.x` IPs directly
- Add /etc/hosts entries for convenience

**Phase 2 (Future):**
- Migrate to **Option 2** (PowerDNS) once mesh is stable
- Use existing PowerDNS on beam00
- Provides centralized DNS management

**Skip for Now:**
- ❌ Option 3 (ExternalDNS) - unnecessary complexity for 4 fixed nodes

---

## Configuration Examples

### Local KinD (Current)

**Gateway Deployment:**
```yaml
env:
  - name: MESH_PEERS
    value: "https://macula-hub-gateway:9443,https://macula-antwerp-gateway:9443"
```

### Beam Clusters (Future)

**Gateway Deployment:**
```yaml
env:
  - name: MESH_PEERS
    value: "https://192.168.1.10:9443,https://192.168.1.11:9443,https://192.168.1.12:9443,https://192.168.1.13:9443"
```

**Gateway Service (per cluster):**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: gateway
  namespace: cortex-iq
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.1.10  # Different per cluster
  ports:
    - name: quic
      port: 9443
      targetPort: 9443
      protocol: UDP
```

---

## Summary

| Environment | DNS Solution | ExternalDNS Needed? |
|-------------|--------------|---------------------|
| Local KinD | CoreDNS + Docker DNS | ❌ No |
| Beam Clusters (Phase 1) | Static IPs | ❌ No |
| Beam Clusters (Phase 2) | PowerDNS | ⚠️ Optional |

**Bottom Line:** We do NOT need ExternalDNS for the current KinD setup, and likely won't need it for beam clusters either due to static node IPs.
