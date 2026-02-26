#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

REGION="${REGION:-us-east1}"
PORT_BASE="${PORT_BASE:-9001}"

# Read from stage 01
cd "$TF_DIR/01-cluster"
NODE_IPS_JSON=$(terraform output -json node_private_ips)

# Read from stage 02
cd "$TF_DIR/02-producer-psc"
SERVICE_ATTACHMENT=$(terraform output -raw service_attachment_self_link)

# Read from stage 03
cd "$TF_DIR/03-loader"
CONSUMER_VPC_ID=$(terraform output -raw consumer_vpc_id)
CONSUMER_SUBNET_ID=$(terraform output -raw consumer_subnet_id)

echo "=== Stage 04: PSC Connection ==="
cd "$TF_DIR/04-psc-connect"
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="gcp_project_id=${GCP_PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="service_attachment_self_link=${SERVICE_ATTACHMENT}" \
  -var="consumer_vpc_id=${CONSUMER_VPC_ID}" \
  -var="consumer_subnet_id=${CONSUMER_SUBNET_ID}" \
  -var="port_base=${PORT_BASE}" \
  -var="node_private_ips=${NODE_IPS_JSON}"

PSC_ENDPOINT_IP=$(terraform output -raw psc_endpoint_ip)
PORT_MAPPING=$(terraform output -json port_mapping)

echo ""
echo "PSC Endpoint IP: $PSC_ENDPOINT_IP"
echo "Port mapping (PSC_VIP:port -> node:9042):"
echo "$PORT_MAPPING" | jq -r 'to_entries[] | "  \(.key) -> \(.value)"'
