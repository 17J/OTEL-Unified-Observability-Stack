#!/usr/bin/env bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Starting Otel-Stack & Monitoring Deployment ===${NC}"

# 1. Add Helm Repositories
echo -e "${YELLOW}Step 1: Adding Helm Repositories...${NC}"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo add fluent-bit https://fluent.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io

echo -e "${YELLOW}Updating Helm Repositories...${NC}"
helm repo update

# Function to check file existence
check_file() {
    if [ ! -f "$1" ]; then
        echo -e "${RED}⚠️  Warning: $1 not found in current directory! Skipping that component...${NC}"
        return 1
    fi
    return 0
}

# 2. Deploy Prometheus & Grafana (kube-prometheus-stack)
echo -e "${YELLOW}Step 2: Deploying Prometheus & Grafana...${NC}"
PROM_EXTRA_ARGS=""
if check_file "alertmanager-config.yaml"; then
    PROM_EXTRA_ARGS="-f alertmanager-config.yaml"
fi

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  $PROM_EXTRA_ARGS

# 3. Deploy Jaeger
echo -e "${YELLOW}Step 3: Deploying Jaeger (Distributed Tracing)...${NC}"
helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace observability --create-namespace \
  --set allInOne.enabled=true \
  --set collector.enabled=false \
  --set query.enabled=false \
  --set agent.enabled=false \
  --set provisionDataStore.cassandra=false \
  --set storage.type=memory \
  --set collector.service.otlp.grpc.port=4317 \
  --set collector.service.otlp.http.port=4318

# 4. Deploy Logging Stack (Elasticsearch, Kibana, Fluent-Bit)
echo -e "${YELLOW}Step 4: Deploying Logging Stack (EFK)...${NC}"

# Elasticsearch
if check_file "elasticsearch-values.yaml"; then
    helm upgrade --install elasticsearch elastic/elasticsearch \
      -n logging --create-namespace -f elasticsearch-values.yaml
else
    echo -e "${RED}Skipping Elasticsearch due to missing values file.${NC}"
fi

# Kibana
if check_file "kibana-values.yaml"; then
    helm upgrade --install kibana elastic/kibana \
      -n logging -f kibana-values.yaml
fi

# Fluent-Bit
if check_file "fluent-bit-values.yaml"; then
    helm upgrade --install fluent-bit fluent-bit/fluent-bit \
      -n logging -f fluent-bit-values.yaml
fi

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "Grafana Password: ${YELLOW}admin123${NC}"
echo -e "Check status: ${CYAN}kubectl get pods -A${NC}"
echo -e "${GREEN}==============================================${NC}"