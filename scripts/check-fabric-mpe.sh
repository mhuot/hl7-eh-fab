#!/bin/bash
# Check Fabric Managed Private Endpoint status and Event Hub connectivity
# This script verifies the MPE is approved and checks Event Hub metrics

set -e

RESOURCE_GROUP="${1:-hl7-demo-rg}"

echo "=== Fabric MPE & Event Hub Status Check ==="
echo ""

# Get Event Hub namespace name
echo "Finding Event Hub namespace..."
EH_NAMESPACE=$(az eventhubs namespace list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)

if [ -z "$EH_NAMESPACE" ]; then
    echo "✗ No Event Hub namespace found in resource group $RESOURCE_GROUP"
    exit 1
fi

echo "Event Hub Namespace: $EH_NAMESPACE"
echo ""

# Check private endpoint connections
echo "=== Private Endpoint Connections ==="
az network private-endpoint-connection list \
    --id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventHub/namespaces/$EH_NAMESPACE" \
    --query "[].{Name:name, Status:properties.privateLinkServiceConnectionState.status, Description:properties.privateLinkServiceConnectionState.description}" \
    -o table 2>/dev/null || echo "Unable to list connections"

echo ""

# Check for Fabric MPE specifically and get detailed status
echo "=== Fabric Managed Private Endpoint Status ==="
FABRIC_MPE=$(az network private-endpoint-connection list \
    --id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventHub/namespaces/$EH_NAMESPACE" \
    -o json 2>/dev/null)

MPE_COUNT=$(echo "$FABRIC_MPE" | jq length)

APPROVED=0
PENDING=0

if [ "$MPE_COUNT" -gt 0 ]; then
    echo "$FABRIC_MPE" | jq -r '.[] | "Name: \(.name)\nStatus: \(.properties.privateLinkServiceConnectionState.status)\nDescription: \(.properties.privateLinkServiceConnectionState.description // "N/A")\n"'
    
    # Check if any are pending
    PENDING=$(echo "$FABRIC_MPE" | jq -r '[.[] | select(.properties.privateLinkServiceConnectionState.status == "Pending")] | length')
    if [ "$PENDING" -gt 0 ]; then
        echo "⚠ $PENDING connection(s) pending approval!"
        echo "  Approve in Azure Portal: Event Hubs namespace → Networking → Private access"
    fi
    
    APPROVED=$(echo "$FABRIC_MPE" | jq -r '[.[] | select(.properties.privateLinkServiceConnectionState.status == "Approved")] | length')
    if [ "$APPROVED" -gt 0 ]; then
        echo "✓ $APPROVED connection(s) approved and ready"
    fi
else
    echo "✗ No Fabric MPE found"
fi

echo ""

# Check Event Hub metrics
echo "=== Event Hub Metrics (Last Hour) ==="
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventHub/namespaces/$EH_NAMESPACE"

# Incoming messages
INCOMING=$(az monitor metrics list \
    --resource "$RESOURCE_ID" \
    --metric "IncomingMessages" \
    --interval PT1H \
    --query "value[0].timeseries[0].data[-1].total" \
    -o tsv 2>/dev/null)

echo "Incoming Messages (last hour): ${INCOMING:-0}"

# Outgoing messages (consumed by Fabric)
OUTGOING=$(az monitor metrics list \
    --resource "$RESOURCE_ID" \
    --metric "OutgoingMessages" \
    --interval PT1H \
    --query "value[0].timeseries[0].data[-1].total" \
    -o tsv 2>/dev/null)

echo "Outgoing Messages (last hour): ${OUTGOING:-0}"

# Active connections
CONNECTIONS_COUNT=$(az monitor metrics list \
    --resource "$RESOURCE_ID" \
    --metric "ActiveConnections" \
    --interval PT5M \
    --query "value[0].timeseries[0].data[-1].average" \
    -o tsv 2>/dev/null)

echo "Active Connections: ${CONNECTIONS_COUNT:-0}"

echo ""

# Summary
echo "=== Summary ==="
if [ "${APPROVED:-0}" -gt 0 ] && [ "${OUTGOING:-0}" != "0" ] && [ -n "$OUTGOING" ]; then
    echo "✓ Fabric MPE is approved and consuming messages"
elif [ "${APPROVED:-0}" -gt 0 ]; then
    echo "✓ Fabric MPE is approved"
    echo "  → If no outgoing messages, verify Fabric Eventhouse data connection is configured"
else
    echo "⚠ Fabric MPE needs attention - check status above"
fi

echo ""
echo "To send test messages: make test IP=<external-ip>"
echo "To view in Fabric KQL: hl7_messages | take 10"
