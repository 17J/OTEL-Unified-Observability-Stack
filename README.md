# 🛠️ OpenTelemetry Observability Stack - Dev/Staging Deployment

Complete deployment guide for OpenTelemetry with Jaeger, Prometheus, and ELK stack in Kubernetes (KIND/Minikube) - optimized for dev/staging with production-like persistence and reliability.

---

## 📋 Prerequisites

```bash
# Verify installations
docker --version
kubectl version --client
helm version
kind --version  # or minikube version
```

**Expected Output:**

```
Docker version 24.0.x, build xxxxx
Client Version: v1.28.x
version.BuildInfo{Version:"v3.12.x", ...}
kind v0.20.0 go1.20.x linux/amd64
```

---

## 🚀 Step 1: Create KIND Cluster with Extra Mounts

```bash
# Create KIND config with proper port mappings and storage
cat > kind-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: otel-poc
nodes:
  - role: control-plane
    # Port mappings for easy access to services
    extraPortMappings:
      - containerPort: 30000  # Grafana
        hostPort: 3000
        protocol: TCP
      - containerPort: 30686  # Jaeger
        hostPort: 16686
        protocol: TCP
      - containerPort: 30601  # Kibana
        hostPort: 5601
        protocol: TCP
    # Mount host directory for persistent storage (dev use)
    extraMounts:
      - hostPath: /tmp/kind-storage
        containerPath: /data
EOF

# Create the storage directory
mkdir -p /tmp/kind-storage

# Create cluster
kind create cluster --config kind-config.yaml
```

**Expected Output:**

```
Creating cluster "otel-poc" ...
 ✓ Ensuring node image (kindest/node:v1.27.3) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-otel-poc"
```

**💡 Dev Note:** Port mappings allow direct access without port-forwarding. Extra mounts provide persistence across pod restarts.

---

## 📦 Step 2: Add Helm Repositories

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo update
```

**Expected Output:**

```
"open-telemetry" has been added to your repositories
"grafana" has been added to your repositories
"prometheus-community" has been added to your repositories
"jaegertracing" has been added to your repositories
"elastic" has been added to your repositories
Update Complete. ⎈Happy Helming!⎈
```

---

## 🔧 Step 3: Deploy Core Backends

### 3.1 Deploy Jaeger with Persistent Storage

```bash
# Create persistent volume for Jaeger (dev-friendly but survives restarts)
cat > jaeger-pv.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jaeger-pv
  labels:
    type: local
spec:
  storageClassName: standard
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/jaeger"  # Mapped to /tmp/kind-storage/jaeger on host
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jaeger-pvc
  namespace: observability
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Create namespace first
kubectl create namespace observability

# Apply PV/PVC
kubectl apply -f jaeger-pv.yaml

# Deploy Jaeger with Badger (file-based) storage
helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace observability \
  --set provisionDataStore.cassandra=false \
  --set allInOne.enabled=true \
  --set storage.type=badger \
  --set allInOne.extraEnv[0].name=SPAN_STORAGE_TYPE \
  --set allInOne.extraEnv[0].value=badger \
  --set allInOne.extraEnv[1].name=BADGER_EPHEMERAL \
  --set allInOne.extraEnv[1].value=false \
  --set allInOne.extraEnv[2].name=BADGER_DIRECTORY_VALUE \
  --set allInOne.extraEnv[2].value=/badger/data \
  --set allInOne.extraEnv[3].name=BADGER_DIRECTORY_KEY \
  --set allInOne.extraEnv[3].value=/badger/key \
  --set allInOne.persistence.enabled=true \
  --set allInOne.persistence.size=5Gi \
  --set service.type=NodePort \
  --set service.nodePort=30686
```

**Expected Output:**

```
persistentvolume/jaeger-pv created
persistentvolumeclaim/jaeger-pvc created
Release "jaeger" does not exist. Installing it now.
NAME: jaeger
NAMESPACE: observability
STATUS: deployed
NOTES:
###############################################################################
# Jaeger with persistent Badger storage is deployed
# Access: http://localhost:16686 (via KIND port mapping)
###############################################################################
```

**💡 Dev Note:** Badger storage persists traces across restarts without needing Cassandra/Elasticsearch. Perfect for dev/staging!

**Verify:**

```bash
kubectl get pods,pvc -n observability
```

**Expected Output:**

```
NAME                          READY   STATUS    RESTARTS   AGE
pod/jaeger-0                  1/1     Running   0          60s

