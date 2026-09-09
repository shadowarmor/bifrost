# Deploy Bifrost to Azure Container Apps

This deployment creates a private Container Apps environment, a single Bifrost OSS replica, PostgreSQL 16, Key Vault, managed identity, ACR and Log Analytics. It also creates PostgreSQL storage and gateway HTTP 5xx alerts. Supply existing action group IDs to receive notifications; otherwise alerts are visible only in Azure Monitor.

The gateway and PostgreSQL have no public ingress. Key Vault and the Basic-tier registry use authenticated public endpoints. You need a route into the new VNet and private DNS resolution to open the gateway. VPN, peering, ExpressRoute, a public frontend and custom certificates are outside this template.

## Files

| File | Purpose |
|---|---|
| `main.bicep` | Resource-group-scoped deployment entry point |
| `main.bicepparam` | Environment-backed parameters; contains no credentials |
| `modules/` | Platform, networking, PostgreSQL, secrets, environment/DNS and gateway |
| `../deploy/config.json` | Bifrost configuration with environment references |
| `../deploy/start.sh` | Copy the mounted configuration, then exec the upstream entrypoint |

The upstream image already includes the API and UI. No Dockerfile or source build is required. The portal option uses the official pinned image directly and does not create ACR. The CLI option below populates ACR between two Bicep deployments because a new registry is initially empty.

## Deploy from the Azure portal

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fshadowarmor%2Fbifrost%2Fdev%2Finfra%2Fazuredeploy.json)

1. Select a subscription, resource group and supported region.
2. Enter and securely retain the PostgreSQL password, Bifrost admin password, setup token and exactly 32 ASCII characters for the encryption key.
3. Review the resources and costs, then deploy. This uses `portal.bicep` compiled to `azuredeploy.json`, with a digest-pinned official Docker Hub image from `image-lock.json`. The image supports the deployed platform; Azure cannot build the repository through this button.
4. Read `gatewayUrl` and `vnetId` from deployment outputs. Connect a client through a suitable VPN, peering or existing private network and resolve the private DNS zone before opening the URL.
5. Configure model providers and issue scoped virtual keys in the Bifrost UI, then run the verification steps below.

The defaults are a pilot deployment: one always-running OSS replica, 1 CPU/2 GiB RAM, a Burstable PostgreSQL server without HA, private gateway/database ingress and authenticated public Key Vault access. Standard ACA HTTP ingress has a documented 240-second request timeout. The initial SQL login is the dedicated server bootstrap administrator; use the configurable main template and a separately provisioned runtime SQL login for broader production use.

The button does not import an image into ACR. Docker Hub availability and pull limits apply. Use the CLI path when you require a private registry or additional sizing/network/provider parameters. If initial Key Vault resolution fails while a new role assignment propagates, verify the assigned role and retry the same deployment with the same parameters; do not regenerate the encryption key.

To update the portal artifact after changing Bicep or the image lock:

```powershell
az bicep install --version v0.47.16
./scripts/azure/build-template.ps1
./scripts/azure/build-template.ps1 -Check
```

Commit both source changes and `infra/azuredeploy.json`. The Azure validation workflow rejects a stale generated template. Image changes are reviewed separately from [upstream source updates](UPSTREAM.md); pulling source code does not redeploy Azure or change the pinned image.

## Prerequisites

- Azure CLI with Bicep support (`az bicep install`) and a selected subscription.
- Permission to create resources in the target resource group and create role assignments, for example Contributor plus Role Based Access Control Administrator scoped to that group.
- Required resource providers registered: Microsoft.App, Microsoft.OperationalInsights, Microsoft.Network, Microsoft.DBforPostgreSQL, Microsoft.ContainerRegistry, Microsoft.ManagedIdentity, Microsoft.KeyVault and Microsoft.Insights.
- A supported region and sufficient Container Apps/PostgreSQL quota. These have not been checked against a subscription.
- An approved Bifrost release supporting the configuration fields in `deploy/config.json`. Resolve its `linux/amd64` image or multi-platform image manifest to an immutable SHA-256 digest. Check the selected release's migration notes. Do not use a development build or `latest` in production.
- A PostgreSQL password meeting Azure password complexity rules, an independent Bifrost admin password, a bootstrap token of at least 32 characters, and a stable encryption key of exactly 32 ASCII characters. Keep these values in your secret manager and reuse them on redeployment. The encryption key is not an ordinary rotatable password: losing or changing it can make persisted data unreadable.

## Supply parameters

Run the examples in PowerShell 7 from the repository root. Replace the non-secret placeholders and obtain secrets from your existing secret manager. The following prompt helper avoids recording passwords as literal command text in shell history.

