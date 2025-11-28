targetScope = 'resourceGroup'

param capacityName string
param location string

@description('Email address of the Fabric capacity administrator')
param fabricAdminEmail string

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: 'F2'
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: [
        fabricAdminEmail
      ]
    }
  }
}

output capacityId string = fabricCapacity.id
output capacityName string = fabricCapacity.name
