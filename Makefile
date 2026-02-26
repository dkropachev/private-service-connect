SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eo pipefail -c
.DEFAULT_GOAL := help

# ─── Defaults ─────────────────────────────────────────────────────────
REGION            ?= us-east1
ZONE              ?= $(REGION)-b
CQL_PORT_BASE     ?= 9001
SSL_CQL_PORT_BASE ?= $(shell echo $$(($(CQL_PORT_BASE) + 100)))
DNS_DOMAIN        ?=
PORT_BASE         ?= $(CQL_PORT_BASE)
LATTE_DURATION    ?= 60s
LATTE_RATE        ?= 1000
LATTE_CONNECTIONS ?= 4

TF_DIR := terraform

# ─── Helpers ──────────────────────────────────────────────────────────

define check_var
$(if $($(1)),,$(error $(1) is required. Set it via env or make var: make $(MAKECMDGOALS) $(1)=...))
endef

# ─── Stage 01: ScyllaDB Cloud Cluster ────────────────────────────────

.PHONY: stage-01
stage-01:
	$(call check_var,SCYLLA_API_TOKEN)
	echo "=== Stage 01: ScyllaDB Cloud Cluster ==="
	cd $(TF_DIR)/01-cluster
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="region=$(REGION)"
	echo ""
	echo "Cluster ID: $$(terraform output -raw cluster_id)"
	echo "Datacenter: $$(terraform output -raw datacenter)"
	echo "Node IPs:   $$(terraform output -json node_private_ips)"

# ─── Stage 02: Producer PSC ──────────────────────────────────────────

.PHONY: stage-02
stage-02:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Stage 02: Producer PSC (in ScyllaDB VPC) ==="
	# Resolve node IPs — explicit NODE_IPS or read from stage 01
	if [ -n "$${NODE_IPS:-}" ]; then
		_NODE_IPS_JSON="$$(echo "$$NODE_IPS" | jq -c '
			if type == "array" then . else split(",") end
		')"
	else
		_NODE_IPS_JSON="$$(cd $(TF_DIR)/01-cluster && terraform output -json node_private_ips 2>/dev/null)" \
			|| { echo "ERROR: Cannot read node_private_ips from stage 01. Set NODE_IPS explicitly."; exit 1; }
	fi
	# Resolve VPC/subnet/instances — explicit overrides or auto-discover
	if [ -n "$${SCYLLA_VPC_NAME:-}" ] && [ -n "$${SCYLLA_SUBNET_NAME:-}" ] && [ -n "$${NODE_INSTANCES:-}" ]; then
		echo "Using explicit SCYLLA_VPC_NAME, SCYLLA_SUBNET_NAME, NODE_INSTANCES"
		_SCYLLA_VPC_NAME="$$SCYLLA_VPC_NAME"
		_SCYLLA_SUBNET_NAME="$$SCYLLA_SUBNET_NAME"
		_NODE_INSTANCES="$$NODE_INSTANCES"
	else
		echo "Discovering ScyllaDB node instances from IPs..."
		IP_FILTER=""
		for ip in $$(echo "$$_NODE_IPS_JSON" | jq -r '.[]'); do
			[ -n "$$IP_FILTER" ] && IP_FILTER+=" OR "
			IP_FILTER+="networkInterfaces[0].networkIP=$${ip}"
		done
		_NODE_INSTANCES=$$(gcloud compute instances list \
			--project="$(GCP_PROJECT_ID)" \
			--filter="$$IP_FILTER" \
			--format='json(name,zone.scope(zones),networkInterfaces[0].networkIP)' | \
			jq -c '[.[] | {name: .name, zone: .zone, ip: .networkInterfaces[0].networkIP}]')
		echo "Node instances: $$_NODE_INSTANCES"
		FIRST_NAME=$$(echo "$$_NODE_INSTANCES" | jq -r '.[0].name')
		FIRST_ZONE=$$(echo "$$_NODE_INSTANCES" | jq -r '.[0].zone')
		INSTANCE_INFO=$$(gcloud compute instances describe "$$FIRST_NAME" \
			--zone="$$FIRST_ZONE" \
			--project="$(GCP_PROJECT_ID)" \
			--format='json(networkInterfaces[0].network,networkInterfaces[0].subnetwork)')
		_SCYLLA_VPC_NAME=$$(echo "$$INSTANCE_INFO" | jq -r '.networkInterfaces[0].network' | xargs basename)
		_SCYLLA_SUBNET_NAME=$$(echo "$$INSTANCE_INFO" | jq -r '.networkInterfaces[0].subnetwork' | xargs basename)
		echo "ScyllaDB VPC:    $$_SCYLLA_VPC_NAME"
		echo "ScyllaDB Subnet: $$_SCYLLA_SUBNET_NAME"
	fi
	cd $(TF_DIR)/02-producer-psc
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="gcp_project_id=$(GCP_PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="scylla_vpc_name=$${_SCYLLA_VPC_NAME}" \
		-var="scylla_subnet_name=$${_SCYLLA_SUBNET_NAME}" \
		-var="node_instances=$${_NODE_INSTANCES}" \
		-var="cql_port_base=$(CQL_PORT_BASE)" \
		-var="ssl_cql_port_base=$(SSL_CQL_PORT_BASE)" \
		-var="dns_domain=$(DNS_DOMAIN)"
	echo ""
	echo "Service Attachment: $$(terraform output -raw service_attachment_self_link)"

