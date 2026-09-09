[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskPortalSource = Join-Path $taskRoot 'infra/portal.bicep'
$taskPortalTarget = Join-Path $taskRoot 'infra/azuredeploy.json'
$taskCandidate = Join-Path ([IO.Path]::GetTempPath()) ('bifrost-arm-' + [guid]::NewGuid().ToString('N') + '.json')

try {
    & az bicep build --file $taskPortalSource --outfile $taskCandidate
    if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }
    $taskCompiled = [IO.File]::ReadAllText($taskCandidate).Replace("`r`n", "`n")
    $taskTemplate = $taskCompiled | ConvertFrom-Json
    foreach ($taskParameter in $taskTemplate.parameters.PSObject.Properties) {
        if ($taskParameter.Value.defaultValue -match '\bvariables\s*\(') {
            throw "Portal parameter '$($taskParameter.Name)' has an invalid ARM variable reference in its default."
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $taskPortalTarget)) { throw 'infra/azuredeploy.json is missing.' }
        $taskCommitted = [IO.File]::ReadAllText($taskPortalTarget).Replace("`r`n", "`n")
        if ($taskCompiled -cne $taskCommitted) {
            throw 'infra/azuredeploy.json is stale. Run ./scripts/azure/build-template.ps1 with Bicep v0.47.16 and commit the result.'
        }
        Write-Output 'Portal ARM template matches the Bicep source.'
    } else {
        [IO.File]::WriteAllText($taskPortalTarget, $taskCompiled, [Text.UTF8Encoding]::new($false))
        Write-Output 'Generated infra/azuredeploy.json.'
    }
} finally {
    if (Test-Path -LiteralPath $taskCandidate) { Remove-Item -LiteralPath $taskCandidate }
}
