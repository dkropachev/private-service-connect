#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

REGION="${REGION:-us-east1}"
CQL_PORT_BASE="${CQL_PORT_BASE:-9001}"
SSL_CQL_PORT_BASE="${SSL_CQL_PORT_BASE:-9101}"
DNS_DOMAIN="${DNS_DOMAIN:-}"

# Read node IPs from stage 01
cd "$TF_DIR/01-cluster"
NODE_IPS_JSON=$(terraform output -json node_private_ips)

# Discover node VM instances and network info
echo "Discovering ScyllaDB node instances..."

IP_FILTER=""
for ip in $(echo "$NODE_IPS_JSON" | jq -r '.[]'); do
  [ -n "$IP_FILTER" ] && IP_FILTER+=" OR "
  IP_FILTER+="networkInterfaces[0].networkIP=${ip}"
done

NODE_INSTANCES=$(gcloud compute instances list \
  --project="$GCP_PROJECT_ID" \
  --filter="$IP_FILTER" \
  --format="json(name,zone.scope(zones),networkInterfaces[0].networkIP)" | \
  jq '[.[] | {name: .name, zone: .zone, ip: .networkInterfaces[0].networkIP}]')

echo "Node instances: $NODE_INSTANCES"

FIRST_NAME=$(echo "$NODE_INSTANCES" | jq -r '.[0].name')
FIRST_ZONE=$(echo "$NODE_INSTANCES" | jq -r '.[0].zone')

INSTANCE_INFO=$(gcloud compute instances describe "$FIRST_NAME" \
  --zone="$FIRST_ZONE" \
  --project="$GCP_PROJECT_ID" \
  --format="json(networkInterfaces[0].network,networkInterfaces[0].subnetwork)")

SCYLLA_VPC_NAME=$(echo "$INSTANCE_INFO" | jq -r '.networkInterfaces[0].network' | xargs basename)
SCYLLA_SUBNET_NAME=$(echo "$INSTANCE_INFO" | jq -r '.networkInterfaces[0].subnetwork' | xargs basename)

echo "ScyllaDB VPC:    $SCYLLA_VPC_NAME"
echo "ScyllaDB Subnet: $SCYLLA_SUBNET_NAME"

echo ""
echo "=== Stage 02: Producer PSC (in ScyllaDB VPC) ==="
cd "$TF_DIR/02-producer-psc"
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="gcp_project_id=${GCP_PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="scylla_vpc_name=${SCYLLA_VPC_NAME}" \
  -var="scylla_subnet_name=${SCYLLA_SUBNET_NAME}" \
  -var="node_instances=${NODE_INSTANCES}" \
  -var="cql_port_base=${CQL_PORT_BASE}" \
  -var="ssl_cql_port_base=${SSL_CQL_PORT_BASE}" \
  -var="dns_domain=${DNS_DOMAIN}"

SERVICE_ATTACHMENT=$(terraform output -raw service_attachment_self_link)
echo ""
echo "Service Attachment: $SERVICE_ATTACHMENT"
