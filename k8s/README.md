# Hubitat Prometheus Exporter - Kubernetes Deployment

This directory contains the Kubernetes manifests for deploying the Hubitat Prometheus Exporter.

## Components

The deployment consists of the following resources:

- **Namespace**: `hubitat-exporter`
- **ConfigMaps**:
  - `hubitat-exporter-server`: Python HTTP server implementation
  - `hubitat-exporter-script`: Bash script for collecting Hubitat metrics
- **Secret**: `hubitat-exporter-config` for Hubitat API credentials
- **Deployment**: Runs the exporter in a Python container
- **Service**: LoadBalancer type for external access
- **ServiceMonitor**: For Prometheus Operator integration (optional)
- **ConfigMap**: `prometheus-config` for standalone Prometheus configuration (optional)

## Configuration Files

1. `deployment-node-exporter-colossus.yaml`: Main deployment file containing all resources

### Key Configuration Parameters

#### Hubitat API Credentials
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: hubitat-exporter-config
type: Opaque
data:
  HE_URI: <base64-encoded-hubitat-api-url>
  HE_TOKEN: <base64-encoded-access-token>
```

Generate the base64 values:
```bash
echo -n "http://your-hubitat-ip/apps/api/26/devices" | base64
echo -n "your-access-token" | base64
```

#### LoadBalancer Configuration
```yaml
apiVersion: v1
kind: Service
metadata:
  name: hubitat-exporter
spec:
  type: LoadBalancer
  loadBalancerIP: "192.168.0.123"
```

## Deployment

1. Update the secret with your Hubitat credentials:
   ```bash
   # Edit deployment-node-exporter-colossus.yaml and update the secret data
   ```

2. Apply the manifests:
   ```bash
   kubectl apply -f deployment-node-exporter-colossus.yaml
   ```

3. Verify the deployment:
   ```bash
   kubectl -n hubitat-exporter get pods
   kubectl -n hubitat-exporter get services
   ```

## Prometheus Integration

### Option 1: Prometheus Operator (recommended)
The ServiceMonitor configuration is included in the deployment file:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: hubitat-exporter
  namespace: monitoring
spec:
  endpoints:
  - port: metrics
    interval: 15s
  namespaceSelector:
    matchNames:
      - hubitat-exporter
```

### Option 2: Standalone Prometheus
A ConfigMap with Prometheus configuration is provided:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    scrape_configs:
      - job_name: 'hubitat'
        static_configs:
          - targets: ['192.168.0.123:80']
```

## Verification

1. Check pod status:
   ```bash
   kubectl -n hubitat-exporter get pods
   ```

2. View pod logs:
   ```bash
   kubectl -n hubitat-exporter logs -l app=hubitat-exporter
   ```

3. Test metrics endpoint:
   ```bash
   curl http://192.168.0.123/metrics
   ```

## Troubleshooting

1. Pod won't start:
   - Check the pod events:
     ```bash
     kubectl -n hubitat-exporter describe pod <pod-name>
     ```
   - Verify the secret values are correct
   - Check pod logs for Python or script errors

2. Can't access metrics:
   - Verify the LoadBalancer IP is assigned:
     ```bash
     kubectl -n hubitat-exporter get service hubitat-exporter
     ```
   - Check if the pod is running and ready
   - Ensure your network allows access to the LoadBalancer IP

3. Prometheus not scraping:
   - For ServiceMonitor: Check the Prometheus Operator logs
   - For standalone: Verify the Prometheus configuration
   - Check the target status in Prometheus UI
