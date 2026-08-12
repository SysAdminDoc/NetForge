param(
    [string]$Version,
    [string]$ReleaseDate = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$metadataPath = Join-Path $repoRoot 'version.json'

function Get-Utf8Text {
    param([string]$Path)

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "version.json was not found."
    }
    $metadata = Get-Utf8Text -Path $metadataPath | ConvertFrom-Json
    $Version = [string]$metadata.Version
    if ($metadata.ReleaseDate) {
        $ReleaseDate = [string]$metadata.ReleaseDate
    }
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must use MAJOR.MINOR.PATCH format."
}

function Set-Utf8Text {
    param(
        [string]$Path,
        [string]$Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

$metadataText = "{`n  `"Version`": `"$Version`",`n  `"ReleaseDate`": `"$ReleaseDate`",`n  `"PackageName`": `"NetForge`"`n}`n"
Set-Utf8Text -Path $metadataPath -Text $metadataText

$scriptPath = Join-Path $repoRoot 'NetForge.ps1'
$scriptText = Get-Utf8Text -Path $scriptPath
$scriptText = $scriptText -replace 'Version: \d+\.\d+\.\d+', "Version: $Version"
$scriptText = $scriptText -replace '\$script:AppVersion = "\d+\.\d+\.\d+"', "`$script:AppVersion = `"$Version`""
$scriptText = $scriptText -replace 'Text="v\d+\.\d+\.\d+"', "Text=`"v$Version`""
$scriptText = $scriptText -replace 'NetForge v\d+\.\d+\.\d+ \|', "NetForge v$Version |"
Set-Utf8Text -Path $scriptPath -Text $scriptText

$readmePath = Join-Path $repoRoot 'README.md'
if (Test-Path -LiteralPath $readmePath) {
    $readmeText = Get-Utf8Text -Path $readmePath
    $readmeText = $readmeText -replace 'Version-\d+\.\d+\.\d+-orange', "Version-$Version-orange"
    $readmeText = $readmeText -replace '(Set-NetForgeVersion\.ps1 -Version )\d+\.\d+\.\d+', "`${1}$Version"
    Set-Utf8Text -Path $readmePath -Text $readmeText
}

$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $changelogPath) {
    $changelogText = Get-Utf8Text -Path $changelogPath
    $heading = "## [v$Version] - $ReleaseDate"
    if ($changelogText -notmatch [regex]::Escape("## [v$Version]")) {
        $insert = "All notable changes to NetForge will be documented in this file.`r`n`r`n$heading`r`n`r`n- Changed: Version metadata updated."
        $changelogText = [regex]::Replace(
            $changelogText,
            'All notable changes to NetForge will be documented in this file\.',
            $insert,
            1
        )
    } else {
        $changelogText = [regex]::Replace($changelogText, "## \[v$([regex]::Escape($Version))\] - \d{4}-\d{2}-\d{2}", $heading, 1)
    }
    Set-Utf8Text -Path $changelogPath -Text $changelogText
}

$claudePath = Join-Path $repoRoot 'CLAUDE.md'
if (Test-Path -LiteralPath $claudePath) {
    $claudeText = Get-Utf8Text -Path $claudePath
    $claudeText = [regex]::Replace($claudeText, 'v\d+\.\d+\.\d+\.', "v$Version.", 1)
    $claudeText = [regex]::Replace($claudeText, '(?ms)(## Version\s*\r?\n)\d+\.\d+\.\d+', "`${1}$Version", 1)
    Set-Utf8Text -Path $claudePath -Text $claudeText
}

Write-Host "NetForge version metadata updated to $Version."
