SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eo pipefail -c
.DEFAULT_GOAL := help

# ─── Defaults ─────────────────────────────────────────────────────────
REGION            ?= us-east1
ZONE              ?= $(REGION)-b
CQL_PORT_BASE     ?= 9001
SSL_CQL_PORT_BASE ?= $(shell echo $$(($(CQL_PORT_BASE) + 100)))
DNS_DOMAIN        ?= dk-test.duckdns.org
PORT_BASE         ?= $(CQL_PORT_BASE)
PSC_ENDPOINT_NAME ?= scylladb-psc-endpoint
SCYLLA_API_HOST   ?= localhost:10000
CONNECTION_ID     ?= 1
LATTE_DURATION    ?= 60s
LATTE_RATE        ?= 1000
LATTE_CONNECTIONS ?= 4

TF_DIR := terraform

# ─── Helpers ──────────────────────────────────────────────────────────

define check_var
$(if $($(1)),,$(error $(1) is required. Set it via env or make var: make $(MAKECMDGOALS) $(1)=...))
endef

# ─── Stage 01: ScyllaDB Cloud Cluster ────────────────────────────────

.PHONY: stage-01-cluster
stage-01-cluster:
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

.PHONY: stage-02-producer-psc
stage-02-producer-psc:
	$(call check_var,GCP_PROJECT_ID)
	$(call check_var,SCYLLA_VPC_NAME)
	echo "=== Stage 02: Producer PSC (in ScyllaDB VPC) ==="
	# Discover node instances from VPC (filter out manager/monitor VMs)
	echo "Discovering ScyllaDB nodes in VPC: $(SCYLLA_VPC_NAME)..."
	_INSTANCES=$$(gcloud compute instances list \
		--project="$(GCP_PROJECT_ID)" \
		--filter="networkInterfaces[0].network ~ /$(SCYLLA_VPC_NAME)$$ AND name ~ -node-" \
		--format='json(name,zone.scope(zones),networkInterfaces[0].networkIP,networkInterfaces[0].subnetwork)')
	_NODE_INSTANCES=$$(echo "$$_INSTANCES" | jq -c '[.[] | {name: .name, zone: .zone, ip: .networkInterfaces[0].networkIP}]')
	_NODE_COUNT=$$(echo "$$_NODE_INSTANCES" | jq 'length')
	if [ "$$_NODE_COUNT" -eq 0 ]; then
		echo "ERROR: No ScyllaDB node instances found in VPC $(SCYLLA_VPC_NAME)"
		exit 1
	fi
	echo "Found $$_NODE_COUNT nodes: $$_NODE_INSTANCES"
	# Auto-discover region and subnet from instances
	_REGION=$$(echo "$$_INSTANCES" | jq -r '.[0].zone' | sed 's/-[a-z]$$//')
	_SCYLLA_SUBNET_NAME=$$(echo "$$_INSTANCES" | jq -r '.[0].networkInterfaces[0].subnetwork' | xargs basename)
	echo "Region: $$_REGION"
	echo "ScyllaDB Subnet: $$_SCYLLA_SUBNET_NAME"
	cd $(TF_DIR)/02-producer-psc
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="gcp_project_id=$(GCP_PROJECT_ID)" \
		-var="region=$$_REGION" \
		-var="scylla_vpc_name=$(SCYLLA_VPC_NAME)" \
		-var="scylla_subnet_name=$${_SCYLLA_SUBNET_NAME}" \
		-var="node_instances=$${_NODE_INSTANCES}" \
		-var="cql_port_base=$(CQL_PORT_BASE)" \
		-var="ssl_cql_port_base=$(SSL_CQL_PORT_BASE)" \
		-var="dns_domain=$(DNS_DOMAIN)"
	echo ""
	echo "Service Attachment: $$(terraform output -raw service_attachment_self_link)"

# ─── Stage 03: Consumer VPC + Loader VM ──────────────────────────────