NAME                              STATUS   VOLUME      CAPACITY   ACCESS MODES
persistentvolumeclaim/jaeger-pvc  Bound    jaeger-pv   5Gi        RWO
```

---

### 3.2 Deploy Prometheus & Grafana with Retention Policies

**Create Alertmanager config with real dev/staging endpoints:**

```bash
cat > alertmanager-config.yaml <<'EOF'
alertmanager:
  config:
    global:
      resolve_timeout: 5m
      # Dev/Staging: Use a dedicated Slack channel for non-critical alerts
      slack_api_url: "https://hooks.slack.com/services/YOUR/DEV/WEBHOOK"

    receivers:
      - name: "null"

      - name: "slack-dev-alerts"
        slack_configs:
          - channel: "#alerts-dev"
            send_resolved: true
            # Dev-friendly formatting
            title: "[DEV-{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
            text: |
              *Environment:* Dev/Staging
              *Severity:* {{ .CommonLabels.severity }}
              *Summary:* {{ .CommonAnnotations.summary }}
              *Description:* {{ .CommonAnnotations.description }}
              *Cluster:* {{ .CommonLabels.cluster }}
            # Dev: Shorter URLs, more casual
            title_link: "http://localhost:3000/alerting/list"

      - name: "email-dev-oncall"
        email_configs:
          - to: "dev-oncall@company.com"
            from: "alertmanager-dev@company.com"
            smarthost: "smtp.gmail.com:587"
            auth_username: "alertmanager-dev@company.com"
            auth_password: "your-app-password"
            headers:
              Subject: "[DEV] Alert: {{ .CommonLabels.alertname }}"

    route:
      # Dev: Faster grouping for quicker feedback
      group_by: ["alertname", "cluster", "namespace"]
      receiver: "null"
      group_wait: 10s        # Dev: Reduced from 30s
      group_interval: 2m     # Dev: Reduced from 5m
      repeat_interval: 2h    # Dev: Reduced from 4h
      routes:
        # Critical alerts go to email (dev oncall)
        - match:
            severity: "critical"
          receiver: "email-dev-oncall"
          group_wait: 5s
          group_interval: 1m
          repeat_interval: 30m

        # Warning/Info to Slack only
        - matchers:
            - severity =~ "warning|info"
          receiver: "slack-dev-alerts"

# Prometheus specific configurations for dev
prometheus:
  prometheusSpec:
    # Dev: Keep data for 7 days (vs 15d production)
    retention: 7d
    retentionSize: "10GB"

    # Dev: Scrape more frequently for faster feedback
    scrapeInterval: 15s
    evaluationInterval: 15s

    # Resource limits appropriate for dev
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2
        memory: 4Gi

    # Enable persistent storage
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 15Gi

    # Enable remote write for long-term storage (optional in dev)
    # remoteWrite:
    #   - url: "http://mimir.monitoring.svc:9009/api/v1/push"

    # Service monitors for auto-discovery
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

# Grafana configurations
grafana:
  adminPassword: "admin123"  # Dev: Simple password, change in production!

  persistence:
    enabled: true
    storageClassName: standard
    size: 5Gi

  # Dev: Enable anonymous access for easy sharing
  grafana.ini:
    auth.anonymous:
      enabled: true
      org_role: Viewer
    server:
      root_url: "http://localhost:3000"

  # Pre-configure datasources
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://monitoring-kube-prometheus-prometheus:9090
          access: proxy
          isDefault: true
        - name: Jaeger
          type: jaeger
          url: http://jaeger-query.observability.svc:16686
          access: proxy
        - name: Elasticsearch
          type: elasticsearch
          url: http://elasticsearch-master.logging.svc:9200
          access: proxy
          database: "otel-logs-*"
          basicAuth: true
          basicAuthUser: elastic
          secureJsonData:
            basicAuthPassword: changeme123

  # Dev: Load useful dashboards
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

  # Import community dashboards
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      otel-collector:
        gnetId: 15983
        revision: 1
        datasource: Prometheus
      jaeger-traces:
        gnetId: 11449
        revision: 1
        datasource: Jaeger

  service:
    type: NodePort
    nodePort: 30000
