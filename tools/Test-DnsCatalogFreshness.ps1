param(
    [switch]$RegenerateHash
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'dns-providers.json'
$hashPath = "$catalogPath.sha256"
$scriptPath = Join-Path $repoRoot 'NetForge.ps1'

if (-not (Test-Path -LiteralPath $catalogPath)) {
    throw "dns-providers.json was not found at $catalogPath."
}

$source = Get-Content -Raw $scriptPath
$ast = [scriptblock]::Create($source).Ast
foreach ($functionName in @('Test-ValidIPv4Address', 'Test-ValidIP', 'Test-DohTemplate', 'ConvertTo-DotHostValue', 'Test-DotHost', 'Test-DnsProviderEntry', 'Format-DnsCatalogFreshnessReport', 'ConvertFrom-DnsProviderCatalog', 'Test-DnsCatalogIntegrity', 'Get-FileSha256')) {
    $functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true)
    if ($null -eq $functionAst) { throw "Function '$functionName' was not found in NetForge.ps1." }
    Invoke-Expression "function global:$functionName $($functionAst.Body.Extent.Text)"
}

$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$conversion = ConvertFrom-DnsProviderCatalog -Catalog $catalog
$providers = @($catalog.Providers)

$issues = @()
if (-not $conversion.IsValid) {
    $issues += "Schema validation: $($conversion.Message)"
}

foreach ($provider in $providers) {
    $entryIssues = @(Test-DnsProviderEntry -Provider $provider)
    $issues += $entryIssues
}

$integrity = Test-DnsCatalogIntegrity -CatalogPath $catalogPath -HashPath $hashPath
$catalogHash = $integrity.Hash

if (-not $integrity.IsValid) {
    if ($RegenerateHash) {
        $hashLine = "$catalogHash  dns-providers.json"
        Set-Content -LiteralPath $hashPath -Value $hashLine -Encoding UTF8 -NoNewline
        Write-Host "Regenerated $hashPath"
        Write-Host "  $hashLine"
    } else {
        $issues += "Hash mismatch: $($integrity.Message) Run with -RegenerateHash to update."
    }
}

$report = Format-DnsCatalogFreshnessReport -TotalProviders $providers.Count -Issues $issues -CatalogHash $catalogHash
Write-Host $report

if ($issues.Count -gt 0) {
    exit 1
}