.PHONY: stage-03-loader
stage-03-loader:
	$(call check_var,GCP_PROJECT_ID)
	$(call check_var,SCYLLA_VPC_NAME)
	$(call check_var,CQL_USERNAME)
	$(call check_var,CQL_PASSWORD)
	echo "=== Stage 03: Loader Infrastructure ==="
	# Discover node IPs and region from VPC (filter to node VMs only)
	_INSTANCES=$$(gcloud compute instances list \
		--project="$(GCP_PROJECT_ID)" \
		--filter="networkInterfaces[0].network ~ /$(SCYLLA_VPC_NAME)$$ AND name ~ -node-" \
		--format='json(zone.scope(zones),networkInterfaces[0].networkIP)')
	_NODE_IPS_JSON=$$(echo "$$_INSTANCES" | jq -c '[.[].networkInterfaces[0].networkIP]')
	_REGION=$$(echo "$$_INSTANCES" | jq -r '.[0].zone' | sed 's/-[a-z]$$//')
	_ZONE="$${_REGION}-b"
	echo "Node IPs: $$_NODE_IPS_JSON"
	echo "Region: $$_REGION  Zone: $$_ZONE"
	cd $(TF_DIR)/03-loader
	terraform init -input=false
	terraform apply -input=false -auto-approve \
		-var="gcp_project_id=$(GCP_PROJECT_ID)" \
		-var="region=$$_REGION" \
		-var="zone=$$_ZONE" \
		-var="cql_username=$(CQL_USERNAME)" \
		-var="cql_password=$(CQL_PASSWORD)" \
		-var="port_base=$(PORT_BASE)" \
		-var="node_private_ips=$${_NODE_IPS_JSON}"
	echo ""
	echo "Loader VM: $$(terraform output -raw loader_vm_name) ($$(terraform output -raw loader_vm_zone))"

# ─── Stage 04: PSC Endpoint Connection ───────────────────────────────

.PHONY: stage-04-psc-connect
stage-04-psc-connect:
	$(call check_var,GCP_PROJECT_ID)
	$(call check_var,SCYLLA_VPC_NAME)
	echo "=== Stage 04: PSC Connection ==="
	# Discover node IPs and region from VPC (filter to node VMs only)
	_INSTANCES=$$(gcloud compute instances list \
		--project="$(GCP_PROJECT_ID)" \
		--filter="networkInterfaces[0].network ~ /$(SCYLLA_VPC_NAME)$$ AND name ~ -node-" \
		--format='json(zone.scope(zones),networkInterfaces[0].networkIP)')
	_NODE_IPS_JSON=$$(echo "$$_INSTANCES" | jq -c '[.[].networkInterfaces[0].networkIP]')
	_REGION=$$(echo "$$_INSTANCES" | jq -r '.[0].zone' | sed 's/-[a-z]$$//')
	# Read from prior stages
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
		-var="region=$$_REGION" \
		-var="service_attachment_self_link=$${_SERVICE_ATTACHMENT}" \
		-var="consumer_vpc_id=$${_CONSUMER_VPC_ID}" \
		-var="consumer_subnet_id=$${_CONSUMER_SUBNET_ID}" \
		-var="psc_endpoint_name=$(PSC_ENDPOINT_NAME)" \
		-var="port_base=$(PORT_BASE)" \
		-var="node_private_ips=$${_NODE_IPS_JSON}"
	echo ""
	echo "PSC Endpoint IP: $$(terraform output -raw psc_endpoint_ip)"
	echo "Port mapping:"
	terraform output -json port_mapping | jq -r 'to_entries[] | "  \(.key) -> \(.value)"'

# ─── Stage 05: Check DNS ─────────────────────────────────────────────

.PHONY: stage-05-check-dns
stage-05-check-dns:
	echo "=== Stage 05: DNS Check ==="
	FQDN="$(PSC_ENDPOINT_NAME).$(DNS_DOMAIN)"
	echo "Resolving $$FQDN..."
	RESULT=$$(dig +short A "$$FQDN")
	if [ -z "$$RESULT" ]; then
		echo "FAIL: $$FQDN does not resolve"
		exit 1
	fi
	echo "OK: $$FQDN -> $$RESULT"

# ─── Stage 06: Check CQL ─────────────────────────────────────────────

