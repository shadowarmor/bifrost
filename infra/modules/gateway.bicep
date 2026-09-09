param name string
param location string
param tags object
param environmentId string
param environmentDomain string
param registryServer string
param imageDigest string
param useUpstreamImage bool = false
param identityId string
param postgresHost string
param postgresUsername string
param vaultUri string
param providerSecretNames array
param providers object
param adminUsername string
param computeSize string
param requestLogRetentionDays int
param enableContentLogging bool
param additionalAllowedOrigins array
param alertActionGroupIds array

var compute = {
  small: { cpu: json('0.5'), memory: '1Gi', goMemory: '900MiB' }
  medium: { cpu: json('1.0'), memory: '2Gi', goMemory: '1800MiB' }
  large: { cpu: json('2.0'), memory: '4Gi', goMemory: '3600MiB' }
}[computeSize]

var configBase = loadJsonContent('../../deploy/config.json')
var config = union(configBase, {
  client: union(configBase.client, {
    allowed_origins: union(['https://${name}.${environmentDomain}'], additionalAllowedOrigins)
    log_retention_days: requestLogRetentionDays
    disable_content_logging: !enableContentLogging
  })
}, empty(providers) ? {} : { providers: providers })

var credentialNames = [
  'postgres-password'
  'bifrost-encryption-key'
  'bifrost-setup-token'
  'bifrost-admin-password'
]

var credentialReferences = [for secretName in credentialNames: {
  name: secretName
  keyVaultUrl: '${vaultUri}secrets/${secretName}'
  identity: identityId
}]
var providerReferences = [for secret in providerSecretNames: {
  name: secret.secretName
  keyVaultUrl: '${vaultUri}secrets/${secret.secretName}'
  identity: identityId
}]
var providerEnvironment = [for secret in providerSecretNames: {
  name: secret.envName
  secretRef: secret.secretName
}]

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: 3
      ingress: {
        // Expose to the VNet through the INTERNAL environment load balancer.
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: useUpstreamImage ? [] : [{ server: registryServer, identity: identityId }]
      secrets: concat(
        [{ name: 'bootstrap-config', value: string(config) }],
        credentialReferences,
        providerReferences
      )
    }
    template: {
      // ACA secret changes alone do not create a revision. A hash in the
      // revision template ensures edits to bootstrap configuration restart it.
      scale: { minReplicas: 1, maxReplicas: 1 }
      terminationGracePeriodSeconds: 60
      containers: [
        {
          name: 'bifrost'
          image: useUpstreamImage ? 'docker.io/maximhq/bifrost@${imageDigest}' : '${registryServer}/bifrost@${imageDigest}'
          command: ['/bin/sh', '-c']
          args: [loadTextContent('../../deploy/start.sh')]
          resources: { cpu: compute.cpu, memory: compute.memory }
          env: concat([
            { name: 'APP_HOST', value: '0.0.0.0' }
            { name: 'APP_PORT', value: '8080' }
            { name: 'APP_DIR', value: '/app/data' }
            { name: 'LOG_LEVEL', value: 'info' }
            { name: 'LOG_STYLE', value: 'json' }
            { name: 'GOMEMLIMIT', value: compute.goMemory }
            { name: 'BOOTSTRAP_CONFIG_HASH', value: uniqueString(string(config)) }
            { name: 'PG_HOST', value: postgresHost }
            { name: 'PG_USER', value: postgresUsername }
            { name: 'PG_PASSWORD', secretRef: 'postgres-password' }
            { name: 'BIFROST_ENCRYPTION_KEY', secretRef: 'bifrost-encryption-key' }
            { name: 'BIFROST_SETUP_TOKEN', secretRef: 'bifrost-setup-token' }
            { name: 'BIFROST_ADMIN_USERNAME', value: adminUsername }
            { name: 'BIFROST_ADMIN_PASSWORD', secretRef: 'bifrost-admin-password' }
          ], providerEnvironment)
          volumeMounts: [{ volumeName: 'bootstrap', mountPath: '/mnt/bootstrap' }]
          probes: [
            {
              type: 'Startup'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 10
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              // /health includes DB checks. Tolerate transient DB failures.
              type: 'Liveness'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 10
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'bootstrap'
          storageType: 'Secret'
          secrets: [{ secretRef: 'bootstrap-config', path: 'config.json' }]
        }
      ]
    }
  }
}

resource errorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${name}-http-errors'
  location: 'global'
  tags: tags
  properties: {
    description: 'Bifrost returns more than 10 HTTP 5xx responses in five minutes.'
    enabled: true
    severity: 2
    scopes: [app.id]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'http5xx'
          metricNamespace: 'Microsoft.App/containerApps'
          metricName: 'Requests'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [{ name: 'statusCodeCategory', operator: 'Include', values: ['5xx'] }]
        }
      ]
    }
    actions: [for id in alertActionGroupIds: { actionGroupId: id }]
  }
}
