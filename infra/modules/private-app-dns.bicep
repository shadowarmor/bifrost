param domain string
param address string
param vnetId string
param tags object

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: domain
  location: 'global'
  tags: tags
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: 'bifrost-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnetId }
  }
}

resource records 'Microsoft.Network/privateDnsZones/A@2024-06-01' = [for recordName in ['*', '@']: {
  parent: zone
  name: recordName
  properties: {
    ttl: 60
    aRecords: [{ ipv4Address: address }]
  }
}]
