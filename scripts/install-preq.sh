#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CLUSTER_NAME="otel-stack-cluster"
CONFIG_FILE="config.yml"

echo -e "${GREEN}=== OTEL-Stack Environment Setup ===${NC}"

# --- Part 1: Tool Installation Functions ---

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

install_tools() {
    # Docker
    if ! cmd_exists docker; then
        echo -e "${YELLOW}Installing Docker...${NC}"
        sudo apt update -y && sudo apt install -y docker.io
        sudo usermod -aG docker "$USER"
        echo -e "${RED}Note: Group changes might need a logout or 'newgrp docker' later.${NC}"
    fi

    # Kind
    if ! cmd_exists kind; then
        echo -e "${YELLOW}Installing Kind...${NC}"
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.31.0/kind-linux-amd64
        chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
    fi

    # kubectl
    if ! cmd_exists kubectl; then
        echo -e "${YELLOW}Installing kubectl...${NC}"
        K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    fi

    # Helm
    if ! cmd_exists helm; then
        echo -e "${YELLOW}Installing Helm...${NC}"
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

# --- Part 2: Cluster Configuration ---

create_kind_config() {
    echo -e "${YELLOW}Creating Kind configuration file...${NC}"
    cat <<EOF > $CONFIG_FILE
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.30.0
- role: worker
  image: kindest/node:v1.30.0
- role: worker
  image: kindest/node:v1.30.0
EOF
}

# --- Part 3: Execution ---

# 1. Install everything
install_tools

# 2. Check Docker (Mandatory for Kind)
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running or permissions not set. Try: newgrp docker${NC}"
    exit 1
fi

# 3. Setup Config
create_kind_config

# 4. Launch Cluster
echo -e "${GREEN}🚀 Creating Kind Cluster: $CLUSTER_NAME...${NC}"
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo -e "${YELLOW}Cluster already exists. Skipping creation.${NC}"
else
    kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG_FILE"
fi

# 5. Verification
echo -e "${YELLOW}Verification:${NC}"
kubectl cluster-info --context "kind-$CLUSTER_NAME"
kubectl get nodes

echo -e "${GREEN}====================================${NC}"
echo -e "✅ All tools installed and Cluster is Ready!"
echo -e "Next step: cd KubeSafe-Core && go run main.go"
echo -e "${GREEN}====================================${NC}"