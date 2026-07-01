param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$CertificateThumbprint = "",
    [string]$TimestampServer = "http://timestamp.digicert.com",
    [switch]$SkipSigning
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

function Set-Utf8Text {
    param(
        [string]$Path,
        [string]$Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Test-CodeSigningCertificate {
    param($Certificate)

    if ($null -eq $Certificate) { return $false }
    if (-not $Certificate.HasPrivateKey) { return $false }
    if ($Certificate.NotAfter -lt (Get-Date)) { return $false }

    foreach ($usage in @($Certificate.EnhancedKeyUsageList)) {
        if ($usage.ObjectId -eq '1.3.6.1.5.5.7.3.3' -or $usage.FriendlyName -eq 'Code Signing') {
            return $true
        }
    }

    return $false
}

function Get-CodeSigningCertificate {
    param([string]$Thumbprint)

    $stores = @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')
    $normalizedThumbprint = if ([string]::IsNullOrWhiteSpace($Thumbprint)) { "" } else { ($Thumbprint -replace '\s', '').ToUpperInvariant() }

    foreach ($store in $stores) {
        if (-not (Test-Path -LiteralPath $store)) { continue }

        $certificates = @(Get-ChildItem -Path $store -ErrorAction SilentlyContinue)
        foreach ($certificate in $certificates) {
            if (-not (Test-CodeSigningCertificate -Certificate $certificate)) { continue }
            if (-not [string]::IsNullOrWhiteSpace($normalizedThumbprint) -and (($certificate.Thumbprint -replace '\s', '').ToUpperInvariant() -ne $normalizedThumbprint)) { continue }
            return $certificate
        }
    }

    return $null
}

$scriptPath = Join-Path $repoRoot 'NetForge.ps1'
$scriptText = Get-Content -Raw -LiteralPath $scriptPath
$escapedVersion = [regex]::Escape($version)
if ($scriptText -notmatch "\`$script:AppVersion\s*=\s*`"$escapedVersion`"") {
    throw "NetForge.ps1 AppVersion does not match version.json ($version). Run Set-NetForgeVersion.ps1 first."
}
$readmePath = Join-Path $repoRoot 'README.md'
if (Test-Path -LiteralPath $readmePath) {
    $readmeText = Get-Content -Raw -LiteralPath $readmePath
    if ($readmeText -notmatch "Version-$escapedVersion-") {
        throw "README.md version badge does not match version.json ($version). Run Set-NetForgeVersion.ps1 first."
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
$sha256Path = "$zipPath.sha256"
$stagingRoot = Join-Path $env:TEMP "$packageName-release-$version-$([guid]::NewGuid().ToString('N'))"
$signatureStatus = "Skipped"
$signerThumbprint = ""
$packageItems = @(
    'NetForge.ps1',
    'README.md',
    'LICENSE',
    'icon.ico',
    'icon.png',
    'screenshot.png',
    'PSScriptAnalyzerSettings.psd1',
    'version.json',
    'dns-providers.json',
    'dns-providers.json.sha256',
    'strings',
    'lib',
    'licenses',
    'tools',
    'tests'
)

try {
    New-Item -Path $stagingRoot -ItemType Directory -Force | Out-Null
    foreach ($item in $packageItems) {
        $sourcePath = Join-Path $repoRoot $item
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Package item was not found: $item"
        }
        Copy-Item -LiteralPath $sourcePath -Destination $stagingRoot -Recurse -Force
    }

    $stagedScriptPath = Join-Path $stagingRoot 'NetForge.ps1'
    if ($SkipSigning) {
        $signatureStatus = "Skipped"
    } else {
        $certificate = Get-CodeSigningCertificate -Thumbprint $CertificateThumbprint
        if ($null -eq $certificate) {
            $signatureStatus = "NoCertificate"
        } else {
            $signArgs = @{
                FilePath = $stagedScriptPath
                Certificate = $certificate
            }
            if (-not [string]::IsNullOrWhiteSpace($TimestampServer)) {
                $signArgs['TimestampServer'] = $TimestampServer
            }

            $signature = Set-AuthenticodeSignature @signArgs
            $signatureStatus = [string]$signature.Status
            $signerThumbprint = [string]$certificate.Thumbprint
            if ($signature.Status -ne 'Valid') {
                throw "Authenticode signing failed with status $($signature.Status): $($signature.StatusMessage)"
            }
        }
    }

    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -Force
    $sha256 = Get-Sha256 -Path $zipPath
    Set-Utf8Text -Path $sha256Path -Text "$sha256  $([System.IO.Path]::GetFileName($zipPath))`r`n"
} finally {
    if ((Test-Path -LiteralPath $stagingRoot) -and $stagingRoot.StartsWith($env:TEMP, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

[pscustomobject]@{
    Version = $version
    ZipPath = $zipPath
    Sha256Path = $sha256Path
    Sha256 = $sha256
    Length = (Get-Item -LiteralPath $zipPath).Length
    SignatureStatus = $signatureStatus
    SignerThumbprint = $signerThumbprint
}
