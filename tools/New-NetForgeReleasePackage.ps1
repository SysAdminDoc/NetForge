param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$metadataPath = Join-Path $repoRoot 'version.json'
if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "version.json was not found."
}

$metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
$version = [string]$metadata.Version
$packageName = if ($metadata.PackageName) { [string]$metadata.PackageName } else { 'NetForge' }

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "version.json contains an invalid Version value."
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

$resolvedRepo = (Resolve-Path -LiteralPath $repoRoot).Path
$resolvedOutputParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $OutputDirectory))
if (-not $resolvedOutputParent.StartsWith($resolvedRepo, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output directory must stay inside the repository."
}

if (Test-Path -LiteralPath $OutputDirectory) {
    $resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
    if (-not $resolvedOutput.StartsWith($resolvedRepo, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove output directory outside the repository."
    }
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

$zipPath = Join-Path $OutputDirectory "$packageName-v$version.zip"
$packageItems = @(
    'NetForge.ps1',
    'README.md',
    'LICENSE',
    'icon.ico',
    'icon.png',
    'screenshot.png',
    'PSScriptAnalyzerSettings.psd1',
    'version.json',
    'tools',
    'tests'
) | ForEach-Object { Join-Path $repoRoot $_ }

Compress-Archive -Path $packageItems -DestinationPath $zipPath -Force
$sha256 = Get-Sha256 -Path $zipPath

[pscustomobject]@{
    Version = $version
    ZipPath = $zipPath
    Sha256 = $sha256
    Length = (Get-Item -LiteralPath $zipPath).Length
}
