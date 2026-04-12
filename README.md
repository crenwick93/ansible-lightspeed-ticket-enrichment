# Ansible Lightspeed Ticket Enrichment

Automated incident diagnostics powered by Ansible Lightspeed (ALIA). When a ServiceNow incident is created, Event-Driven Ansible picks it up, runs real system diagnostics against the affected host, sends the results to an AI agent for analysis, and publishes the findings back to the incident — no human intervention required.

## Demo Flow

```
  ServiceNow             EDA Rulebook            AAP Workflow
  ┌──────────┐          ┌──────────────┐       ┌─────────────────────────────────┐
  │ Incident │──polled──│ listen_snow  │──run──│  1. CMDB Lookup                 │
  │ created  │  every   │ _incidents   │       │     (get host IP from CI)       │
  └──────────┘  10s     └──────────────┘       │            │ set_stats          │
                                               │            ▼                    │
                                               │  2. Gather Diagnostics          │
                                               │     (SSH to EC2, inspect host)  │
                                               │            │ set_stats          │
                                               │            ▼                    │
       ┌───────────────────────────────────────│  3. ALIA Enrichment             │
       │                                       │     (send to AI, get analysis)  │
       │                                       └─────────────────────────────────┘
       ▼
  ┌──────────┐
  │ Incident │
  │ updated  │
  │ with AI  │
  │ worknotes│
  └──────────┘
```

1. A **ServiceNow incident** is created (manually, or via the Prometheus monitoring stack in `setup/`). The incident is linked to a **CMDB Configuration Item** representing the EC2 host.
2. The **EDA rulebook** polls the incident table every 10 seconds and detects the new record
3. EDA launches the **Incident Diagnostics Workflow** on AAP Controller
4. **Step 1 — CMDB Lookup**: Queries the incident for its CMDB CI reference, then resolves the CI to the affected host's IP address
5. **Step 2 — Gather Diagnostics**: SSHs into the affected host (using the IP from CMDB), checks systemd status, pulls journal logs, collects system health (disk, memory, uptime)
6. **Step 3 — ALIA Enrichment**: Sends the incident description + diagnostics report to the Ansible Lightspeed AI agent
7. The AI analysis is **posted back** to the ServiceNow incident as worknotes

## AAP Workflow Detail

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Incident Diagnostics Workflow                          │
│                                                                             │
│  ┌───────────────┐       ┌────────────────────┐       ┌────────────────┐   │
│  │  CMDB Lookup  │──OK──▶│ Gather Diagnostics │──OK──▶│ ALIA Enrichment│   │
│  └───────────────┘       └────────────────────┘       └────────────────┘   │
│                                                                             │
│  Inventory:              Inventory:                    Inventory:           │
│    Demo Inventory          Demo Inventory                Demo Inventory     │
│                                                                             │
│  Credentials:            Credentials:                  Credentials:         │
│    ServiceNow ITSM         Monitoring SSH                ServiceNow ITSM   │
│                                                          ALIA API          │
│                                                                             │
│  What it does:           What it does:                 What it does:        │
│    - Query incident      - add_host with IP from       - Build prompt with  │
│      for cmdb_ci           CMDB lookup                   incident +         │
│    - Query CMDB CI       - SSH to host                   diagnostics        │
│      for ip_address      - systemctl status            - POST to ALIA API   │
│    - set_stats:          - journalctl logs             - Update ServiceNow  │
│      target_host_ip      - disk, memory, uptime          incident with      │
│                          - set_stats:                    AI worknotes        │
│                            diagnostics_report                               │
└─────────────────────────────────────────────────────────────────────────────┘

Data flow:
  incident_sys_id ──▶ CMDB Lookup ──▶ target_host_ip ──▶ Gather Diagnostics
  ──▶ diagnostics_report ──▶ ALIA Enrichment ──▶ ServiceNow work_notes
