param(
    [switch]$SkipPester
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'NetForge.ps1'
$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$versionPath = Join-Path $repoRoot 'version.json'
$dnsCatalogPath = Join-Path $repoRoot 'dns-providers.json'
$dnsCatalogHashPath = "$dnsCatalogPath.sha256"

if (-not (Test-Path -LiteralPath $versionPath)) {
    throw "version.json was not found."
}
if (-not (Test-Path -LiteralPath $dnsCatalogPath)) {
    throw "dns-providers.json was not found."
}
if (-not (Test-Path -LiteralPath $dnsCatalogHashPath)) {
    throw "dns-providers.json.sha256 was not found."
}

$versionMetadata = Get-Content -Raw -LiteralPath $versionPath | ConvertFrom-Json
$version = [string]$versionMetadata.Version
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "version.json Version must use MAJOR.MINOR.PATCH format."
}

function Assert-ContainsPattern {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name does not match expected version metadata pattern: $Pattern"
    }
}

function Get-Sha256 {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $hashBytes = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($sha) { $sha.Dispose() }
    }
}

$dnsCatalogHash = Get-Sha256 -Path $dnsCatalogPath
$dnsCatalogHashText = Get-Content -Raw -LiteralPath $dnsCatalogHashPath
if ($dnsCatalogHashText -notmatch "$dnsCatalogHash\s+dns-providers\.json") {
    throw "dns-providers.json.sha256 does not match dns-providers.json."
}

$scriptText = Get-Content -Raw -LiteralPath $scriptPath
$escapedVersion = [regex]::Escape($version)
Assert-ContainsPattern -Name 'NetForge.ps1 header' -Text $scriptText -Pattern "Version:\s+$escapedVersion"
Assert-ContainsPattern -Name 'NetForge.ps1 AppVersion' -Text $scriptText -Pattern "\`$script:AppVersion\s*=\s*`"$escapedVersion`""
Assert-ContainsPattern -Name 'NetForge.ps1 header badge' -Text $scriptText -Pattern "Text=`"v$escapedVersion`""
Assert-ContainsPattern -Name 'NetForge.ps1 footer' -Text $scriptText -Pattern "NetForge v$escapedVersion \| Running as Administrator"

$readmePath = Join-Path $repoRoot 'README.md'
if (Test-Path -LiteralPath $readmePath) {
    $readmeText = Get-Content -Raw -LiteralPath $readmePath
    Assert-ContainsPattern -Name 'README version badge' -Text $readmeText -Pattern "Version-$escapedVersion-orange"
}

$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $changelogPath) {
    $changelogText = Get-Content -Raw -LiteralPath $changelogPath
    Assert-ContainsPattern -Name 'CHANGELOG heading' -Text $changelogText -Pattern "## \[v$escapedVersion\]"
}

$claudePath = Join-Path $repoRoot 'CLAUDE.md'
if (Test-Path -LiteralPath $claudePath) {
    $claudeText = Get-Content -Raw -LiteralPath $claudePath
    Assert-ContainsPattern -Name 'CLAUDE overview version' -Text $claudeText -Pattern "v$escapedVersion\."
    Assert-ContainsPattern -Name 'CLAUDE version section' -Text $claudeText -Pattern "(?ms)## Version\s*\r?\n$escapedVersion"
}

$distPath = Join-Path $repoRoot 'dist'
if (Test-Path -LiteralPath $distPath) {
    $zipFiles = @(Get-ChildItem -Path $distPath -Filter 'NetForge-v*.zip' -File -ErrorAction SilentlyContinue)
    if ($zipFiles.Count -gt 0) {
        $expectedZip = "NetForge-v$version.zip"
        if ($zipFiles.Name -notcontains $expectedZip) {
            throw "dist does not contain expected release package $expectedZip."
        }
        $unexpectedZip = @($zipFiles | Where-Object { $_.Name -ne $expectedZip })
        if ($unexpectedZip.Count -gt 0) {
            throw "dist contains stale release package(s): $($unexpectedZip.Name -join ', ')"
        }

        $expectedZipPath = Join-Path $distPath $expectedZip
        $expectedShaPath = "$expectedZipPath.sha256"
        if (-not (Test-Path -LiteralPath $expectedShaPath -PathType Leaf)) {
            throw "dist does not contain expected checksum file $([System.IO.Path]::GetFileName($expectedShaPath))."
        }

        $actualHash = Get-Sha256 -Path $expectedZipPath
        $shaContent = Get-Content -Raw -LiteralPath $expectedShaPath
        $expectedShaPattern = "$actualHash\s+$([regex]::Escape($expectedZip))"
        if ($shaContent -notmatch $expectedShaPattern) {
            throw "dist checksum file does not match $expectedZip."
        }

        $unexpectedSha = @(Get-ChildItem -Path $distPath -Filter 'NetForge-v*.zip.sha256' -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $expectedShaPath })
        if ($unexpectedSha.Count -gt 0) {
            throw "dist contains stale checksum file(s): $($unexpectedSha.Name -join ', ')"
        }
    }
}

$scriptPaths = @($scriptPath)
$scriptPaths += @(Get-ChildItem -Path (Join-Path $repoRoot 'tools'), (Join-Path $repoRoot 'tests') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
$scriptPaths = @($scriptPaths | Select-Object -Unique)

foreach ($path in $scriptPaths) {
    $parseErrors = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $path), [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $parseErrors | Format-List * | Out-String | Write-Error
    }
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