.PHONY: stage-06-check-cql
stage-06-check-cql:
	$(call check_var,GCP_PROJECT_ID)
	$(call check_var,SCYLLA_VPC_NAME)
	echo "=== Stage 06: CQL Port Check (via loader VM) ==="
	FQDN="$(PSC_ENDPOINT_NAME).$(DNS_DOMAIN)"
	# Discover node count from VPC (filter to node VMs only)
	NODE_COUNT=$$(gcloud compute instances list \
		--project="$(GCP_PROJECT_ID)" \
		--filter="networkInterfaces[0].network ~ /$(SCYLLA_VPC_NAME)$$ AND name ~ -node-" \
		--format='value(name)' | wc -l)
	echo "Found $$NODE_COUNT nodes, checking CQL ports $(CQL_PORT_BASE)..$$(($(CQL_PORT_BASE) + NODE_COUNT - 1)) on $$FQDN"
	# Read loader VM info from stage 03
	LOADER_VM_NAME=$$(cd $(TF_DIR)/03-loader && terraform output -raw loader_vm_name 2>/dev/null) \
		|| { echo "ERROR: Cannot read loader_vm_name from stage 03."; exit 1; }
	LOADER_VM_ZONE=$$(cd $(TF_DIR)/03-loader && terraform output -raw loader_vm_zone 2>/dev/null) \
		|| { echo "ERROR: Cannot read loader_vm_zone from stage 03."; exit 1; }
	echo "Running check from $$LOADER_VM_NAME ($$LOADER_VM_ZONE)..."
	# Build remote check script
	REMOTE_CMD="FAILED=0; for i in \$$(seq 0 $$((NODE_COUNT - 1))); do PORT=\$$(($(CQL_PORT_BASE) + \$$i)); if timeout 5 bash -c \"exec 3<>/dev/tcp/$$FQDN/\$$PORT\" 2>/dev/null; then echo \"  OK:   $$FQDN:\$$PORT\"; else echo \"  FAIL: $$FQDN:\$$PORT\"; FAILED=1; fi; done; exit \$$FAILED"
	gcloud compute ssh "$$LOADER_VM_NAME" \
		--zone="$$LOADER_VM_ZONE" \
		--project="$(GCP_PROJECT_ID)" \
		--tunnel-through-iap \
		-- bash -c "$$REMOTE_CMD"
	echo ""
	echo "All CQL ports reachable"

# ─── Stage 07: Configure ScyllaDB Client Routes ─────────────────────

.PHONY: stage-07-configure-scylla
stage-07-configure-scylla:
	echo "=== Stage 07: Configure ScyllaDB client routes ==="
	FQDN="$(PSC_ENDPOINT_NAME).$(DNS_DOMAIN)"
	echo "ScyllaDB API: $(SCYLLA_API_HOST)"
	echo "PSC Endpoint: $$FQDN"
	echo ""
	# Fetch host IDs from ScyllaDB REST API
	HOST_IDS=$$(curl -sf http://$(SCYLLA_API_HOST)/storage_service/host_id/ | jq -r '[.[].value]')
	NODE_COUNT=$$(echo "$$HOST_IDS" | jq 'length')
	echo "Found $$NODE_COUNT nodes"
	echo "Host IDs: $$HOST_IDS"
	# Build routes JSON dynamically
	ROUTES=$$(echo "$$HOST_IDS" | jq -c --arg ep "$$FQDN" \
		--arg cid "$(CONNECTION_ID)" \
		--argjson cql_base $(CQL_PORT_BASE) \
		--argjson ssl_base $(SSL_CQL_PORT_BASE) \
		'[to_entries[] | {
			connection_id: $$cid,
			host_id: .value,
			address: $$ep,
			port: ($$cql_base + .key),
			tls_port: ($$ssl_base + .key)
		}]')
	echo "Routes: $$ROUTES"
	echo ""
	# POST client routes
	curl -sf -X POST \
		-H 'Content-Type: application/json' \
		-H 'Accept: application/json' \
		-d "$$ROUTES" \
		http://$(SCYLLA_API_HOST)/v2/client-routes
	echo ""
	echo ""
	# Verify
	echo "=== Current client routes ==="
	curl -sf http://$(SCYLLA_API_HOST)/v2/client-routes | \
		jq -c '.[] | {connection_id, host_id, address, port, tls_port}'

# ─── Stage 08: Run Latte Benchmark ───────────────────────────────────

.PHONY: stage-08-bench
stage-08-bench:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Stage 08: Run Latte Benchmark ==="
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

# ─── Bulk Targets ─────────────────────────────────────────────────────

.PHONY: deploy all stages-02-06 stages-02-08

deploy all: stage-01-cluster stage-02-producer-psc stage-03-loader stage-04-psc-connect stage-05-check-dns stage-06-check-cql stage-07-configure-scylla stage-08-bench

stages-02-06: stage-02-producer-psc stage-03-loader stage-04-psc-connect stage-05-check-dns stage-06-check-cql

stages-02-08: stage-02-producer-psc stage-03-loader stage-04-psc-connect stage-05-check-dns stage-06-check-cql stage-07-configure-scylla stage-08-bench

# ─── Destroy Targets ──────────────────────────────────────────────────
# Only terraform stages (01-04, 08) have state to destroy.
# Stages 05-07 are stateless checks.

