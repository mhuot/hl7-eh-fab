targetScope = 'resourceGroup'

param capacityName string
param location string

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: 'F2' // Copilot claims we need F64 for to use Private Endpoints, but F2 works fine for testing
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: [
        'michaelhuot@MngEnvMCAP732807.onmicrosoft.com'
      ]
    }
  }
}

output capacityId string = fabricCapacity.id
output capacityName string = fabricCapacity.name