# ─── Stage 03: Consumer VPC + Loader VM ──────────────────────────────

.PHONY: stage-03
stage-03:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Stage 03: Loader Infrastructure ==="
	# Read CQL credentials and node IPs from stage 01
	_NODE_IPS_JSON="$$(cd $(TF_DIR)/01-cluster && terraform output -json node_private_ips 2>/dev/null)" \
		|| { echo "ERROR: Cannot read node_private_ips from stage 01."; exit 1; }
	_CQL_USERNAME="$$(cd $(TF_DIR)/01-cluster && terraform output -raw cql_username 2>/dev/null)" \
		|| { echo "ERROR: Cannot read cql_username from stage 01."; exit 1; }
	_CQL_PASSWORD="$$(cd $(TF_DIR)/01-cluster && terraform output -raw cql_password 2>/dev/null)" \
		|| { echo "ERROR: Cannot read cql_password from stage 01."; exit 1; }
	cd $(TF_DIR)/03-loader
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="gcp_project_id=$(GCP_PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="cql_username=$${_CQL_USERNAME}" \
		-var="cql_password=$${_CQL_PASSWORD}" \
		-var="port_base=$(PORT_BASE)" \
		-var="node_private_ips=$${_NODE_IPS_JSON}"
	echo ""
	echo "Loader VM: $$(terraform output -raw loader_vm_name) ($$(terraform output -raw loader_vm_zone))"

# ─── Stage 04: PSC Endpoint Connection ───────────────────────────────

.PHONY: stage-04
stage-04:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Stage 04: PSC Connection ==="
	# Read from prior stages
	_NODE_IPS_JSON="$$(cd $(TF_DIR)/01-cluster && terraform output -json node_private_ips 2>/dev/null)" \
		|| { echo "ERROR: Cannot read node_private_ips from stage 01."; exit 1; }
	_SERVICE_ATTACHMENT="$$(cd $(TF_DIR)/02-producer-psc && terraform output -raw service_attachment_self_link 2>/dev/null)" \
		|| { echo "ERROR: Cannot read service_attachment_self_link from stage 02."; exit 1; }
	_CONSUMER_VPC_ID="$$(cd $(TF_DIR)/03-loader && terraform output -raw consumer_vpc_id 2>/dev/null)" \
		|| { echo "ERROR: Cannot read consumer_vpc_id from stage 03."; exit 1; }
	_CONSUMER_SUBNET_ID="$$(cd $(TF_DIR)/03-loader && terraform output -raw consumer_subnet_id 2>/dev/null)" \
		|| { echo "ERROR: Cannot read consumer_subnet_id from stage 03."; exit 1; }
	cd $(TF_DIR)/04-psc-connect
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="gcp_project_id=$(GCP_PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="service_attachment_self_link=$${_SERVICE_ATTACHMENT}" \
		-var="consumer_vpc_id=$${_CONSUMER_VPC_ID}" \
		-var="consumer_subnet_id=$${_CONSUMER_SUBNET_ID}" \
		-var="port_base=$(PORT_BASE)" \
		-var="node_private_ips=$${_NODE_IPS_JSON}"
	echo ""
	echo "PSC Endpoint IP: $$(terraform output -raw psc_endpoint_ip)"
	echo "Port mapping:"
	terraform output -json port_mapping | jq -r 'to_entries[] | "  \(.key) -> \(.value)"'

