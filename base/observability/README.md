# Observability Stack

Lightweight Prometheus + Grafana observability for CortexIQ Macula Mesh.

## Components

### Prometheus
- **Purpose**: Metrics collection and storage
- **Access**: http://localhost:30090
- **Retention**: 7 days
- **Resources**: 100m CPU, 256Mi RAM (bursts to 500m CPU, 512Mi RAM)

### Grafana
- **Purpose**: Metrics visualization and dashboards
- **Access**: http://localhost:30300
- **Credentials**: admin/admin (auto-login enabled)
- **Resources**: 100m CPU, 128Mi RAM (bursts to 500m CPU, 256Mi RAM)

## Deployment

Deployed to `macula-hub` cluster only (centralized observability).

```bash
# Via GitOps (automatic)
git add clusters/macula-hub/infrastructure/observability/
git commit -m "Add observability stack"
git push

# FluxCD will reconcile within 1 minute

# Or force reconciliation
flux reconcile kustomization infrastructure --context kind-macula-hub
```

## Accessing Dashboards

### Prometheus UI
```bash
# Via port-forward (KinD clusters)
kubectl --context kind-macula-hub port-forward -n observability svc/prometheus 9090:9090
# Then access: http://localhost:9090

# Note: NodePort 30090 is configured but requires KinD cluster port mappings to be accessible on host
```

### Grafana UI
```bash
# Via port-forward (KinD clusters)
kubectl --context kind-macula-hub port-forward -n observability svc/grafana 3000:3000
# Then access: http://localhost:3000

# Note: NodePort 30300 is configured but requires KinD cluster port mappings to be accessible on host
```

**Default Credentials**: admin/admin (anonymous login enabled - no password needed)

## What Gets Monitored

### Automatic Discovery
Prometheus automatically scrapes:
- Kubernetes API server
- Kubernetes nodes (cAdvisor metrics)
- All pods with annotation: `prometheus.io/scrape: "true"`

### Application Instrumentation

To expose metrics from your Elixir application:

1. **Add dependencies** to `mix.exs`:
   ```elixir
   defp deps do
     [
       {:telemetry, "~> 1.2"},
       {:telemetry_metrics, "~> 0.6"},
       {:telemetry_metrics_prometheus, "~> 1.1"},
       # ... other deps
     ]
   end
   ```

2. **Add Prometheus endpoint** to your application:
   ```elixir
   # In application.ex
   def start(_type, _args) do
     children = [
       # ... other children
       {TelemetryMetricsPrometheus, metrics: metrics(), port: 9090}
     ]

     opts = [strategy: :one_for_one, name: MyApp.Supervisor]
     Supervisor.start_link(children, opts)
   end

   defp metrics do
     [
       # VM metrics
       last_value("vm.memory.total", unit: :byte),
       last_value("vm.total_run_queue_lengths.total"),

       # Application metrics
       counter("myapp.events.processed.count"),
       summary("myapp.event.processing_time", unit: {:native, :millisecond}),

       # Add your own metrics here
     ]
   end
   ```

3. **Add Prometheus annotations** to Kubernetes deployment:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-app
   spec:
     template:
       metadata:
         annotations:
           prometheus.io/scrape: "true"
           prometheus.io/port: "9090"
           prometheus.io/path: "/metrics"
   ```

### Gateway Mesh Metrics (To Be Implemented)

When Macula Gateway is instrumented, it should expose:
- `gateway_messages_total` - Total messages routed (by type: pub/sub/RPC)
- `gateway_message_latency_seconds` - Message routing latency
- `gateway_connections_active` - Active client connections
- `gateway_mesh_peers_connected` - Number of connected peer gateways
- `gateway_mesh_message_bytes_total` - Bytes transferred between gateways

## Pre-built Queries (Prometheus UI)

### Cluster Health
```promql
# Node CPU usage
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod count per namespace
count(kube_pod_info) by (namespace)
```

### CortexIQ Application Metrics (Once Instrumented)
```promql
# Events processed per second
rate(cortexiq_events_processed_total[1m])

# Event processing latency (p95)
histogram_quantile(0.95, rate(cortexiq_event_processing_time_bucket[5m]))

# Active GenServers
cortexiq_genservers_active

# BEAM VM memory usage
vm_memory_total_bytes
```

### Gateway Mesh Metrics (Once Instrumented)
```promql
# Messages per second across mesh
rate(gateway_messages_total[1m])

# Gateway-to-gateway latency
histogram_quantile(0.95, rate(gateway_mesh_latency_seconds_bucket[5m]))

# Active mesh connections
gateway_mesh_peers_connected
```

## Creating Grafana Dashboards

### Import Community Dashboards

1. Go to http://localhost:30300
2. Click **Dashboards** → **Import**
3. Enter dashboard ID:
   - **15760** - Kubernetes cluster monitoring (detailed)
   - **315** - Kubernetes cluster monitoring (simple)
   - **13770** - BEAM/Elixir metrics (if instrumented)

### Custom CortexIQ Dashboard (TODO)

Create dashboards for:
1. **Gateway Mesh Health**
   - Network topology visualization
   - Per-gateway message throughput
   - Gateway-to-gateway latency heatmap
   - Mesh connection status

2. **CortexIQ Business Metrics**
   - Active homes per region
   - Contracts signed (24h, 7d)
   - Provider switches per region
   - Energy traded (kWh)
   - Average savings per home

3. **Application Health**
   - BEAM VM metrics per app
   - GenServer mailbox sizes
   - Event processing latency
   - Database query performance

## Troubleshooting

### Prometheus Not Scraping Pods

Check pod annotations:
```bash
kubectl --context kind-macula-hub get pods -n cortex-iq -o yaml | grep -A 3 annotations
```

Should have:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"
  prometheus.io/path: "/metrics"
```

### Grafana Can't Connect to Prometheus

Check service connectivity:
```bash
kubectl --context kind-macula-hub exec -n observability deployment/grafana -- curl http://prometheus:9090/-/healthy
```

Should return: `Prometheus is Healthy.`

### High Resource Usage

Reduce Prometheus retention:
```yaml
# In deployment.yaml, change:
- '--storage.tsdb.retention.time=7d'
# To:
- '--storage.tsdb.retention.time=2d'
```

## Next Steps

1. **Instrument Elixir applications** with `telemetry_metrics_prometheus`
2. **Create custom Grafana dashboards** for CortexIQ business metrics
3. **Add alerting** (optional) via Prometheus AlertManager
4. **Add log aggregation** (optional) with Loki + Promtail

## Resources

- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- Telemetry Metrics Prometheus: https://hexdocs.pm/telemetry_metrics_prometheus/
- BEAM Telemetry: https://hexdocs.pm/telemetry/
