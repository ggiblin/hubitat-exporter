#!/bin/bash

# Check if the required arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <hubitat-uri> <hubitat-token>"
    echo "Example: $0 http://192.168.1.100/apps/api/26/devices your-access-token"
    exit 1
fi

# Create the k8s directory if it doesn't exist
mkdir -p k8s

# Base64 encode the URI and token
uri_encoded=$(echo -n "$1" | base64)
token_encoded=$(echo -n "$2" | base64)

# Update the Secret with the encoded values
sed -i "s|HE_URI: \"\"|HE_URI: \"$uri_encoded\"|" k8s/deployment.yaml
sed -i "s|HE_TOKEN: \"\"|HE_TOKEN: \"$token_encoded\"|" k8s/deployment.yaml

# Copy the script content to the ConfigMap
awk '
    BEGIN {print "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: hubitat-exporter-script\ndata:\n  hubitat-exporter.sh: |"}
    {print "    " $0}
' hubitat-exporter.sh > k8s/configmap.yaml

# Append the rest of the kubernetes resources
cat >> k8s/configmap.yaml << 'EOF'
---
apiVersion: v1
kind: Secret
metadata:
  name: hubitat-exporter-config
type: Opaque
data:
  HE_URI: "${uri_encoded}"
  HE_TOKEN: "${token_encoded}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hubitat-exporter
  labels:
    app: hubitat-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hubitat-exporter
  template:
    metadata:
      labels:
        app: hubitat-exporter
    spec:
      containers:
      - name: hubitat-exporter
        image: ubuntu:22.04
        ports:
        - containerPort: 5000
          name: metrics
        volumeMounts:
        - name: script
          mountPath: /app
        env:
        - name: HE_URI
          valueFrom:
            secretKeyRef:
              name: hubitat-exporter-config
              key: HE_URI
        - name: HE_TOKEN
          valueFrom:
            secretKeyRef:
              name: hubitat-exporter-config
              key: HE_TOKEN
        command:
        - "/bin/bash"
        - "-c"
        - |
          apt-get update && \
          apt-get install -y curl jq socat && \
          chmod +x /app/hubitat-exporter.sh && \
          /app/hubitat-exporter.sh
      volumes:
      - name: script
        configMap:
          name: hubitat-exporter-script
          defaultMode: 0755
---
apiVersion: v1
kind: Service
metadata:
  name: hubitat-exporter
  labels:
    app: hubitat-exporter
spec:
  type: ClusterIP
  ports:
  - port: 5000
    targetPort: metrics
    protocol: TCP
    name: metrics
  selector:
    app: hubitat-exporter
EOF

# Replace the secret values
sed -i "s/HE_URI: \"\${uri_encoded}\"/HE_URI: \"$uri_encoded\"/" k8s/configmap.yaml
sed -i "s/HE_TOKEN: \"\${token_encoded}\"/HE_TOKEN: \"$token_encoded\"/" k8s/configmap.yaml

echo "Kubernetes manifests have been updated with your configuration"
echo "To deploy:"
echo "kubectl apply -f k8s/deployment.yaml"