# ─── Stage 05: Bench VM ──────────────────────────────────────────────

.PHONY: stage-05
stage-05:
	$(call check_var,GCP_PROJECT_ID)
	$(call check_var,DNS_DOMAIN)
	echo "=== Stage 05: Bench VM ==="
	cd $(TF_DIR)/05-bench
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="gcp_project_id=$(GCP_PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="dns_domain=$(DNS_DOMAIN)"
	echo ""
	echo "Bench VM: $$(terraform output -raw bench_vm_name) ($$(terraform output -raw bench_vm_zone))"
	echo "Test FQDN: $$(terraform output -raw test_fqdn)"

# ─── Bulk Targets ─────────────────────────────────────────────────────

.PHONY: deploy all stages-02-04 stages-02-05

deploy all: stage-01 stage-02 stage-03 stage-04 stage-05

stages-02-04: stage-02 stage-03 stage-04

stages-02-05: stage-02 stage-03 stage-04 stage-05

# ─── Destroy Targets ──────────────────────────────────────────────────

.PHONY: destroy-05
destroy-05:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Destroying Stage 05: Bench VM ==="
	cd $(TF_DIR)/05-bench
	if [ -d .terraform ]; then
		terraform destroy -input=false -auto-approve \
			-var="gcp_project_id=$(GCP_PROJECT_ID)" \
			-var="region=$(REGION)" \
			-var="zone=$(ZONE)" \
			-var="dns_domain=$${DNS_DOMAIN:-placeholder}" \
			|| echo "Stage 05 destroy failed or already clean"
	else
		echo "Stage 05: not initialized, skipping"
	fi

.PHONY: destroy-04
destroy-04:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Destroying Stage 04: PSC Connection ==="
	cd $(TF_DIR)/04-psc-connect
	if [ -d .terraform ]; then
		terraform destroy -input=false -auto-approve \
			-var="gcp_project_id=$(GCP_PROJECT_ID)" \
			-var="region=$(REGION)" \
			-var="service_attachment_self_link=placeholder" \
			-var="consumer_vpc_id=placeholder" \
			-var="consumer_subnet_id=placeholder" \
			-var='node_private_ips=[]' \
			|| echo "Stage 04 destroy failed or already clean"
	else
		echo "Stage 04: not initialized, skipping"
	fi

.PHONY: destroy-03
destroy-03:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Destroying Stage 03: Loader Infrastructure ==="
	cd $(TF_DIR)/03-loader
	if [ -d .terraform ]; then
		terraform destroy -input=false -auto-approve \
			-var="gcp_project_id=$(GCP_PROJECT_ID)" \
			-var="region=$(REGION)" \
			-var="zone=$(ZONE)" \
			-var="cql_username=placeholder" \
			-var="cql_password=placeholder" \
			-var='node_private_ips=[]' \
			|| echo "Stage 03 destroy failed or already clean"
	else
		echo "Stage 03: not initialized, skipping"
	fi

.PHONY: destroy-02
destroy-02:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Destroying Stage 02: Producer PSC ==="
	cd $(TF_DIR)/02-producer-psc
	if [ -d .terraform ]; then
		terraform destroy -input=false -auto-approve \
			-var="gcp_project_id=$(GCP_PROJECT_ID)" \
			-var="region=$(REGION)" \
			-var="scylla_vpc_name=placeholder" \
			-var="scylla_subnet_name=placeholder" \
			-var='node_instances=[]' \
			|| echo "Stage 02 destroy failed or already clean"
	else
		echo "Stage 02: not initialized, skipping"
	fi

