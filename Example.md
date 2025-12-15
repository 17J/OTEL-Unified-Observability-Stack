# otel-dev-observability-stack

## 🛠️ OpenTelemetry Observability Stack for Dev/Staging (Jaeger, Prometheus, ELK)

This document provides a complete, production-grade template for deploying a unified OpenTelemetry observability stack in a Kubernetes **Dev/Staging** environment, typically using a local cluster like **KIND** or **Minikube**.

It integrates the OpenTelemetry Collector with all three major backends: **Jaeger** (Traces), **Prometheus/Grafana** (Metrics), and **Elasticsearch/Kibana** (Logs).



### 🚀 Step-by-Step Deployment Guide

This guide assumes you have **Docker**, **kubectl**, and **Helm** installed.


#### Step 1: Add Helm Repositories

Add all necessary Helm charts for the observability components.

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo update
```

#### Step 2: Install Core Backends (Jaeger, Prometheus/Grafana, ELK)

We will install each component into its own namespace for clear separation.

##### 2.1. Jaeger (Traces)

Deploy Jaeger in all-in-one mode for simplicity, using in-memory storage.

```bash
helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace observability --create-namespace \
  --set allInOne.enabled=true \
  --set collector.enabled=false \
  --set storage.type=memory \
  --set collector.service.otlp.grpc.port=4317 \
  --set collector.service.otlp.http.port=4318
```

##### 2.2. Prometheus & Grafana (Metrics)

Deploy the `kube-prometheus-stack` using the provided Alertmanager configuration. **You will need to save the content of `prometheus/alertmanager-config.yaml` to a file before running this command.**

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  -f prometheus/alertmanager-config.yaml
```

##### 2.3. Elasticsearch & Kibana (Logs)

Deploy a single-node Elasticsearch cluster and Kibana using the provided values files. **Remember to update the passwords in `elk/elasticsearch-values.yaml` and save the content of both `elk/elasticsearch-values.yaml` and `elk/kibana-values.yaml` to files before running these commands.**

```bash
# Deploy Elasticsearch
helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging --create-namespace -f elk/elasticsearch-values.yaml

# Deploy Kibana
helm upgrade --install kibana elastic/kibana \
  -n logging -f elk/kibana-values.yaml
```

#### Step 3: Install OpenTelemetry Operator and Collector

##### 3.1. Install OTel Operator

The Operator is required for auto-instrumentation.

```bash
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace observability
```

##### 3.2. Deploy OpenTelemetry Collector

Deploy the Collector using the comprehensive `otel-collector/collector-values.yaml` file. **You will need to save the content of `otel-collector/collector-values.yaml` to a file before running this command.**

```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability -f otel-collector/collector-values.yaml --wait
```

##### 3.3. Apply Auto-Instrumentation CRD

Apply the `instrumentation.yaml` to enable zero-code auto-instrumentation for your applications (e.g., Java). **You will need to save the content of `otel-collector/instrumentation.yaml` to a file before running this command.**

```bash
kubectl apply -f otel-collector/instrumentation.yaml
```

#### Step 4: Verification and Access

Check the status of all pods and access the UIs via port-forwarding.

```bash
# Check all pods in the observability namespace
kubectl get pods -n observability

# Check all pods in the monitoring namespace
kubectl get pods -n monitoring

# Check all pods in the logging namespace
kubectl get pods -n logging

# Access Grafana (User: admin, Pass: admin123)
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

# Access Jaeger UI
kubectl port-forward svc/jaeger-query -n observability 16686:16686

# Access Kibana (NodePort 30601 is configured in kibana-values.yaml)
# Find your cluster's node IP and access: http://<Node-IP>:30601
# Alternatively, use port-forwarding:
# kubectl port-forward svc/kibana -n logging 5601:5601
```

### 💡 Key Features of the Dev/Staging Configuration

| Feature                       | Purpose                                                                                                                                             | Configuration File                     |
| :---------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------- |
| **`filelog` Receiver**        | Collects container logs directly from the Kubernetes node filesystem (`/var/log/pods`).                                                             | `otel-collector/collector-values.yaml` |
| **`tail_sampling` Processor** | Implements intelligent trace sampling (e.g., always keep error traces, always keep traces for critical routes like `/cart`).                        | `otel-collector/collector-values.yaml` |
| **`k8sattributes` Processor** | Enriches all telemetry data (Traces, Metrics, Logs) with Kubernetes metadata (pod name, namespace, etc.).                                           | `otel-collector/collector-values.yaml` |
| **Alertmanager Config**       | Pre-configured routing for critical alerts to PagerDuty and lower-severity alerts to Slack.                                                         | `prometheus/alertmanager-config.yaml`  |
| **Auto-Instrumentation**      | The `instrumentation.yaml` CRD enables zero-code instrumentation for supported languages (e.g., Java) by injecting the OTel agent at the pod level. | `otel-collector/instrumentation.yaml`  |