EOF
```

**Deploy:**

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f alertmanager-config.yaml \
  --wait --timeout 10m
```

**Expected Output:**

```
Release "monitoring" does not exist. Installing it now.
NAME: monitoring
NAMESPACE: monitoring
STATUS: deployed
NOTES:
kube-prometheus-stack has been installed with:
- Prometheus (7d retention, 15Gi storage)
- Grafana (admin/admin123)
- Alertmanager (dev-configured)
Access Grafana: http://localhost:3000
```

**💡 Dev Note:**

- 7-day retention balances storage vs debugging needs
- Pre-configured datasources save setup time
- Community dashboards give instant visibility
- NodePort service = no port-forwarding needed

**Verify:**

```bash
kubectl get pods,pvc -n monitoring
```

**Expected Output:**

```
NAME                                                     READY   STATUS    RESTARTS   AGE
pod/alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2     Running   0          3m
pod/monitoring-grafana-7b4d7c8f9d-xk2ls                      3/3     Running   0          3m
pod/monitoring-kube-prometheus-operator-5d8b9c8d7f-9h4j2     1/1     Running   0          3m
pod/prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   0          3m

NAME                                                                   STATUS   VOLUME                                     CAPACITY
persistentvolumeclaim/prometheus-monitoring-kube-prometheus-prometheus-db-0   Bound    pvc-xxx   15Gi
persistentvolumeclaim/monitoring-grafana                               Bound    pvc-yyy   5Gi
```

---

### 3.3 Deploy Elasticsearch & Kibana with ILM Policies

**Create Elasticsearch with Index Lifecycle Management:**

```bash
cat > elasticsearch-values.yaml <<'EOF'
clusterName: elasticsearch
replicas: 1
minimumMasterNodes: 1

# Dev: Appropriate resources (can handle moderate load)
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 2
    memory: 4Gi

# Persistent storage (survives restarts)
volumeClaimTemplate:
  storageClassName: standard
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 30Gi  # Dev: 30GB should handle 1-2 weeks of logs

esJavaOpts: "-Xmx2048m -Xms2048m"

# Security settings
secret:
  enabled: true
  password: "changeme123"  # Dev: Simple password

# Additional ES config for better dev experience
esConfig:
  elasticsearch.yml: |
    # Dev: Disable security warnings
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: false
    xpack.security.http.ssl.enabled: false

    # Enable ILM for automatic index management
    xpack.ilm.enabled: true

    # Dev: More lenient index settings
    action.auto_create_index: true
    action.destructive_requires_name: false

# Lifecycle hooks to create ILM policy
lifecycle:
  postStart:
    exec:
      command:
        - bash
        - -c
        - |
          # Wait for ES to be ready
          until curl -s -u "elastic:changeme123" http://localhost:9200/_cluster/health | grep -q '"status":"green\|yellow"'; do
            echo "Waiting for Elasticsearch..."
            sleep 5
          done

          # Create ILM policy for dev (7-day retention)
          curl -X PUT "http://localhost:9200/_ilm/policy/otel-logs-dev-policy" \
            -H 'Content-Type: application/json' \
            -u "elastic:changeme123" \
            -d '{
              "policy": {
                "phases": {
                  "hot": {
                    "min_age": "0ms",
                    "actions": {
                      "rollover": {
                        "max_age": "1d",
                        "max_size": "5gb"
                      },
                      "set_priority": {
                        "priority": 100
                      }
                    }
                  },
                  "delete": {
                    "min_age": "7d",
                    "actions": {
                      "delete": {}
                    }
                  }
                }
              }
            }'

          # Create index template with ILM
          curl -X PUT "http://localhost:9200/_index_template/otel-logs-dev" \
            -H 'Content-Type: application/json' \
            -u "elastic:changeme123" \
            -d '{
              "index_patterns": ["otel-logs-*"],
              "template": {
                "settings": {
                  "number_of_shards": 1,
                  "number_of_replicas": 0,
                  "index.lifecycle.name": "otel-logs-dev-policy",
                  "index.lifecycle.rollover_alias": "otel-logs-dev"
                },
                "mappings": {
                  "properties": {
                    "@timestamp": { "type": "date" },
                    "message": { "type": "text" },
                    "level": { "type": "keyword" },
                    "service.name": { "type": "keyword" },
                    "trace_id": { "type": "keyword" },
                    "span_id": { "type": "keyword" }
                  }
                }
              }
            }'

          echo "ILM policy and index template created successfully!"

# Readiness probe
readinessProbe:
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
EOF
```