.PHONY: destroy-01
destroy-01:
	echo "=== Destroying Stage 01: ScyllaDB Cluster ==="
	cd $(TF_DIR)/01-cluster
	if [ -d .terraform ]; then
		terraform destroy -input=false -auto-approve \
			-var="region=$(REGION)" \
			|| echo "Stage 01 destroy failed or already clean"
	else
		echo "Stage 01: not initialized, skipping"
	fi

.PHONY: destroy
destroy: destroy-05 destroy-04 destroy-03 destroy-02 destroy-01
	echo ""
	echo "=== Destroy complete ==="

# ─── Init & Validate ──────────────────────────────────────────────────

.PHONY: init
init:
	for stage in 01-cluster 02-producer-psc 03-loader 04-psc-connect 05-bench; do
		echo "=== terraform init: $$stage ==="
		(cd $(TF_DIR)/$$stage && terraform init -input=false)
	done

.PHONY: validate
validate:
	for stage in 01-cluster 02-producer-psc 03-loader 04-psc-connect 05-bench; do
		echo "=== terraform validate: $$stage ==="
		(cd $(TF_DIR)/$$stage && terraform validate)
	done

# ─── Run Latte Benchmark ──────────────────────────────────────────────

.PHONY: run-latte
run-latte:
	$(call check_var,GCP_PROJECT_ID)
	# Read loader VM info from stage 03
	cd $(TF_DIR)/03-loader
	LOADER_VM_NAME=$$(terraform output -raw loader_vm_name)
	LOADER_VM_ZONE=$$(terraform output -raw loader_vm_zone)
	# Read port mapping from stage 04
	cd ../04-psc-connect
	PORT_MAPPING=$$(terraform output -json port_mapping 2>/dev/null || echo "{}")
	echo "Loader VM:    $$LOADER_VM_NAME ($$LOADER_VM_ZONE)"
	echo "Duration:     $(LATTE_DURATION)"
	echo "Rate:         $(LATTE_RATE) ops/s"
	echo "Connections:  $(LATTE_CONNECTIONS)"
	echo ""
	if [ "$$PORT_MAPPING" != "{}" ]; then
		echo "Port mapping:"
		echo "$$PORT_MAPPING" | jq -r 'to_entries[] | "  \(.key) -> \(.value)"'
		echo ""
	fi
	REMOTE_CMD=$$(cat <<'REMOTEOF'
	set -euo pipefail
	source /opt/latte/env.sh
	DURATION="$${1:-60s}"
	RATE="$${2:-1000}"
	CONNECTIONS="$${3:-4}"
	LATTE="docker run --rm --network host -v /opt/latte:/workdir scylladb/latte:latest"
	echo "Connecting to: $$PSC_ENDPOINT"
	echo ""
	echo "=== Creating schema ==="
	$$LATTE schema \
		--user "$$CQL_USERNAME" --password "$$CQL_PASSWORD" \
		/workdir/basic_read_write.rn "$$PSC_ENDPOINT"
	echo "=== Running write workload ==="
	$$LATTE run \
		--user "$$CQL_USERNAME" --password "$$CQL_PASSWORD" \
		--duration "$$DURATION" --rate "$$RATE" --connections "$$CONNECTIONS" \
		--function write \
		/workdir/basic_read_write.rn "$$PSC_ENDPOINT"
	echo "=== Running read workload ==="
	$$LATTE run \
		--user "$$CQL_USERNAME" --password "$$CQL_PASSWORD" \
		--duration "$$DURATION" --rate "$$RATE" --connections "$$CONNECTIONS" \
		--function read \
		/workdir/basic_read_write.rn "$$PSC_ENDPOINT"
	REMOTEOF
	)
	gcloud compute ssh "$$LOADER_VM_NAME" \
		--zone="$$LOADER_VM_ZONE" \
		--project="$(GCP_PROJECT_ID)" \
		--tunnel-through-iap \
		-- bash -c "$$REMOTE_CMD" -- "$(LATTE_DURATION)" "$(LATTE_RATE)" "$(LATTE_CONNECTIONS)"

