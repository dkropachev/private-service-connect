# ScyllaDB + GCP Private Service Connect

POC for ScyllaDB Cloud PSC support. Uses native GCP port mapping NEGs so clients reach individual ScyllaDB nodes through a single PSC VIP:

```
PSC_VIP:10001  ->  node1:9042
PSC_VIP:10002  ->  node2:9042
PSC_VIP:10003  ->  node3:9042
```

The producer-side infrastructure (Port Mapping NEG, ILB, PSC Service Attachment) is deployed directly in the ScyllaDB VPC — simulating what ScyllaDB Cloud would provide natively. No proxies, no VPC peering.

See [ARCH.md](ARCH.md) for the full architecture.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5.0 | Infrastructure provisioning |
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | latest | GCP authentication, instance discovery, SSH |
| [jq](https://jqlang.github.io/jq/download/) | any | JSON parsing in deploy scripts |

## Credentials

### GCP Credentials

Required IAM roles on the target project:

- `roles/compute.admin` — VPCs, subnets, VMs, firewall rules, forwarding rules, NEGs, service attachments
- `roles/iam.serviceAccountUser` — attach service accounts to VMs

Authenticate:

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

Or use a service account:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

Required GCP APIs:

```bash
gcloud services enable compute.googleapis.com
gcloud services enable servicenetworking.googleapis.com
```

### ScyllaDB Cloud API Token

1. Log in to [ScyllaDB Cloud Console](https://cloud.scylladb.com/)
2. Go to **Settings** > **API Keys**
3. Click **Generate API Key**
4. Copy the token

```bash
export SCYLLA_API_TOKEN="your-token"
```

### Environment Variables

| Variable | Required | Default | Used by | Description |
|---|---|---|---|---|
| `SCYLLA_API_TOKEN` | Yes | — | 01-cluster | ScyllaDB Cloud API token |
| `SCYLLADB_CLOUD_ENDPOINT` | No | `https://api.cloud.scylladb.com` | 01-cluster | ScyllaDB Cloud API server URL |
| `GCP_PROJECT_ID` | Yes | — | 02, 03, 04 | GCP project ID |
| `REGION` | No | `us-east1` | all stages | GCP region |
| `ZONE` | No | `us-east1-b` | 03-loader | GCP zone for loader VM |
| `PORT_BASE` | No | `10001` | 02, 03, 04 | First port in the per-node mapping range |

The ScyllaDB VPC name and subnet are auto-discovered from node VM instances.

See `terraform/terraform.tfvars.example` for all Terraform-level defaults.

## Deploy

### All stages at once

```bash
export SCYLLA_API_TOKEN="your-token"
export GCP_PROJECT_ID="your-project"

./scripts/deploy.sh
```

### Individual stages

Each stage can be run independently. Stages read outputs from previous stages via `terraform output`, so prerequisites must be deployed first.

```bash
# Stage 01: ScyllaDB Cloud cluster
export SCYLLA_API_TOKEN="your-token"
./scripts/01-cluster.sh

# Stage 02: Port Mapping NEG + ILB + PSC attachment (in ScyllaDB VPC)
export GCP_PROJECT_ID="your-project"
./scripts/02-producer-psc.sh

# Stage 03: Consumer VPC + Cloud NAT + loader VM
export GCP_PROJECT_ID="your-project"
./scripts/03-loader.sh

# Stage 04: PSC endpoint connecting consumer to producer
export GCP_PROJECT_ID="your-project"
./scripts/04-psc-connect.sh
```

| Script | What it deploys | Reads from |
|---|---|---|
| `01-cluster.sh` | ScyllaDB Cloud cluster + CQL credentials | — |
| `02-producer-psc.sh` | Port Mapping NEG, ILB, PSC Service Attachment in ScyllaDB VPC | stage 01 |
| `03-loader.sh` | Consumer VPC, subnet, Cloud NAT, loader VM | stage 01 |
| `04-psc-connect.sh` | PSC endpoint forwarding rule | stages 01, 02, 03 |

Stages 02 and 03 both depend only on stage 01, so they can be run in either order. Stage 04 depends on all three.

### Output

```
=========================================
  Deployment complete!
=========================================
PSC Endpoint IP:  10.1.1.10
Loader VM:        latte-loader (us-east1-b)

Port mapping (PSC_VIP:port -> node:9042):
  10.1.1.10:10001 -> 10.x.x.1:9042
  10.1.1.10:10002 -> 10.x.x.2:9042
  10.1.1.10:10003 -> 10.x.x.3:9042
```

## Run Benchmarks

```bash
./scripts/run-latte.sh
```

SSHs into the loader VM via IAP tunnel and runs [Latte](https://github.com/scylladb/latte) against the first node via PSC.

| Variable | Default | Description |
|---|---|---|
| `LATTE_DURATION` | `60s` | Duration of each workload phase |
| `LATTE_RATE` | `1000` | Target operations per second |
| `LATTE_CONNECTIONS` | `4` | Number of CQL connections |

```bash
LATTE_DURATION=120s LATTE_RATE=5000 ./scripts/run-latte.sh
```

## Port Mapping and Driver Address Translation

Each node gets a unique port: `client_port = PORT_BASE + node_index`.

ScyllaDB drivers discover nodes via internal IPs that aren't reachable through PSC. Your driver must translate:

```
discovered node_private_ip:9042  ->  PSC_VIP:mapped_port
```

Get the mapping:

```bash
cd terraform/04-psc-connect
terraform output -json port_mapping
```

## Destroy

```bash
./scripts/destroy.sh
```

## Project Structure

```
.
├── ARCH.md                              # Architecture document
├── README.md
├── scripts/
│   ├── deploy.sh                        # Full deployment (all 4 stages)
│   ├── 01-cluster.sh                    # Stage 01 only
│   ├── 02-producer-psc.sh              # Stage 02 only
│   ├── 03-loader.sh                     # Stage 03 only
│   ├── 04-psc-connect.sh               # Stage 04 only
│   ├── destroy.sh                       # Full teardown
│   └── run-latte.sh                     # Run benchmarks
├── terraform/
│   ├── terraform.tfvars.example
│   ├── 01-cluster/                      # ScyllaDB Cloud cluster
│   ├── 02-producer-psc/                 # Port Mapping NEG + ILB + PSC (in ScyllaDB VPC)
│   ├── 03-loader/                       # Consumer VPC + loader VM
│   └── 04-psc-connect/                  # PSC endpoint connection
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
gcloud compute ssh latte-loader --zone=us-east1-b --project=$GCP_PROJECT_ID --tunnel-through-iap \
  -- cat /opt/latte/setup.done
```

### PSC NAT subnet CIDR conflict

The PSC NAT subnet (`10.0.201.0/24`) is created in the ScyllaDB VPC. If it overlaps with an existing subnet, override in stage 02:

```bash
-var="psc_nat_subnet_cidr=10.0.211.0/24"
```
