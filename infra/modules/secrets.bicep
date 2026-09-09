param name string
param location string
param tags object
param principalId string
param workspaceId string
@secure()
param postgresPassword string
@secure()
param encryptionKey string
@secure()
param setupToken string
@secure()
param adminPassword string
@secure()
param providerSecrets object

resource vault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    // Authenticated public endpoint allows ACA's platform to resolve secret
    // references. The gateway and database remain on private ingress.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

var secretValues = {
  'postgres-password': postgresPassword
  'bifrost-encryption-key': encryptionKey
  'bifrost-setup-token': setupToken
  'bifrost-admin-password': adminPassword
}

resource credentials 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = [for secret in items(secretValues): {
  parent: vault
  name: secret.key
  properties: { value: secret.value }
}]

resource providers 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = [for secret in items(providerSecrets): {
  parent: vault
  name: 'provider-${toLower(replace(secret.key, '_', '-'))}'
  properties: { value: secret.value }
}]

resource secretReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, principalId, 'Key Vault Secrets User')
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'vault-audit'
  scope: vault
  properties: {
    workspaceId: workspaceId
    logs: [{ category: 'AuditEvent', enabled: true }]
  }
}

output name string = vault.name
output vaultUri string = vault.properties.vaultUri
// Only names leave this module; credential values never appear in outputs.
#disable-next-line outputs-should-not-contain-secrets
output providerSecretNames array = [for secret in items(providerSecrets): {
  envName: secret.key
  secretName: 'provider-${toLower(replace(secret.key, '_', '-'))}'
}]
