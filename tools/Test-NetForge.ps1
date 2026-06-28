param(
    [switch]$SkipPester
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'NetForge.ps1'
$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

$parseErrors = $null
[System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $scriptPath), [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List * | Out-String | Write-Error
}

$analysis = Invoke-ScriptAnalyzer -Path $scriptPath -Settings $settingsPath
if ($analysis.Count -gt 0) {
    $analysis | Format-Table RuleName, Severity, Line, Message -AutoSize | Out-String | Write-Error
}

if (-not $SkipPester) {
    Import-Module Pester -MinimumVersion 5.0 -Force
    $pesterResult = Invoke-Pester -Path (Join-Path $repoRoot 'tests') -CI -PassThru
    if ($pesterResult.FailedCount -gt 0) {
        throw "Pester failed with $($pesterResult.FailedCount) failing test(s)."
    }
}

Write-Host "NetForge local checks passed."