**Deploy Elasticsearch:**

```bash
kubectl create namespace logging
helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging -f elasticsearch-values.yaml \
  --wait --timeout 10m
```

**Expected Output:**

```
Release "elasticsearch" does not exist. Installing it now.
NAME: elasticsearch
NAMESPACE: logging
STATUS: deployed
NOTES:
1. Elasticsearch with ILM policies deployed
2. Index retention: 7 days (dev/staging)
3. Credentials: elastic/changeme123
```

**💡 Dev Note:**

- ILM automatically deletes logs older than 7 days (prevents disk filling)
- Daily rollover keeps indices manageable
- Single replica = faster but still persistent

**Create Kibana values:**

```bash
cat > kibana-values.yaml <<'EOF'
elasticsearchHosts: "http://elasticsearch-master:9200"
elasticsearchCredentialSecret: "elasticsearch-master-credentials"

# Dev-appropriate resources
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1
    memory: 1Gi

# Persistent storage for saved objects
persistence:
  enabled: true
  storageClassName: standard
  size: 2Gi

service:
  type: NodePort
  nodePort: 30601

# Kibana config optimized for dev
kibanaConfig:
  kibana.yml: |
    server.host: "0.0.0.0"
    server.name: "kibana-dev"

    # Pre-configure index pattern
    elasticsearch.username: "elastic"

    # Dev: Disable telemetry
    telemetry.enabled: false
    telemetry.optIn: false

    # Dev: More relaxed timeouts
    elasticsearch.requestTimeout: 60000
    elasticsearch.pingTimeout: 30000

# Lifecycle to create default index pattern
lifecycle:
  postStart:
    exec:
      command:
        - bash
        - -c
        - |
          # Wait for Kibana to be ready
          until curl -s -u "elastic:changeme123" http://localhost:5601/api/status | grep -q '"level":"available"'; do
            echo "Waiting for Kibana..."
            sleep 10
          done

          # Create default index pattern for OTel logs
          curl -X POST "http://localhost:5601/api/saved_objects/index-pattern/otel-logs-dev" \
            -H 'kbn-xsrf: true' \
            -H 'Content-Type: application/json' \
            -u "elastic:changeme123" \
            -d '{
              "attributes": {
                "title": "otel-logs-*",
                "timeFieldName": "@timestamp"
              }
            }'

          # Set as default
          curl -X POST "http://localhost:5601/api/kibana/settings/defaultIndex" \
            -H 'kbn-xsrf: true' \
            -H 'Content-Type: application/json' \
            -u "elastic:changeme123" \
            -d '{"value": "otel-logs-dev"}'

          echo "Kibana index pattern created!"

readinessProbe:
  initialDelaySeconds: 90
  timeoutSeconds: 10
  periodSeconds: 10
  failureThreshold: 5
EOF
```

**Deploy Kibana:**

```bash
helm upgrade --install kibana elastic/kibana \
  -n logging -f kibana-values.yaml \
  --wait --timeout 10m
```

**Expected Output:**

```
Release "kibana" does not exist. Installing it now.
NAME: kibana
NAMESPACE: logging
STATUS: deployed
NOTES:
Kibana deployed with:
- Pre-configured index pattern: otel-logs-*
- Access: http://localhost:5601
- Credentials: elastic/changeme123
```

**💡 Dev Note:** Pre-configured index pattern = zero manual setup!

**Verify:**

```bash
kubectl get pods,pvc -n logging
```

**Expected Output:**

```
NAME                                 READY   STATUS    RESTARTS   AGE
pod/elasticsearch-master-0           1/1     Running   0          5m
pod/kibana-kibana-7d8c9f8b5d-xj4k2   1/1     Running   0          3m

NAME                                              STATUS   VOLUME                                     CAPACITY
persistentvolumeclaim/elasticsearch-master-elasticsearch-master-0   Bound    pvc-xxx   30Gi
persistentvolumeclaim/kibana-kibana                                Bound    pvc-yyy   2Gi
```

