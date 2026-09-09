using './main.bicep'

param environmentName = readEnvironmentVariable('BIFROST_ENVIRONMENT', 'bifrost-dev')
param location = readEnvironmentVariable('AZURE_LOCATION')
param deployGateway = readEnvironmentVariable('DEPLOY_GATEWAY', 'false') == 'true'
param bifrostImageDigest = readEnvironmentVariable('BIFROST_IMAGE_DIGEST')
param postgresPassword = readEnvironmentVariable('BIFROST_POSTGRES_PASSWORD')
param bifrostEncryptionKey = readEnvironmentVariable('BIFROST_ENCRYPTION_KEY')
param bifrostSetupToken = readEnvironmentVariable('BIFROST_SETUP_TOKEN')
param bifrostAdminPassword = readEnvironmentVariable('BIFROST_ADMIN_PASSWORD')

// To seed providers, add a non-secret providers object and read credentials from
// environment variables into providerSecrets. See README.md for an example.
