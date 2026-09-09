// Deploy to Azure consumes the compiled azuredeploy.json, not this source file.
targetScope = 'resourceGroup'

@description('Azure region for the private Bifrost deployment.')
param location string = resourceGroup().location

@description('Stable environment naming seed. Reuse when updating this deployment.')
@minLength(1)
@maxLength(32)
param environmentName string = 'bifrost-dev'

@description('Approved upstream image digest. Defaults to the release recorded in image-lock.json; updates require review and template regeneration.')
@minLength(71)
@maxLength(71)
param bifrostImageDigest string = loadJsonContent('./image-lock.json').digest

@secure()
@minLength(16)
@maxLength(128)
@description('PostgreSQL bootstrap administrator password. Use upper/lowercase, numbers and symbols.')
param postgresPassword string

@secure()
@minLength(32)
@maxLength(32)
@description('Exactly 32 ASCII characters. Keep this encryption key with backups and reuse on every update.')
param bifrostEncryptionKey string

@secure()
@minLength(32)
@description('Secret required if the selected release displays the first-admin setup flow.')
param bifrostSetupToken string

@secure()
@minLength(16)
@description('Password for the Bifrost admin account. Use a different password from PostgreSQL.')
param bifrostAdminPassword string

@description('Bifrost administrator username.')
param bifrostAdminUsername string = 'admin'

module deployment './main.bicep' = {
  name: 'bifrost-portal'
  params: {
    location: location
    environmentName: environmentName
    deployGateway: true
    useUpstreamImage: true
    bifrostImageDigest: bifrostImageDigest
    postgresPassword: postgresPassword
    bifrostEncryptionKey: bifrostEncryptionKey
    bifrostSetupToken: bifrostSetupToken
    bifrostAdminPassword: bifrostAdminPassword
    bifrostAdminUsername: bifrostAdminUsername
  }
}

output gatewayUrl string = deployment.outputs.gatewayUrl
output containerAppName string = deployment.outputs.containerAppName
output keyVaultName string = deployment.outputs.keyVaultName
output postgresServerName string = deployment.outputs.postgresServerName
output vnetId string = deployment.outputs.vnetId
