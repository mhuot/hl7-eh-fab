# HL7 MLLP → Kafka → Azure Event Hubs → Microsoft Fabric

> ⚠️ **POC/Lab Only**: This project is intended for learning and demonstration purposes. It is not production-ready. See [Security Considerations](docs/REFERENCE.md#security-considerations) before deploying.

## Overview

This project demonstrates a healthcare data streaming pipeline:
- HL7 v2.x messages ingested via MLLP on AKS
- Streamed to Azure Event Hubs using Kafka protocol
- Ingested into Microsoft Fabric via **Eventstream** with managed private endpoint
- Stored in Eventhouse (KQL Database) for real-time analytics

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

To deploy into a different resource group or region, override the variables inline, for example:

```bash
make infra RESOURCE_GROUP=my-rg LOCATION=westus2
```

If the default AKS VM size (`Standard_B2ps_v2`) is unavailable in your target region/subscription, override it during deployment:

```bash
make infra RESOURCE_GROUP=eastus2-rg LOCATION=eastus2 AKS_NODE_VM_SIZE=Standard_D2s_v3
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

After deploying infrastructure, configure Fabric to ingest HL7 messages using **Eventstream** with a managed private endpoint.

> **Note**: Eventstream with MPE is the recommended approach for connecting to Event Hubs with private networking. Direct Eventhouse-to-Event Hub connections with MPE have known limitations. See [Connect to Azure resources securely using managed private endpoints](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/set-up-private-endpoint) for Microsoft’s official guidance.

### Step 1: Create Fabric Workspace

1. Go to [Microsoft Fabric](https://app.fabric.microsoft.com)
2. **Workspaces** → **New workspace** → Name it `hl7-analytics`
3. Under **Advanced**, select your Fabric capacity (`hl7fabriccap`)
4. Click **Apply**

### Step 2: Create Managed Private Endpoint

Create a private endpoint for secure Event Hub connectivity (see the [Fabric managed private endpoint article](https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-overview) for prerequisites).

1. Open your workspace → **Workspace settings** (gear icon)
2. Select **Network security** → **+ Create**
3. Configure:
   - **Name**: `hl7-eventhub-mpe`
   - **Resource identifier**: *(get with command below)*
   - **Target sub-resource**: `Azure Event Hub`

   ```bash
   # Get Event Hub namespace resource ID
   az eventhubs namespace list \
     --resource-group hl7-demo-rg \
     --query "[0].id" -o tsv
   ```

4. Click **Create** (status shows `Provisioning`)

**Approve in Azure Portal:**
1. Go to your **Event Hubs namespace** → **Networking** → **Private endpoint connections**
2. Select the pending connection → **Approve**
3. Wait for status to show **Approved** in both Azure and Fabric

### Step 3: Create Eventstream

1. In your workspace, click **+ New item** → **Eventstream**
2. Name it `hl7-eventstream` → **Create**

### Step 4: Add Event Hub as Source

1. In the Eventstream editor, click **Add source** → **Azure Event Hubs**
2. Select **New connection** and configure:

   | Field | Value |
   |-------|-------|
   | **Event Hub namespace** | Your namespace (e.g., `hl7ehnsh7kcjfwhqnvre`) |
   | **Event Hub** | `hl7-events` |
   | **Authentication** | Shared Access Key |
   | **Shared Access Key Name** | `FabricListen` |
   | **Shared Access Key** | *(see below)* |

   ```bash
   # Get the shared access key
   EH_NAMESPACE=$(az eventhubs namespace list --resource-group hl7-demo-rg --query "[0].name" -o tsv)
   az eventhubs eventhub authorization-rule keys list \
     --resource-group hl7-demo-rg \
     --namespace-name $EH_NAMESPACE \
     --eventhub-name hl7-events \
     --name FabricListen \
     --query primaryKey -o tsv
   ```

3. **Uncheck** "Test connection" (required for private endpoints)
4. Enter **Consumer group**: `$Default`
5. Click **Connect**

Once connected, a secure connection icon appears indicating MPE is active. Refer to the [Eventstream connectivity guide](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/connect-azure-event-hubs) for troubleshooting tips.

### Step 5: Create Eventhouse

1. In your workspace, click **+ New item** → **Eventhouse**
2. Name it `hl7-eventhouse` → **Create**

### Step 6: Route Eventstream to Eventhouse

1. Return to `hl7-eventstream`
2. Click **Add destination** → **Eventhouse**
3. Select your `hl7-eventhouse` and create table `hl7_messages`
4. Configure data mapping as needed
5. Click **Save**

### Step 7: Verify Data Flow

```bash
# Send test messages
make test IP=<EXTERNAL-IP>
```

Query in KQL Database:
```kusto
hl7_messages
| take 10
```

### Step 8: Check Fabric connectivity (optional)

Run the helper script to confirm the managed private endpoint and Event Hub metrics:

```bash
make check-fabric RESOURCE_GROUP=<your-resource-group>
```

The command surfaces pending approvals, active connections, and message counts.

### Step 9: Verify DNS resolution from Fabric Spark (optional)

Managed private endpoints rely on Fabric’s managed VNet DNS to resolve the Event Hubs namespace to a private IP. You can confirm this from a Spark notebook in the same workspace:

1. In your Fabric workspace, create a **Notebook** (Spark). Attach it to the same workspace/capacity.
2. Paste the following cell and run it (replace `<your-namespace>` with the Event Hubs namespace host, e.g., `hl7ehnsh7kcjfwhqnvre.servicebus.windows.net`).

```python
%%pyspark
import re
import subprocess

hostname = "<your-namespace>"
print(f"Resolving {hostname} from Fabric Spark...")
result = subprocess.run(["nslookup", hostname], capture_output=True, text=True)
print(result.stdout)

rfc1918_pattern = re.compile(
  r"(10\.\d{1,3}\.\d{1,3}\.\d{1,3})|"
  r"(172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})|"
  r"(192\.168\.\d{1,3}\.\d{1,3})"
)

if rfc1918_pattern.search(result.stdout):
  print("✅ Managed private endpoint resolves to an RFC1918 private IP")
else:
  print("⚠️ Resolution did not return an RFC1918 address. Check MPE status and private DNS.")
```

3. The output should list an IP in the private ranges (10.x.x.x, 172.16-31.x.x, or 192.168.x.x). If you see a public address, the MPE or private DNS link isn’t active yet.

---

## Teardown

### Azure Resources

```bash
az group delete --name <your-resource-group> --yes --no-wait
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
| `make check-fabric` | Inspect Fabric managed private endpoint & metrics |
| `make scale REPLICAS=n` | Scale the HL7 listener deployment |
| `make restart` | Restart HL7 listener pods |
| `make clean` | Delete the provisioned resource group |

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
