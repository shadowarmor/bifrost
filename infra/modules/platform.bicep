@minLength(13)
@maxLength(13)
param suffix string
param location string
param tags object
param createRegistry bool = true

// Pinned Azure Verified Modules; disable their optional usage telemetry.
module identity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'gateway-identity'
  params: {
    name: 'id-${suffix}'
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module registry 'br/public:avm/res/container-registry/registry:0.13.0' = if (createRegistry) {
  name: 'gateway-registry'
  params: {
    name: 'acr${suffix}'
    location: location
    tags: tags
    enableTelemetry: false
    acrSku: 'Basic'
    acrAdminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleSetDefaultAction: 'Allow'
    zoneRedundancy: 'Disabled'
    retentionPolicyStatus: 'disabled'
    // Container Apps managed-identity pulls require ARM-audience authentication.
    azureADAuthenticationAsArmPolicyStatus: 'enabled'
    roleAssignmentMode: 'LegacyRegistryPermissions'
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'AcrPull'
        principalId: identity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'gateway-logs'
  params: {
    name: 'log-${suffix}'
    location: location
    tags: tags
    enableTelemetry: false
    dataRetention: 30
    forceCmkForQuery: false
  }
}

output identityId string = identity.outputs.resourceId
output identityPrincipalId string = identity.outputs.principalId
output registryName string = createRegistry ? registry!.outputs.name : ''
output registryServer string = createRegistry ? registry!.outputs.loginServer : ''
output workspaceId string = workspace.outputs.resourceId
output workspaceName string = workspace.outputs.name