```powershell
az login
az account set --subscription '<subscription-id>'

$env:AZURE_LOCATION = '<azure-region>'
$env:BIFROST_ENVIRONMENT = 'bifrost-dev'
$env:BIFROST_IMAGE_DIGEST = 'sha256:<64 hexadecimal characters from the approved image>'
$taskResourceGroup = 'rg-bifrost-dev'

function Set-TaskSecretEnvironment([string]$Name) {
    $taskSecret = Read-Host $Name -AsSecureString
    [Environment]::SetEnvironmentVariable(
        $Name,
        [System.Net.NetworkCredential]::new('', $taskSecret).Password,
        'Process'
    )
}

Set-TaskSecretEnvironment 'BIFROST_POSTGRES_PASSWORD'
Set-TaskSecretEnvironment 'BIFROST_ENCRYPTION_KEY'
Set-TaskSecretEnvironment 'BIFROST_SETUP_TOKEN'
Set-TaskSecretEnvironment 'BIFROST_ADMIN_PASSWORD'
```

Environment variables are readable by the deploying process and its children. Do not echo them, enable debug logging, print a compiled parameter file, or commit a parameter file containing resolved secrets. The Bicep parameters are marked secure, and the deployed app receives credentials through Key Vault references.

For production sizing, copy `main.bicepparam` to `infra/production.local.bicepparam` and add values such as:

```bicep
param postgresTier = 'GeneralPurpose'
param postgresSkuName = 'Standard_D2ds_v5'
param postgresHighAvailability = 'ZoneRedundant'
param postgresBackupRetentionDays = 14
```

Confirm that this SKU and HA mode are available in your region. The default Burstable tier must use `Disabled` HA. Default compute is 1 CPU and 2 GiB; `computeSize` also accepts `small` and `large`. Keep CIDRs non-overlapping with networks you plan to peer. The templates are scoped to Azure public cloud DNS suffixes.

## Deploy the foundation

```powershell
az group create --name $taskResourceGroup --location $env:AZURE_LOCATION
if ($LASTEXITCODE -ne 0) { throw 'Resource group creation failed.' }

az bicep build --file infra/main.bicep --outdir infra/out
if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }

$env:DEPLOY_GATEWAY = 'false'
az deployment group validate --resource-group $taskResourceGroup --parameters infra/main.bicepparam
if ($LASTEXITCODE -ne 0) { throw 'Azure validation failed.' }

az deployment group what-if --resource-group $taskResourceGroup --parameters infra/main.bicepparam
if ($LASTEXITCODE -ne 0) { throw 'What-if failed.' }

az deployment group create --name bifrost-foundation --resource-group $taskResourceGroup --parameters infra/main.bicepparam --output none
if ($LASTEXITCODE -ne 0) { throw 'Foundation deployment failed.' }
```

Review the what-if before running `create`. Foundation deployment also creates the database, credentials and identity role assignments. This separate stage gives RBAC time to propagate before Container Apps resolves its Key Vault references and pulls its image.

## Import the image and start the gateway

```powershell
$taskRegistry = az deployment group show --name bifrost-foundation --resource-group $taskResourceGroup --query properties.outputs.registryName.value --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Could not read registry name.' }

az acr import --name $taskRegistry --source "docker.io/maximhq/bifrost@$env:BIFROST_IMAGE_DIGEST" --image bifrost:approved --force
if ($LASTEXITCODE -ne 0) { throw 'Image import failed.' }

$taskImportedDigest = az acr repository show --name $taskRegistry --image bifrost:approved --query digest --output tsv
if ($LASTEXITCODE -ne 0 -or $taskImportedDigest -ne $env:BIFROST_IMAGE_DIGEST) {
    throw 'Imported image digest does not match the approved digest.'
}

$env:DEPLOY_GATEWAY = 'true'
az deployment group validate --resource-group $taskResourceGroup --parameters infra/main.bicepparam
if ($LASTEXITCODE -ne 0) { throw 'Gateway validation failed.' }

az deployment group what-if --resource-group $taskResourceGroup --parameters infra/main.bicepparam
if ($LASTEXITCODE -ne 0) { throw 'Gateway what-if failed.' }

az deployment group create --name bifrost-runtime --resource-group $taskResourceGroup --parameters infra/main.bicepparam --output none
if ($LASTEXITCODE -ne 0) { throw 'Gateway deployment failed.' }

$taskGatewayUrl = az deployment group show --name bifrost-runtime --resource-group $taskResourceGroup --query properties.outputs.gatewayUrl.value --output tsv
```

This retags only the local `bifrost:approved` alias. Running revisions use the immutable digest. Keep `DEPLOY_GATEWAY=true` for subsequent deployments. Setting it to false is for initial provisioning, not a stop/remove operation; use incremental deployment mode.

If Key Vault access initially fails, verify the managed identity has Key Vault Secrets User on this vault and AcrPull on this registry, wait for RBAC propagation, then retry the runtime deployment. Do not weaken authentication to work around propagation.

## Configure providers

Sign in at the private gateway URL with the configured admin credentials. If the selected release presents the first-admin setup workflow, supply the setup token. Add a provider and issue a virtual key with permitted models and limits. Provider credentials added through the UI are held in Bifrost's encrypted database configuration.

