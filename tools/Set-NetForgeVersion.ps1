param(
    [string]$Version,
    [string]$ReleaseDate = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$metadataPath = Join-Path $repoRoot 'version.json'

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "version.json was not found."
    }
    $metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
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

$metadataObject = [ordered]@{
    Version = $Version
    ReleaseDate = $ReleaseDate
    PackageName = 'NetForge'
}
Set-Utf8Text -Path $metadataPath -Text (([pscustomobject]$metadataObject | ConvertTo-Json -Depth 4) + "`r`n")

$scriptPath = Join-Path $repoRoot 'NetForge.ps1'
$scriptText = Get-Content -Raw -LiteralPath $scriptPath
$scriptText = $scriptText -replace 'Version: \d+\.\d+\.\d+', "Version: $Version"
$scriptText = $scriptText -replace '\$script:AppVersion = "\d+\.\d+\.\d+"', "`$script:AppVersion = `"$Version`""
$scriptText = $scriptText -replace 'Text="v\d+\.\d+\.\d+"', "Text=`"v$Version`""
$scriptText = $scriptText -replace 'NetForge v\d+\.\d+\.\d+ \|', "NetForge v$Version |"
Set-Utf8Text -Path $scriptPath -Text $scriptText

$readmePath = Join-Path $repoRoot 'README.md'
if (Test-Path -LiteralPath $readmePath) {
    $readmeText = Get-Content -Raw -LiteralPath $readmePath
    $readmeText = $readmeText -replace 'Version-\d+\.\d+\.\d+-orange', "Version-$Version-orange"
    Set-Utf8Text -Path $readmePath -Text $readmeText
}

$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $changelogPath) {
    $changelogText = Get-Content -Raw -LiteralPath $changelogPath
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
    $claudeText = Get-Content -Raw -LiteralPath $claudePath
    $claudeText = [regex]::Replace($claudeText, 'v\d+\.\d+\.\d+\.', "v$Version.", 1)
    $claudeText = [regex]::Replace($claudeText, '(?ms)(## Version\s*\r?\n)\d+\.\d+\.\d+', "`${1}$Version", 1)
    Set-Utf8Text -Path $claudePath -Text $claudeText
}

Write-Host "NetForge version metadata updated to $Version."
