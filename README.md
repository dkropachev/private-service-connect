# ScyllaDB + GCP Private Service Connect

POC for ScyllaDB Cloud PSC support. Uses native GCP port mapping NEGs so clients reach individual ScyllaDB nodes through a single PSC VIP:

```
PSC_VIP:9001  ->  node1:9042
PSC_VIP:9002  ->  node2:9042
PSC_VIP:9003  ->  node3:9042
```

The producer-side infrastructure (Port Mapping NEG, ILB, PSC Service Attachment) is deployed directly in the ScyllaDB VPC — simulating what ScyllaDB Cloud would provide natively. No proxies, no VPC peering.

## Architecture

![Architecture Diagram](docs/architecture.png)

See [ARCH.md](ARCH.md) for full details.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5.0 | Infrastructure provisioning |
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | latest | GCP authentication, instance discovery, SSH |
| [jq](https://jqlang.github.io/jq/download/) | any | JSON parsing |
| [GNU Make](https://www.gnu.org/software/make/) | any | Orchestration |

## Credentials

### GCP

Required IAM roles on the target project:

- `roles/compute.admin` — VPCs, subnets, VMs, firewall rules, forwarding rules, NEGs, service attachments
- `roles/iam.serviceAccountUser` — attach service accounts to VMs
- `roles/iap.tunnelResourceAccessor` — SSH into VMs via IAP tunnel

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

Required GCP APIs:

```bash
gcloud services enable compute.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable iap.googleapis.com
```

### ScyllaDB Cloud API Token

1. Log in to [ScyllaDB Cloud Console](https://cloud.scylladb.com/)
2. Go to **Settings** > **API Keys**
3. Click **Generate API Key**
4. Copy the token

```bash
export SCYLLA_API_TOKEN="your-token"
```

## Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `GCP_PROJECT_ID` | Yes | — | GCP project (stages 02-04, 06, 08) |
| `SCYLLA_API_TOKEN` | Yes | — | ScyllaDB Cloud API token (stage 01) |
| `SCYLLA_VPC_NAME` | Yes | — | ScyllaDB VPC name (stages 02-04, 06) |
| `CQL_USERNAME` | Yes | — | CQL username (stage 03) |
| `CQL_PASSWORD` | Yes | — | CQL password (stage 03) |
| `REGION` | No | auto-discovered | GCP region (derived from VPC instances) |
| `ZONE` | No | `REGION-b` | GCP zone |
| `CQL_PORT_BASE` | No | `9001` | Base CQL port in the per-node mapping range |
| `SSL_CQL_PORT_BASE` | No | `CQL_PORT_BASE+100` | Base SSL CQL port |
| `DNS_DOMAIN` | No | `dk-test.duckdns.org` | GCP-verified DNS domain for PSC |
| `PSC_ENDPOINT_NAME` | No | `scylladb-psc-endpoint` | PSC endpoint name |
| `LATTE_DURATION` | No | `60s` | Benchmark duration |
| `LATTE_RATE` | No | `1000` | Benchmark target ops/s |
| `LATTE_CONNECTIONS` | No | `4` | Benchmark CQL connections |

Region and zone are auto-discovered from VPC instance metadata. Override with `REGION=` / `ZONE=` if needed.

## Stages

| Stage | Target | What it does |
|---|---|---|
| 01 | `stage-01-cluster` | Create ScyllaDB Cloud cluster |
| 02 | `stage-02-producer-psc` | Port Mapping NEG + ILB + PSC Service Attachment (in ScyllaDB VPC) |
| 03 | `stage-03-loader` | Consumer VPC + Cloud NAT + loader VM |
| 04 | `stage-04-psc-connect` | PSC endpoint connecting consumer to producer |
| 05 | `stage-05-check-dns` | Verify DNS resolution for PSC FQDN |
| 06 | `stage-06-check-cql` | Verify CQL port reachability (via loader VM) |
| 07 | `stage-07-configure-scylla` | Configure ScyllaDB client routes via REST API |
| 08 | `stage-08-bench` | Run latte benchmark (via loader VM) |

Stages 01-04 provision infrastructure (Terraform). Stages 05-07 are stateless checks/config. Stage 08 deploys and runs the benchmark.

## Deploy

### Full pipeline

```bash
export SCYLLA_API_TOKEN="your-token"
make deploy GCP_PROJECT_ID=your-project SCYLLA_VPC_NAME=your-vpc CQL_USERNAME=user CQL_PASSWORD=pass
```

### With existing cluster (stages 02-08)

```bash
make stages-02-08 GCP_PROJECT_ID=your-project SCYLLA_VPC_NAME=your-vpc CQL_USERNAME=user CQL_PASSWORD=pass
```

### Infrastructure only (stages 02-06)

```bash
make stages-02-06 GCP_PROJECT_ID=your-project SCYLLA_VPC_NAME=your-vpc CQL_USERNAME=user CQL_PASSWORD=pass
```

### Individual stages

```bash
make stage-02-producer-psc GCP_PROJECT_ID=your-project SCYLLA_VPC_NAME=your-vpc
make stage-05-check-dns
make stage-08-bench GCP_PROJECT_ID=your-project
```

Run `make help` for the full list.

## Destroy

```bash
# All stages (reverse order)
make destroy GCP_PROJECT_ID=your-project

# Individual stage
make destroy-03-loader GCP_PROJECT_ID=your-project
```

## Port Mapping and Driver Address Translation

Each node gets a unique port: `client_port = CQL_PORT_BASE + node_index`.

ScyllaDB drivers discover nodes via internal IPs that aren't reachable through PSC. Your driver must translate:

```
discovered node_private_ip:9042  ->  PSC_FQDN:mapped_port
```

Stage 07 (`configure-scylla`) automates this by pushing client routes to the ScyllaDB REST API.

Get the mapping manually:

```bash
cd terraform/04-psc-connect
terraform output -json port_mapping
```

## Project Structure

```
.
├── ARCH.md                              # Architecture document
├── README.md
├── Makefile                             # Orchestration (all stages)
├── docs/
│   └── architecture.png                 # Architecture diagram
├── terraform/
│   ├── terraform.tfvars.example
│   ├── 01-cluster/                      # ScyllaDB Cloud cluster
│   ├── 02-producer-psc/                 # Port Mapping NEG + ILB + PSC (in ScyllaDB VPC)
│   ├── 03-loader/                       # Consumer VPC + loader VM
│   ├── 04-psc-connect/                  # PSC endpoint connection
│   └── 08-bench/                        # Benchmark VM
└── workloads/
    └── basic_read_write.rn              # Latte benchmark workload
```

## Troubleshooting

### Cannot SSH to loader VM

Ensure IAP is enabled and you have the right role:

```bash
gcloud services enable iap.googleapis.com
```

Your account needs `roles/iap.tunnelResourceAccessor`.

### Loader VM not ready

Startup script takes 2-3 minutes. Check:

```bash
gcloud compute ssh latte-loader --zone=us-west1-b --project=$GCP_PROJECT_ID --tunnel-through-iap \
  -- cat /opt/latte/setup.done
```

### PSC NAT subnet CIDR conflict

The PSC NAT subnet (`10.0.201.0/24`) is created in the ScyllaDB VPC. If it overlaps with an existing subnet, override in stage 02:

```bash
-var="psc_nat_subnet_cidr=10.0.211.0/24"
```

### Missing required variables

Each stage validates its inputs and prints what's missing:

```bash
$ make stage-02-producer-psc
Makefile:47: *** GCP_PROJECT_ID is required. Set it via env or make var: make stage-02-producer-psc GCP_PROJECT_ID=...  Stop.
```