```

## Key Files

| File | Purpose |
|------|---------|
| `playbooks/cmdb_lookup.yml` | Queries ServiceNow CMDB to resolve the affected host IP from the incident's CI |
| `playbooks/gather_diagnostics.yml` | SSHs to the affected host (dynamic from CMDB), collects systemd + journal + system health data |
| `playbooks/alia_enrichment.yml` | Sends diagnostics to ALIA, updates the ServiceNow incident with AI analysis |
| `rulebooks/listen_snow_incidents.yml` | EDA rulebook — monitors ServiceNow incident table, triggers the workflow |
| `ansible_deployment/cac/` | Configuration as Code to push all AAP objects (projects, job templates, workflow, EDA activations) |

## How to Demo This

### 1. SSH into the EC2 instance

```bash
ssh -i setup/terraform/demo-key.pem ec2-user@<EC2_IP>
```

### 2. Break httpd with a bad config change

Introduce a syntax error into the Apache config and restart the service:

```bash
sudo sh -c 'echo "InvalidDirective broken" >> /etc/httpd/conf/httpd.conf'
sudo systemctl restart httpd
```

httpd will fail to start because of the invalid directive. You can confirm with:

```bash
sudo systemctl status httpd
sudo journalctl -u httpd.service -n 20 --no-pager
```

### 3. Wait and watch

Within ~30 seconds:

1. **Prometheus** detects `httpd.service` is no longer active
2. **AlertManager** fires the alert and the webhook bridge creates a **ServiceNow incident**
3. **EDA rulebook** picks up the new incident and launches the **Incident Diagnostics Workflow** on AAP:
   - **CMDB Lookup** — resolves the incident's CMDB CI to the affected host's IP address
   - **Gather Diagnostics** — SSHs into the EC2 host, captures the systemd status, journal logs (including the config error), and system health
   - **ALIA Enrichment** — sends the full diagnostics report to the AI agent for root-cause analysis
4. **ServiceNow** — the incident is updated to "In Progress" with AI-generated worknotes explaining the issue

### 4. Fix and restore

Remove the bad line and restart:

```bash
sudo sed -i '/InvalidDirective broken/d' /etc/httpd/conf/httpd.conf
sudo systemctl restart httpd
```

Verify it's running:

```bash
curl -s http://localhost
```

## Getting Started

### Prerequisites

- AWS CLI configured (`aws configure` or environment variables)
- Terraform >= 1.5
- Ansible with the `servicenow.itsm` collection installed
- Access to an AAP 2.5+ instance with EDA
- A ServiceNow developer instance
- An ALIA (Ansible Lightspeed) API token

### Step 1 — Configure `.env`

Create a `.env` file at the repo root with your credentials:

| Variable | Purpose |
|----------|---------|
| `AAP_HOSTNAME` | AAP gateway URL (e.g. `https://aap.example.com/`) |
| `AAP_TOKEN` | AAP OAuth token |
| `AAP_VALIDATE_CERTS` | Set to `false` for self-signed certs |
| `AAP_ORG` | AAP organization (default: `Default`) |
| `ALIA_TOKEN` | Ansible Lightspeed AI agent bearer token |
| `SN_INSTANCE` | ServiceNow instance URL (e.g. `https://devXXXXX.service-now.com`) |
| `SN_USERNAME` | ServiceNow API username |
| `SN_PASSWORD` | ServiceNow API password |

`MONITORING_HOST_IP` is set automatically by Terraform — you don't need to fill it in.

### Step 2 — Provision the EC2 instance

```bash
cd setup/terraform
terraform init
terraform apply
```

This creates a RHEL 9 EC2 instance with an Elastic IP, generates an SSH key pair, writes the Ansible inventory, and updates `MONITORING_HOST_IP` in `.env` — all automatically.

### Step 3 — Deploy the monitoring stack

```bash
./setup/scripts/setup-apply.sh
```

This installs and configures everything on the EC2 instance:

| Service | Port | Role |
|---------|------|------|
| httpd | 80 | Hello-world app (the monitored workload) |
| Node Exporter | 9100 | Exposes system and systemd metrics |
| Prometheus | 9090 | Scrapes metrics, evaluates alert rules |
| AlertManager | 9093 | Fires alerts to the webhook bridge |
| Webhook bridge | 5001 | Translates alerts into ServiceNow incidents |

It also registers the EC2 instance in **ServiceNow CMDB** as a Configuration Item and links the webhook bridge to it.

### Step 4 — Push to git

The AAP project syncs from GitHub, so push your changes:

```bash
git add -A && git commit -m "Deploy" && git push
```

### Step 5 — Apply AAP Configuration as Code

```bash
./ansible_deployment/scripts/cac-apply.sh
```

This creates all AAP objects in one shot: credential types, credentials, projects, job templates, the 3-step workflow, and the EDA rulebook activation.

### Step 6 — Manual AAP step

Create an inventory called **"Demo Inventory"** in AAP containing `localhost`. All job templates use this inventory — the affected host is resolved dynamically from CMDB at runtime.

### Verify

After all steps complete, check:

- **httpd Hello World** — `http://<EC2_IP>`
- **Prometheus Targets** — `http://<EC2_IP>:9090/targets`
- **AlertManager** — `http://<EC2_IP>:9093`
- **ServiceNow CMDB** — search for `prom-alertmgr-demo` under Linux Servers
- **AAP** — the "Incident Diagnostics Workflow" should be visible with 3 nodes

### Tear down

```bash
cd setup/terraform && terraform destroy
```

## Day-2 Operations

### Instance stopped overnight

The Elastic IP survives stop/start, so just start the instance:

```bash
aws ec2 start-instances --instance-ids <id> --region eu-west-1
```

Everything auto-starts — no re-provisioning needed.

### Full rebuild (instance terminated)

```bash
cd setup/terraform && terraform destroy && terraform apply
cd ../.. && ./setup/scripts/setup-apply.sh
git add -A && git commit -m "Rebuild" && git push
./ansible_deployment/scripts/cac-apply.sh
```