---

## 🔄 Step 4: Deploy OpenTelemetry Collector with Auto-Instrumentation

### 4.1 Install OTel Operator

```bash
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace observability \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
  --set "manager.collectorImage.tag=0.140.0" \
  --wait
```

**Expected Output:**

```
NAME: opentelemetry-operator
NAMESPACE: observability
STATUS: deployed
REVISION: 1
NOTES:
OpenTelemetry Operator installed successfully!
You can now create Instrumentation and Collector resources.
```

---

### 4.2 Deploy OTel Collector with Enhanced Config

```bash
cat > collector-values.yaml <<'EOF'
mode: deployment

image:
  repository: otel/opentelemetry-collector-contrib
  tag: 0.140.0
  pullPolicy: IfNotPresent

# Dev: Single replica is fine, but set it for clarity
replicaCount: 1

presets:
  # Auto-add k8s attributes (pod, namespace, node, etc.)
  kubernetesAttributes:
    enabled: true
  # Enable k8s cluster metrics
  kubernetesEvents:
    enabled: true
  # Collect host metrics
  hostMetrics:
    enabled: true

service:
  type: ClusterIP

ports:
  # OTLP receivers
  otlp-grpc:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    protocol: TCP
  # Prometheus scrape endpoint
  metrics:
    enabled: true
    containerPort: 8888
    servicePort: 8888
    protocol: TCP
  # Health check
  health:
    enabled: true
    containerPort: 13133
    servicePort: 13133
    protocol: TCP

# Dev: Moderate resources
resources:
  requests:
    cpu: 300m
    memory: 512Mi
  limits:
    cpu: 1
    memory: 1Gi

# Pod annotations for Prometheus scraping
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8888"
  prometheus.io/path: "/metrics"

config:
  extensions:
    health_check:
      endpoint: ":13133"

    # Enable pprof for debugging (dev only!)
    pprof:
      endpoint: ":1777"

    # Memory ballast for stability
    memory_ballast:
      size_mib: 256

  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
          cors:
            allowed_origins:
              - "http://*"
              - "https://*"

    # Scrape collector's own metrics
    prometheus:
      config:
        scrape_configs:
          - job_name: 'otel-collector'
            scrape_interval: 30s
            static_configs:
              - targets: ['localhost:8888']

  processors:
    # Memory limiter to prevent OOM
    memory_limiter:
      check_interval: 5s
      limit_percentage: 75
      spike_limit_percentage: 25

    # Batch for efficiency
    batch:
      send_batch_size: 1024
      timeout: 10s
      send_batch_max_size: 2048

    # Add resource attributes
    resource:
      attributes:
        - key: environment
          value: "dev"
          action: upsert
        - key: cluster.name
          value: "otel-poc"
          action: upsert

    # K8s attributes (from preset)
    k8sattributes:
      auth_type: "serviceAccount"
      passthrough: false
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.deployment.name
          - k8s.statefulset.name
          - k8s.daemonset.name
          - k8s.cronjob.name
          - k8s.job.name
          - k8s.node.name
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.pod.start_time
        labels:
          - tag_name: app
            key: app
            from: pod
          - tag_name: version
            key: version
            from: pod

    # Tail sampling for trace filtering (keep errors, slow requests)
    tail_sampling:
      decision_wait: 10s
      num_traces: 100
      expected_new_traces_per_sec: 10
      policies:
        # Always sample errors
        - name: errors-policy
          type: status_code
          status_code:
            status_codes: [ERROR]
        # Always sample slow traces (>1s)
        - name: slow-traces-policy
          type: latency
          latency:
            threshold_ms: 1000
        # Sample 10% of normal traces
        - name: probabilistic-policy
          type: probabilistic
          probabilistic:
            sampling_percentage: 10

  exporters:
    # Debug exporter for troubleshooting
    debug:
      verbosity: detailed
      sampling_initial: 5
      sampling_thereafter: 200

    # Jaeger for traces
    otlp/jaeger:
      endpoint: jaeger-collector.observability.svc.cluster.local:4317
      tls:
        insecure: true
      sending_queue:
        enabled: true
        num_consumers: 10
        queue_size: 5000
      retry_on_failure:
        enabled: true
        initial_interval: 5s
        max_interval: 30s
        max_elapsed_time: 300s

    # Prometheus for metrics (remote write)
    prometheusremotewrite:
      endpoint: http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/write
      tls:
        insecure: true

    # Also expose metrics endpoint for scraping
    prometheus:
      endpoint: "0.0.0.0:8888"
      namespace: otel_collector
      const_labels:
        cluster: otel-poc
        environment: dev

    # Elasticsearch for logs
    elasticsearch:
      endpoints: ["http://elasticsearch-master.logging.svc.cluster.local:9200"]
      logs_index: otel-logs-dev
      user: elastic
      password: changeme123
      tls:
        insecure_skip_verify: true
      retry:
        enabled: true
        max_requests: 5
        initial_interval: 1s
        max_interval: 30s
      sending_queue:
        enabled: true
        num_consumers: 10
        queue_size: 5000
      # Add index mapping for better Kibana experience
      mapping:
        mode: ecs

  service:
    extensions: [health_check, pprof, memory_ballast]

    pipelines:
      # Traces pipeline
      traces:
        receivers: [otlp]
        processors:
          - memory_limiter
          - k8sattributes
          - resource
          - tail_sampling
          - batch
        exporters: [debug, otlp/jaeger]

      # Metrics pipeline
      metrics:
        receivers: [otlp, prometheus]
        processors:
          - memory_limiter
          - k8sattributes
          - resource
          - batch
        exporters: [prometheus, prometheusremotewrite, debug]

      # Logs pipeline
      logs:
        receivers: [otlp]
        processors:
          - memory_limiter
          - k8sattributes
          - resource
          - batch
        exporters: [debug, elasticsearch]

    # Telemetry for collector itself
    telemetry:
      logs:
        level: info
        encoding: json
      metrics:
        level: detailed
        address: ":8888"
EOF
```