### 🧹 Cleanup

To remove all deployed components and the KIND cluster:

```bash
# Delete all Helm releases
helm delete otel-collector jaeger -n observability
helm delete monitoring -n monitoring
helm delete elasticsearch kibana -n logging

# Delete the KIND cluster
kind delete cluster --name otel-poc
```

---

## 📄 Configuration File Contents

### 1. `otel-collector/collector-values.yaml`

```yaml
# ==============================================================================
# OpenTelemetry Collector Helm Values (Dev/Staging)
# ==============================================================================
mode: deployment

image:
  repository: otel/opentelemetry-collector-contrib
  tag: 0.140.0 # Use a stable, recent contrib image
  pullPolicy: IfNotPresent

presets:
  - kubernetesAttributes
  - kubeRBACProxy

service:
  type: ClusterIP
  ports:
    otlp-grpc:
      enabled: true
      servicePort: 4317
      containerPort: 4317
      protocol: TCP
    otlp-http:
      enabled: true
      servicePort: 4318
      containerPort: 4318
      protocol: TCP
    metrics:
      enabled: true
      servicePort: 8888
      containerPort: 8888
      protocol: TCP

resources:
  requests:
    cpu: 300m
    memory: 512Mi
  limits:
    cpu: 1
    memory: 1Gi

config:
  ####################
  # EXTENSIONS
  ####################
  extensions:
    health_check:
      endpoint: ":13133"
    pprof:
      endpoint: ":1777"
    zpages:
      endpoint: ":55679"

  ####################
  # RECEIVERS
  ####################
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

    prometheus:
      config:
        scrape_configs:
          - job_name: "otel-collector"
            static_configs:
              - targets: ["0.0.0.0:8888"]

    # Filelog receiver for Kubernetes logs (as requested in original config)
    filelog:
      include:
        - /var/log/pods/*/*/*.log
      start_at: beginning
      include_file_path: true
      include_file_name: true
      operators:
        - type: json_parser
          if: 'body matches "^\\{"'
          parse_from: body
          parse_to: attributes

        - type: regex_parser
          regex: '^/var/log/pods/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<pod_uid>[^/]+)/(?P<container_name>[^/]+)/(?P<restart_count>\d+)\.log$'
          parse_from: attributes["log.file.path"]

  ####################
  # PROCESSORS
  ####################
  processors:
    memory_limiter:
      check_interval: 5s
      limit_percentage: 75
      spike_limit_percentage: 25

    k8sattributes:
      auth_type: serviceAccount
      passthrough: false

    resource:
      attributes:
        - key: deployment.environment
          value: dev
          action: insert
        - key: k8s.cluster.name
          value: otel-poc
          action: insert

    # Tail Sampling for Traces (as requested in original config)
    tail_sampling:
      decision_wait: 10s
      num_traces: 20000
      expected_new_traces_per_sec: 50
      policies:
        # Always keep 500+ errors
        - name: http-errors-only
          type: status_code
          status_code:
            status_codes: [ERROR]

        # Always keep business-critical routes
        - name: cart-and-checkout-only
          type: string_attribute
          string_attribute:
            key: http.route
            values:
              - /cart
              - /checkout

    batch:
      send_batch_size: 1024
      timeout: 10s

  ####################
  # EXPORTERS
  ####################
  exporters:
    debug:
      verbosity: detailed

    prometheus:
      endpoint: 0.0.0.0:8888
      resource_to_telemetry_conversion:
        enabled: true

    otlp/jaeger:
      endpoint: jaeger-all-in-one.observability.svc.cluster.local:4317
      tls:
        insecure: true

    elasticsearch:
      endpoint: https://elasticsearch-master.logging.svc.cluster.local:9200
      logs_index: otel-logs-dev-%{+yyyy.MM}
      user: elastic
      password: CHANGE_ME # MUST be updated with the actual password
      tls:
        insecure_skip_verify: true

  ####################
  # SERVICE PIPELINES
  ####################
  service:
    extensions: [health_check, pprof, zpages]

    telemetry:
      logs:
        level: info
      metrics:
        address: 0.0.0.0:8889

    pipelines:
      traces:
        receivers: [otlp]
        processors:
          - memory_limiter
          - k8sattributes
          - resource
          - tail_sampling
          - batch
        exporters: [debug, otlp/jaeger]

      metrics:
        receivers: [otlp, prometheus]
        processors:
          - memory_limiter
          - k8sattributes
          - resource
          - batch
        exporters: [prometheus, debug]

      logs:
        receivers: [otlp, filelog]
        processors:
          - memory_limiter
          - k8sattributes
          - resource
          - batch
        exporters: [debug, elasticsearch]
```

