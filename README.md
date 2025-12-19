![OpenTelemetry Collector Architecture Diagram](https://cdn.sanity.io/images/rdn92ihu/production/b1c172e7f1a8895bf3b9a2a6d4ab10f9f93161b5-2902x1398.png?w=1200)

---

# 🛠️ OpenTelemetry Observability Stack - Dev/Staging Deployment

Complete deployment guide for OpenTelemetry with Jaeger, Prometheus, and ELK stack in Kubernetes (KIND/Minikube).

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

## 🚀 Step 1: Create KIND Cluster

```bash
# Create a KIND cluster named otel-poc
kind create cluster --name otel-poc
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
You can now use your cluster with:

kubectl cluster-info --context kind-otel-poc
```

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
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "open-telemetry" chart repository
...Successfully got an update from the "elastic" chart repository
Update Complete. ⎈Happy Helming!⎈
```

---

## 🔧 Step 3: Deploy Core Backends

### 3.1 Deploy Jaeger (Traces)

```bash
helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace observability --create-namespace \
  --set allInOne.enabled=true \
  --set collector.enabled=false \
  --set storage.type=memory \
  --set allInOne.ingester.service.otlp.grpc.port=4317 \
  --set allInOne.ingester.service.otlp.http.port=4318
```

**Expected Output:**

```
Release "jaeger" does not exist. Installing it now.
NAME: jaeger
LAST DEPLOYED: Mon Dec 15 10:30:45 2025
NAMESPACE: observability
STATUS: deployed
REVISION: 1
NOTES:
###############################################################################
# Jaeger all-in-one is deployed
# Access the UI: kubectl port-forward -n observability svc/jaeger-query 16686:16686
###############################################################################
```

**Verify Deployment:**

```bash
kubectl get pods -n observability
```

**Expected Output:**

```
NAME                              READY   STATUS    RESTARTS   AGE
jaeger-all-in-one-0               1/1     Running   0          45s
```

---

### 3.2 Deploy Prometheus & Grafana (Metrics)

**First, create the Alertmanager config file:**

```bash
cat > alertmanager-config.yaml <<'EOF'
alertmanager:
  config:
    global: {}
    receivers:
      - name: "null"
      - name: "slack-notifications"
        slack_configs:
          - channel: "#alerts-devops"
            api_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
            send_resolved: true
            title: "[{{ .Status | toUpper }}] - {{ .CommonLabels.alertname }}"
            text: |
              *Severity:* {{ .CommonLabels.severity }}
              *Summary:* {{ .CommonLabels.summary }}
      - name: "pagerduty-critical"
        pagerduty_configs:
          - service_key: "YOUR_PAGERDUTY_KEY"
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
EOF
```

**Deploy:**

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  -f alertmanager-config.yaml
```

**Expected Output:**

```
Release "monitoring" does not exist. Installing it now.
NAME: monitoring
LAST DEPLOYED: Mon Dec 15 10:32:15 2025
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=monitoring"

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.
```

**Verify Deployment:**

```bash
kubectl get pods -n monitoring
```

**Expected Output:**

```
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2     Running   0          2m
monitoring-grafana-7b4d7c8f9d-xk2ls                      3/3     Running   0          2m
monitoring-kube-prometheus-operator-5d8b9c8d7f-9h4j2     1/1     Running   0          2m
monitoring-kube-state-metrics-6c7f8b9d8c-7x2k4           1/1     Running   0          2m
monitoring-prometheus-node-exporter-k8j2l                1/1     Running   0          2m
prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   0          2m
```

---

### 3.3 Deploy Elasticsearch & Kibana (Logs)

**Create Elasticsearch values file:**

```bash
cat > elasticsearch-values.yaml <<'EOF'
clusterName: elasticsearch
replicas: 1
minimumMasterNodes: 1

resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 1
    memory: 4Gi

volumeClaimTemplate:
  storageClassName: standard
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 20Gi

esJavaOpts: "-Xmx2048m -Xms2048m"

secret:
  enabled: true
  password: "changeme123"
EOF
```

**Deploy Elasticsearch:**

```bash
helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging --create-namespace -f elasticsearch-values.yaml
```

**Expected Output:**

```
Release "elasticsearch" does not exist. Installing it now.
NAME: elasticsearch
LAST DEPLOYED: Mon Dec 15 10:35:00 2025
NAMESPACE: logging
STATUS: deployed
REVISION: 1
NOTES:
1. Watch all cluster members come up.
  $ kubectl get pods --namespace=logging -l app=elasticsearch-master -w
```

**Create Kibana values file:**

```bash
cat > kibana-values.yaml <<'EOF'
elasticsearchHosts: "http://elasticsearch-master:9200"

elasticsearchCredentialSecret: "elasticsearch-master-credentials"

resources:
  requests:
    cpu: "100m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"

service:
  type: NodePort
  nodePort: 30601

readinessProbe:
  initialDelaySeconds: 60
  timeoutSeconds: 10
EOF
```

**Deploy Kibana:**

```bash
helm upgrade --install kibana elastic/kibana \
  -n logging -f kibana-values.yaml
```

**Expected Output:**

```
Release "kibana" does not exist. Installing it now.
NAME: kibana
LAST DEPLOYED: Mon Dec 15 10:36:30 2025
NAMESPACE: logging
STATUS: deployed
REVISION: 1
```

**Verify Deployment:**

```bash
kubectl get pods -n logging
```

**Expected Output:**

```
NAME                             READY   STATUS    RESTARTS   AGE
elasticsearch-master-0           1/1     Running   0          3m
kibana-kibana-7d8c9f8b5d-xj4k2   1/1     Running   0          90s
```

---

## 🔄 Step 4: Deploy OpenTelemetry Collector

### 4.1 Install OTel Operator

```bash
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace observability
```

**Expected Output:**

```
NAME: opentelemetry-operator
LAST DEPLOYED: Mon Dec 15 10:38:00 2025
NAMESPACE: observability
STATUS: deployed
REVISION: 1
```

---

### 4.2 Deploy OTel Collector

**Create collector values file:**

```bash
cat > collector-values.yaml <<'EOF'
mode: deployment

image:
  repository: otel/opentelemetry-collector-contrib
  tag: 0.140.0
  pullPolicy: IfNotPresent

presets:
  kubernetesAttributes:
    enabled: true

service:
  type: ClusterIP

ports:
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
  metrics:
    enabled: true
    containerPort: 8888
    servicePort: 8888
    protocol: TCP

resources:
  requests:
    cpu: 300m
    memory: 512Mi
  limits:
    cpu: 1
    memory: 1Gi

config:
  extensions:
    health_check:
      endpoint: ":13133"

  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      send_batch_size: 1024
      timeout: 10s

    memory_limiter:
      check_interval: 5s
      limit_percentage: 75
      spike_limit_percentage: 25

  exporters:
    debug:
      verbosity: detailed

    otlp/jaeger:
      endpoint: jaeger-all-in-one.observability.svc.cluster.local:4317
      tls:
        insecure: true

    prometheus:
      endpoint: 0.0.0.0:8888

    elasticsearch:
      endpoints: ["https://elasticsearch-master.logging.svc.cluster.local:9200"]
      logs_index: otel-logs-dev
      user: elastic
      password: changeme123
      tls:
        insecure_skip_verify: true

  service:
    extensions: [health_check]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [debug, otlp/jaeger]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheus, debug]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [debug, elasticsearch]
EOF
```

**Deploy:**

```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability -f collector-values.yaml --wait
```

**Expected Output:**

```
Release "otel-collector" does not exist. Installing it now.
NAME: otel-collector
LAST DEPLOYED: Mon Dec 15 10:40:00 2025
NAMESPACE: observability
STATUS: deployed
REVISION: 1
```

**Verify:**

```bash
kubectl get pods -n observability
```

**Expected Output:**

```
NAME                                                READY   STATUS    RESTARTS   AGE
jaeger-all-in-one-0                                 1/1     Running   0          10m
opentelemetry-operator-75d8c9f8b5d-k2j4l            2/2     Running   0          2m
otel-collector-opentelemetry-collector-7b8d9c8-xj2  1/1     Running   0          45s
```

---

## 🎯 Step 5: Access the UIs

### Access Grafana

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
```

**Expected Output:**

```
Forwarding from 127.0.0.1:3000 -> 3000
Forwarding from [::1]:3000 -> 3000
```

**Access:** http://localhost:3000

- **Username:** admin
- **Password:** admin123

---

### Access Jaeger

```bash
kubectl port-forward svc/jaeger-query -n observability 16686:16686
```

**Expected Output:**

```
Forwarding from 127.0.0.1:16686 -> 16686
Forwarding from [::1]:16686 -> 16686
```

**Access:** http://localhost:16686

---

### Access Kibana

```bash
kubectl port-forward svc/kibana-kibana -n logging 5601:5601
```

**Expected Output:**

```
Forwarding from 127.0.0.1:5601 -> 5601
Forwarding from [::1]:5601 -> 5601
```

**Access:** http://localhost:5601

- **Username:** elastic
- **Password:** changeme123

---

## ✅ Verification Commands

### Check All Namespaces

```bash
kubectl get all -n observability
kubectl get all -n monitoring
kubectl get all -n logging
```

**Expected Summary:**

```
# observability namespace: 3+ pods running
# monitoring namespace: 6+ pods running
# logging namespace: 2+ pods running
```

---

### Test OTel Collector Connectivity

```bash
kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -- \
  curl -X POST http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
```

**Expected Output:**

```
{}
pod "test-curl" deleted
```

---

## 🧹 Cleanup

```bash
# Delete Helm releases
helm delete otel-collector opentelemetry-operator jaeger -n observability
helm delete monitoring -n monitoring
helm delete elasticsearch kibana -n logging

# Delete namespaces
kubectl delete namespace observability monitoring logging

# Delete KIND cluster
kind delete cluster --name otel-poc
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
Deleting cluster "otel-poc" ...
```

---

## 🎉 Success Criteria

✅ All pods in `observability`, `monitoring`, and `logging` namespaces are in **Running** state  
✅ Grafana accessible at http://localhost:3000  
✅ Jaeger UI accessible at http://localhost:16686  
✅ Kibana accessible at http://localhost:5601  
✅ OTel Collector accepting OTLP traces/metrics/logs on ports 4317/4318

---

## 📊 Expected Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Application Pods                    │
│            (Auto-instrumented via OTel)             │
└────────────────────┬────────────────────────────────┘
                     │ OTLP (4317/4318)
                     ▼
┌─────────────────────────────────────────────────────┐
│           OpenTelemetry Collector                    │
│  (Receives, Processes, Exports Telemetry)           │
└──────┬──────────────┬──────────────┬────────────────┘
       │              │              │
       │ Traces       │ Metrics      │ Logs
       ▼              ▼              ▼
┌──────────┐   ┌──────────────┐   ┌──────────────┐
│  Jaeger  │   │  Prometheus  │   │ Elasticsearch│
│  :16686  │   │  + Grafana   │   │  + Kibana    │
└──────────┘   │  :3000       │   │  :5601       │
               └──────────────┘   └──────────────┘
```