**Deploy Collector:**

```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability -f collector-values.yaml \
  --wait --timeout 5m
```

**Expected Output:**

```
Release "otel-collector" does not exist. Installing it now.
NAME: otel-collector
NAMESPACE: observability
STATUS: deployed
NOTES:
OTel Collector deployed with:
- OTLP gRPC: otel-collector:4317
- OTLP HTTP: otel-collector:4318
- Metrics: otel-collector:8888
- Health: otel-collector:13133
```

### 🧹 Cleanup Section

### Step 1: Delete All Helm Releases

```bash
# List all releases first (optional)
helm list -A

# Delete the main components
helm delete otel-collector -n observability
helm delete opentelemetry-operator -n observability
helm delete jaeger -n observability
helm delete monitoring -n monitoring
helm delete elasticsearch -n logging
helm delete kibana -n logging

# Delete namespaces (will remove any remaining resources)
kubectl delete namespace observability
kubectl delete namespace monitoring
kubectl delete namespace logging
```

**Expected Output:**

```
release "otel-collector" uninstalled
release "opentelemetry-operator" uninstalled
release "jaeger" uninstalled
release "monitoring" uninstalled
release "elasticsearch" uninstalled
release "kibana" uninstalled

namespace "observability" deleted
namespace "monitoring" deleted
namespace "logging" deleted
```

### Step 2: Remove Persistent Volumes (Optional)

If you want to fully clean local storage:

```bash
# List remaining PVs
kubectl get pv

# Delete the manually created Jaeger PV (and any others)
kubectl delete pv jaeger-pv

# Clean the host directory used for persistence
rm -rf /tmp/kind-storage
```

### Step 3: Delete the KIND Cluster

```bash
kind delete cluster --name otel-poc
```

**Expected Output:**

```
Deleting cluster "otel-poc" ...
Deleted nodes: ["otel-poc-control-plane"]
```

### Step 4: Verify Complete Cleanup

```bash
# Check clusters
kind get clusters

# Check kubectl contexts
kubectl config get-contexts

# Optional: Remove the context if it still exists
kubectl config delete-context kind-otel-poc
```

**Expected Output:**

```
No kind clusters found.
```
