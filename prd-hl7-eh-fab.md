
# Product Requirements Document: HL7 MLLP → Kafka → Azure Event Hubs → Microsoft Fabric

## Objective
Create a workshop-ready architecture for ingesting HL7 v2.x messages via MLLP, streaming through Kafka (via Event Hubs Kafka endpoint), and landing in Microsoft Fabric for real-time analytics. Include Infrastructure as Code (IaC) using Bicep for easy deployment and teardown.

---

## Scope
- HL7 ingestion via MLLP listener on AKS.
- Kafka integration using Event Hubs Kafka endpoint (no separate Kafka cluster).
- Fabric Eventstream for ingestion and routing to KQL DB.
- IaC with Bicep for AKS, Event Hubs, Private Link, and Fabric capacity.
- Easy cleanup: single resource group deletion.

---

## Functional Requirements

### 1. HL7 Ingestion
- MLLP listener service on AKS.
- ACK responses per HL7 protocol.
- Convert HL7 to JSON for downstream processing.

### 2. Kafka Integration
- Kafka producer sends HL7 payloads to Event Hubs Kafka endpoint.
- Headers for dynamic schema mapping in Fabric.

### 3. Event Hubs
- Kafka-enabled namespace.
- SAS authentication.
- Private Link for secure connectivity.

### 4. Fabric
- Eventstream connected to Event Hubs.
- Route to KQL DB for analytics.
- Optional Power BI dashboard.

### 5. IaC
- Bicep template provisions:
  - Resource group
  - AKS cluster
  - Event Hubs namespace + hub
  - Private Link
  - Fabric capacity resource

---

## Non-Functional Requirements
- **Performance**: 1,000 HL7 messages/sec.
- **Scalability**: AKS autoscaling + Event Hubs partitions.
- **Security**: Private endpoints, SAS tokens.
- **Observability**: Azure Monitor + AKS logs.

---

## Deletion Strategy
All resources in one resource group → `az group delete`.

---

## Alternative Option
HTTP/FHIR ingestion using Azure Logic Apps HL7 connector or FHIR Converter for cloud-native approach. This can replace MLLP for modern healthcare APIs.

---

## Architecture Overview
**Flow**:  
`HL7 MLLP Listener (AKS) → Kafka Producer → Event Hubs (Kafka endpoint) → Fabric Eventstream → KQL DB → Power BI`

**Components**:
- AKS cluster (HL7 ingestion service + optional Kafka Connect).
- Azure Event Hubs namespace.
- Microsoft Fabric workspace with Eventstream and KQL DB.

---

## Workshop Deliverables
- AKS deployment YAML for HL7 ingestion service.
- Kafka producer sample (Python or Java).
- Event Hubs namespace setup guide.
- Fabric Eventstream configuration steps.
- KQL queries and dashboard template.

---

## Risks & Mitigations
- **Firewall issues**: Fabric cannot ingest from Event Hubs behind firewall without Managed Private Endpoint.  
- **Schema drift**: Use dynamic mapping in Eventstream.
- **Latency**: Optimize ACK handling and Kafka batching.

---

## References
- [Event Hubs Kafka integration](https://learn.microsoft.com/en-us/azure/event-hubs/azure-event-hubs-apache-kafka-overview)
- [Fabric Eventstream setup](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/overview)
- [Private Link for Event Hubs](https://learn.microsoft.com/en-us/azure/event-hubs/private-link-service)