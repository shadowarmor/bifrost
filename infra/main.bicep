targetScope = 'resourceGroup'

@description('Azure region. Defaults to the resource group region.')
param location string = resourceGroup().location

@description('Naming seed; resource names use a deterministic hash to satisfy service naming rules.')
@minLength(1)
@maxLength(32)
param environmentName string = 'bifrost-dev'

@description('False for the initial foundation deployment. Set true only after importing the image into ACR. Keep true on subsequent deployments.')
param deployGateway bool = false

@description('Use the pinned official Docker Hub image directly. The portal entry point enables this to avoid a manual ACR import. CLI deployments default to the private registry path.')
param useUpstreamImage bool = false

@description('Digest of the approved Bifrost image, including sha256:. Import this exact digest into the ACR bifrost repository first.')
@minLength(71)
@maxLength(71)
param bifrostImageDigest string

@secure()
@minLength(16)
@maxLength(128)
@description('PostgreSQL password. Supply through a secure parameter; reuse on subsequent deployments.')
param postgresPassword string

@description('Runtime SQL login. Defaults to the dedicated server bootstrap administrator. Set to a separately provisioned schema-owner login for production; Bicep does not create SQL roles.')
param postgresRuntimeUsername string = 'bifrostadmin'

@secure()
@description('Password of postgresRuntimeUsername. Defaults to the bootstrap password; override together with the username after provisioning a runtime SQL role.')
param postgresRuntimePassword string = postgresPassword

@secure()
@minLength(32)
@maxLength(32)
@description('Stable 32-character ASCII encryption key. Preserve with backups; never regenerate on redeployment.')
param bifrostEncryptionKey string

@secure()
@minLength(32)
@description('Secret protecting the initial administrator bootstrap.')
param bifrostSetupToken string

@secure()
@minLength(16)
@description('Bifrost administrator password. Independent of the database password.')
param bifrostAdminPassword string

@description('Administrator username for Bifrost, not PostgreSQL.')
param bifrostAdminUsername string = 'admin'

@description('Bifrost provider definitions using env.VARIABLE_NAME references. Omit credentials from this object.')
param providers object = {}

@secure()
@description('Optional provider credentials keyed by environment variable name, for example OPENAI_API_KEY. Use uppercase letters, digits and underscores; names must be unique after replacing underscores with hyphens.')
param providerSecrets object = {}

@description('VNet CIDR. Change all subnet prefixes together when integrating with existing networks.')
param vnetAddressPrefix string = '10.42.0.0/16'
param containerAppsSubnetPrefix string = '10.42.0.0/23'
param postgresSubnetPrefix string = '10.42.2.0/24'

@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param postgresTier string = 'Burstable'

@description('SKU must match postgresTier and be available in the chosen region.')
param postgresSkuName string = 'Standard_B2s'

@allowed(['Disabled', 'SameZone', 'ZoneRedundant'])
@description('Use Disabled for Burstable. HA requires a supported GeneralPurpose or MemoryOptimized SKU.')
param postgresHighAvailability string = 'Disabled'

@minValue(32)
@maxValue(32768)
param postgresStorageSizeGB int = 32

@minValue(7)
@maxValue(35)
param postgresBackupRetentionDays int = 7

@allowed(['small', 'medium', 'large'])
@description('small=0.5 CPU/1Gi, medium=1 CPU/2Gi, large=2 CPU/4Gi. Replica count stays one for database-backed OSS.')
param computeSize string = 'medium'

@minValue(1)
@maxValue(365)
param requestLogRetentionDays int = 7

@description('Persist request/response bodies in Bifrost logs. Metadata logging remains enabled.')
param enableContentLogging bool = false

@description('Additional browser origins; the private gateway origin is added automatically.')
param additionalAllowedOrigins array = []

@description('Optional existing Azure Monitor action group IDs for alert notifications.')
param alertActionGroupIds array = []

param tags object = {}

var suffix = uniqueString(resourceGroup().id, environmentName)
var resourceTags = union(tags, {
  application: 'bifrost'
  environment: environmentName
})

module platform './modules/platform.bicep' = {
  name: 'bifrost-platform'
  params: {
    suffix: suffix
    location: location
    tags: resourceTags
    createRegistry: !useUpstreamImage
  }
}

module network './modules/network.bicep' = {
  name: 'bifrost-network'
  params: {
    suffix: suffix
    location: location
    tags: resourceTags
    vnetAddressPrefix: vnetAddressPrefix
    containerAppsSubnetPrefix: containerAppsSubnetPrefix
    postgresSubnetPrefix: postgresSubnetPrefix
  }
}

module database './modules/database.bicep' = {
  name: 'bifrost-database'
  params: {
    name: 'psql-${suffix}'
    location: location
    tags: resourceTags
    subnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresDnsZoneId
    administratorPassword: postgresPassword
    tier: postgresTier
    skuName: postgresSkuName
    highAvailability: postgresHighAvailability
    storageSizeGB: postgresStorageSizeGB
    backupRetentionDays: postgresBackupRetentionDays
    workspaceId: platform.outputs.workspaceId
    alertActionGroupIds: alertActionGroupIds
  }
}

module secrets './modules/secrets.bicep' = {
  name: 'bifrost-secrets'
  params: {
    name: 'kv-${suffix}'
    location: location
    tags: resourceTags
    principalId: platform.outputs.identityPrincipalId
    postgresPassword: postgresRuntimePassword
    encryptionKey: bifrostEncryptionKey
    setupToken: bifrostSetupToken
    adminPassword: bifrostAdminPassword
    providerSecrets: providerSecrets
    workspaceId: platform.outputs.workspaceId
  }
}

module environment './modules/environment.bicep' = {
  name: 'bifrost-environment'
  params: {
    name: 'cae-${suffix}'
    location: location
    tags: resourceTags
    subnetId: network.outputs.containerAppsSubnetId
    vnetId: network.outputs.vnetId
    workspaceName: platform.outputs.workspaceName
  }
}

module gateway './modules/gateway.bicep' = if (deployGateway) {
  name: 'bifrost-gateway'
  params: {
    name: 'ca-${suffix}'
    location: location
    tags: resourceTags
    environmentId: environment.outputs.environmentId
    environmentDomain: environment.outputs.defaultDomain
    registryServer: platform.outputs.registryServer
    imageDigest: bifrostImageDigest
    useUpstreamImage: useUpstreamImage
    identityId: platform.outputs.identityId
    postgresHost: database.outputs.fqdn
    postgresUsername: postgresRuntimeUsername
    vaultUri: secrets.outputs.vaultUri
    providerSecretNames: secrets.outputs.providerSecretNames
    providers: providers
    adminUsername: bifrostAdminUsername
    computeSize: computeSize
    requestLogRetentionDays: requestLogRetentionDays
    enableContentLogging: enableContentLogging
    additionalAllowedOrigins: additionalAllowedOrigins
    alertActionGroupIds: alertActionGroupIds
  }
}

output resourceGroupName string = resourceGroup().name
output registryName string = platform.outputs.registryName
output registryServer string = platform.outputs.registryServer
output keyVaultName string = secrets.outputs.name
output containerAppName string = 'ca-${suffix}'
output environmentName string = environment.outputs.name
output vnetId string = network.outputs.vnetId
output postgresServerName string = database.outputs.name
output gatewayUrl string = 'https://ca-${suffix}.${environment.outputs.defaultDomain}'
output gatewayDeployed bool = deployGateway