.PHONY: destroy-08-bench
destroy-08-bench:
	$(call check_var,GCP_PROJECT_ID)
	echo "=== Destroying Stage 08: Bench VM ==="
	cd $(TF_DIR)/08-bench
	if [ -d .terraform ]; then
		terraform destroy -input=false -auto-approve \
			-var="gcp_project_id=$(GCP_PROJECT_ID)" \
			-var="region=$(REGION)" \
			-var="zone=$(ZONE)" \
			-var="dns_domain=$${DNS_DOMAIN:-placeholder}" \
			|| echo "Stage 08 destroy failed or already clean"
	else
		echo "Stage 08: not initialized, skipping"
	fi

.PHONY: destroy-04-psc-connect
destroy-04-psc-connect:
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

.PHONY: destroy-03-loader
destroy-03-loader:
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

.PHONY: destroy-02-producer-psc
destroy-02-producer-psc:
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

.PHONY: destroy-01-cluster
destroy-01-cluster:
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
destroy: destroy-08-bench destroy-04-psc-connect destroy-03-loader destroy-02-producer-psc destroy-01-cluster
	echo ""
	echo "=== Destroy complete ==="

# ─── Init & Validate ──────────────────────────────────────────────────

.PHONY: init
init:
	for stage in 01-cluster 02-producer-psc 03-loader 04-psc-connect 08-bench; do
		echo "=== terraform init: $$stage ==="
		(cd $(TF_DIR)/$$stage && terraform init -input=false)
	done

.PHONY: validate
validate:
	for stage in 01-cluster 02-producer-psc 03-loader 04-psc-connect 08-bench; do
		echo "=== terraform validate: $$stage ==="
		(cd $(TF_DIR)/$$stage && terraform validate)
	done

# ─── Help ──────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo "ScyllaDB GCP Private Service Connect — Makefile Orchestration"
	@echo ""
	@echo "Stages:"
	@echo "  make stage-01-cluster           ScyllaDB Cloud cluster"
	@echo "  make stage-02-producer-psc      Producer PSC — NEG, ILB, Service Attachment"
	@echo "  make stage-03-loader            Consumer VPC + loader VM"
	@echo "  make stage-04-psc-connect       PSC endpoint connection"
	@echo "  make stage-05-check-dns         Check DNS resolution"
	@echo "  make stage-06-check-cql         Check CQL port connectivity"
	@echo "  make stage-07-configure-scylla  Configure ScyllaDB client routes"
	@echo "  make stage-08-bench             Run latte benchmark"
	@echo ""
	@echo "Bulk:"
	@echo "  make deploy                     All stages 01-08"
	@echo "  make stages-02-06               Stages 02-06 (infra + checks)"
	@echo "  make stages-02-08               Stages 02-08 (infra + checks + configure + bench)"
	@echo ""
	@echo "Teardown:"
	@echo "  make destroy                    All terraform stages in reverse"
	@echo "  make destroy-XX-name            Individual stage destroy (e.g. destroy-02-producer-psc)"
	@echo ""
	@echo "Helpers:"
	@echo "  make init                       terraform init all stages"
	@echo "  make validate                   terraform validate all stages"
	@echo ""
	@echo "Variables (pass via env or make VAR=value):"
	@echo ""
	@echo "  Required:"
	@echo "    GCP_PROJECT_ID           GCP project (stages 02-04, 06, 08)"
	@echo "    SCYLLA_API_TOKEN         ScyllaDB Cloud API token (stage 01)"
	@echo "    SCYLLA_VPC_NAME          ScyllaDB VPC name (stages 02-04, 06)"
	@echo "    CQL_USERNAME             CQL username (stage 03)"
	@echo "    CQL_PASSWORD             CQL password (stage 03)"
	@echo ""
	@echo "  Optional — defaults:"
	@echo "    REGION                   GCP region                    [auto-discovered from VPC]"
	@echo "    ZONE                     GCP zone                      [auto-discovered REGION-b]"
	@echo "    CQL_PORT_BASE            Base CQL port                 [9001]"
	@echo "    SSL_CQL_PORT_BASE        Base SSL CQL port             [CQL_PORT_BASE+100]"
	@echo "    DNS_DOMAIN               GCP-verified DNS domain       [dk-test.duckdns.org]"
	@echo "    PSC_ENDPOINT_NAME        PSC endpoint name             [scylladb-psc-endpoint]"
	@echo "    SCYLLA_API_HOST          ScyllaDB REST API host:port   [localhost:10000]"
	@echo "    CONNECTION_ID            Client route connection ID    [1]"
	@echo "    LATTE_DURATION           Benchmark duration            [60s]"
	@echo "    LATTE_RATE               Benchmark ops/s               [1000]"
	@echo "    LATTE_CONNECTIONS        Benchmark connections          [4]"
