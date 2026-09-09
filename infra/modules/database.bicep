param name string
param location string
param tags object
param subnetId string
param privateDnsZoneId string
@secure()
param administratorPassword string
param tier string
param skuName string
param highAvailability string
param storageSizeGB int
param backupRetentionDays int
param workspaceId string
param alertActionGroupIds array

// Dedicated Bifrost server. ARM cannot create PostgreSQL SQL roles: see README
// before using this bootstrap administrator as a permanent runtime identity.
var username = 'bifrostadmin'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: skuName, tier: tier }
  properties: {
    version: '16'
    administratorLogin: username
    administratorLoginPassword: administratorPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: { mode: highAvailability }
    network: {
      publicNetworkAccess: 'Disabled'
      delegatedSubnetResourceId: subnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: 'bifrost'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource secureTransport 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: server
  name: 'require_secure_transport'
  properties: { value: 'on', source: 'user-override' }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'postgres-diagnostics'
  scope: server
  properties: {
    workspaceId: workspaceId
    logs: [{ category: 'PostgreSQLLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

resource storageAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${name}-storage-high'
  location: 'global'
  tags: tags
  properties: {
    description: 'PostgreSQL storage utilization exceeds 80 percent.'
    severity: 2
    enabled: true
    scopes: [server.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'storage'
          metricNamespace: 'Microsoft.DBforPostgreSQL/flexibleServers'
          metricName: 'storage_percent'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [for id in alertActionGroupIds: { actionGroupId: id }]
  }
}

output name string = server.name
output fqdn string = server.properties.fullyQualifiedDomainName
output username string = username
