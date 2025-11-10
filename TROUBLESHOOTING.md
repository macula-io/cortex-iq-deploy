# Troubleshooting Guide

## Macula Gateway Deployment Issue (2025-11-10)

### Status
Gateway Docker image builds and runs successfully locally but crashes immediately in Kubernetes with no logs.

### What Works
- ✅ Docker image builds successfully (`macula/macula-gateway:latest`)
- ✅ Container runs locally: `docker run --rm --user macula -e GATEWAY_PORT=9443 -e GATEWAY_REALM=be.cortexiq.energy -e RELEASE_COOKIE=test-cookie -e RELEASE_NODE=gateway@127.0.0.1 macula/macula-gateway:latest`
- ✅ Erlang VM starts correctly
- ✅ All dependencies (including jiffy NIF) load successfully

### What Doesn't Work
- ❌ Pod crashes immediately in Kubernetes (CrashLoopBackOff)
- ❌ No logs captured (`kubectl logs` returns empty)
- ❌ Restarts continuously every few seconds

### Fixes Applied
1. **Switched from Alpine to Debian base images** (erlang:26 and erlang:26-slim)
   - Reason: jiffy NIF glibc compatibility
   - Files: `macula/Dockerfile.gateway`

2. **Added .dockerignore**
   - Excludes `_build/` to force fresh NIF compilation in container
   - Files: `macula/.dockerignore`

3. **Increased memory limits**
   - Request: 512Mi → 1Gi
   - Limit: 1Gi → 2Gi
   - Files: `base/macula-gateway/deployment.yaml`

### Investigation Findings
- Image SHA verified in KinD node matches local
- No command/args overrides in pod spec
- No security context restrictions
- Probes have reasonable delays (30s liveness, 10s readiness)
- User permissions correct (macula:macula, uid 1000)
- Binary executable and accessible
- Tested exact Dockerfile CMD locally - works fine

### Deployment Configuration
**Location**: `base/macula-gateway/`
- `namespace.yaml` - macula-system namespace
- `deployment.yaml` - Gateway deployment with 1 replica
- `service.yaml` - ClusterIP service exposing port 9443 (UDP+TCP)
- `kustomization.yaml` - Kustomize configuration

**GitOps**: `clusters/macula-hub/infrastructure/macula-gateway.yaml`

### Environment Variables
```yaml
GATEWAY_PORT: "9443"
GATEWAY_REALM: "be.cortexiq.energy"
RELEASE_COOKIE: "macula-gateway-cookie"
RELEASE_NODE: "gateway@127.0.0.1"
```

### Possible Causes
The silent crash with zero logs suggests:
1. **Containerd/runtime issue** - Container runtime failing before any output
2. **Kernel/cgroup incompatibility** - BEAM VM incompatibility with KinD's environment
3. **Network namespace problem** - Port 9443 binding failure (though no logs to confirm)
4. **Missing runtime dependency** - Something required at runtime but not in Debian slim image
5. **KinD-specific limitation** - UDP port or QUIC protocol incompatibility

### Next Steps
1. Try running with `--init` flag to handle signal propagation
2. Add startup script that logs to a file before launching Erlang
3. Test with `strace` to see syscall failures
4. Try on a different Kubernetes cluster (not KinD) to isolate KinD issues
5. Simplify to a minimal Erlang application first (remove all macula apps)
6. Check KinD containerd logs directly: `docker exec macula-hub-control-plane journalctl -u containerd`

### Files Modified

**macula repository** (`/home/rl/work/github.com/macula-io/macula/`):
- `Dockerfile.gateway` - Multi-stage Debian-based build
- `.dockerignore` - Excludes _build/ directory
- Commits:
  - `08d10c3` - Fix Docker build for macula-gateway with NIF compatibility

**cortex-iq-deploy repository** (`/home/rl/work/github.com/macula-io/cortex-iq-deploy/`):
- `base/macula-gateway/*` - All manifest files created
- `clusters/macula-hub/infrastructure/macula-gateway.yaml` - GitOps configuration
- Commits:
  - `2f9efa0` - Increase macula-gateway memory limits to fix OOMKilled issue

### Testing Locally
```bash
# Build image
cd /home/rl/work/github.com/macula-io/macula
docker build -f Dockerfile.gateway -t macula/macula-gateway:latest .

# Test locally
docker run --rm --user macula \
  -e GATEWAY_PORT=9443 \
  -e GATEWAY_REALM=be.cortexiq.energy \
  -e RELEASE_COOKIE=test-cookie \
  -e RELEASE_NODE=gateway@127.0.0.1 \
  macula/macula-gateway:latest
```

### Deploying to KinD
```bash
# Remove old image from KinD
docker exec macula-hub-control-plane crictl rmi docker.io/macula/macula-gateway:latest

# Load new image
kind load docker-image macula/macula-gateway:latest --name macula-hub

# Restart deployment
kubectl --context kind-macula-hub rollout restart deployment/macula-gateway -n macula-system

# Check status
kubectl --context kind-macula-hub get pods -n macula-system
kubectl --context kind-macula-hub logs -n macula-system -l app=macula-gateway
```

## Known Issues

### Issue: No logs from crashing container
**Impact**: Cannot diagnose why container crashes in Kubernetes
**Workaround**: None currently
**Status**: Under investigation

### Issue: jiffy NIF glibc compatibility
**Impact**: Alpine-based images fail to load jiffy NIF
**Solution**: Use Debian-based images (erlang:26 and erlang:26-slim)
**Status**: Resolved
