param name string
param location string
param tags object
param subnetId string
param vnetId string
param workspaceName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: workspaceName
}

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: subnetId
      internal: true
    }
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
  }
}

// The environment's domain is assigned during provisioning, so DNS lives in a
// separate nested deployment rather than using a runtime value as a resource name.
module dns './private-app-dns.bicep' = {
  name: 'container-apps-private-dns'
  params: {
    domain: environment.properties.defaultDomain
    address: environment.properties.staticIp
    vnetId: vnetId
    tags: tags
  }
}

output name string = environment.name
output environmentId string = environment.id
output defaultDomain string = environment.properties.defaultDomain