# ─── Run Scylla Bench Test ─────────────────────────────────────────────

.PHONY: run-scylla-bench
run-scylla-bench:
	$(call check_var,GCP_PROJECT_ID)
	cd $(TF_DIR)/05-bench
	VM_NAME=$$(terraform output -raw bench_vm_name)
	VM_ZONE=$$(terraform output -raw bench_vm_zone)
	FQDN=$$(terraform output -raw test_fqdn)
	echo "VM:   $$VM_NAME ($$VM_ZONE)"
	echo "FQDN: $$FQDN"
	echo ""
	gcloud compute ssh "$$VM_NAME" \
		--zone="$$VM_ZONE" \
		--project="$(GCP_PROJECT_ID)" \
		-- -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
		"cat /opt/bench-test.done 2>/dev/null && echo 'Startup test already ran. Re-running:' ; echo '=== DNS ===' && dig A $$FQDN +short && echo '' && echo '=== CQL ports ===' && source /opt/bench/env.sh 2>/dev/null; for p in \$$(seq 9001 9003); do timeout 3 bash -c \"exec 3<>/dev/tcp/$$FQDN/\$$p\" 2>/dev/null && echo \"$$FQDN:\$$p OPEN\" || echo \"$$FQDN:\$$p CLOSED\"; done"

# ─── Help ──────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo "ScyllaDB GCP Private Service Connect — Makefile Orchestration"
	@echo ""
	@echo "Individual stages:"
	@echo "  make stage-01              ScyllaDB Cloud cluster (needs SCYLLA_API_TOKEN)"
	@echo "  make stage-02              Producer PSC — NEG, ILB, Service Attachment"
	@echo "  make stage-03              Consumer VPC + loader VM"
	@echo "  make stage-04              PSC endpoint connection"
	@echo "  make stage-05              Bench VM (needs DNS_DOMAIN)"
	@echo ""
	@echo "Bulk:"
	@echo "  make deploy                All stages 01-05"
	@echo "  make stages-02-04          Stages 02, 03, 04"
	@echo "  make stages-02-05          Stages 02, 03, 04, 05"
	@echo ""
	@echo "Teardown:"
	@echo "  make destroy               All stages in reverse"
	@echo "  make destroy-XX            Individual stage destroy (e.g. destroy-02)"
	@echo ""
	@echo "Benchmarks:"
	@echo "  make run-latte             Run latte benchmark on loader VM"
	@echo "  make run-scylla-bench      Run connectivity test on bench VM"
	@echo ""
	@echo "Helpers:"
	@echo "  make init                  terraform init all stages"
	@echo "  make validate              terraform validate all stages"
	@echo ""
	@echo "Variables (env or make vars):"
	@echo "  GCP_PROJECT_ID             GCP project (required for stages 02-05)"
	@echo "  SCYLLA_API_TOKEN           ScyllaDB Cloud API token (stage 01)"
	@echo "  REGION                     GCP region (default: us-east1)"
	@echo "  ZONE                       GCP zone (default: REGION-b)"
	@echo "  CQL_PORT_BASE              Base CQL port (default: 9001)"
	@echo "  SSL_CQL_PORT_BASE          Base SSL CQL port (default: CQL_PORT_BASE+100)"
	@echo "  DNS_DOMAIN                 PSC DNS domain (stage 02 optional, stage 05 required)"
	@echo "  NODE_IPS                   Comma-separated or JSON node IPs (stage 02 override)"
	@echo "  SCYLLA_VPC_NAME            Explicit VPC name (stage 02 override)"
	@echo "  SCYLLA_SUBNET_NAME         Explicit subnet name (stage 02 override)"
	@echo "  NODE_INSTANCES             Explicit node instances JSON (stage 02 override)"
	@echo "  LATTE_DURATION             Benchmark duration (default: 60s)"
	@echo "  LATTE_RATE                 Benchmark ops/s (default: 1000)"
	@echo "  LATTE_CONNECTIONS          Benchmark connections (default: 4)"
