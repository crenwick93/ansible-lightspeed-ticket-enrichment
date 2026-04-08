# Ansible Lightspeed Ticket Enrichment

Automated incident diagnostics powered by Ansible Lightspeed (ALIA). When a ServiceNow incident is created, Event-Driven Ansible picks it up, runs real system diagnostics against the affected host, sends the results to an AI agent for analysis, and publishes the findings back to the incident — no human intervention required.

## Demo Flow

```
  ServiceNow             EDA Rulebook            AAP Workflow
  ┌──────────┐          ┌──────────────┐       ┌─────────────────────────────────┐
  │ Incident │──polled──│ listen_snow  │──run──│  1. Gather Diagnostics          │
  │ created  │  every   │ _incidents   │       │     (SSH to EC2, inspect host)  │
  └──────────┘  10s     └──────────────┘       │            │ set_stats          │
                                               │            ▼                    │
       ┌───────────────────────────────────────│  2. ALIA Enrichment             │
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

1. A **ServiceNow incident** is created (manually, or via the Prometheus monitoring stack in `setup/`)
2. The **EDA rulebook** polls the incident table every 10 seconds and detects the new record
3. EDA launches the **Incident Diagnostics Workflow** on AAP Controller
4. **Step 1 — Gather Diagnostics**: SSHs into the affected host, checks systemd status, pulls journal logs, collects system health (disk, memory, uptime)
5. **Step 2 — ALIA Enrichment**: Sends the incident description + diagnostics report to the Ansible Lightspeed AI agent
6. The AI analysis is **posted back** to the ServiceNow incident as worknotes

## Key Files

| File | Purpose |
|------|---------|
| `playbooks/gather_diagnostics.yml` | SSHs to the affected host, collects systemd + journal + system health data |
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

## Setup

First-time environment provisioning (EC2 instance, Prometheus, AlertManager) is documented in [`setup/README.md`](setup/README.md).

## AAP Configuration-as-Code

Push all AAP objects (credential types, credentials, projects, job templates, workflow, EDA rulebook activations) in one shot:

```bash
source .env
ansible-playbook ansible_deployment/cac/apply.yml
```

**Note:** After running CaC, you still need to manually add to AAP:
- An inventory called "Monitoring Hosts" containing the EC2 instance IP (from `terraform output`)
- A Machine credential called "Monitoring SSH" with the private key from `setup/terraform/demo-key.pem`

## Environment Variables

Copy `.env` and fill in your values:

| Variable | Purpose |
|----------|---------|
| `SN_INSTANCE` | ServiceNow instance URL |
| `SN_USERNAME` | ServiceNow API username |
| `SN_PASSWORD` | ServiceNow API password |
| `AAP_HOSTNAME` | AAP gateway URL |
| `AAP_TOKEN` | AAP OAuth token |
| `ALIA_TOKEN` | Ansible Lightspeed AI agent bearer token |
