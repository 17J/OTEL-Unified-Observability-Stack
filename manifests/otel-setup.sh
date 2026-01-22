#!/bin/bash

# Colors for output
GREEN='\033[032m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="observability"

echo -e "${YELLOW}🚀 Starting OpenTelemetry Operator Installation...${NC}"

# 1. Create namespace if it doesn't exist
if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    echo -e "Creating namespace: $NAMESPACE..."
    kubectl create namespace $NAMESPACE
else
    echo -e "Namespace $NAMESPACE already exists."
fi

# 2. Add Helm Repository
echo -e "Adding Open-Telemetry Helm repository..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# 3. Install Cert-Manager (Required for OTEL Operator Webhooks)
# Note: OTEL Operator requires cert-manager to handle certificates for admission webhooks.
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing cert-manager (Required for OTEL)...${NC}"
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager --create-namespace \
      --set installCRDs=true --wait
fi

# 4. Install OTEL Operator
echo -e "${GREEN}Installing OpenTelemetry Operator...${NC}"
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace $NAMESPACE \
  --set admissionWebhooks.certManager.enabled=true \
  --wait

echo -e "${GREEN}✅ OTEL Operator is ready in '$NAMESPACE' namespace!${NC}"
kubectl get pods -n $NAMESPACE