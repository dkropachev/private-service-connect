#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

: "${SCYLLA_API_TOKEN:?Set SCYLLA_API_TOKEN}"

REGION="${REGION:-us-east1}"

echo "=== Stage 01: ScyllaDB Cloud Cluster ==="
cd "$TF_DIR/01-cluster"
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="region=${REGION}"

CLUSTER_ID=$(terraform output -raw cluster_id)
DATACENTER=$(terraform output -raw datacenter)
NODE_IPS_JSON=$(terraform output -json node_private_ips)

echo ""
echo "Cluster ID: $CLUSTER_ID"
echo "Datacenter: $DATACENTER"
echo "Node IPs:   $NODE_IPS_JSON"
