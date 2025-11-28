targetScope = 'resourceGroup'

param location string
param aksName string
param acrName string
param eventHubNamespaceName string
param eventHubName string
param adminUsername string
@description('Resource ID of an existing Log Analytics workspace. Leave empty to create a new one.')
param existingLogAnalyticsWorkspaceId string = ''
@secure()
param sshPublicKey string

// Determine if we need to create a new Log Analytics workspace
var createLogAnalytics = empty(existingLogAnalyticsWorkspaceId)
var logAnalyticsWorkspaceId = createLogAnalytics ? logAnalyticsWorkspace.id : existingLogAnalyticsWorkspaceId

// Log Analytics Workspace (created only if not using existing)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (createLogAnalytics) {
  name: 'hl7-logs-la'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'hl7-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.200.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.200.0.0/22'
        }
      }
      {
        name: 'pe-subnet'
        properties: {
          addressPrefix: '10.200.4.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${aksName}-dns'
    kubernetesVersion: '1.32'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: 1
        vmSize: 'Standard_B2ps_v2'
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: vnet.properties.subnets[0].id
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
      }
    ]
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.201.0.0/16'
      dnsServiceIP: '10.201.0.10'
    }
  }
}

// Role assignment: AKS can pull from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, 'acrpull')
  scope: acr
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  tags: {
    SecurityControl: 'Ignore'  // Required to allow local (SAS) auth for Fabric connectivity
  }
  properties: {
    kafkaEnabled: true
    isAutoInflateEnabled: false
    publicNetworkAccess: 'Disabled'  // Fully private - AKS and Fabric use private endpoints
  }
}

// Event Hub
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    partitionCount: 4
    messageRetentionInDays: 1
  }
}

// Private DNS Zone for Event Hubs
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.servicebus.windows.net'
  location: 'global'
}

// Link Private DNS Zone to VNet
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'hl7-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint for Event Hubs
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'hl7-eventhub-pe'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'eh-connection'
        properties: {
          privateLinkServiceId: eventHubNamespace.id
          groupIds: ['namespace']
        }
      }
    ]
  }
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-servicebus-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Authorization rule for Kafka access
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: 'KafkaSendListen'
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

// Diagnostic settings for Event Hubs (sends logs to Log Analytics)
resource eventHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'hl7-eventhub-diag'
  scope: eventHubNamespace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'OperationalLogs'
        enabled: true
      }
      {
        category: 'RuntimeAuditLogs'
        enabled: true
      }
      {
        category: 'EventHubVNetConnectionEvent'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output aksClusterName string = aks.name
output aksClusterId string = aks.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output vnetId string = vnet.id
output privateEndpointId string = privateEndpoint.id
output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceId
output logAnalyticsWorkspaceName string = createLogAnalytics ? logAnalyticsWorkspace.name : 'existing'