### 2. `otel-collector/instrumentation.yaml`

```yaml
# ==============================================================================
# OpenTelemetry Operator Instrumentation CRD (Auto-Instrumentation)
# ==============================================================================
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: auto-instrumentation
  namespace: default # Apply to the default namespace for Dev/Staging apps
spec:
  exporter:
    # Target the OTel Collector service (assuming default Helm release name)
    endpoint: http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318

  propagators:
    - tracecontext
    - baggage

  sampler:
    type: always_on # Always sample for Dev/Staging

  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
    env:
      - name: OTEL_TRACES_EXPORTER
        value: "otlp"
      - name: OTEL_METRICS_EXPORTER
        value: "otlp"
      - name: OTEL_LOGS_EXPORTER
        value: "otlp"
      - name: OTEL_EXPORTER_OTLP_PROTOCOL
        value: "http/protobuf" # Use HTTP/protobuf for local/KIND stability
```

### 3. `prometheus/alertmanager-config.yaml`

```yaml
# ==============================================================================
# Prometheus Alertmanager Helm Values (Dev/Staging)
# ==============================================================================
alertmanager:
  config:
    global: {}

    receivers:
      - name: "null"

      - name: "slack-notifications"
        slack_configs:
          - channel: "#alerts-devops"
            api_url: "{SLACK_WEBHOOK_URL}" # Placeholder for Slack Webhook
            send_resolved: true
            title: "[{{ .Status | toUpper }}] - {{ .CommonLabels.alertname }}"
            text: |
              *Severity:* {{ .CommonLabels.severity }}
              *Summary:* {{ .CommonLabels.summary }}

      - name: "pagerduty-critical"
        pagerduty_configs:
          - service_key: "{PAGERDUTY_INTEGRATION_KEY}" # Placeholder for PagerDuty Key
            send_resolved: true
            severity: "critical"

    route:
      group_by: ["alertname", "cluster", "service"]
      receiver: "null"
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h

      routes:
        - match:
            severity: "critical"
          receiver: "pagerduty-critical"
          group_wait: 5s
          group_interval: 1m

        - matchers:
            - severity =~ "warning|info"
          receiver: "slack-notifications"
```

### 4. `elk/elasticsearch-values.yaml`

```yaml
# ==============================================================================
# Elasticsearch Helm Values (Dev/Staging)
# ==============================================================================
clusterName: elasticsearch

# Security settings (MUST be changed for any environment)
auth:
  enabled: true
  elasticUser:
    password: "CHANGE_ME" # Must change
  kibana:
    password: "CHANGE_ME_KIBANA"

# Reduced replicas for Dev/Staging
replicas: 1 # Changed from 3 to 1 for simplicity and resource saving
minimumMasterNodes: 1

# Resource allocation (reduced for Dev/Staging)
resources:
  requests:
    cpu: 500m # Reduced from 1
    memory: 2Gi # Reduced from 4Gi
  limits:
    cpu: 1
    memory: 4Gi

# Volume Claim Template (using default storage class)
volumeClaimTemplate:
  storageClassName: standard # Changed from gp2 to standard for broader compatibility
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 20Gi # Reduced from 50Gi

# Java Heap Size (50% of memory limit)
esJavaOpts: "-Xmx2048m -Xms2048m" # 2GB heap for 4GB limit
```

### 5. `elk/kibana-values.yaml`

```yaml
# ==============================================================================
# Kibana Helm Values (Dev/Staging)
# ==============================================================================
# Match Elasticsearch service name
elasticsearchHosts: "http://elasticsearch-master:9200"

# Match Elasticsearch password secret
elasticsearchCredentialSecret: "elasticsearch-master-credentials" # Assuming the default secret name

# Resource allocation
resources:
  requests:
    cpu: "100m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"

# Service configuration
service:
  type: NodePort
  nodePort: 30601 # Expose Kibana on this port for easy access

# Readiness check
readinessProbe:
  initialDelaySeconds: 60
  timeoutSeconds: 10
```
