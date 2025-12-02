targetScope = 'subscription'

param location string = 'centralus'
param rgName string = 'hl7-demo-rg'
param aksName string = 'hl7-aks'
param acrName string = 'hl7acr${uniqueString(rgName)}'
param eventHubNamespaceName string = 'hl7ehns${uniqueString(rgName)}'
param eventHubName string = 'hl7-events'
param capacityName string = 'hl7fabriccap'
param adminUsername string = 'azureuser'
@description('VM size for AKS system node pool')
param aksNodeVmSize string = 'Standard_B2ps_v2'
param deployFabricCapacity bool = true  // Set to true if you have Fabric quota
@description('Resource ID of an existing Log Analytics workspace. Leave empty to create a new one.')
param existingLogAnalyticsWorkspaceId string = ''
@description('Email address of the Fabric capacity administrator')
param fabricAdminEmail string = ''
@secure()
param sshPublicKey string

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
}

// Deploy all resources into the resource group
module resources 'resources.bicep' = {
  scope: rg
  name: 'hl7ResourcesDeployment'
  params: {
    location: location
    aksName: aksName
    acrName: acrName
    eventHubNamespaceName: eventHubNamespaceName
    eventHubName: eventHubName
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    existingLogAnalyticsWorkspaceId: existingLogAnalyticsWorkspaceId
    aksNodeVmSize: aksNodeVmSize
  }
}

// Deploy Fabric capacity (optional - requires quota)
module fabricCapacity 'fabricCapacity.bicep' = if (deployFabricCapacity) {
  scope: rg
  name: 'fabricCapacityDeployment'
  params: {
    capacityName: capacityName
    location: location
    fabricAdminEmail: fabricAdminEmail
  }
}

output resourceGroupName string = rg.name
output aksClusterName string = resources.outputs.aksClusterName
output acrName string = resources.outputs.acrName
output acrLoginServer string = resources.outputs.acrLoginServer
output eventHubNamespace string = resources.outputs.eventHubNamespaceName
output logAnalyticsWorkspaceId string = resources.outputs.logAnalyticsWorkspaceId