Alternatively, seed providers and keep their keys in Key Vault. Add this to a local copy of the parameter file:

```bicep
param providers = {
  openai: {
    keys: [
      {
        name: 'primary'
        value: 'env.OPENAI_API_KEY'
        models: ['*']
        weight: 1
      }
    ]
  }
}
param providerSecrets = {
  OPENAI_API_KEY: readEnvironmentVariable('OPENAI_API_KEY')
}
```

Use the same parameter file for both phases. Only use uppercase letters, digits and underscores for provider environment variable names, keep them under 100 characters and avoid names that normalize to the same Key Vault secret name. The secret-name mapping is `OPENAI_API_KEY` → `provider-openai-api-key`. Do not place plaintext keys in `providers`, which is a non-secret parameter.

The default empty `providers` object is omitted from the bootstrap file so existing UI-created providers are preserved. Bifrost reconciles file-backed entities by hash. Changing a seeded definition can replace the corresponding database definition on restart; unchanged definitions preserve UI edits. Configuration changes create a new Container Apps revision through `BOOTSTRAP_CONFIG_HASH`.

## Verify and operate

From a machine with VNet access and DNS resolution:

1. Request `$taskGatewayUrl/health`; expect HTTP 200. Verify successful migrations in startup logs.
2. Confirm unauthenticated inference and management requests are rejected. Authenticate as admin and create a scoped virtual key.
3. Make an inference request with that key and a configured model. Verify an out-of-scope model is rejected.
4. Test SSE streaming through the final endpoint, including long first-token delays and your longest requests. Standard ACA ingress documents a 240-second HTTP request timeout; use this as a hosting acceptance test.
5. Replace the container and verify provider configuration, keys and logs persist. Test provider fallback and recovery from a transient database outage.
6. Restore a database backup to a separate server and verify it using the retained encryption key and a compatible image.

The example connects Bifrost with `bifrostadmin`, the bootstrap administrator of its dedicated PostgreSQL server, because Bicep/ARM cannot provision PostgreSQL SQL roles. Before broader production use, create a separate SQL login from a VNet-connected administrative client, grant it ownership of the Bifrost schema/database and migration permissions, then set `postgresRuntimeUsername` and secure `postgresRuntimePassword` in your local parameter file. Continue supplying the original `postgresPassword` as the server administrator password. The runtime credential is stored in Key Vault; the server administrator password is used only for server provisioning when these values differ. Do not reuse the bootstrap administrator for unrelated applications.

PostgreSQL uses certificate-validated TLS (`verify-full`). The selected Bifrost image must contain the current Azure PostgreSQL CA chain in its system trust store. Validate this during staging; fix CA trust rather than disabling verification.

Key Vault references use versionless URLs. Secret rotation may restart active revisions when ACA refreshes references. Coordinate database password rotation with the database and app; retain old values until recovery is verified. Bootstrap admin credentials may be persisted by the selected Bifrost release: verify the documented admin-password rotation flow rather than assuming an environment change updates that account. Do not rotate the encryption key without Bifrost's supported data migration procedure.

One OSS replica is intentional. Database-backed OSS does not synchronize live configuration across replicas. Single-revision deployments can briefly overlap old and new containers; freeze administrative changes and use a maintenance window when compatibility requires it. A previous image may not work after a schema migration, so image rollback alone is insufficient.

Container system/console logs go to Log Analytics. Bifrost request metadata remains in PostgreSQL with seven-day retention; content logging is off by default. No external telemetry connector is enabled. Connect action groups to receive alerts and set retention/budget based on actual usage.

Clear secret environment variables after deploying:

```powershell
'BIFROST_POSTGRES_PASSWORD', 'BIFROST_ENCRYPTION_KEY', 'BIFROST_SETUP_TOKEN', 'BIFROST_ADMIN_PASSWORD', 'OPENAI_API_KEY' | ForEach-Object {
    [Environment]::SetEnvironmentVariable($_, $null, 'Process')
}
```

## Validation status

Bicep compilation and local configuration-schema validation are performed during authoring. Subscription policy, regional quota, Azure template validation, what-if, image-specific startup and inference tests must be completed before deployment is considered validated. Docker Desktop was not running in the authoring environment, so no container smoke test was performed.

## References

- [Bifrost container runtime contract](https://docs.getbifrost.ai/deployment-guides/runtime-contract)
- [Bifrost storage configuration](https://docs.getbifrost.ai/deployment-guides/config-json/storage)
- [Bifrost governance configuration](https://docs.getbifrost.ai/deployment-guides/config-json/governance)
- [Container Apps ingress and private visibility](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Container Apps Key Vault references](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [ACR image import](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-import-images)
- [Azure PostgreSQL private networking](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private)
- [AVM registry module](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/container-registry/registry)
- [AVM workspace module](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/operational-insights/workspace)
- [AVM managed identity module](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/managed-identity/user-assigned-identity)
