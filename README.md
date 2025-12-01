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
