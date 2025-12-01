# HL7 MLLP → Kafka → Azure Event Hubs → Microsoft Fabric

> ⚠️ **POC/Lab Only**: This project is intended for learning and demonstration purposes. It is not production-ready. See [Security Considerations](docs/REFERENCE.md#security-considerations) before deploying.

## Overview

This project demonstrates a healthcare data streaming pipeline:
- HL7 v2.x messages ingested via MLLP on AKS
- Streamed to Azure Event Hubs using Kafka protocol
- Ingested into Microsoft Fabric Eventhouse (KQL Database) for real-time analytics

![Architecture Overview](docs/images/architecture-overview.png)

## Prerequisites

- Azure subscription with the following providers registered:
  ```bash
  az provider register --namespace Microsoft.EventHub --wait
  az provider register --namespace Microsoft.Fabric --wait
  ```
- Azure CLI with Bicep installed
- SSH public key (`~/.ssh/id_rsa.pub`)

## Quick Start

### 1. Create your local parameters file

```bash
cp infra/main.parameters.json infra/main.parameters.local.json
```

### 2. Edit the local file with your values

Open `infra/main.parameters.local.json` and set:
- `sshPublicKey`: Your SSH public key (`cat ~/.ssh/id_rsa.pub`)
- `fabricAdminEmail`: Your email for Fabric capacity admin

### 3. Validate prerequisites

```bash
make validate
```

### 4. Deploy infrastructure

```bash
make infra
```

### 5. Deploy HL7 listener

```bash
make deploy
```

### 6. Test

```bash
make test IP=<EXTERNAL-IP>
```

Replace `<EXTERNAL-IP>` with the external IP shown at the end of `make deploy`.

---

## Microsoft Fabric Setup

After deploying infrastructure, configure Fabric to ingest HL7 messages.

### Step 1: Create Fabric Workspace

1. Go to [Microsoft Fabric](https://app.fabric.microsoft.com)
2. **Workspaces** → **New workspace** → Name it `hl7-analytics`
3. Under **Advanced**, select your Fabric capacity (`hl7fabriccap`)
4. Click **Apply**

### Step 2: Create Managed Private Endpoint

Event Hubs requires a private endpoint for Fabric connectivity.

1. Open your workspace → **Workspace settings** (gear icon)
2. Select **Outbound networking** → **+ Create**
3. Configure:
   - **Name**: `hl7-eventhub-mpe`
   - **Resource identifier**: *(get with command below)*
   - **Target sub-resource**: `namespace`

   ```bash
   az eventhubs namespace show \
     --resource-group hl7-demo-rg \
     --name $(az eventhubs namespace list --resource-group hl7-demo-rg --query "[0].name" -o tsv) \
     --query id -o tsv
   ```

4. Click **Create** (status shows `Provisioning`)

![Creating Managed Private Endpoint](docs/images/Add_MPE_to_Fabric.gif)

**Approve in Azure Portal:**
1. Go to your **Event Hubs namespace** → **Networking** → **Private access**
2. Select the pending connection → **Approve**

### Step 3: Create Eventhouse

1. In your workspace, click **+ New item** → **Eventhouse**
2. Name it `hl7-eventhouse` → **Create**

### Step 4: Connect to Event Hubs

1. In the Eventhouse, click **Get data** → **Event Hubs**
2. Expand `hl7-eventhouse` → **+ New table** → name it `hl7_messages`
3. Create new connection with:

   | Field | Value |
   |-------|-------|
   | **Event Hub namespace** | Your namespace (e.g., `hl7ehnsh7kcjfwhqnvre`) |
   | **Event Hub** | `hl7-events` |
   | **Authentication** | Shared Access Key |
   | **Key Name** | `FabricListen` |
   | **Key** | *(see below)* |

   ```bash
   # Create the FabricListen policy (if needed)
   EH_NAMESPACE=$(az eventhubs namespace list --resource-group hl7-demo-rg --query "[0].name" -o tsv)
   az eventhubs eventhub authorization-rule create \
     --resource-group hl7-demo-rg \
     --namespace-name $EH_NAMESPACE \
     --eventhub-name hl7-events \
     --name FabricListen \
     --rights Listen

   # Get the key
   az eventhubs eventhub authorization-rule keys list \
     --resource-group hl7-demo-rg \
     --namespace-name $EH_NAMESPACE \
     --eventhub-name hl7-events \
     --name FabricListen \
     --query primaryKey -o tsv
   ```

4. Select **Consumer group**: `$Default`
5. Click **Next** → proceed through schema inspection → **Finish**

### Step 5: Verify Data Flow

```bash
# Send test messages
make test IP=<EXTERNAL-IP>
```

Query in KQL Database:
```kusto
hl7_messages
| take 10
```

---

## Teardown

### Azure Resources

```bash
az group delete --name hl7-demo-rg --yes --no-wait
```

### Microsoft Fabric Resources

Fabric resources must be deleted manually:

1. **Delete Eventhouse/KQL Database**: Right-click → **Delete**
2. **Delete Managed Private Endpoints**: Workspace settings → Outbound networking → Delete
3. **Delete Workspace** (optional): Workspace settings → General → Remove this workspace

> **Note**: The Fabric capacity is billed hourly. Delete it when not in use.

## Documentation

| Document | Description |
|----------|-------------|
| [Reference Guide](docs/REFERENCE.md) | Detailed architecture, parameters, and configuration |
| [Troubleshooting](TROUBLESHOOTING.md) | Common issues and solutions |
| [PRD](prd-hl7-eh-fab.md) | Product requirements document |

## Key Commands

| Command | Description |
|---------|-------------|
| `make validate` | Check prerequisites |
| `make infra` | Deploy Azure infrastructure |
| `make deploy` | Build and deploy HL7 listener to AKS |
| `make test IP=<ip>` | Send test HL7 messages |
| `make logs` | View HL7 listener logs |
| `make status` | Check pod and service status |

## Project Structure

```
hl7-eh-fab/
├── infra/                 # Bicep templates
├── k8s/                   # Kubernetes manifests
├── src/hl7-listener/      # HL7 MLLP listener app
├── docs/                  # Documentation & images
├── deploy.sh              # Deployment script (bash)
├── deploy.ps1             # Deployment script (PowerShell)
├── Makefile               # Make commands
└── README.md              # This file
```

## License

Apache License 2.0
