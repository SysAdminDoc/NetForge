<#
.SYNOPSIS
    NetForge - Professional Network Adapter Management Utility
.DESCRIPTION
    Comprehensive network adapter configuration tool with static IP management,
    DNS control, profile saving, ping/latency monitoring, connection status,
    WiFi info, speed testing, DNS lookup, and extensive customization options.
.NOTES
    Author: NetForge
    Version: 1.52.0
    Requires: Windows PowerShell 5.1+ with Administrator privileges
#>

#Requires -Version 5.1

param(
    [string]$ApplyProfile = "",
    [string]$AdapterName = "",
    [switch]$Silent,
    [switch]$Debug
)

# ============================================================================
# ELEVATION CHECK
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        function ConvertTo-ElevationArgument {
            param([string]$Value)

            $text = [string]$Value
            if ($text -match '[\s"]') {
                return '"' + ($text -replace '"', '\"') + '"'
            }
            return $text
        }

        $cliMode = -not [string]::IsNullOrWhiteSpace($ApplyProfile)
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            (ConvertTo-ElevationArgument -Value $scriptPath)
        )
        if (-not [string]::IsNullOrWhiteSpace($ApplyProfile)) {
            $arguments += "-ApplyProfile"
            $arguments += (ConvertTo-ElevationArgument -Value $ApplyProfile)
        }
        if (-not [string]::IsNullOrWhiteSpace($AdapterName)) {
            $arguments += "-AdapterName"
            $arguments += (ConvertTo-ElevationArgument -Value $AdapterName)
        }
        if ($Silent) { $arguments += "-Silent" }
        if ($Debug) { $arguments += "-Debug" }

        $startArgs = @{
            FilePath = "powershell.exe"
            ArgumentList = ($arguments -join " ")
            Verb = "RunAs"
        }
        if ($cliMode) {
            $startArgs["Wait"] = $true
            $startArgs["PassThru"] = $true
        }

        $process = Start-Process @startArgs
        if ($cliMode -and $process) {
            exit $process.ExitCode
        }
    } else {
        Write-Host "Please run this script as Administrator." -ForegroundColor Red
        pause
    }
    exit
}

# ============================================================================
# ASSEMBLIES
# ============================================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:AppName = "NetForge"
$script:AppVersion = "1.52.0"
$script:ConfigPath = Join-Path $env:APPDATA "NetForge"
$script:DefaultProfilesPath = Join-Path $script:ConfigPath "Profiles"
$script:ProfilesPath = $script:DefaultProfilesPath
$script:LogsPath = Join-Path $script:ConfigPath "Logs"
$script:SettingsFile = Join-Path $script:ConfigPath "settings.json"
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$script:LibraryPath = Join-Path $script:ScriptRoot "lib"
$script:DnsCatalogPath = Join-Path $script:ScriptRoot "dns-providers.json"
$script:DnsCatalogHashPath = "$script:DnsCatalogPath.sha256"
$script:DnsCatalogStatus = "Embedded DNS preset defaults"
$script:StringsPath = Join-Path $script:ScriptRoot "strings"
$script:DefaultLocale = "en-US"
$script:UiLocale = $script:DefaultLocale
$script:UiTheme = "GitHub Dark"
$script:CompactModeEnabled = $false
$script:StringResources = @{}
$script:DefaultStringResources = @{}
$script:LocalizationStatus = "Embedded English UI text"
$script:LocalizationMissingKeys = @()
$script:ProfileSchemaVersion = 3
$script:ProfileQrPayloadPrefix = "NETFORGE-PROFILE-V1:"
$script:ProfileQrMaxPayloadLength = 2950
$script:ProfileStoreLoadWarning = ""
$script:ContinuousPingRunning = $false
$script:ContinuousPingPS = $null
$script:MtrRunning = $false
$script:MtrProbeRunning = $false
$script:MtrTimer = $null
$script:MtrPowerShell = $null
$script:MtrHistory = @{}
$script:MtrTarget = ""
$script:MtrCycle = 0
$script:PortScanRunning = $false
$script:PortScanPowerShell = $null
$script:ReachabilityWizardRunning = $false
$script:ReachabilityWizardPowerShell = $null
$script:PacketCaptureRunning = $false
$script:PacketCaptureEtlPath = ""
$script:PacketCapturePcapPath = ""
$script:CachedPublicIP = $null
$script:PublicIpLookupEnabled = $true
$script:ExternalSpeedTestEnabled = $true
$script:SpeedTestEndpoint = "https://speed.cloudflare.com/__down?bytes=1048576"
$script:DiscordWebhookEnabled = $false
$script:DiscordWebhookUrl = ""
$script:DiscordWebhookLastStatus = "Discord webhook notifications are disabled."
$script:SettingsSchemaVersion = 1
$script:ProtectedSettingNames = @("DiscordWebhookUrl")
$script:PendingProtectedSettingMigrations = [ordered]@{}
$script:SecretSettingLoadWarning = ""
$script:SpeedTestRunning = $false
$script:WifiScanRunning = $false
$script:WifiNetworks = @()
$script:WifiInterfaceName = $null
$script:ShowAdvancedAdapters = $false
$script:EncryptedDnsHealthRunning = $false
$script:EncryptedDnsHealthJob = $null
$script:EncryptedDnsHealthTimer = $null
$script:DoqProxyProcess = $null
$script:DoqProxyStderrPath = $null
$script:LastAutoAppliedProfile = ""
$script:LastAutoApplySignature = ""
$script:LastAutoApplyAttemptKey = ""
$script:LastScheduledProfileKey = ""
$script:LastNetworkSnapshot = $null
$script:LastProfileLoadWarnings = @()
$script:AutoProfileTimer = $null
$script:ScheduleProfileTimer = $null
$script:NetworkChangeHandlers = @{}
$script:NetworkChangeSubscribed = $false
$script:TrayIcon = $null
$script:TrayContextMenu = $null
$script:AppRoutingRuleGroup = "NetForge App Routing"
$script:AppRoutingPolicySettingName = "AppRoutingPolicies"
$script:RdpProcess = $null
$script:RdpRestoreSnapshot = $null
$script:RdpMonitorTimer = $null
$script:RdpLaunchTarget = ""
$script:ThemeSelectorInitializing = $false
$script:CompactModeInitializing = $false
$script:CompactOriginalMetrics = @{}
$script:AccessibilityNames = @{
    lstAdapters = "Network adapter list"
    cmbUiTheme = "Theme selector"
    chkCompactMode = "Compact mode"
    btnRefresh = "Refresh adapters"
    chkAdvancedAdapters = "Show advanced adapters"
    btnEnableAdapter = "Enable selected adapter"
    btnDisableAdapter = "Disable selected adapter"
    txtMacOverride = "MAC address override"
    btnGenerateMac = "Generate random MAC address"
    btnApplyMac = "Apply MAC address override"
    btnRevertMac = "Revert MAC address override"
    txtMetricValue = "Interface metric value"
    btnApplyMetric = "Apply interface metric"
    btnAutoMetric = "Restore automatic interface metric"
    btnIPv4FirstMetric = "Prefer IPv4 binding priority"
    btnIPv6FirstMetric = "Prefer IPv6 binding priority"
    rbDHCP = "Use DHCP IP configuration"
    rbStatic = "Use static IP configuration"
    txtIPAddress = "Static IP address"
    txtSubnet = "Subnet mask"
    txtGateway = "Default gateway"
    txtPrefix = "CIDR prefix length"
    chkConfigureIPv6Address = "Configure static IPv6 address"
    txtIPv6Address = "Static IPv6 address"
    txtIPv6Prefix = "IPv6 prefix length"
    txtIPv6Gateway = "IPv6 default gateway"
    btnApplyIP = "Apply IP configuration"
    rbDnsDHCP = "Use automatic DNS"
    rbDnsPreset = "Use DNS preset"
    rbDnsCustom = "Use custom DNS"
    txtDnsSearch = "Search DNS presets"
    cmbDnsCategory = "DNS category"
    lstDnsPresets = "DNS preset list"
    chkIPv6Dns = "Also configure IPv6 DNS"
    txtDnsPrimary = "Primary DNS server"
    txtDnsSecondary = "Secondary DNS server"
    btnApplyDns = "Apply DNS configuration"
    btnRegisterDoh = "Register DNS over HTTPS"
    btnRegisterDot = "Register DNS over TLS"
    btnTestEncryptedDns = "Test encrypted DNS health"
    txtNextDnsConfigId = "NextDNS configuration ID"
    btnApplyNextDnsEndpoints = "Apply NextDNS endpoints"
    btnValidateDoqProxy = "Validate DoQ proxy"
    btnStartDoqProxy = "Start DoQ proxy"
    btnStopDoqProxy = "Stop DoQ proxy"
    btnApplyDoqLocalDns = "Apply local DoQ DNS"
    btnWifiRefresh = "Scan WiFi networks"
    lstWifiNetworks = "WiFi network list"
    txtWifiSpectrumOutput = "WiFi spectrum channel utilization"
    btnWifiConnect = "Connect WiFi network"
    btnWifiDisconnect = "Disconnect WiFi"
    lstProfiles = "Saved profile list"
    btnNewProfile = "Create new profile"
    btnDeleteProfile = "Delete selected profile"
    btnExportProfileQr = "Export selected profile QR code"
    btnImportProfileQr = "Import profile QR code"
    btnChooseProfileStore = "Choose profile storage folder"
    btnUseOneDriveProfileStore = "Use OneDrive profile storage"
    btnRevertProfileStore = "Use local profile storage"
    btnProfileStoreHealth = "Check profile storage health"
    txtProfileName = "Profile name"
    txtProfileDesc = "Profile description"
    chkProfileAutoApply = "Enable profile auto-apply"
    txtProfileMatchSsid = "Profile match SSID"
    txtProfileGatewayMac = "Profile gateway MAC"
    btnCaptureProfileMatch = "Capture current network match"
    chkProfileSchedule = "Enable scheduled profile apply"
    txtProfileScheduleTime = "Scheduled profile time"
    txtProfileScheduleDays = "Scheduled profile days"
    chkProfileNetworkCategory = "Set Windows network category"
    cmbProfileNetworkCategory = "Profile network category"
    chkProfileProxy = "Set system proxy"
    chkProfileProxyEnabled = "Enable system proxy"
    txtProfileProxyServer = "Profile proxy server"
    txtProfileProxyBypass = "Profile proxy bypass list"
    chkProfilePrinter = "Set default printer"
    txtProfilePrinterName = "Profile default printer name"
    chkProfileMappedDrives = "Map network drives"
    txtProfileMappedDrives = "Profile mapped drive definitions"
    btnSaveProfile = "Save profile"
    btnProfileDiff = "Preview profile differences"
    btnApplyProfile = "Apply selected profile"
    btnFlushDns = "Flush DNS cache"
    btnReleaseIP = "Release IP address"
    btnRenewIP = "Renew IP address"
    btnRestoreNetworkState = "Restore last network state"
    chkDiagnosticsPrivacyMode = "Redact diagnostics export"
    btnExportDiagnostics = "Export diagnostics"
    btnCheckRelease = "Check latest GitHub release"
    btnRefreshAutoApply = "Refresh auto-apply inspector"
    cmbLocaleSelector = "UI language selector"
    btnSaveLocale = "Save locale setting"
    btnRefreshCapabilities = "Scan host capabilities"
    txtCapabilityMatrix = "Host capability scan results"
    txtAutoApplyInspector = "Auto-apply match status"
    txtReleaseCheckOutput = "Release check results"
    txtRdpTarget = "Remote Desktop host or RDP file"
    txtRdpProfileName = "Remote Desktop profile name"
    txtRdpAdapterName = "Remote Desktop adapter name or interface index"
    btnLaunchRdpProfile = "Launch Remote Desktop with profile"
    btnRevertRdpProfile = "Revert Remote Desktop profile"
    txtRdpStatus = "Remote Desktop profile launch status"
    txtAppRoutingProgram = "Application executable path for interface guard"
    btnBrowseAppRoutingProgram = "Browse for application executable"
    cmbAppRoutingInterface = "Allowed app routing interface"
    btnApplyAppRouting = "Apply app interface guard"
    btnRemoveAppRouting = "Remove selected app interface guard"
    btnRefreshAppRouting = "Refresh app interface guards"
    lstAppRoutingRules = "NetForge app interface guard list"
    chkPublicIpLookup = "Enable public IP lookup"
    chkExternalSpeedTest = "Allow external speed test downloads"
    cmbSpeedTestEndpoint = "Speed test endpoint"
    btnSaveEndpointPolicy = "Save endpoint policy"
    chkDiscordWebhook = "Enable Discord profile webhook"
    txtDiscordWebhookUrl = "Discord profile webhook URL"
    btnSaveDiscordWebhook = "Save Discord profile webhook"
    txtDiagPingTarget = "Diagnostics ping target"
    btnDiagPing = "Run diagnostics ping test"
    btnContinuousPing = "Start continuous ping"
    txtLatencyHistogramSeconds = "Latency histogram duration in seconds"
    btnLatencyHistogram = "Run latency histogram"
    txtPingLog = "Ping and latency output"
    btnResetWinsock = "Reset Winsock"
    btnResetTCP = "Reset TCP IP stack"
    btnNetworkReset = "Full network reset"
    txtPingTarget = "Network diagnostic target"
    btnPing = "Run ping"
    btnTraceroute = "Run traceroute"
    btnMtrTrace = "Start MTR trace"
    btnPortScan = "Run port scan"
    btnReachabilityWizard = "Run reachability wizard"
    btnPacketCapture = "Start packet capture"
    btnCableDiagnostics = "Run cable diagnostics"
    btnNslookup = "Run NSLookup"
    txtRouteDestination = "Static route destination prefix"
    txtRouteNextHop = "Static route next hop"
    txtRouteMetric = "Static route metric"
    btnAddStaticRoute = "Add static route"
    btnRemoveStaticRoute = "Remove selected static route"
    btnRefreshStaticRoutes = "Refresh static routes"
    lstStaticRoutes = "Manual static route list"
    txtHostsGroupName = "Hosts group name"
    txtHostsAddress = "Hosts entry address"
    txtHostsNames = "Hosts entry hostnames"
    btnHostsAddEntry = "Add hosts entry"
    btnHostsToggleGroup = "Toggle hosts group"
    btnHostsRemoveGroup = "Remove hosts group"
    btnHostsRefresh = "Refresh hosts groups"
    btnHostsApply = "Apply hosts groups"
    lstHostsGroups = "Hosts group list"
}
$script:AccessibilityTabOrder = @(
    "lstAdapters", "cmbUiTheme", "chkCompactMode", "btnRefresh", "chkAdvancedAdapters", "btnEnableAdapter", "btnDisableAdapter",
    "txtInterfaceMetric", "chkMetricIPv4", "chkMetricIPv6", "btnApplyMetric", "btnAutoMetric", "btnIPv4FirstMetric", "btnIPv6FirstMetric",
    "rbDHCP", "rbStatic", "txtIPAddress", "txtSubnet", "txtGateway", "txtPrefix", "chkConfigureIPv6Address", "txtIPv6Address", "txtIPv6Prefix", "txtIPv6Gateway", "btnApplyIP",
    "rbDnsDHCP", "rbDnsPreset", "rbDnsCustom", "txtDnsSearch", "cmbDnsCategory", "lstDnsPresets", "btnApplyDns",
    "lstProfiles", "btnNewProfile", "btnDeleteProfile", "btnExportProfileQr", "btnImportProfileQr", "btnChooseProfileStore", "btnUseOneDriveProfileStore", "btnRevertProfileStore", "btnProfileStoreHealth",
    "txtProfileName", "chkProfileAutoApply", "txtProfileMatchSsid", "txtProfileGatewayMac", "btnCaptureProfileMatch",
    "chkProfileSchedule", "txtProfileScheduleTime", "txtProfileScheduleDays", "chkProfileNetworkCategory", "cmbProfileNetworkCategory", "chkProfileProxy", "chkProfilePrinter", "chkProfileMappedDrives",
    "btnSaveProfile", "btnProfileDiff", "btnApplyProfile", "btnRefreshAutoApply",
    "btnFlushDns", "btnRestoreNetworkState", "chkDiagnosticsPrivacyMode", "btnExportDiagnostics", "btnCheckRelease", "cmbLocaleSelector", "btnSaveLocale", "btnRefreshCapabilities", "txtRdpTarget", "txtRdpProfileName", "txtRdpAdapterName", "btnLaunchRdpProfile", "btnRevertRdpProfile",
    "txtAppRoutingProgram", "btnBrowseAppRoutingProgram", "cmbAppRoutingInterface", "btnApplyAppRouting", "btnRemoveAppRouting", "btnRefreshAppRouting", "lstAppRoutingRules",
    "txtPingTarget", "btnPing", "btnTraceroute", "btnMtrTrace", "btnPortScan", "btnReachabilityWizard", "btnPacketCapture", "btnCableDiagnostics", "btnNslookup",
    "txtRouteDestination", "txtRouteNextHop", "txtRouteMetric", "btnAddStaticRoute", "btnRemoveStaticRoute", "btnRefreshStaticRoutes", "lstStaticRoutes",
    "txtHostsGroupName", "txtHostsAddress", "txtHostsNames", "btnHostsAddEntry", "btnHostsToggleGroup", "btnHostsRemoveGroup", "btnHostsRefresh", "btnHostsApply", "lstHostsGroups",
    "chkPublicIpLookup", "chkExternalSpeedTest", "cmbSpeedTestEndpoint", "btnSaveEndpointPolicy", "chkDiscordWebhook", "txtDiscordWebhookUrl", "btnSaveDiscordWebhook",
    "txtDiagPingTarget", "btnDiagPing", "btnContinuousPing", "txtLatencyHistogramSeconds", "btnLatencyHistogram"
)

function Get-UiThemeCatalog {
    return [ordered]@{
        "GitHub Dark" = [ordered]@{
            BgPrimary = "#0d1117"
            BgSecondary = "#161b22"
            BgTertiary = "#21262d"
            BgStatus = "#0f1318"
            BorderColor = "#30363d"
            AccentBlue = "#58a6ff"
            AccentGreen = "#3fb950"
            AccentOrange = "#d29922"
            AccentRed = "#f85149"
            AccentPurple = "#a371f7"
            TextPrimary = "#f0f6fc"
            TextSecondary = "#8b949e"
            TextMuted = "#6e7681"
            ButtonHover = "#30363d"
            ButtonPressed = "#282e36"
            SuccessButton = "#238636"
            SuccessButtonHover = "#2ea043"
            DangerButtonBg = "#21262d"
            DangerButtonHover = "#26f85149"
            DangerButtonPressed = "#40f85149"
            ListItemHover = "#1f2428"
            ListItemSelected = "#261f6feb"
        }
        "Catppuccin Mocha" = [ordered]@{
            BgPrimary = "#1e1e2e"
            BgSecondary = "#181825"
            BgTertiary = "#313244"
            BgStatus = "#11111b"
            BorderColor = "#45475a"
            AccentBlue = "#89b4fa"
            AccentGreen = "#a6e3a1"
            AccentOrange = "#fab387"
            AccentRed = "#f38ba8"
            AccentPurple = "#cba6f7"
            TextPrimary = "#cdd6f4"
            TextSecondary = "#bac2de"
            TextMuted = "#6c7086"
            ButtonHover = "#45475a"
            ButtonPressed = "#313244"
            SuccessButton = "#3d7a50"
            SuccessButtonHover = "#4f8f63"
            DangerButtonBg = "#313244"
            DangerButtonHover = "#26f38ba8"
            DangerButtonPressed = "#40f38ba8"
            ListItemHover = "#313244"
            ListItemSelected = "#2689b4fa"
        }
        "Nord" = [ordered]@{
            BgPrimary = "#2e3440"
            BgSecondary = "#3b4252"
            BgTertiary = "#434c5e"
            BgStatus = "#242933"
            BorderColor = "#4c566a"
            AccentBlue = "#88c0d0"
            AccentGreen = "#a3be8c"
            AccentOrange = "#ebcb8b"
            AccentRed = "#bf616a"
            AccentPurple = "#b48ead"
            TextPrimary = "#eceff4"
            TextSecondary = "#d8dee9"
            TextMuted = "#aeb6c4"
            ButtonHover = "#4c566a"
            ButtonPressed = "#3b4252"
            SuccessButton = "#5e8a65"
            SuccessButtonHover = "#6f9a75"
            DangerButtonBg = "#3b4252"
            DangerButtonHover = "#26bf616a"
            DangerButtonPressed = "#40bf616a"
            ListItemHover = "#3b4252"
            ListItemSelected = "#2688c0d0"
        }
    }
}

function Get-UiThemeNames {
    return @((Get-UiThemeCatalog).Keys)
}

function Resolve-UiThemeName {
    param([string]$Name)

    $themes = Get-UiThemeCatalog
    $candidate = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return "GitHub Dark"
    }

    foreach ($themeName in $themes.Keys) {
        if ($themeName -ieq $candidate) {
            return $themeName
        }
    }

    return "GitHub Dark"
}

function Test-ProtectedAppSettingName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    foreach ($settingName in @($script:ProtectedSettingNames)) {
        if ($settingName -ieq $Name) { return $true }
    }

    return $false
}

function Get-ProtectedAppSettingName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Setting name is required."
    }

    return ("{0}Protected" -f $Name)
}

function Initialize-ProtectedDataApi {
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
    } catch {
        [void]$_.Exception
    }
}

function Protect-AppSettingSecret {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return "" }

    Initialize-ProtectedDataApi
    try {
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Convert]::ToBase64String($protectedBytes)
    } catch {
        throw "Could not protect setting secret with current-user DPAPI. $($_.Exception.Message)"
    }
}

function Unprotect-AppSettingSecret {
    param([AllowEmptyString()][string]$ProtectedValue)

    if ([string]::IsNullOrWhiteSpace($ProtectedValue)) { return "" }

    Initialize-ProtectedDataApi
    try {
        $protectedBytes = [Convert]::FromBase64String($ProtectedValue)
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } catch {
        throw "Could not decrypt protected setting secret. $($_.Exception.Message)"
    }
}

function Get-AppSettingSecretValue {
    param(
        $Settings,
        [string]$Name
    )

    $result = [ordered]@{
        HasValue = $false
        Value = ""
        IsProtected = $false
        NeedsMigration = $false
        Error = ""
    }

    if ($null -eq $Settings -or [string]::IsNullOrWhiteSpace($Name)) {
        return [pscustomobject]$result
    }

    $protectedName = Get-ProtectedAppSettingName -Name $Name
    $protectedProperty = $Settings.PSObject.Properties[$protectedName]
    $plainProperty = $Settings.PSObject.Properties[$Name]

    if ($protectedProperty -and -not [string]::IsNullOrWhiteSpace([string]$protectedProperty.Value)) {
        $result.IsProtected = $true
        try {
            $plainValue = Unprotect-AppSettingSecret -ProtectedValue ([string]$protectedProperty.Value)
            if (-not [string]::IsNullOrWhiteSpace($plainValue)) {
                $result.HasValue = $true
                $result.Value = $plainValue.Trim()
            }
            return [pscustomobject]$result
        } catch {
            $result.Error = $_.Exception.Message
            if (-not $plainProperty -or [string]::IsNullOrWhiteSpace([string]$plainProperty.Value)) {
                return [pscustomobject]$result
            }
        }
    }

    if ($plainProperty -and -not [string]::IsNullOrWhiteSpace([string]$plainProperty.Value)) {
        $result.HasValue = $true
        $result.Value = ([string]$plainProperty.Value).Trim()
        $result.NeedsMigration = $true
    }

    return [pscustomobject]$result
}

if (Test-Path -LiteralPath $script:SettingsFile) {
    try {
        $settings = Get-Content -Raw -LiteralPath $script:SettingsFile | ConvertFrom-Json
        if ($settings.ProfileStorePath) {
            $candidatePath = [Environment]::ExpandEnvironmentVariables(([string]$settings.ProfileStorePath).Trim())
            if ([System.IO.Path]::IsPathRooted($candidatePath)) {
                $script:ProfilesPath = [System.IO.Path]::GetFullPath($candidatePath)
            } else {
                $script:ProfileStoreLoadWarning = "ProfileStorePath is not rooted; using local profile storage."
            }
        }
        if ($settings.UiLocale) {
            $candidateLocale = ([string]$settings.UiLocale).Trim()
            if ($candidateLocale -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$') {
                $script:UiLocale = $candidateLocale
            } else {
                $script:LocalizationStatus = "Invalid UiLocale in settings.json; using en-US."
            }
        }
        if ($settings.UiTheme) {
            $script:UiTheme = Resolve-UiThemeName -Name ([string]$settings.UiTheme)
        }
        if ($null -ne $settings.CompactMode) {
            $script:CompactModeEnabled = ([string]$settings.CompactMode).Trim() -match '^(1|true|yes|on|enabled)$'
        }
        if ($null -ne $settings.PublicIpLookupEnabled) {
            $script:PublicIpLookupEnabled = -not (([string]$settings.PublicIpLookupEnabled).Trim() -match '^(0|false|no|off|disabled)$')
        }
        if ($null -ne $settings.ExternalSpeedTestEnabled) {
            $script:ExternalSpeedTestEnabled = -not (([string]$settings.ExternalSpeedTestEnabled).Trim() -match '^(0|false|no|off|disabled)$')
        }
        if ($settings.SpeedTestEndpoint) {
            $script:SpeedTestEndpoint = [string]$settings.SpeedTestEndpoint
        }
        if ($null -ne $settings.DiscordWebhookEnabled) {
            $script:DiscordWebhookEnabled = -not (([string]$settings.DiscordWebhookEnabled).Trim() -match '^(0|false|no|off|disabled)$')
        }
        $discordWebhookSecret = Get-AppSettingSecretValue -Settings $settings -Name "DiscordWebhookUrl"
        if ($discordWebhookSecret.HasValue) {
            $script:DiscordWebhookUrl = [string]$discordWebhookSecret.Value
        }
        if ($discordWebhookSecret.NeedsMigration -and -not [string]::IsNullOrWhiteSpace($script:DiscordWebhookUrl)) {
            $script:PendingProtectedSettingMigrations["DiscordWebhookUrl"] = $script:DiscordWebhookUrl
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$discordWebhookSecret.Error)) {
            $script:SecretSettingLoadWarning = [string]$discordWebhookSecret.Error
        }
    } catch {
        $script:ProfileStoreLoadWarning = "Could not read settings.json; using local profile storage. $($_.Exception.Message)"
    }
}

# Create directories
if (-not (Test-Path $script:ConfigPath)) { New-Item -Path $script:ConfigPath -ItemType Directory -Force | Out-Null }
try {
    if (-not (Test-Path $script:ProfilesPath)) {
        New-Item -Path $script:ProfilesPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $script:ProfileStoreLoadWarning = "Saved profile store was unavailable; using local profile storage. $($_.Exception.Message)"
    $script:ProfilesPath = $script:DefaultProfilesPath
    if (-not (Test-Path $script:ProfilesPath)) {
        New-Item -Path $script:ProfilesPath -ItemType Directory -Force | Out-Null
    }
}
if (-not (Test-Path $script:LogsPath)) { New-Item -Path $script:LogsPath -ItemType Directory -Force | Out-Null }

# ============================================================================
# DNS PRESETS DATABASE
# ============================================================================
$script:DnsPresets = [ordered]@{
    "DHCP (Automatic)" = @{
        Primary = "DHCP"
        Secondary = "DHCP"
        Description = "Obtain DNS server address automatically"
        Category = "Default"
    }
    "Google Public DNS" = @{
        Primary = "8.8.8.8"
        Secondary = "8.8.4.4"
        PrimaryV6 = "2001:4860:4860::8888"
        SecondaryV6 = "2001:4860:4860::8844"
        DoHTemplate = "https://dns.google/dns-query"
        DoTHost = "dns.google:853"
        Description = "Fast, reliable DNS by Google"
        Category = "Public"
    }
    "Cloudflare DNS" = @{
        Primary = "1.1.1.1"
        Secondary = "1.0.0.1"
        PrimaryV6 = "2606:4700:4700::1111"
        SecondaryV6 = "2606:4700:4700::1001"
        DoHTemplate = "https://cloudflare-dns.com/dns-query"
        DoTHost = "one.one.one.one:853"
        Description = "Privacy-focused, fastest DNS resolver"
        Category = "Public"
    }
    "Cloudflare Malware Blocking" = @{
        Primary = "1.1.1.2"
        Secondary = "1.0.0.2"
        PrimaryV6 = "2606:4700:4700::1112"
        SecondaryV6 = "2606:4700:4700::1002"
        DoHTemplate = "https://security.cloudflare-dns.com/dns-query"
        DoTHost = "security.cloudflare-dns.com:853"
        Description = "Cloudflare with malware protection"
        Category = "Security"
    }
    "Cloudflare Family" = @{
        Primary = "1.1.1.3"
        Secondary = "1.0.0.3"
        PrimaryV6 = "2606:4700:4700::1113"
        SecondaryV6 = "2606:4700:4700::1003"
        DoHTemplate = "https://family.cloudflare-dns.com/dns-query"
        DoTHost = "family.cloudflare-dns.com:853"
        Description = "Cloudflare with malware + adult content blocking"
        Category = "Family"
    }
    "Quad9 DNS" = @{
        Primary = "9.9.9.9"
        Secondary = "149.112.112.112"
        PrimaryV6 = "2620:fe::fe"
        SecondaryV6 = "2620:fe::9"
        DoHTemplate = "https://dns.quad9.net/dns-query"
        DoTHost = "dns.quad9.net:853"
        Description = "Security-focused with threat blocking"
        Category = "Security"
    }
    "Quad9 Unsecured" = @{
        Primary = "9.9.9.10"
        Secondary = "149.112.112.10"
        PrimaryV6 = "2620:fe::10"
        SecondaryV6 = "2620:fe::fe:10"
        Description = "Quad9 without security filtering"
        Category = "Public"
    }
    "OpenDNS Home" = @{
        Primary = "208.67.222.222"
        Secondary = "208.67.220.220"
        PrimaryV6 = "2620:119:35::35"
        SecondaryV6 = "2620:119:53::53"
        Description = "Cisco's reliable DNS service"
        Category = "Public"
    }
    "OpenDNS FamilyShield" = @{
        Primary = "208.67.222.123"
        Secondary = "208.67.220.123"
        Description = "OpenDNS with adult content blocking"
        Category = "Family"
    }
    "AdGuard DNS" = @{
        Primary = "94.140.14.14"
        Secondary = "94.140.15.15"
        PrimaryV6 = "2a10:50c0::ad1:ff"
        SecondaryV6 = "2a10:50c0::ad2:ff"
        DoHTemplate = "https://dns.adguard-dns.com/dns-query"
        DoTHost = "dns.adguard-dns.com:853"
        Description = "Ad-blocking DNS service"
        Category = "Ad-Blocking"
    }
    "AdGuard Family" = @{
        Primary = "94.140.14.15"
        Secondary = "94.140.15.16"
        PrimaryV6 = "2a10:50c0::bad1:ff"
        SecondaryV6 = "2a10:50c0::bad2:ff"
        Description = "AdGuard with family protection"
        Category = "Family"
    }
    "AdGuard Non-Filtering" = @{
        Primary = "94.140.14.140"
        Secondary = "94.140.14.141"
        PrimaryV6 = "2a10:50c0::1:ff"
        SecondaryV6 = "2a10:50c0::2:ff"
        Description = "AdGuard without filtering"
        Category = "Public"
    }
    "CleanBrowsing Security" = @{
        Primary = "185.228.168.9"
        Secondary = "185.228.169.9"
        PrimaryV6 = "2a0d:2a00:1::2"
        SecondaryV6 = "2a0d:2a00:2::2"
        Description = "Blocks phishing and malware"
        Category = "Security"
    }
    "CleanBrowsing Adult" = @{
        Primary = "185.228.168.10"
        Secondary = "185.228.169.11"
        PrimaryV6 = "2a0d:2a00:1::1"
        SecondaryV6 = "2a0d:2a00:2::1"
        Description = "Blocks adult content"
        Category = "Family"
    }
    "CleanBrowsing Family" = @{
        Primary = "185.228.168.168"
        Secondary = "185.228.169.168"
        PrimaryV6 = "2a0d:2a00:1::"
        SecondaryV6 = "2a0d:2a00:2::"
        Description = "Strictest family filter"
        Category = "Family"
    }
    "Comodo Secure DNS" = @{
        Primary = "8.26.56.26"
        Secondary = "8.20.247.20"
        Description = "Security-focused DNS"
        Category = "Security"
    }
    "Neustar UltraDNS" = @{
        Primary = "64.6.64.6"
        Secondary = "64.6.65.6"
        Description = "Fast and reliable DNS"
        Category = "Public"
    }
    "Neustar Threat Protection" = @{
        Primary = "156.154.70.2"
        Secondary = "156.154.71.2"
        Description = "Neustar with threat blocking"
        Category = "Security"
    }
    "Neustar Family Secure" = @{
        Primary = "156.154.70.3"
        Secondary = "156.154.71.3"
        Description = "Neustar family protection"
        Category = "Family"
    }
    "DNS.Watch" = @{
        Primary = "84.200.69.80"
        Secondary = "84.200.70.40"
        PrimaryV6 = "2001:1608:10:25::1c04:b12f"
        SecondaryV6 = "2001:1608:10:25::9249:d69b"
        Description = "No logging, no censorship"
        Category = "Privacy"
    }
    "Verisign Public DNS" = @{
        Primary = "64.6.64.6"
        Secondary = "64.6.65.6"
        PrimaryV6 = "2620:74:1b::1:1"
        SecondaryV6 = "2620:74:1c::2:2"
        Description = "Stable and secure DNS"
        Category = "Public"
    }
    "Alternate DNS" = @{
        Primary = "76.76.19.19"
        Secondary = "76.223.122.150"
        PrimaryV6 = "2602:fcbc::ad"
        SecondaryV6 = "2602:fcbc:2::ad"
        Description = "Ad-blocking DNS"
        Category = "Ad-Blocking"
    }
    "UncensoredDNS" = @{
        Primary = "91.239.100.100"
        Secondary = "89.233.43.71"
        PrimaryV6 = "2001:67c:28a4::"
        SecondaryV6 = "2a01:3a0:53:53::"
        Description = "Danish uncensored DNS"
        Category = "Privacy"
    }
    "Yandex DNS Basic" = @{
        Primary = "77.88.8.8"
        Secondary = "77.88.8.1"
        PrimaryV6 = "2a02:6b8::feed:0ff"
        SecondaryV6 = "2a02:6b8:0:1::feed:0ff"
        Description = "Fast Russian DNS"
        Category = "Public"
    }
    "Yandex DNS Safe" = @{
        Primary = "77.88.8.88"
        Secondary = "77.88.8.2"
        PrimaryV6 = "2a02:6b8::feed:bad"
        SecondaryV6 = "2a02:6b8:0:1::feed:bad"
        Description = "Yandex with threat protection"
        Category = "Security"
    }
    "Yandex DNS Family" = @{
        Primary = "77.88.8.7"
        Secondary = "77.88.8.3"
        PrimaryV6 = "2a02:6b8::feed:a11"
        SecondaryV6 = "2a02:6b8:0:1::feed:a11"
        Description = "Yandex family filter"
        Category = "Family"
    }
    "NextDNS" = @{
        Primary = "45.90.28.167"
        Secondary = "45.90.30.167"
        PrimaryV6 = "2a07:a8c0::c4:4c6f"
        SecondaryV6 = "2a07:a8c1::c4:4c6f"
        Description = "Customizable cloud DNS"
        Category = "Privacy"
    }
    "Control D" = @{
        Primary = "76.76.2.0"
        Secondary = "76.76.10.0"
        PrimaryV6 = "2606:1a40::"
        SecondaryV6 = "2606:1a40:1::"
        Description = "Customizable DNS service"
        Category = "Privacy"
    }
    "Mullvad DNS" = @{
        Primary = "194.242.2.2"
        Secondary = "193.19.108.2"
        PrimaryV6 = "2a07:e340::2"
        Description = "Privacy-focused, no logging"
        Category = "Privacy"
    }
    "LibreDNS" = @{
        Primary = "116.202.176.26"
        Secondary = "116.202.176.26"
        Description = "OpenNIC DNS, no logging"
        Category = "Privacy"
    }
    "Hurricane Electric" = @{
        Primary = "74.82.42.42"
        Secondary = "74.82.42.42"
        PrimaryV6 = "2001:470:20::2"
        Description = "IPv6-focused DNS"
        Category = "Public"
    }
    "Level3 DNS" = @{
        Primary = "4.2.2.1"
        Secondary = "4.2.2.2"
        Description = "Legacy enterprise DNS"
        Category = "Public"
    }
    "SafeDNS" = @{
        Primary = "195.46.39.39"
        Secondary = "195.46.39.40"
        Description = "Cloud-based filtering DNS"
        Category = "Security"
    }
    "Dyn DNS" = @{
        Primary = "216.146.35.35"
        Secondary = "216.146.36.36"
        Description = "Oracle Dyn DNS service"
        Category = "Public"
    }
    "FreeDNS" = @{
        Primary = "37.235.1.174"
        Secondary = "37.235.1.177"
        Description = "Austrian free DNS"
        Category = "Public"
    }
    "Freenom World" = @{
        Primary = "80.80.80.80"
        Secondary = "80.80.81.81"
        Description = "Global anycast DNS"
        Category = "Public"
    }
    "puntCAT" = @{
        Primary = "109.69.8.51"
        Description = "Catalan DNS service"
        Category = "Public"
    }
}

function ConvertFrom-StringResourceDocument {
    param(
        $ResourceDocument,
        [string]$Path = ""
    )

    $messages = New-Object System.Collections.Generic.List[string]
    $strings = [ordered]@{}

    if ($null -eq $ResourceDocument) {
        $messages.Add("Resource document is empty.")
    } elseif ($null -eq $ResourceDocument.strings) {
        $messages.Add("Resource document must contain a strings object.")
    } else {
        foreach ($property in $ResourceDocument.strings.PSObject.Properties) {
            $key = [string]$property.Name
            $value = $property.Value

            if ([string]::IsNullOrWhiteSpace($key)) {
                $messages.Add("Resource key cannot be blank.")
                continue
            }
            if ($null -eq $value) {
                $messages.Add("Resource key '$key' cannot be null.")
                continue
            }

            $strings[$key] = [string]$value
        }
    }

    return [pscustomobject]@{
        IsValid = ($messages.Count -eq 0)
        Strings = $strings
        Message = ($messages -join " ")
        Path = $Path
    }
}

function Read-StringResourceFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            IsValid = $false
            Strings = [ordered]@{}
            Message = "Resource file was not found: $Path"
            Path = $Path
        }
    }

    try {
        $resourceDocument = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        return ConvertFrom-StringResourceDocument -ResourceDocument $resourceDocument -Path $Path
    } catch {
        return [pscustomobject]@{
            IsValid = $false
            Strings = [ordered]@{}
            Message = $_.Exception.Message
            Path = $Path
        }
    }
}

function Get-DynamicLocalizationKeyList {
    return @(
        "button.continuousPing.start",
        "button.continuousPing.stop",
        "button.latencyHistogram.idle",
        "button.latencyHistogram.running",
        "button.mtr.start",
        "button.mtr.stop",
        "button.portScan.idle",
        "button.portScan.running",
        "button.packetCapture.start",
        "button.packetCapture.stop",
        "button.speedTest.idle",
        "button.speedTest.running",
        "footer.adminStatusFormat"
    )
}

function ConvertTo-SettingsBoolean {
    param(
        $Value,
        [bool]$DefaultValue = $false
    )

    if ($null -eq $Value) { return $DefaultValue }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $DefaultValue }
    if ($text -match '^(1|true|yes|on|enabled)$') { return $true }
    if ($text -match '^(0|false|no|off|disabled)$') { return $false }

    return $DefaultValue
}

function Test-HttpsEndpointUri {
    param([string]$Uri)

    if ([string]::IsNullOrWhiteSpace($Uri)) { return $false }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Uri.Trim(), [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    return ($parsedUri.Scheme -eq [System.Uri]::UriSchemeHttps)
}

function Get-PublicIpEndpointList {
    return @(
        "https://api.ipify.org",
        "https://icanhazip.com"
    )
}

function Get-SpeedTestEndpointCatalog {
    return @(
        [pscustomobject]@{ Name = "Cloudflare 1 MB (HTTPS)"; Url = "https://speed.cloudflare.com/__down?bytes=1048576" },
        [pscustomobject]@{ Name = "OVH 1 MB (HTTPS)"; Url = "https://proof.ovh.net/files/1Mb.dat" }
    )
}

function Resolve-SpeedTestEndpoint {
    param([string]$Endpoint)

    $catalog = @(Get-SpeedTestEndpointCatalog)
    $fallback = $catalog[0]
    if ([string]::IsNullOrWhiteSpace($Endpoint)) { return $fallback }

    foreach ($entry in $catalog) {
        if ($entry.Url -eq $Endpoint -or $entry.Name -eq $Endpoint) {
            if (Test-HttpsEndpointUri -Uri $entry.Url) { return $entry }
        }
    }

    return $fallback
}

function Initialize-StringResources {
    param([string]$Locale = $script:UiLocale)

    $script:StringResources = @{}
    $script:DefaultStringResources = @{}
    $script:LocalizationMissingKeys = @()

    $defaultPath = Join-Path $script:StringsPath "$($script:DefaultLocale).json"
    $defaultResult = Read-StringResourceFile -Path $defaultPath
    if (-not $defaultResult.IsValid) {
        $script:LocalizationStatus = "Using embedded English UI text. $($defaultResult.Message)"
        return $defaultResult
    }

    foreach ($key in $defaultResult.Strings.Keys) {
        $script:StringResources[$key] = $defaultResult.Strings[$key]
        $script:DefaultStringResources[$key] = $defaultResult.Strings[$key]
    }

    $requestedLocale = if ([string]::IsNullOrWhiteSpace($Locale)) { $script:DefaultLocale } else { $Locale.Trim() }
    if ($requestedLocale -notmatch '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$') {
        $script:LocalizationStatus = "Invalid locale '$requestedLocale'; using $($script:DefaultLocale)."
        return $defaultResult
    }

    if ($requestedLocale -ne $script:DefaultLocale) {
        $localePath = Join-Path $script:StringsPath "$requestedLocale.json"
        $localeResult = Read-StringResourceFile -Path $localePath
        if ($localeResult.IsValid) {
            foreach ($key in $localeResult.Strings.Keys) {
                $script:StringResources[$key] = $localeResult.Strings[$key]
            }

            $missingKeys = @($defaultResult.Strings.Keys | Where-Object { -not $localeResult.Strings.Contains($_) })
            $script:LocalizationMissingKeys = $missingKeys
            if ($missingKeys.Count -gt 0) {
                $script:LocalizationStatus = "Loaded $requestedLocale with $($missingKeys.Count) fallback string(s)."
            } else {
                $script:LocalizationStatus = "Loaded $requestedLocale UI strings."
            }
        } else {
            $script:LocalizationStatus = "Could not load $requestedLocale; using $($script:DefaultLocale). $($localeResult.Message)"
        }
    } else {
        $script:LocalizationStatus = "Loaded $($script:DefaultLocale) UI strings."
    }

    return [pscustomobject]@{
        IsValid = $true
        Strings = $script:StringResources
        Message = $script:LocalizationStatus
        Path = $defaultPath
    }
}

function Get-UiString {
    param(
        [string]$Key,
        [string]$DefaultValue = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Key) -and $script:StringResources.ContainsKey($Key)) {
        return [string]$script:StringResources[$Key]
    }

    return $DefaultValue
}

function Invoke-XamlLocalization {
    param([xml]$XamlDocument)

    if ($null -eq $XamlDocument -or $script:DefaultStringResources.Count -eq 0) { return }

    $textToKey = @{}
    foreach ($key in $script:DefaultStringResources.Keys) {
        $defaultText = [string]$script:DefaultStringResources[$key]
        if ([string]::IsNullOrEmpty($defaultText)) { continue }
        if (-not $textToKey.ContainsKey($defaultText)) {
            $textToKey[$defaultText] = $key
        }
    }

    $attributes = @("Title", "Header", "Content", "Text")
    $nodes = $XamlDocument.SelectNodes("//*[@Title or @Header or @Content or @Text]")
    foreach ($node in $nodes) {
        foreach ($attributeName in $attributes) {
            if (-not $node.HasAttribute($attributeName)) { continue }

            $currentValue = $node.GetAttribute($attributeName)
            if (-not $textToKey.ContainsKey($currentValue)) { continue }

            $key = $textToKey[$currentValue]
            $node.SetAttribute($attributeName, (Get-UiString -Key $key -DefaultValue $currentValue))
        }
    }
}

function Apply-Localization {
    if ($script:txtFooterStatus) {
        $footerFormat = Get-UiString -Key "footer.adminStatusFormat" -DefaultValue "NetForge v{0} | Running as Administrator"
        $script:txtFooterStatus.Text = $footerFormat -f $script:AppVersion
    }
}

# ============================================================================
# XAML INTERFACE
# ============================================================================
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="NetForge - Network Adapter Management"
    Width="1200"
    Height="900"
    MinWidth="1000"
    MinHeight="700"
    WindowStartupLocation="CenterScreen"
    Background="#0d1117">

    <Window.Resources>
        <!-- Color Palette -->
        <Color x:Key="BgPrimary">#0d1117</Color>
        <Color x:Key="BgSecondary">#161b22</Color>
        <Color x:Key="BgTertiary">#21262d</Color>
        <Color x:Key="BgStatus">#0f1318</Color>
        <Color x:Key="BorderColor">#30363d</Color>
        <Color x:Key="AccentBlue">#58a6ff</Color>
        <Color x:Key="AccentGreen">#3fb950</Color>
        <Color x:Key="AccentOrange">#d29922</Color>
        <Color x:Key="AccentRed">#f85149</Color>
        <Color x:Key="AccentPurple">#a371f7</Color>
        <Color x:Key="TextPrimary">#f0f6fc</Color>
        <Color x:Key="TextSecondary">#8b949e</Color>
        <Color x:Key="TextMuted">#6e7681</Color>
        <Color x:Key="ButtonHover">#30363d</Color>
        <Color x:Key="ButtonPressed">#282e36</Color>
        <Color x:Key="SuccessButton">#238636</Color>
        <Color x:Key="SuccessButtonHover">#2ea043</Color>
        <Color x:Key="DangerButtonBg">#21262d</Color>
        <Color x:Key="DangerButtonHover">#26f85149</Color>
        <Color x:Key="DangerButtonPressed">#40f85149</Color>
        <Color x:Key="ListItemHover">#1f2428</Color>
        <Color x:Key="ListItemSelected">#261f6feb</Color>

        <SolidColorBrush x:Key="BgPrimaryBrush" Color="{StaticResource BgPrimary}"/>
        <SolidColorBrush x:Key="BgSecondaryBrush" Color="{StaticResource BgSecondary}"/>
        <SolidColorBrush x:Key="BgTertiaryBrush" Color="{StaticResource BgTertiary}"/>
        <SolidColorBrush x:Key="BgStatusBrush" Color="{StaticResource BgStatus}"/>
        <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}"/>
        <SolidColorBrush x:Key="AccentBlueBrush" Color="{StaticResource AccentBlue}"/>
        <SolidColorBrush x:Key="AccentGreenBrush" Color="{StaticResource AccentGreen}"/>
        <SolidColorBrush x:Key="AccentOrangeBrush" Color="{StaticResource AccentOrange}"/>
        <SolidColorBrush x:Key="AccentRedBrush" Color="{StaticResource AccentRed}"/>
        <SolidColorBrush x:Key="AccentPurpleBrush" Color="{StaticResource AccentPurple}"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimary}"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondary}"/>
        <SolidColorBrush x:Key="TextMutedBrush" Color="{StaticResource TextMuted}"/>
        <SolidColorBrush x:Key="ButtonHoverBrush" Color="{StaticResource ButtonHover}"/>
        <SolidColorBrush x:Key="ButtonPressedBrush" Color="{StaticResource ButtonPressed}"/>
        <SolidColorBrush x:Key="SuccessButtonBrush" Color="{StaticResource SuccessButton}"/>
        <SolidColorBrush x:Key="SuccessButtonHoverBrush" Color="{StaticResource SuccessButtonHover}"/>
        <SolidColorBrush x:Key="DangerButtonBgBrush" Color="{StaticResource DangerButtonBg}"/>
        <SolidColorBrush x:Key="DangerButtonHoverBrush" Color="{StaticResource DangerButtonHover}"/>
        <SolidColorBrush x:Key="DangerButtonPressedBrush" Color="{StaticResource DangerButtonPressed}"/>
        <SolidColorBrush x:Key="ListItemHoverBrush" Color="{StaticResource ListItemHover}"/>
        <SolidColorBrush x:Key="ListItemSelectedBrush" Color="{StaticResource ListItemSelected}"/>

        <!-- Button Style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BgTertiaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource ButtonHoverBrush}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource ButtonPressedBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary Button Style -->
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="{StaticResource SuccessButtonBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource SuccessButtonHoverBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource SuccessButtonHoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource SuccessButtonBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger Button Style -->
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="{StaticResource DangerButtonBgBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource AccentRedBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AccentRedBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource DangerButtonHoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource DangerButtonPressedBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource BgPrimaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- PasswordBox Style -->
        <Style x:Key="ModernPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="{StaticResource BgPrimaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="PasswordBox">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ComboBox Style -->
        <Style x:Key="ModernComboBox" TargetType="ComboBox">
            <Setter Property="Background" Value="{StaticResource BgPrimaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <!-- ListBox Style -->
        <Style x:Key="ModernListBox" TargetType="ListBox">
            <Setter Property="Background" Value="{StaticResource BgPrimaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>

        <!-- ListBoxItem Style -->
        <Style TargetType="ListBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}" BorderThickness="0,0,0,1"
                                BorderBrush="{StaticResource BorderBrush}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource ListItemHoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource ListItemSelectedBrush}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2,0,0,1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- CheckBox Style -->
        <Style x:Key="ModernCheckBox" TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal">
                            <Border x:Name="checkBorder" Width="18" Height="18" CornerRadius="4"
                                    BorderBrush="{StaticResource BorderBrush}" BorderThickness="1"
                                    Background="{StaticResource BgPrimaryBrush}" Margin="0,0,8,0">
                                <TextBlock x:Name="checkMark" Text="*" FontFamily="Segoe MDL2 Assets"
                                           FontSize="12" Foreground="{StaticResource TextPrimaryBrush}"
                                           HorizontalAlignment="Center" VerticalAlignment="Center"
                                           Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="checkBorder" Property="Background" Value="{StaticResource AccentBlueBrush}"/>
                                <Setter TargetName="checkBorder" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="checkBorder" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- RadioButton Style -->
        <Style x:Key="ModernRadioButton" TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <StackPanel Orientation="Horizontal">
                            <Border x:Name="radioBorder" Width="18" Height="18" CornerRadius="9"
                                    BorderBrush="{StaticResource BorderBrush}" BorderThickness="1"
                                    Background="{StaticResource BgPrimaryBrush}" Margin="0,0,8,0">
                                <Ellipse x:Name="radioMark" Width="8" Height="8"
                                         Fill="{StaticResource TextPrimaryBrush}"
                                         HorizontalAlignment="Center" VerticalAlignment="Center"
                                         Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="radioMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="radioBorder" Property="Background" Value="{StaticResource AccentBlueBrush}"/>
                                <Setter TargetName="radioBorder" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="radioBorder" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Tab Control Style -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="border" Background="Transparent" Padding="{TemplateBinding Padding}"
                                BorderThickness="0,0,0,2" BorderBrush="Transparent" Margin="0,0,4,0">
                            <ContentPresenter ContentSource="Header"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentOrangeBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar Style -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="10"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="{StaticResource BgSecondaryBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="24,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="N" FontSize="28" FontWeight="Bold" Foreground="{StaticResource AccentOrangeBrush}" Margin="0,0,2,0"/>
                    <TextBlock Text="etForge" FontSize="28" FontWeight="Light" Foreground="{StaticResource TextPrimaryBrush}"/>
                    <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="4" Padding="8,4" Margin="16,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="v1.52.0" FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                    </Border>
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,12,0">
                        <TextBlock Text="Theme" FontSize="11" Foreground="{StaticResource TextMutedBrush}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <ComboBox x:Name="cmbUiTheme" Width="160" Style="{StaticResource ModernComboBox}"/>
                    </StackPanel>
                    <CheckBox x:Name="chkCompactMode" Content="Compact" Style="{StaticResource ModernCheckBox}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                    <Button x:Name="btnRefresh" Content="Refresh Adapters" Style="{StaticResource ModernButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnExport" Content="Export All" Style="{StaticResource ModernButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnImport" Content="Import" Style="{StaticResource ModernButton}"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Connection Status Bar -->
        <Border Grid.Row="1" Background="{StaticResource BgStatusBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="24,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Connection Status -->
                <StackPanel Grid.Column="0" Orientation="Horizontal" Margin="0,0,24,0" VerticalAlignment="Center">
                    <Border x:Name="connStatusDot" Width="10" Height="10" CornerRadius="5" Background="{StaticResource AccentRedBrush}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <StackPanel>
                        <TextBlock Text="STATUS" FontSize="9" Foreground="{StaticResource TextMutedBrush}"/>
                        <TextBlock x:Name="txtConnStatus" Text="Checking..." FontSize="12" Foreground="{StaticResource TextPrimaryBrush}" FontWeight="Medium"/>
                    </StackPanel>
                </StackPanel>

                <!-- Local IP -->
                <StackPanel Grid.Column="1" Margin="0,0,24,0" VerticalAlignment="Center">
                    <TextBlock Text="LOCAL IP" FontSize="9" Foreground="{StaticResource TextMutedBrush}"/>
                    <TextBlock x:Name="txtConnLocalIP" Text="--" FontSize="12" Foreground="{StaticResource AccentBlueBrush}" FontFamily="Consolas"/>
                </StackPanel>

                <!-- Public IP -->
                <StackPanel Grid.Column="2" Margin="0,0,24,0" VerticalAlignment="Center">
                    <TextBlock Text="PUBLIC IP" FontSize="9" Foreground="{StaticResource TextMutedBrush}"/>
                    <TextBlock x:Name="txtConnPublicIP" Text="--" FontSize="12" Foreground="{StaticResource AccentBlueBrush}" FontFamily="Consolas"/>
                </StackPanel>

                <!-- Gateway -->
                <StackPanel Grid.Column="3" Margin="0,0,24,0" VerticalAlignment="Center">
                    <TextBlock Text="GATEWAY" FontSize="9" Foreground="{StaticResource TextMutedBrush}"/>
                    <TextBlock x:Name="txtConnGateway" Text="--" FontSize="12" Foreground="{StaticResource TextPrimaryBrush}" FontFamily="Consolas"/>
                </StackPanel>

                <!-- Connection Type -->
                <StackPanel Grid.Column="4" Margin="0,0,24,0" VerticalAlignment="Center">
                    <TextBlock Text="TYPE" FontSize="9" Foreground="{StaticResource TextMutedBrush}"/>
                    <TextBlock x:Name="txtConnType" Text="--" FontSize="12" Foreground="{StaticResource AccentOrangeBrush}" FontWeight="Medium"/>
                </StackPanel>

                <!-- WiFi Info (only visible when WiFi) -->
                <StackPanel x:Name="pnlWifiInfo" Grid.Column="5" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
                    <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="10,4" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="SSID: " FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                            <TextBlock x:Name="txtWifiSSID" Text="--" FontSize="11" Foreground="{StaticResource TextPrimaryBrush}" FontWeight="Medium"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="10,4" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Signal: " FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                            <TextBlock x:Name="txtWifiSignal" Text="--" FontSize="11" Foreground="{StaticResource AccentGreenBrush}" FontWeight="Medium"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="10,4" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Ch: " FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                            <TextBlock x:Name="txtWifiChannel" Text="--" FontSize="11" Foreground="{StaticResource TextPrimaryBrush}"/>
                            <TextBlock Text=" / " FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                            <TextBlock x:Name="txtWifiBand" Text="--" FontSize="11" Foreground="{StaticResource TextPrimaryBrush}"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="10,4" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Auth: " FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                            <TextBlock x:Name="txtWifiAuth" Text="--" FontSize="11" Foreground="{StaticResource TextPrimaryBrush}"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="10,4">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Speed: " FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                            <TextBlock x:Name="txtWifiSpeed" Text="--" FontSize="11" Foreground="{StaticResource TextPrimaryBrush}"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Speed Test Button -->
                <Button x:Name="btnSpeedTest" Grid.Column="6" Content="Speed Test" Style="{StaticResource ModernButton}" Padding="12,6" VerticalAlignment="Center"/>
            </Grid>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="320"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Left Panel - Adapter List -->
            <Border Grid.Column="0" Background="{StaticResource BgSecondaryBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,1,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="16,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="NETWORK ADAPTERS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" VerticalAlignment="Center"/>
                            <CheckBox x:Name="chkAdvancedAdapters" Grid.Column="1" Content="Advanced" Style="{StaticResource ModernCheckBox}" FontSize="11" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>

                    <ListBox x:Name="lstAdapters" Grid.Row="1" Style="{StaticResource ModernListBox}" BorderThickness="0" Background="Transparent"/>

                    <Border Grid.Row="2" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Padding="12">
                        <StackPanel>
                            <Button x:Name="btnEnableAdapter" Content="Enable Adapter" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8"/>
                            <Button x:Name="btnDisableAdapter" Content="Disable Adapter" Style="{StaticResource DangerButton}"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </Border>

            <!-- Right Panel - Configuration -->
            <Grid Grid.Column="1">
                <TabControl x:Name="tabMain" Margin="0">
                    <TabControl.Background>
                        <SolidColorBrush Color="{StaticResource BgPrimary}"/>
                    </TabControl.Background>

                    <!-- IP Configuration Tab -->
                    <TabItem Header="IP Configuration">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <StackPanel Margin="24">
                                <!-- Current Status -->
                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,16">
                                            <Ellipse x:Name="statusIndicator" Width="10" Height="10" Fill="{StaticResource AccentGreenBrush}" Margin="0,0,10,0" VerticalAlignment="Center"/>
                                            <TextBlock x:Name="txtAdapterName" Text="Select an adapter" FontSize="16" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <Grid Grid.Row="1">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>

                                            <StackPanel Grid.Column="0">
                                                <TextBlock Text="Current IP" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="txtCurrentIP" Text="--" FontSize="14" Foreground="{StaticResource TextPrimaryBrush}"/>
                                            </StackPanel>

                                            <StackPanel Grid.Column="1">
                                                <TextBlock Text="MAC Address" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="txtMAC" Text="--" FontSize="14" Foreground="{StaticResource TextPrimaryBrush}"/>
                                            </StackPanel>

                                            <StackPanel Grid.Column="2">
                                                <TextBlock Text="Status" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="txtStatus" Text="--" FontSize="14" Foreground="{StaticResource TextPrimaryBrush}"/>
                                            </StackPanel>
                                        </Grid>
                                    </Grid>
                                </Border>

                                <!-- MAC Address Override -->
                                <TextBlock Text="MAC ADDRESS OVERRIDE" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,12,16">
                                            <TextBlock Text="Current MAC" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtMacOverrideCurrent" Text="--" FontSize="13" Foreground="{StaticResource AccentBlueBrush}" FontFamily="Consolas"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,12,16">
                                            <TextBlock Text="Override Status" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtMacOverrideStatus" Text="No override" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,12,0">
                                            <TextBlock Text="New MAC (12 hex characters)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtMacOverride" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="0" Grid.RowSpan="2" Grid.Column="2" Width="150">
                                            <Button x:Name="btnGenerateMac" Content="Generate" Style="{StaticResource ModernButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnApplyMac" Content="Apply MAC" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnRevertMac" Content="Revert MAC" Style="{StaticResource DangerButton}" Padding="14,8"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- Interface Metric / Priority -->
                                <TextBlock Text="ADAPTER PRIORITY / INTERFACE METRIC" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,12,16">
                                            <TextBlock Text="IPv4 Metric" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtMetricIPv4Current" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,12,16">
                                            <TextBlock Text="IPv6 Metric" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtMetricIPv6Current" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,12,0">
                                            <TextBlock Text="Manual Metric (lower wins)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtInterfaceMetric" Style="{StaticResource ModernTextBox}" Text="25"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom" Margin="0,0,12,0">
                                            <CheckBox x:Name="chkMetricIPv4" Content="IPv4" Style="{StaticResource ModernCheckBox}" IsChecked="True" Margin="0,0,16,0"/>
                                            <CheckBox x:Name="chkMetricIPv6" Content="IPv6" Style="{StaticResource ModernCheckBox}" IsChecked="True"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="0" Grid.RowSpan="2" Grid.Column="2" Width="150">
                                            <Button x:Name="btnApplyMetric" Content="Apply Metric" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnAutoMetric" Content="Auto Metric" Style="{StaticResource ModernButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnIPv4FirstMetric" Content="IPv4 First" Style="{StaticResource ModernButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnIPv6FirstMetric" Content="IPv6 First" Style="{StaticResource ModernButton}" Padding="14,8"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- IP Mode Selection -->
                                <TextBlock Text="IP CONFIGURATION MODE" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <StackPanel>
                                        <RadioButton x:Name="rbDHCP" Content="Obtain IP address automatically (DHCP)" Style="{StaticResource ModernRadioButton}" GroupName="IPMode" IsChecked="True" Margin="0,0,0,12"/>
                                        <RadioButton x:Name="rbStatic" Content="Use the following IP address (Static)" Style="{StaticResource ModernRadioButton}" GroupName="IPMode"/>
                                    </StackPanel>
                                </Border>

                                <!-- Static IP Configuration -->
                                <Border x:Name="pnlStaticIP" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20" IsEnabled="False" Opacity="0.6">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,10,16">
                                            <TextBlock Text="IP Address" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtIPAddress" Style="{StaticResource ModernTextBox}" Text="192.168.1.100"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="10,0,0,16">
                                            <TextBlock Text="Subnet Mask" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtSubnet" Style="{StaticResource ModernTextBox}" Text="255.255.255.0"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,10,0">
                                            <TextBlock Text="Default Gateway" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtGateway" Style="{StaticResource ModernTextBox}" Text="192.168.1.1"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="1" Margin="10,0,0,0">
                                            <TextBlock Text="Prefix Length (CIDR)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtPrefix" Style="{StaticResource ModernTextBox}" Text="24"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <TextBlock Text="IPv6 ADDRESS CONFIGURATION" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <StackPanel>
                                        <CheckBox x:Name="chkConfigureIPv6Address" Content="Configure static IPv6 address" Style="{StaticResource ModernCheckBox}" Margin="0,0,0,16"/>
                                        <Grid x:Name="pnlIPv6StaticConfig" IsEnabled="False" Opacity="0.6">
                                            <Grid.RowDefinitions>
                                                <RowDefinition Height="Auto"/>
                                                <RowDefinition Height="Auto"/>
                                            </Grid.RowDefinitions>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>

                                            <StackPanel Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,16">
                                                <TextBlock Text="IPv6 Address" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtIPv6Address" Style="{StaticResource ModernTextBox}" Text="2001:db8::100"/>
                                            </StackPanel>

                                            <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,10,0">
                                                <TextBlock Text="IPv6 Prefix Length" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtIPv6Prefix" Style="{StaticResource ModernTextBox}" Text="64"/>
                                            </StackPanel>

                                            <StackPanel Grid.Row="1" Grid.Column="1" Margin="10,0,0,0">
                                                <TextBlock Text="IPv6 Gateway (optional)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtIPv6Gateway" Style="{StaticResource ModernTextBox}" Text=""/>
                                            </StackPanel>
                                        </Grid>
                                    </StackPanel>
                                </Border>

                                <!-- Apply Button -->
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button x:Name="btnApplyIP" Content="Apply IP Configuration" Style="{StaticResource PrimaryButton}" Padding="24,12"/>
                                </StackPanel>
                            </StackPanel>
                        </ScrollViewer>
                    </TabItem>

                    <!-- DNS Configuration Tab -->
                    <TabItem Header="DNS Configuration">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <StackPanel Margin="24">
                                <!-- DNS Preset Selection -->
                                <TextBlock Text="DNS SERVER PRESETS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="300"/>
                                        </Grid.RowDefinitions>

                                        <!-- Filter Bar -->
                                        <Border Grid.Row="0" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="16,12">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <TextBox x:Name="txtDnsSearch" Style="{StaticResource ModernTextBox}" Grid.Column="0" Margin="0,0,12,0">
                                                    <TextBox.Tag>Search DNS presets...</TextBox.Tag>
                                                </TextBox>
                                                <ComboBox x:Name="cmbDnsCategory" Grid.Column="1" Width="150" Style="{StaticResource ModernComboBox}">
                                                    <ComboBoxItem Content="All Categories" IsSelected="True"/>
                                                    <ComboBoxItem Content="Public"/>
                                                    <ComboBoxItem Content="Security"/>
                                                    <ComboBoxItem Content="Privacy"/>
                                                    <ComboBoxItem Content="Family"/>
                                                    <ComboBoxItem Content="Ad-Blocking"/>
                                                </ComboBox>
                                            </Grid>
                                        </Border>

                                        <ListBox x:Name="lstDnsPresets" Grid.Row="1" Style="{StaticResource ModernListBox}" BorderThickness="0" Background="Transparent"/>
                                    </Grid>
                                </Border>

                                <!-- DNS Mode Selection -->
                                <TextBlock Text="DNS CONFIGURATION MODE" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <StackPanel>
                                        <RadioButton x:Name="rbDnsDHCP" Content="Obtain DNS server address automatically" Style="{StaticResource ModernRadioButton}" GroupName="DNSMode" IsChecked="True" Margin="0,0,0,12"/>
                                        <RadioButton x:Name="rbDnsPreset" Content="Use selected DNS preset" Style="{StaticResource ModernRadioButton}" GroupName="DNSMode" Margin="0,0,0,12"/>
                                        <RadioButton x:Name="rbDnsCustom" Content="Use custom DNS servers" Style="{StaticResource ModernRadioButton}" GroupName="DNSMode"/>
                                    </StackPanel>
                                </Border>

                                <!-- Custom DNS Configuration -->
                                <Border x:Name="pnlCustomDns" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20" IsEnabled="False" Opacity="0.6">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <TextBlock Grid.Row="0" Grid.ColumnSpan="2" Text="IPv4 DNS Servers" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,10,16">
                                            <TextBlock Text="Primary DNS" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtDnsPrimary" Style="{StaticResource ModernTextBox}" Text="8.8.8.8"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="1" Margin="10,0,0,16">
                                            <TextBlock Text="Secondary DNS" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtDnsSecondary" Style="{StaticResource ModernTextBox}" Text="8.8.4.4"/>
                                        </StackPanel>

                                        <CheckBox x:Name="chkIPv6Dns" Grid.Row="2" Grid.ColumnSpan="2" Content="Also configure IPv6 DNS (if available)" Style="{StaticResource ModernCheckBox}"/>
                                    </Grid>
                                </Border>

                                <!-- Selected DNS Info -->
                                <Border x:Name="pnlSelectedDns" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource AccentBlueBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20" Visibility="Collapsed">
                                    <StackPanel>
                                        <TextBlock x:Name="txtSelectedDnsName" Text="Selected DNS" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                        <TextBlock x:Name="txtSelectedDnsDesc" Text="Description" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <StackPanel Grid.Column="0">
                                                <TextBlock Text="Primary" FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                                                <TextBlock x:Name="txtSelectedDnsPrimary" Text="--" FontSize="13" Foreground="{StaticResource AccentBlueBrush}"/>
                                            </StackPanel>
                                            <StackPanel Grid.Column="1">
                                                <TextBlock Text="Secondary" FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                                                <TextBlock x:Name="txtSelectedDnsSecondary" Text="--" FontSize="13" Foreground="{StaticResource AccentBlueBrush}"/>
                                            </StackPanel>
                                        </Grid>
                                    </StackPanel>
                                </Border>

                                <!-- Encrypted DNS -->
                                <TextBlock Text="ENCRYPTED DNS (DOH / DOT)" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,12,16">
                                            <TextBlock Text="Servers to register" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtDohServers" Text="Select a DNS preset or enter custom DNS servers." FontSize="12" Foreground="{StaticResource TextPrimaryBrush}" TextWrapping="Wrap"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,16">
                                            <TextBlock Text="DoH Template" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtDohTemplate" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,16">
                                            <TextBlock Text="DoT Host" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtDotHost" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="3" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                            <CheckBox x:Name="chkDohAutoUpgrade" Content="Auto-upgrade DNS queries" Style="{StaticResource ModernCheckBox}" IsChecked="True" Margin="0,0,20,0"/>
                                            <CheckBox x:Name="chkDohUdpFallback" Content="Allow UDP fallback" Style="{StaticResource ModernCheckBox}" IsChecked="True"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="0" Grid.RowSpan="4" Grid.Column="1" Width="190">
                                            <Button x:Name="btnRegisterDoh" Content="Register DoH" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <TextBlock x:Name="txtDohStatus" Text="Uses netsh dns add encryption." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                            <Button x:Name="btnRegisterDot" Content="Register DoT" Style="{StaticResource ModernButton}" Margin="0,14,0,8" Padding="14,8"/>
                                            <TextBlock x:Name="txtDotStatus" Text="Uses netsh dns add encryption dothost." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                            <Button x:Name="btnTestEncryptedDns" Content="Test Health" Style="{StaticResource ModernButton}" Margin="0,14,0,8" Padding="14,8"/>
                                            <TextBlock x:Name="txtEncryptedDnsHealthStatus" Text="Shows adapter DNS, encrypted probes, fallback, proxy, and latency." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- Account-Specific Endpoints -->
                                <TextBlock Text="ACCOUNT-SPECIFIC ENDPOINTS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="260"/>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Column="0" Margin="0,0,14,0">
                                            <TextBlock Text="NextDNS Config ID" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtNextDnsConfigId" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>

                                        <Button x:Name="btnApplyNextDnsEndpoints" Grid.Column="1" Content="Apply NextDNS" Style="{StaticResource ModernButton}" Margin="0,20,14,0" Padding="14,8" VerticalAlignment="Top"/>

                                        <TextBlock x:Name="txtNextDnsEndpointStatus" Grid.Column="2" Text="Fills DoH, DoT, and DoQ fields from a NextDNS account configuration ID." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>

                                <!-- DoQ Local Proxy -->
                                <TextBlock Text="DOQ LOCAL PROXY" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="180"/>
                                        </Grid.ColumnDefinitions>

                                        <Grid Grid.Row="0" Grid.Column="0" Margin="0,0,14,14">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                                                <TextBlock Text="dnsproxy.exe Path" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtDoqProxyPath" Style="{StaticResource ModernTextBox}" Text="dnsproxy.exe"/>
                                            </StackPanel>
                                            <StackPanel Grid.Column="1" Margin="10,0,0,0">
                                                <TextBlock Text="DoQ Upstream" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtDoqUpstream" Style="{StaticResource ModernTextBox}" Text="quic://dns.adguard.com"/>
                                            </StackPanel>
                                        </Grid>

                                        <Grid Grid.Row="1" Grid.Column="0" Margin="0,0,14,14">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="120"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                                                <TextBlock Text="Listen Address" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtDoqListenAddress" Style="{StaticResource ModernTextBox}" Text="127.0.0.1"/>
                                            </StackPanel>
                                            <StackPanel Grid.Column="1" Margin="10,0,10,0">
                                                <TextBlock Text="Port" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtDoqListenPort" Style="{StaticResource ModernTextBox}" Text="53"/>
                                            </StackPanel>
                                            <StackPanel Grid.Column="2" Margin="10,0,0,0">
                                                <TextBlock Text="Bootstrap DNS" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                                <TextBox x:Name="txtDoqBootstrap" Style="{StaticResource ModernTextBox}" Text="1.1.1.1:53"/>
                                            </StackPanel>
                                        </Grid>

                                        <TextBlock x:Name="txtDoqProxyStatus" Grid.Row="2" Grid.Column="0" Text="Requires AdGuard dnsproxy or a compatible DNS proxy binary." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap" Margin="0,2,14,0"/>

                                        <StackPanel Grid.Row="0" Grid.RowSpan="3" Grid.Column="1">
                                            <Button x:Name="btnValidateDoqProxy" Content="Validate Proxy" Style="{StaticResource ModernButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnStartDoqProxy" Content="Start Proxy" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnStopDoqProxy" Content="Stop Proxy" Style="{StaticResource DangerButton}" Margin="0,0,0,8" Padding="14,8"/>
                                            <Button x:Name="btnApplyDoqLocalDns" Content="Apply Local DNS" Style="{StaticResource ModernButton}" Padding="14,8"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- Apply Button -->
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button x:Name="btnApplyDns" Content="Apply DNS Configuration" Style="{StaticResource PrimaryButton}" Padding="24,12"/>
                                </StackPanel>
                            </StackPanel>
                        </ScrollViewer>
                    </TabItem>

                    <!-- WiFi Tab -->
                    <TabItem Header="WiFi">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <StackPanel Margin="24">
                                <TextBlock Text="WIFI NETWORKS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="360"/>
                                        </Grid.RowDefinitions>

                                        <Border Grid.Row="0" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="16,12">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>

                                                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                                    <TextBlock x:Name="txtWifiScanSummary" Text="Click Scan Networks to find nearby wireless networks." FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>
                                                    <TextBlock Text="Saved Windows WLAN profiles can connect immediately. Unsaved secured networks require a password." FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                                                </StackPanel>

                                                <Button x:Name="btnWifiRefresh" Grid.Column="1" Content="Scan Networks" Style="{StaticResource ModernButton}" Margin="12,0,0,0" Padding="16,8"/>
                                                <Button x:Name="btnWifiConnect" Grid.Column="2" Content="Connect" Style="{StaticResource PrimaryButton}" Margin="8,0,0,0" Padding="16,8" IsEnabled="False"/>
                                                <Button x:Name="btnWifiDisconnect" Grid.Column="3" Content="Disconnect" Style="{StaticResource DangerButton}" Margin="8,0,0,0" Padding="16,8"/>
                                            </Grid>
                                        </Border>

                                        <ListBox x:Name="lstWifiNetworks" Grid.Row="1" Style="{StaticResource ModernListBox}" BorderThickness="0" Background="Transparent"/>
                                    </Grid>
                                </Border>

                                <TextBlock Text="WIFI SPECTRUM" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="220">
                                        <TextBlock x:Name="txtWifiSpectrumOutput" Text="Scan WiFi networks to build channel utilization." FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap"/>
                                    </ScrollViewer>
                                </Border>

                                <TextBlock Text="SELECTED NETWORK" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border x:Name="pnlWifiDetails" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20" Visibility="Collapsed">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,16,16">
                                            <TextBlock Text="SSID" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtWifiDetailSsid" Text="--" FontSize="14" Foreground="{StaticResource TextPrimaryBrush}" FontWeight="SemiBold"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="PROFILE" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtWifiDetailProfile" Text="--" FontSize="14" Foreground="{StaticResource AccentBlueBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,16,16">
                                            <TextBlock Text="SECURITY" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtWifiDetailSecurity" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="SIGNAL" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtWifiDetailSignal" Text="--" FontSize="13" Foreground="{StaticResource AccentGreenBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="2" Grid.Column="0" Margin="0,0,16,16">
                                            <TextBlock Text="RADIO / BAND" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtWifiDetailRadio" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="2" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="CHANNELS / BSSIDS" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtWifiDetailBssids" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="3" Grid.ColumnSpan="2">
                                            <TextBlock Text="Password for unsaved secured networks" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <PasswordBox x:Name="txtWifiPassword" Style="{StaticResource ModernPasswordBox}"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </TabItem>

                    <!-- Profiles Tab -->
                    <TabItem Header="Profiles">
                        <Grid Margin="24">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="300"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Profile List -->
                            <Border Grid.Column="0" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Margin="0,0,20,0">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <Border Grid.Row="0" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="16,12">
                                        <TextBlock Text="SAVED PROFILES" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}"/>
                                    </Border>

                                    <ListBox x:Name="lstProfiles" Grid.Row="1" Style="{StaticResource ModernListBox}" BorderThickness="0" Background="Transparent"/>

                                    <Border Grid.Row="2" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Padding="12">
                                        <StackPanel>
                                            <Button x:Name="btnNewProfile" Content="Create New Profile" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8"/>
                                            <Button x:Name="btnExportProfileQr" Content="Export QR" Style="{StaticResource ModernButton}" Margin="0,0,0,8"/>
                                            <Button x:Name="btnImportProfileQr" Content="Import QR" Style="{StaticResource ModernButton}" Margin="0,0,0,8"/>
                                            <Button x:Name="btnDeleteProfile" Content="Delete Profile" Style="{StaticResource DangerButton}"/>
                                        </StackPanel>
                                    </Border>
                                </Grid>
                            </Border>

                            <!-- Profile Details -->
                            <Border Grid.Column="1" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1">
                                <ScrollViewer VerticalScrollBarVisibility="Auto">
                                    <StackPanel Margin="20">
                                        <TextBlock Text="PROFILE DETAILS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,16"/>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                                            <StackPanel>
                                                <TextBlock Text="Profile Storage" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,10"/>
                                                <TextBlock x:Name="txtProfileStorePath" Text="Profile store path loading..." FontFamily="Consolas" FontSize="11" Foreground="{StaticResource AccentBlueBrush}" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                                <TextBlock x:Name="txtProfileStoreStatus" Text="Profile storage health loading..." FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                                                <WrapPanel>
                                                    <Button x:Name="btnChooseProfileStore" Content="Choose Folder" Style="{StaticResource ModernButton}" Margin="0,0,8,8" Padding="14,8"/>
                                                    <Button x:Name="btnUseOneDriveProfileStore" Content="Use OneDrive" Style="{StaticResource ModernButton}" Margin="0,0,8,8" Padding="14,8"/>
                                                    <Button x:Name="btnRevertProfileStore" Content="Use Local" Style="{StaticResource ModernButton}" Margin="0,0,8,8" Padding="14,8"/>
                                                    <Button x:Name="btnProfileStoreHealth" Content="Check Health" Style="{StaticResource ModernButton}" Margin="0,0,0,8" Padding="14,8"/>
                                                </WrapPanel>
                                            </StackPanel>
                                        </Border>

                                        <StackPanel Margin="0,0,0,16">
                                            <TextBlock Text="Profile Name" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtProfileName" Style="{StaticResource ModernTextBox}"/>
                                        </StackPanel>

                                        <StackPanel Margin="0,0,0,16">
                                            <TextBlock Text="Description" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtProfileDesc" Style="{StaticResource ModernTextBox}" Height="60" TextWrapping="Wrap" AcceptsReturn="True"/>
                                        </StackPanel>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                                            <StackPanel>
                                                <TextBlock Text="Auto-Apply Rules" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                                <CheckBox x:Name="chkProfileAutoApply" Content="Auto-apply when current network matches" Style="{StaticResource ModernCheckBox}" Margin="0,0,0,10"/>
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                                        <TextBlock Text="Match SSID" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileMatchSsid" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Column="1" Margin="8,0,8,0">
                                                        <TextBlock Text="Gateway MAC" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileGatewayMac" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <Button x:Name="btnCaptureProfileMatch" Grid.Column="2" Content="Capture Current" Style="{StaticResource ModernButton}" Padding="14,8" VerticalAlignment="Bottom"/>
                                                </Grid>
                                            </StackPanel>
                                        </Border>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                                            <StackPanel>
                                                <TextBlock Text="Scheduled Apply" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                                <CheckBox x:Name="chkProfileSchedule" Content="Apply profile on schedule" Style="{StaticResource ModernCheckBox}" Margin="0,0,0,10"/>
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="160"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                                        <TextBlock Text="Time (HH:mm)" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileScheduleTime" Style="{StaticResource ModernTextBox}" Text="08:00"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Column="1" Margin="8,0,0,0">
                                                        <TextBlock Text="Days" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileScheduleDays" Style="{StaticResource ModernTextBox}" Text="Every day"/>
                                                    </StackPanel>
                                                </Grid>
                                            </StackPanel>
                                        </Border>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                                            <StackPanel>
                                                <TextBlock Text="IP Configuration" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                                <CheckBox x:Name="chkProfileDHCP" Content="Use DHCP" Style="{StaticResource ModernCheckBox}" Margin="0,0,0,8"/>
                                                <Grid Margin="0,8,0,0">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <Grid.RowDefinitions>
                                                        <RowDefinition Height="Auto"/>
                                                        <RowDefinition Height="Auto"/>
                                                    </Grid.RowDefinitions>

                                                    <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,8,8">
                                                        <TextBlock Text="IP Address" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileIP" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Row="0" Grid.Column="1" Margin="8,0,0,8">
                                                        <TextBlock Text="Subnet Mask" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileSubnet" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,8,0">
                                                        <TextBlock Text="Gateway" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileGateway" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Row="1" Grid.Column="1" Margin="8,0,0,0">
                                                        <TextBlock Text="Prefix Length" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfilePrefix" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                </Grid>
                                            </StackPanel>
                                        </Border>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                                            <StackPanel>
                                                <TextBlock Text="DNS Configuration" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                                <CheckBox x:Name="chkProfileDnsDHCP" Content="Use DHCP for DNS" Style="{StaticResource ModernCheckBox}" Margin="0,0,0,8"/>
                                                <Grid Margin="0,8,0,0">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                                        <TextBlock Text="Primary DNS" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileDns1" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Column="1" Margin="8,0,0,0">
                                                        <TextBlock Text="Secondary DNS" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileDns2" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                </Grid>
                                            </StackPanel>
                                        </Border>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                                            <StackPanel>
                                                <TextBlock Text="Environment Actions" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>

                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="240"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <CheckBox x:Name="chkProfileNetworkCategory" Grid.Column="0" Content="Set Windows network category" Style="{StaticResource ModernCheckBox}" VerticalAlignment="Center"/>
                                                    <ComboBox x:Name="cmbProfileNetworkCategory" Grid.Column="1" Style="{StaticResource ModernComboBox}">
                                                        <ComboBoxItem Content="Private" IsSelected="True"/>
                                                        <ComboBoxItem Content="Public"/>
                                                    </ComboBox>
                                                </Grid>

                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="240"/>
                                                        <ColumnDefinition Width="160"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <CheckBox x:Name="chkProfileProxy" Grid.Column="0" Content="Set system proxy" Style="{StaticResource ModernCheckBox}" VerticalAlignment="Center"/>
                                                    <CheckBox x:Name="chkProfileProxyEnabled" Grid.Column="1" Content="Enable proxy" Style="{StaticResource ModernCheckBox}" VerticalAlignment="Center"/>
                                                    <StackPanel Grid.Column="2" Margin="0,0,8,0">
                                                        <TextBlock Text="Proxy server" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileProxyServer" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                    <StackPanel Grid.Column="3" Margin="8,0,0,0">
                                                        <TextBlock Text="Bypass list" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                        <TextBox x:Name="txtProfileProxyBypass" Style="{StaticResource ModernTextBox}"/>
                                                    </StackPanel>
                                                </Grid>

                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="240"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <CheckBox x:Name="chkProfilePrinter" Grid.Column="0" Content="Set default printer" Style="{StaticResource ModernCheckBox}" VerticalAlignment="Center"/>
                                                    <TextBox x:Name="txtProfilePrinterName" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>

                                                <StackPanel>
                                                    <CheckBox x:Name="chkProfileMappedDrives" Content="Map network drives" Style="{StaticResource ModernCheckBox}" Margin="0,0,0,8"/>
                                                    <TextBlock Text="One drive per line, for example Z: \\server\share" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                                    <TextBox x:Name="txtProfileMappedDrives" Style="{StaticResource ModernTextBox}" Height="72" TextWrapping="Wrap" AcceptsReturn="True"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </Border>

                                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                            <Button x:Name="btnSaveProfile" Content="Save Profile" Style="{StaticResource PrimaryButton}" Margin="0,0,8,0" Padding="20,10"/>
                                            <Button x:Name="btnProfileDiff" Content="Preview Diff" Style="{StaticResource ModernButton}" Margin="0,0,8,0" Padding="20,10"/>
                                            <Button x:Name="btnApplyProfile" Content="Apply to Adapter" Style="{StaticResource ModernButton}" Padding="20,10"/>
                                        </StackPanel>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,16,0,0">
                                            <StackPanel>
                                                <TextBlock Text="Profile Diff" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,10"/>
                                                <TextBlock x:Name="txtProfileDiffOutput" Text="Click Preview Diff to compare this profile against the selected adapter." FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap"/>
                                            </StackPanel>
                                        </Border>

                                        <Border Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,16,0,0">
                                            <StackPanel>
                                                <Grid Margin="0,0,0,10">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Grid.Column="0" Text="Auto-Apply Inspector" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" VerticalAlignment="Center"/>
                                                    <Button x:Name="btnRefreshAutoApply" Grid.Column="1" Content="Refresh" Style="{StaticResource ModernButton}" Padding="12,6"/>
                                                </Grid>
                                                <TextBlock x:Name="txtAutoApplyInspector" Text="Click Refresh to inspect auto-apply match status." FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap"/>
                                            </StackPanel>
                                        </Border>
                                    </StackPanel>
                                </ScrollViewer>
                            </Border>
                        </Grid>
                    </TabItem>

                    <!-- Tools Tab -->
                    <TabItem Header="Network Tools">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <StackPanel Margin="24">
                                <!-- Quick Actions -->
                                <TextBlock Text="QUICK ACTIONS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <WrapPanel>
                                        <Button x:Name="btnFlushDns" Content="Flush DNS Cache" Style="{StaticResource ModernButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnReleaseIP" Content="Release IP" Style="{StaticResource ModernButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnRenewIP" Content="Renew IP" Style="{StaticResource ModernButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnRestoreNetworkState" Content="Restore Last Network State" Style="{StaticResource ModernButton}" Margin="0,0,12,12" IsEnabled="False"/>
                                        <CheckBox x:Name="chkDiagnosticsPrivacyMode" Content="Redact Bundle" Style="{StaticResource ModernCheckBox}" IsChecked="True" Margin="0,0,12,12" VerticalAlignment="Center"/>
                                        <Button x:Name="btnExportDiagnostics" Content="Export Diagnostics" Style="{StaticResource ModernButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnResetWinsock" Content="Reset Winsock" Style="{StaticResource DangerButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnResetTCP" Content="Reset TCP/IP Stack" Style="{StaticResource DangerButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnNetworkReset" Content="Full Network Reset" Style="{StaticResource DangerButton}" Margin="0,0,0,12"/>
                                    </WrapPanel>
                                </Border>

                                <!-- Remote Desktop Profile Launch -->
                                <TextBlock Text="REMOTE DESKTOP PROFILE LAUNCH" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="2*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,10,12">
                                            <TextBlock Text="Host or .rdp file" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtRdpTarget" Style="{StaticResource ModernTextBox}" Text="server.example.com"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="10,0,10,12">
                                            <TextBlock Text="Profile" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtRdpProfileName" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="2" Margin="10,0,0,12">
                                            <TextBlock Text="Adapter optional" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtRdpAdapterName" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Orientation="Horizontal" Margin="0,0,0,12">
                                            <Button x:Name="btnLaunchRdpProfile" Content="Launch RDP with Profile" Style="{StaticResource PrimaryButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnRevertRdpProfile" Content="Revert RDP Profile" Style="{StaticResource ModernButton}" IsEnabled="False"/>
                                        </StackPanel>

                                        <TextBlock x:Name="txtRdpStatus" Grid.Row="2" Grid.ColumnSpan="3" Text="Enter a host and saved profile, or leave Profile blank to use the selected profile." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                    </Grid>
                                </Border>

                                <!-- App Interface Guard -->
                                <TextBlock Text="APP INTERFACE GUARD" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="2*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,10,12">
                                            <TextBlock Text="Program path" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtAppRoutingProgram" Style="{StaticResource ModernTextBox}" Text=""/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="2" Margin="10,20,0,12">
                                            <Button x:Name="btnBrowseAppRoutingProgram" Content="Browse" Style="{StaticResource ModernButton}" Padding="16,8"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,10,12">
                                            <TextBlock Text="Allowed interface" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <ComboBox x:Name="cmbAppRoutingInterface" Style="{StaticResource ModernComboBox}"/>
                                        </StackPanel>
                                        <WrapPanel Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Margin="10,20,0,12">
                                            <Button x:Name="btnApplyAppRouting" Content="Apply Guard" Style="{StaticResource PrimaryButton}" Margin="0,0,12,0" Padding="16,8"/>
                                            <Button x:Name="btnRemoveAppRouting" Content="Remove Guard" Style="{StaticResource DangerButton}" Margin="0,0,12,0" Padding="16,8"/>
                                            <Button x:Name="btnRefreshAppRouting" Content="Refresh Guards" Style="{StaticResource ModernButton}" Padding="16,8"/>
                                        </WrapPanel>

                                        <TextBlock x:Name="txtAppRoutingStatus" Grid.Row="2" Grid.ColumnSpan="3" Text="Blocks the selected app on other current adapters using Windows Firewall interface filters." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                        <ListBox x:Name="lstAppRoutingRules" Grid.Row="3" Grid.ColumnSpan="3" Style="{StaticResource ModernListBox}" Height="120"/>
                                    </Grid>
                                </Border>

                                <!-- Network Diagnostics -->
                                <TextBlock Text="NETWORK DIAGNOSTICS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <WrapPanel Grid.Row="0" Margin="0,0,0,16">
                                            <TextBox x:Name="txtPingTarget" Style="{StaticResource ModernTextBox}" Width="300" Text="8.8.8.8" Margin="0,0,12,0"/>
                                            <Button x:Name="btnPing" Content="Ping" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnTraceroute" Content="Traceroute" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnMtrTrace" Content="Start MTR" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnPortScan" Content="Port Scan" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnReachabilityWizard" Content="Why Can't I Reach X?" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnPacketCapture" Content="Start Capture" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnCableDiagnostics" Content="Cable Diag" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnNslookup" Content="NSLookup" Style="{StaticResource ModernButton}"/>
                                        </WrapPanel>

                                        <Border Grid.Row="1" Background="{StaticResource BgPrimaryBrush}" CornerRadius="6" Padding="16" MaxHeight="250">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <TextBlock x:Name="txtDiagOutput" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Text="Diagnostic output will appear here..."/>
                                            </ScrollViewer>
                                        </Border>
                                    </Grid>
                                </Border>

                                <!-- Static Routes -->
                                <TextBlock Text="STATIC ROUTES" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="120"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,10,12">
                                            <TextBlock Text="Destination Prefix" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtRouteDestination" Style="{StaticResource ModernTextBox}" Text="10.10.0.0/16"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="10,0,10,12">
                                            <TextBlock Text="Next Hop" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtRouteNextHop" Style="{StaticResource ModernTextBox}" Text="192.168.1.1"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="2" Margin="10,0,0,12">
                                            <TextBlock Text="Route Metric" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtRouteMetric" Style="{StaticResource ModernTextBox}" Text="25"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Orientation="Horizontal" Margin="0,0,0,12">
                                            <Button x:Name="btnAddStaticRoute" Content="Add Route" Style="{StaticResource PrimaryButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnRemoveStaticRoute" Content="Remove Selected" Style="{StaticResource DangerButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnRefreshStaticRoutes" Content="Refresh Routes" Style="{StaticResource ModernButton}"/>
                                        </StackPanel>

                                        <ListBox x:Name="lstStaticRoutes" Grid.Row="2" Grid.ColumnSpan="3" Style="{StaticResource ModernListBox}" Height="140" Margin="0,0,0,8"/>
                                        <TextBlock x:Name="txtStaticRouteStatus" Grid.Row="3" Grid.ColumnSpan="3" Text="Select an adapter to view manual static routes." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                    </Grid>
                                </Border>

                                <!-- Hosts File Groups -->
                                <TextBlock Text="HOSTS FILE GROUPS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="180"/>
                                            <ColumnDefinition Width="180"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,10,12">
                                            <TextBlock Text="Group Name" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtHostsGroupName" Style="{StaticResource ModernTextBox}" Text="Work"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="10,0,10,12">
                                            <TextBlock Text="Address" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtHostsAddress" Style="{StaticResource ModernTextBox}" Text="10.10.0.10"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="2" Margin="10,0,0,12">
                                            <TextBlock Text="Hostnames" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,6"/>
                                            <TextBox x:Name="txtHostsNames" Style="{StaticResource ModernTextBox}" Text="intranet.local files.local"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Orientation="Horizontal" Margin="0,0,0,12">
                                            <Button x:Name="btnHostsAddEntry" Content="Add Entry" Style="{StaticResource PrimaryButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnHostsToggleGroup" Content="Toggle Group" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnHostsRemoveGroup" Content="Remove Group" Style="{StaticResource DangerButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnHostsRefresh" Content="Refresh Hosts" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnHostsApply" Content="Apply Hosts" Style="{StaticResource ModernButton}"/>
                                        </StackPanel>

                                        <ListBox x:Name="lstHostsGroups" Grid.Row="2" Grid.ColumnSpan="3" Style="{StaticResource ModernListBox}" Height="150" Margin="0,0,0,8"/>
                                        <TextBlock x:Name="txtHostsStatus" Grid.Row="3" Grid.ColumnSpan="3" Text="NetForge-managed hosts groups are written inside a marked section; unmanaged hosts lines are preserved." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                    </Grid>
                                </Border>

                                <!-- Adapter Information -->
                                <TextBlock Text="ADAPTER DETAILS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,16">
                                            <TextBlock Text="Interface Index" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoIndex" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="Interface Type" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoType" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,0,16">
                                            <TextBlock Text="Link Speed" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoSpeed" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="Media State" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoMedia" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="2" Grid.Column="0" Margin="0,0,0,16">
                                            <TextBlock Text="DHCP Enabled" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoDHCP" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="2" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="DHCP Server / Lease" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoDHCPServer" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}" TextWrapping="Wrap"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="3" Grid.Column="0" Margin="0,0,0,16">
                                            <TextBlock Text="DNS Servers" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoDNS" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}" TextWrapping="Wrap"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="3" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="Default Gateway" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoGateway" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="4" Grid.Column="0" Margin="0,0,0,16">
                                            <TextBlock Text="IPv6 Address" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoIPv6" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}" TextWrapping="Wrap"/>
                                        </StackPanel>
                                        <StackPanel Grid.Row="4" Grid.Column="1" Margin="0,0,0,16">
                                            <TextBlock Text="Driver Description" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoDriver" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}" TextWrapping="Wrap"/>
                                        </StackPanel>

                                        <StackPanel Grid.Row="5" Grid.ColumnSpan="2">
                                            <TextBlock Text="Physical Address (MAC)" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoMAC" Text="--" FontSize="13" Foreground="{StaticResource AccentBlueBrush}" FontFamily="Consolas"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </TabItem>

                    <!-- Diagnostics Tab -->
                    <TabItem Header="Diagnostics">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <StackPanel Margin="24">
                                <!-- Privacy / Endpoint Policy -->
                                <TextBlock Text="PRIVACY / ENDPOINT POLICY" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,14">
                                            <CheckBox x:Name="chkPublicIpLookup" Content="Public IP lookup" Style="{StaticResource ModernCheckBox}" IsChecked="True" Margin="0,0,24,0"/>
                                            <CheckBox x:Name="chkExternalSpeedTest" Content="Allow external speed test downloads" Style="{StaticResource ModernCheckBox}" IsChecked="True"/>
                                        </StackPanel>

                                        <Grid Grid.Row="1" Margin="0,0,0,12">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Grid.Column="0" Text="Speed test endpoint" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                                            <ComboBox x:Name="cmbSpeedTestEndpoint" Grid.Column="1" Style="{StaticResource ModernComboBox}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnSaveEndpointPolicy" Grid.Column="2" Content="Save Policy" Style="{StaticResource PrimaryButton}" Padding="16,8"/>
                                        </Grid>

                                        <TextBlock x:Name="txtEndpointPolicyStatus" Grid.Row="2" Text="Endpoint policy settings load from settings.json." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap" Margin="0,0,0,12"/>

                                        <Grid Grid.Row="3" Margin="0,0,0,8">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <CheckBox x:Name="chkDiscordWebhook" Grid.Column="0" Content="Profile apply webhook" Style="{StaticResource ModernCheckBox}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                                            <TextBox x:Name="txtDiscordWebhookUrl" Grid.Column="1" Style="{StaticResource ModernTextBox}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnSaveDiscordWebhook" Grid.Column="2" Content="Save Webhook" Style="{StaticResource ModernButton}" Padding="16,8"/>
                                        </Grid>

                                        <TextBlock x:Name="txtDiscordWebhookStatus" Grid.Row="4" Text="Discord webhook notifications are disabled." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
                                    </Grid>
                                </Border>

                                <!-- Locale -->
                                <TextBlock Text="LOCALE" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <StackPanel>
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Grid.Column="0" Text="UI language" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                                            <ComboBox x:Name="cmbLocaleSelector" Grid.Column="1" Style="{StaticResource ModernComboBox}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnSaveLocale" Grid.Column="2" Content="Save Locale" Style="{StaticResource PrimaryButton}" Padding="16,8"/>
                                        </Grid>
                                        <TextBlock x:Name="txtLocaleStatus" Text="Current locale loaded from settings." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap" Margin="0,8,0,0"/>
                                    </StackPanel>
                                </Border>

                                <!-- Ping Test -->
                                <TextBlock Text="PING / LATENCY MONITOR" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,16">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBox x:Name="txtDiagPingTarget" Style="{StaticResource ModernTextBox}" Text="8.8.8.8" Grid.Column="0" Margin="0,0,12,0"/>
                                            <Button x:Name="btnDiagPing" Content="Ping Test (10x)" Style="{StaticResource PrimaryButton}" Grid.Column="1" Margin="0,0,12,0"/>
                                            <Button x:Name="btnContinuousPing" Content="Start Continuous Ping" Style="{StaticResource ModernButton}" Grid.Column="2"/>
                                        </Grid>

                                        <Grid Margin="0,0,0,16">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Grid.Column="0" Text="Duration (sec)" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                                            <TextBox x:Name="txtLatencyHistogramSeconds" Grid.Column="1" Style="{StaticResource ModernTextBox}" Text="30" Width="80" Margin="0,0,12,0"/>
                                            <Button x:Name="btnLatencyHistogram" Content="Latency Histogram" Style="{StaticResource ModernButton}" Grid.Column="2"/>
                                        </Grid>

                                        <!-- Ping Statistics -->
                                        <Border x:Name="pnlPingStats" Background="{StaticResource BgTertiaryBrush}" CornerRadius="6" Padding="16" Margin="0,0,0,16" Visibility="Collapsed">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                                                    <TextBlock Text="MIN" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock x:Name="txtPingMin" Text="--" FontSize="18" FontWeight="Bold" Foreground="{StaticResource AccentGreenBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock Text="ms" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                </StackPanel>
                                                <StackPanel Grid.Column="1" HorizontalAlignment="Center">
                                                    <TextBlock Text="AVG" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock x:Name="txtPingAvg" Text="--" FontSize="18" FontWeight="Bold" Foreground="{StaticResource AccentBlueBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock Text="ms" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                </StackPanel>
                                                <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                                                    <TextBlock Text="MAX" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock x:Name="txtPingMax" Text="--" FontSize="18" FontWeight="Bold" Foreground="{StaticResource AccentOrangeBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock Text="ms" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                </StackPanel>
                                                <StackPanel Grid.Column="3" HorizontalAlignment="Center">
                                                    <TextBlock Text="LOSS" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock x:Name="txtPingLoss" Text="--" FontSize="18" FontWeight="Bold" Foreground="{StaticResource AccentRedBrush}" HorizontalAlignment="Center"/>
                                                    <TextBlock Text="%" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                                </StackPanel>
                                            </Grid>
                                        </Border>

                                        <!-- Continuous Ping Log -->
                                        <Border Background="{StaticResource BgPrimaryBrush}" CornerRadius="6" Padding="16" MaxHeight="350">
                                            <ScrollViewer x:Name="svPingLog" VerticalScrollBarVisibility="Auto">
                                                <TextBlock x:Name="txtPingLog" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Text="Ping results will appear here..."/>
                                            </ScrollViewer>
                                        </Border>
                                    </StackPanel>
                                </Border>

                                <!-- DNS Lookup -->
                                <TextBlock Text="DNS LOOKUP" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,16">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBox x:Name="txtDnsLookupDomain" Style="{StaticResource ModernTextBox}" Text="example.com" Grid.Column="0" Margin="0,0,12,0"/>
                                            <Button x:Name="btnDnsLookup" Content="Lookup" Style="{StaticResource PrimaryButton}" Grid.Column="1"/>
                                        </Grid>

                                        <Border Background="{StaticResource BgPrimaryBrush}" CornerRadius="6" Padding="16" MaxHeight="200">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <TextBlock x:Name="txtDnsLookupOutput" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Text="Enter a domain name and click Lookup..."/>
                                            </ScrollViewer>
                                        </Border>
                                    </StackPanel>
                                </Border>

                                <!-- Speed Test Result -->
                                <TextBlock Text="SPEED TEST RESULT" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border x:Name="pnlSpeedResult" Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                                            <TextBlock Text="DOWNLOAD" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                            <TextBlock x:Name="txtSpeedDown" Text="--" FontSize="24" FontWeight="Bold" Foreground="{StaticResource AccentGreenBrush}" HorizontalAlignment="Center"/>
                                            <TextBlock Text="Mbps" FontSize="11" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                        </StackPanel>
                                        <StackPanel Grid.Column="1" HorizontalAlignment="Center">
                                            <TextBlock Text="FILE SIZE" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                            <TextBlock x:Name="txtSpeedSize" Text="--" FontSize="24" FontWeight="Bold" Foreground="{StaticResource AccentBlueBrush}" HorizontalAlignment="Center"/>
                                            <TextBlock Text="MB" FontSize="11" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                        </StackPanel>
                                        <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                                            <TextBlock Text="DURATION" FontSize="10" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                            <TextBlock x:Name="txtSpeedTime" Text="--" FontSize="24" FontWeight="Bold" Foreground="{StaticResource AccentOrangeBrush}" HorizontalAlignment="Center"/>
                                            <TextBlock Text="sec" FontSize="11" Foreground="{StaticResource TextMutedBrush}" HorizontalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- Release Check -->
                                <TextBlock Text="RELEASE CHECK" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,20,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,16">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock x:Name="txtReleaseCheckVersion" Grid.Column="0" Text="Current version: --" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"/>
                                            <Button x:Name="btnCheckRelease" Content="Check Release" Style="{StaticResource PrimaryButton}" Grid.Column="1"/>
                                        </Grid>

                                        <Border Background="{StaticResource BgPrimaryBrush}" CornerRadius="6" Padding="16" MaxHeight="200">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <TextBlock x:Name="txtReleaseCheckOutput" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Text="Click Check Release to query the latest GitHub release."/>
                                            </ScrollViewer>
                                        </Border>
                                    </StackPanel>
                                </Border>

                                <!-- Capability Matrix -->
                                <TextBlock Text="CAPABILITY MATRIX" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,20,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,16">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Grid.Column="0" Text="Host capabilities for NetForge features" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"/>
                                            <Button x:Name="btnRefreshCapabilities" Grid.Column="1" Content="Scan" Style="{StaticResource PrimaryButton}"/>
                                        </Grid>

                                        <Border Background="{StaticResource BgPrimaryBrush}" CornerRadius="6" Padding="16" MaxHeight="280">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <TextBlock x:Name="txtCapabilityMatrix" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Text="Click Scan to check host capabilities."/>
                                            </ScrollViewer>
                                        </Border>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </TabItem>
                </TabControl>
            </Grid>
        </Grid>

        <!-- Status Bar -->
        <Border Grid.Row="3" Background="{StaticResource BgSecondaryBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Padding="16,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock x:Name="txtStatusBar" Grid.Column="0" Text="Ready" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"/>
                <TextBlock x:Name="txtFooterStatus" Grid.Column="1" Text="NetForge v1.52.0 | Running as Administrator" FontSize="11" Foreground="{StaticResource TextMutedBrush}" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ============================================================================
# WINDOW INITIALIZATION
# ============================================================================
[void](Initialize-StringResources -Locale $script:UiLocale)
Invoke-XamlLocalization -XamlDocument $xaml
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

                try {
                    $brandingIconPath = Join-Path $PSScriptRoot 'icon.ico'
                    if (Test-Path $brandingIconPath) {
                        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($brandingIconPath)))
                    }
                } catch {
                    Write-Warning "NetForge icon load failed: $($_.Exception.Message)"
                }

# Get all named controls
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    $name = $_.Name
    Set-Variable -Name $name -Value $window.FindName($name) -Scope Script
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Get-OperationLogPath {
    return (Join-Path $script:LogsPath "operations-$(Get-Date -Format 'yyyyMMdd').log")
}

function Write-OperationLog {
    param(
        [string]$Action,
        [string]$Result = "Info",
        [string]$Detail = ""
    )

    try {
        if (-not (Test-Path -LiteralPath $script:LogsPath)) {
            New-Item -Path $script:LogsPath -ItemType Directory -Force | Out-Null
        }

        $line = "{0}`t{1}`t{2}`t{3}" -f (Get-Date).ToString("o"), $Result, $Action, (($Detail -replace "`r?`n", " ") -replace "`t", " ")
        Add-Content -LiteralPath (Get-OperationLogPath) -Value $line -Encoding UTF8
    } catch {
        Write-Warning "NetForge operation log write failed: $($_.Exception.Message)"
    }
}

function Write-CrashLog {
    param(
        $Exception,
        [string]$Context = "Unhandled"
    )

    try {
        if (-not (Test-Path -LiteralPath $script:LogsPath)) {
            New-Item -Path $script:LogsPath -ItemType Directory -Force | Out-Null
        }

        $path = Join-Path $script:LogsPath "crash-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $exceptionText = if ($Exception -is [System.Exception]) { $Exception.ToString() } else { [string]$Exception }
        $lines = @(
            "NetForge crash log",
            "Version: $script:AppVersion",
            "Time: $((Get-Date).ToString('o'))",
            "Context: $Context",
            "",
            $exceptionText
        )
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-OperationLog -Action "CrashLog" -Result "Error" -Detail "$Context -> $path"
        return $path
    } catch {
        Write-Warning "NetForge crash log write failed: $($_.Exception.Message)"
        return ""
    }
}

function Register-CrashHandler {
    [System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($eventSource, $exceptionEvent)
        [void]$eventSource
        [void](Write-CrashLog -Exception $exceptionEvent.ExceptionObject -Context "AppDomain unhandled exception")
    })

    $window.Dispatcher.add_UnhandledException({
        param($eventSource, $dispatcherEvent)
        [void]$eventSource
        $path = Write-CrashLog -Exception $dispatcherEvent.Exception -Context "WPF dispatcher unhandled exception"
        Update-Status "Unexpected error logged to $path" -Type Error
        Show-MessageBox -Message "An unexpected error was logged to:`n$path" -Title "NetForge Error" -Icon Error
        $dispatcherEvent.Handled = $true
    })
}

function Update-Status {
    param([string]$Message, [string]$Type = "Info")

    $window.Dispatcher.Invoke([action]{
        $script:txtStatusBar.Text = $Message
        switch ($Type) {
            "Success" { $script:txtStatusBar.Foreground = [System.Windows.Media.Brushes]::LightGreen }
            "Error"   { $script:txtStatusBar.Foreground = [System.Windows.Media.Brushes]::Salmon }
            "Warning" { $script:txtStatusBar.Foreground = [System.Windows.Media.Brushes]::Orange }
            default   { $script:txtStatusBar.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(139,148,158))) }
        }
    })
    Write-OperationLog -Action "Status" -Result $Type -Detail $Message
}

function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title = "NetForge",
        [System.Windows.MessageBoxButton]$Buttons = [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]$Icon = [System.Windows.MessageBoxImage]::Information
    )
    return [System.Windows.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

Register-CrashHandler

function Set-ThemeBrushColor {
    param(
        [string]$BrushKey,
        [string]$Color
    )

    if ([string]::IsNullOrWhiteSpace($BrushKey) -or [string]::IsNullOrWhiteSpace($Color)) { return }

    $brush = $window.Resources[$BrushKey]
    $wpfColor = [System.Windows.Media.ColorConverter]::ConvertFromString($Color)
    if ($brush -is [System.Windows.Media.SolidColorBrush]) {
        $brush.Color = $wpfColor
    } else {
        $window.Resources[$BrushKey] = New-Object System.Windows.Media.SolidColorBrush $wpfColor
    }
}

function Apply-UiTheme {
    param([string]$ThemeName)

    $resolvedName = Resolve-UiThemeName -Name $ThemeName
    $theme = (Get-UiThemeCatalog)[$resolvedName]
    $script:UiTheme = $resolvedName

    $brushMap = [ordered]@{
        BgPrimaryBrush = "BgPrimary"
        BgSecondaryBrush = "BgSecondary"
        BgTertiaryBrush = "BgTertiary"
        BgStatusBrush = "BgStatus"
        BorderBrush = "BorderColor"
        AccentBlueBrush = "AccentBlue"
        AccentGreenBrush = "AccentGreen"
        AccentOrangeBrush = "AccentOrange"
        AccentRedBrush = "AccentRed"
        AccentPurpleBrush = "AccentPurple"
        TextPrimaryBrush = "TextPrimary"
        TextSecondaryBrush = "TextSecondary"
        TextMutedBrush = "TextMuted"
        ButtonHoverBrush = "ButtonHover"
        ButtonPressedBrush = "ButtonPressed"
        SuccessButtonBrush = "SuccessButton"
        SuccessButtonHoverBrush = "SuccessButtonHover"
        DangerButtonBgBrush = "DangerButtonBg"
        DangerButtonHoverBrush = "DangerButtonHover"
        DangerButtonPressedBrush = "DangerButtonPressed"
        ListItemHoverBrush = "ListItemHover"
        ListItemSelectedBrush = "ListItemSelected"
    }

    foreach ($brushKey in $brushMap.Keys) {
        Set-ThemeBrushColor -BrushKey $brushKey -Color $theme[$brushMap[$brushKey]]
    }

    $window.Background = $window.Resources["BgPrimaryBrush"]
    Write-OperationLog -Action "UI theme" -Result "Applied" -Detail $resolvedName
}

function Initialize-ThemeSelector {
    if ($null -eq $script:cmbUiTheme) {
        Apply-UiTheme -ThemeName $script:UiTheme
        return
    }

    $script:ThemeSelectorInitializing = $true
    try {
        $script:cmbUiTheme.Items.Clear()
        foreach ($themeName in Get-UiThemeNames) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $themeName
            $item.Tag = $themeName
            [void]$script:cmbUiTheme.Items.Add($item)
            if ($themeName -eq $script:UiTheme) {
                $script:cmbUiTheme.SelectedItem = $item
            }
        }

        if ($null -eq $script:cmbUiTheme.SelectedItem -and $script:cmbUiTheme.Items.Count -gt 0) {
            $script:cmbUiTheme.SelectedIndex = 0
            $selected = $script:cmbUiTheme.SelectedItem
            if ($selected -and $selected.Tag) {
                $script:UiTheme = [string]$selected.Tag
            }
        }
    } finally {
        $script:ThemeSelectorInitializing = $false
    }

    Apply-UiTheme -ThemeName $script:UiTheme
}

function Save-UiThemeSelection {
    if ($script:ThemeSelectorInitializing -or $null -eq $script:cmbUiTheme.SelectedItem) { return }

    $themeName = Resolve-UiThemeName -Name ([string]$script:cmbUiTheme.SelectedItem.Tag)
    Apply-UiTheme -ThemeName $themeName
    Save-AppSetting -Name "UiTheme" -Value $themeName
    Update-Status "Theme set to $themeName" -Type Success
}

function Resolve-CompactModeSetting {
    param($Value)

    return (ConvertTo-SettingsBoolean -Value $Value -DefaultValue $false)
}

function ConvertTo-ScaledThickness {
    param(
        [System.Windows.Thickness]$Thickness,
        [double]$Scale,
        [double]$Minimum = 0
    )

    return New-Object System.Windows.Thickness -ArgumentList @(
        [Math]::Max($Minimum, [Math]::Round($Thickness.Left * $Scale, 1)),
        [Math]::Max($Minimum, [Math]::Round($Thickness.Top * $Scale, 1)),
        [Math]::Max($Minimum, [Math]::Round($Thickness.Right * $Scale, 1)),
        [Math]::Max($Minimum, [Math]::Round($Thickness.Bottom * $Scale, 1))
    )
}

function ConvertTo-CompactFontSize {
    param(
        [double]$FontSize,
        [double]$Scale,
        [double]$Minimum = 9
    )

    if ($FontSize -le 0) { return $FontSize }
    return [Math]::Max($Minimum, [Math]::Round($FontSize * $Scale, 1))
}

function Get-VisualDescendants {
    param($Root)

    $items = @()
    if ($null -eq $Root) { return $items }

    $items += $Root
    try {
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
        for ($index = 0; $index -lt $count; $index++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $index)
            $items += Get-VisualDescendants -Root $child
        }
    } catch {
        return $items
    }

    return $items
}

function Get-CompactMetricKey {
    param($Element)

    return [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Element).ToString()
}

function Get-ClrPropertyValue {
    param(
        $Object,
        [string]$PropertyName
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.GetType().GetProperty($PropertyName)
    if ($null -eq $property -or -not $property.CanRead) { return $null }
    return $property.GetValue($Object, $null)
}

function Set-ClrPropertyValue {
    param(
        $Object,
        [string]$PropertyName,
        $Value
    )

    if ($null -eq $Object) { return }
    $property = $Object.GetType().GetProperty($PropertyName)
    if ($null -eq $property -or -not $property.CanWrite) { return }
    $property.SetValue($Object, $Value, $null)
}

function Register-CompactOriginalMetrics {
    param($Element)

    $key = Get-CompactMetricKey -Element $Element
    if ($script:CompactOriginalMetrics.ContainsKey($key)) { return }

    $script:CompactOriginalMetrics[$key] = [pscustomobject]@{
        Margin = Get-ClrPropertyValue -Object $Element -PropertyName "Margin"
        Padding = Get-ClrPropertyValue -Object $Element -PropertyName "Padding"
        FontSize = Get-ClrPropertyValue -Object $Element -PropertyName "FontSize"
    }
}

function Apply-CompactMode {
    param([bool]$Enabled)

    $script:CompactModeEnabled = $Enabled
    $window.MinWidth = if ($Enabled) { 900 } else { 1000 }
    $window.MinHeight = if ($Enabled) { 620 } else { 700 }

    $scale = if ($Enabled) { 0.82 } else { 1.0 }
    foreach ($element in Get-VisualDescendants -Root $window) {
        Register-CompactOriginalMetrics -Element $element
        $key = Get-CompactMetricKey -Element $element
        $original = $script:CompactOriginalMetrics[$key]
        if ($null -eq $original) { continue }

        if ($original.Margin -is [System.Windows.Thickness]) {
            Set-ClrPropertyValue -Object $element -PropertyName "Margin" -Value (ConvertTo-ScaledThickness -Thickness $original.Margin -Scale $scale)
        }
        if ($original.Padding -is [System.Windows.Thickness]) {
            Set-ClrPropertyValue -Object $element -PropertyName "Padding" -Value (ConvertTo-ScaledThickness -Thickness $original.Padding -Scale $scale)
        }
        if ($original.FontSize -is [double]) {
            Set-ClrPropertyValue -Object $element -PropertyName "FontSize" -Value (ConvertTo-CompactFontSize -FontSize $original.FontSize -Scale $scale)
        }
    }
}

function Initialize-CompactModeControl {
    if ($null -eq $script:chkCompactMode) {
        Apply-CompactMode -Enabled $script:CompactModeEnabled
        return
    }

    $script:CompactModeInitializing = $true
    try {
        $script:chkCompactMode.IsChecked = $script:CompactModeEnabled
    } finally {
        $script:CompactModeInitializing = $false
    }

    Apply-CompactMode -Enabled $script:CompactModeEnabled
}

function Save-CompactModeSelection {
    if ($script:CompactModeInitializing) { return }

    $enabled = [bool]$script:chkCompactMode.IsChecked
    Apply-CompactMode -Enabled $enabled
    Save-AppSetting -Name "CompactMode" -Value $enabled
    $status = if ($enabled) { "enabled" } else { "disabled" }
    Update-Status "Compact mode $status" -Type Success
}

function Initialize-AccessibilityMetadata {
    foreach ($controlName in $script:AccessibilityNames.Keys) {
        $control = $window.FindName($controlName)
        if ($null -eq $control) { continue }
        [System.Windows.Automation.AutomationProperties]::SetName($control, $script:AccessibilityNames[$controlName])
    }

    $tabIndex = 0
    foreach ($controlName in $script:AccessibilityTabOrder) {
        $control = $window.FindName($controlName)
        if ($null -eq $control) { continue }
        if ($control -is [System.Windows.Controls.Control]) {
            $control.TabIndex = $tabIndex
            $tabIndex++
        }
    }

    if ([System.Windows.SystemParameters]::HighContrast) {
        Write-OperationLog -Action "Accessibility" -Result "HighContrast" -Detail "Windows high contrast mode detected; native system contrast remains active."
    }
}

function Test-ValidIP {
    param([string]$IP)
    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    try {
        $parsed = [System.Net.IPAddress]::Parse($IP)
        return $true
    } catch {
        return $false
    }
}

function Test-ValidIPv4Address {
    param([string]$IP)

    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    try {
        $parsed = [System.Net.IPAddress]::Parse($IP)
        return ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork)
    } catch {
        return $false
    }
}

function Test-ValidIPv4PrefixLength {
    param([int]$PrefixLength)

    return ($PrefixLength -ge 1 -and $PrefixLength -le 32)
}

function Test-ValidIPv6Address {
    param([string]$IP)

    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    try {
        $parsed = [System.Net.IPAddress]::Parse($IP)
        return ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6)
    } catch {
        return $false
    }
}

function Test-ValidIPv6PrefixLength {
    param([int]$PrefixLength)

    return ($PrefixLength -ge 1 -and $PrefixLength -le 128)
}

function Get-ApplyValidationResult {
    param(
        [bool]$IsValid,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    $result = [ordered]@{
        IsValid = $IsValid
        Message = $Message
    }

    foreach ($key in $Data.Keys) {
        $result[$key] = $Data[$key]
    }

    return [pscustomobject]$result
}

function Get-AdapterInterfaceRegistryPath {
    param(
        $Adapter,
        [string]$AddressFamily
    )

    if (-not $Adapter -or -not $Adapter.InterfaceGuid) { return "" }

    $basePath = if ($AddressFamily -eq "IPv6") {
        "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces"
    } else {
        "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    }

    $guidText = ([string]$Adapter.InterfaceGuid).Trim()
    $guidTrimmed = $guidText.Trim("{}")
    $candidateKeys = @($guidText, "{$guidTrimmed}", $guidTrimmed) | Select-Object -Unique

    foreach ($candidate in $candidateKeys) {
        $path = Join-Path $basePath $candidate
        if (Test-Path -LiteralPath $path) { return $path }
    }

    return ""
}

function Get-StaticDnsServersFromRegistry {
    param(
        $Adapter,
        [string]$AddressFamily
    )

    $path = Get-AdapterInterfaceRegistryPath -Adapter $Adapter -AddressFamily $AddressFamily
    if ([string]::IsNullOrWhiteSpace($path)) { return @() }

    try {
        $nameServer = (Get-ItemProperty -LiteralPath $path -Name NameServer -ErrorAction SilentlyContinue).NameServer
        if ([string]::IsNullOrWhiteSpace($nameServer)) { return @() }

        return @($nameServer -split '[,\s]+' | Where-Object { Test-ValidIP $_ } | Select-Object -Unique)
    } catch {
        return @()
    }
}

function Get-AdapterNetworkSnapshot {
    param(
        $Adapter,
        [string]$Reason
    )

    if ($null -eq $Adapter) {
        throw "No adapter was supplied for network snapshot."
    }

    $ipInterface = Get-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1
    $addresses = @(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
        ForEach-Object {
            [pscustomobject]@{
                IPAddress = $_.IPAddress
                PrefixLength = [int]$_.PrefixLength
                PrefixOrigin = [string]$_.PrefixOrigin
            }
        })

    $ipv6Addresses = @(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.IPAddress -ne "::1" -and $_.IPAddress -notlike "fe80:*" } |
        ForEach-Object {
            [pscustomobject]@{
                IPAddress = $_.IPAddress
                PrefixLength = [int]$_.PrefixLength
                PrefixOrigin = [string]$_.PrefixOrigin
            }
        })

    $routes = @(Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        ForEach-Object {
            [pscustomobject]@{
                NextHop = $_.NextHop
                RouteMetric = $_.RouteMetric
            }
        })

    $ipv6Routes = @(Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "::/0" -ErrorAction SilentlyContinue |
        Where-Object { (-not $_.PSObject.Properties["RouteProtocol"]) -or [string]$_.RouteProtocol -eq "NetMgmt" } |
        ForEach-Object {
            [pscustomobject]@{
                NextHop = $_.NextHop
                RouteMetric = $_.RouteMetric
            }
        })

    $staticDnsServers = @()
    $staticDnsServers += Get-StaticDnsServersFromRegistry -Adapter $Adapter -AddressFamily IPv4
    $staticDnsServers += Get-StaticDnsServersFromRegistry -Adapter $Adapter -AddressFamily IPv6
    $staticDnsServers = @($staticDnsServers | Where-Object { Test-ValidIP $_ } | Select-Object -Unique)

    $effectiveDnsServers = @()
    $dnsRows = @(Get-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ErrorAction SilentlyContinue)
    foreach ($row in $dnsRows) {
        if ($row.ServerAddresses) {
            $effectiveDnsServers += @($row.ServerAddresses | Where-Object { Test-ValidIP $_ })
        }
    }
    $effectiveDnsServers = @($effectiveDnsServers | Select-Object -Unique)
    $networkProfile = Get-NetConnectionProfile -InterfaceIndex $Adapter.ifIndex -ErrorAction SilentlyContinue | Select-Object -First 1
    $networkCategory = if ($networkProfile) { [string]$networkProfile.NetworkCategory } else { "" }

    return [pscustomobject]@{
        CapturedAt = (Get-Date).ToString("o")
        Reason = $Reason
        InterfaceIndex = $Adapter.ifIndex
        InterfaceAlias = $Adapter.Name
        Dhcp = [string]$ipInterface.Dhcp
        IPv4Addresses = $addresses
        DefaultRoutes = $routes
        IPv6Addresses = $ipv6Addresses
        IPv6DefaultRoutes = $ipv6Routes
        DnsAutomatic = ($staticDnsServers.Count -eq 0)
        StaticDnsServers = $staticDnsServers
        EffectiveDnsServers = $effectiveDnsServers
        Environment = [pscustomobject]@{
            NetworkCategory = $networkCategory
            Proxy = Get-SystemProxySnapshot
            DefaultPrinterName = Get-DefaultPrinterName
            MappedDrives = @(Get-MappedDriveState)
        }
    }
}

function Show-RestoreSnapshotButtonState {
    if ($script:btnRestoreNetworkState) {
        $script:btnRestoreNetworkState.IsEnabled = ($null -ne $script:LastNetworkSnapshot)
    }
}

function Register-LastNetworkSnapshot {
    param([pscustomobject]$Snapshot)

    $script:LastNetworkSnapshot = $Snapshot
    Show-RestoreSnapshotButtonState
}

function Restore-NetworkSnapshot {
    param([pscustomobject]$Snapshot)

    if ($null -eq $Snapshot) {
        return [pscustomobject]@{ Restored = $false; Message = "No network snapshot is available." }
    }

    try {
        $adapter = Get-NetAdapter -InterfaceIndex $Snapshot.InterfaceIndex -ErrorAction Stop

        Get-NetIPAddress -InterfaceIndex $Snapshot.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        Get-NetRoute -InterfaceIndex $Snapshot.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        if ($Snapshot.Dhcp -eq "Enabled") {
            Set-NetIPInterface -InterfaceIndex $Snapshot.InterfaceIndex -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
        } else {
            Set-NetIPInterface -InterfaceIndex $Snapshot.InterfaceIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop

            foreach ($address in @($Snapshot.IPv4Addresses)) {
                if ((Test-ValidIPv4Address -IP $address.IPAddress) -and (Test-ValidIPv4PrefixLength -PrefixLength ([int]$address.PrefixLength))) {
                    New-NetIPAddress -InterfaceIndex $Snapshot.InterfaceIndex -IPAddress $address.IPAddress -PrefixLength ([int]$address.PrefixLength) -ErrorAction Stop | Out-Null
                }
            }

            foreach ($route in @($Snapshot.DefaultRoutes)) {
                if (Test-ValidIPv4Address -IP $route.NextHop) {
                    $routeParams = @{
                        InterfaceIndex = $Snapshot.InterfaceIndex
                        DestinationPrefix = "0.0.0.0/0"
                        NextHop = $route.NextHop
                        ErrorAction = "Stop"
                    }
                    if ($null -ne $route.RouteMetric) {
                        $routeParams.RouteMetric = [int]$route.RouteMetric
                    }
                    New-NetRoute @routeParams | Out-Null
                }
            }
        }

        Get-NetIPAddress -InterfaceIndex $Snapshot.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.IPAddress -ne "::1" -and $_.IPAddress -notlike "fe80:*" } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        Get-NetRoute -InterfaceIndex $Snapshot.InterfaceIndex -DestinationPrefix "::/0" -ErrorAction SilentlyContinue |
            Where-Object { (-not $_.PSObject.Properties["RouteProtocol"]) -or [string]$_.RouteProtocol -eq "NetMgmt" } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        foreach ($address in @($Snapshot.IPv6Addresses)) {
            if ((Test-ValidIPv6Address -IP $address.IPAddress) -and (Test-ValidIPv6PrefixLength -PrefixLength ([int]$address.PrefixLength))) {
                New-NetIPAddress -InterfaceIndex $Snapshot.InterfaceIndex -IPAddress $address.IPAddress -PrefixLength ([int]$address.PrefixLength) -ErrorAction Stop | Out-Null
            }
        }

        foreach ($route in @($Snapshot.IPv6DefaultRoutes)) {
            if (Test-ValidIPv6Address -IP $route.NextHop) {
                $routeParams = @{
                    InterfaceIndex = $Snapshot.InterfaceIndex
                    DestinationPrefix = "::/0"
                    NextHop = $route.NextHop
                    ErrorAction = "Stop"
                }
                if ($null -ne $route.RouteMetric) {
                    $routeParams.RouteMetric = [int]$route.RouteMetric
                }
                New-NetRoute @routeParams | Out-Null
            }
        }

        if ($Snapshot.DnsAutomatic) {
            Set-DnsClientServerAddress -InterfaceIndex $Snapshot.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
        } else {
            $dnsServers = @($Snapshot.StaticDnsServers | Where-Object { Test-ValidIP $_ } | Select-Object -Unique)
            if ($dnsServers.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $Snapshot.InterfaceIndex -ServerAddresses $dnsServers -ErrorAction Stop
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $Snapshot.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            }
        }

        if ($Snapshot.Environment) {
            if (-not [string]::IsNullOrWhiteSpace($Snapshot.Environment.NetworkCategory)) {
                Set-NetConnectionProfile -InterfaceIndex $Snapshot.InterfaceIndex -NetworkCategory $Snapshot.Environment.NetworkCategory -ErrorAction SilentlyContinue
            }
            if ($Snapshot.Environment.Proxy) {
                Set-SystemProxyState -Enabled ([bool]$Snapshot.Environment.Proxy.Enabled) -Server ([string]$Snapshot.Environment.Proxy.Server) -Bypass ([string]$Snapshot.Environment.Proxy.Bypass)
            }
            if (-not [string]::IsNullOrWhiteSpace($Snapshot.Environment.DefaultPrinterName)) {
                Set-DefaultPrinterByName -Name $Snapshot.Environment.DefaultPrinterName
            }
            if ($null -ne $Snapshot.Environment.MappedDrives) {
                Set-MappedDriveState -MappedDrives $Snapshot.Environment.MappedDrives
            }
        }

        return [pscustomobject]@{ Restored = $true; Message = "Restored network state for $($adapter.Name)." }
    } catch {
        return [pscustomobject]@{ Restored = $false; Message = $_.Exception.Message }
    }
}

function Invoke-RestoreLastNetworkState {
    $result = Restore-NetworkSnapshot -Snapshot $script:LastNetworkSnapshot
    if ($result.Restored) {
        Update-Status $result.Message -Type Success
        Start-Sleep -Milliseconds 500
        Update-AdapterDisplay
    } else {
        Update-Status "Restore failed: $($result.Message)" -Type Error
        Show-MessageBox -Message "Failed to restore the last network state:`n$($result.Message)" -Title "Restore Failed" -Icon Error
    }
}

function Invoke-NetworkMutation {
    param(
        $Adapter,
        [string]$ActionName,
        [scriptblock]$ScriptBlock,
        [switch]$Quiet
    )

    $snapshot = $null

    try {
        $snapshot = Get-AdapterNetworkSnapshot -Adapter $Adapter -Reason $ActionName
        Register-LastNetworkSnapshot -Snapshot $snapshot
        Write-OperationLog -Action $ActionName -Result "Started" -Detail "Adapter=$($Adapter.Name); Snapshot=$($snapshot.CapturedAt)"
        & $ScriptBlock
        Write-OperationLog -Action $ActionName -Result "Succeeded" -Detail "Adapter=$($Adapter.Name)"
        return $true
    } catch {
        $changeError = $_.Exception.Message

        if ($null -eq $snapshot) {
            Update-Status "$ActionName failed before a rollback snapshot was captured" -Type Error
            Write-OperationLog -Action $ActionName -Result "Failed" -Detail "Snapshot capture failed: $changeError"
            if (-not $Quiet) {
                Show-MessageBox -Message "$ActionName failed before a rollback snapshot was captured:`n$changeError" -Title "Network Change Failed" -Icon Error
            }
            return $false
        }

        $restoreResult = Restore-NetworkSnapshot -Snapshot $snapshot
        if ($restoreResult.Restored) {
            Update-Status "$ActionName failed; previous network state restored" -Type Error
            Write-OperationLog -Action $ActionName -Result "RolledBack" -Detail "$changeError; $($restoreResult.Message)"
            if (-not $Quiet) {
                Show-MessageBox -Message "$ActionName failed:`n$changeError`n`nPrevious network state was restored." -Title "Network Change Rolled Back" -Icon Error
            }
        } else {
            Update-Status "$ActionName failed; restore failed" -Type Error
            Write-OperationLog -Action $ActionName -Result "RollbackFailed" -Detail "$changeError; Restore failed: $($restoreResult.Message)"
            if (-not $Quiet) {
                Show-MessageBox -Message "$ActionName failed:`n$changeError`n`nRestore failed:`n$($restoreResult.Message)" -Title "Network Change Failed" -Icon Error
            }
        }

        return $false
    }
}

function Get-IPApplyTarget {
    $configureIPv6 = ($script:chkConfigureIPv6Address -and $script:chkConfigureIPv6Address.IsChecked)
    $ipv6Target = Get-IPv6ApplyTarget `
        -ConfigureIPv6 $configureIPv6 `
        -IPv6Address $script:txtIPv6Address.Text `
        -IPv6PrefixText $script:txtIPv6Prefix.Text `
        -IPv6Gateway $script:txtIPv6Gateway.Text

    if (-not $ipv6Target.IsValid) {
        return $ipv6Target
    }

    $statusParts = @()
    if ($script:rbDHCP.IsChecked) {
        $statusParts += "DHCP enabled"
        if ($ipv6Target.ConfigureIPv6) {
            $statusParts += "static IPv6 $($ipv6Target.IPv6Address) configured"
        }
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            UseDHCP = $true
            ConfigureIPv6 = $ipv6Target.ConfigureIPv6
            IPv6Address = $ipv6Target.IPv6Address
            IPv6PrefixLength = $ipv6Target.IPv6PrefixLength
            IPv6Gateway = $ipv6Target.IPv6Gateway
            StatusMessage = ($statusParts -join "; ")
        }
    }

    $ip = $script:txtIPAddress.Text.Trim()
    $gateway = $script:txtGateway.Text.Trim()
    $prefixText = $script:txtPrefix.Text.Trim()
    $prefix = 0

    if (-not (Test-ValidIPv4Address -IP $ip)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Invalid IPv4 address format."
    }
    if (-not [int]::TryParse($prefixText, [ref]$prefix) -or -not (Test-ValidIPv4PrefixLength -PrefixLength $prefix)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Prefix length must be a number from 1 to 32."
    }
    if (-not [string]::IsNullOrWhiteSpace($gateway) -and -not (Test-ValidIPv4Address -IP $gateway)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Invalid default gateway IPv4 address."
    }

    $statusParts += "Static IP $ip configured"
    if ($ipv6Target.ConfigureIPv6) {
        $statusParts += "static IPv6 $($ipv6Target.IPv6Address) configured"
    }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        UseDHCP = $false
        IPAddress = $ip
        Gateway = $gateway
        PrefixLength = $prefix
        ConfigureIPv6 = $ipv6Target.ConfigureIPv6
        IPv6Address = $ipv6Target.IPv6Address
        IPv6PrefixLength = $ipv6Target.IPv6PrefixLength
        IPv6Gateway = $ipv6Target.IPv6Gateway
        StatusMessage = ($statusParts -join "; ")
    }
}

function Get-IPv6ApplyTarget {
    param(
        [bool]$ConfigureIPv6,
        [string]$IPv6Address,
        [string]$IPv6PrefixText,
        [string]$IPv6Gateway
    )

    if (-not $ConfigureIPv6) {
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            ConfigureIPv6 = $false
            IPv6Address = ""
            IPv6PrefixLength = 0
            IPv6Gateway = ""
        }
    }

    $address = ([string]$IPv6Address).Trim()
    $gateway = ([string]$IPv6Gateway).Trim()
    $prefix = 0

    if (-not (Test-ValidIPv6Address -IP $address)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Invalid IPv6 address format."
    }

    if (-not [int]::TryParse(([string]$IPv6PrefixText).Trim(), [ref]$prefix) -or -not (Test-ValidIPv6PrefixLength -PrefixLength $prefix)) {
        return Get-ApplyValidationResult -IsValid $false -Message "IPv6 prefix length must be a number from 1 to 128."
    }

    if (-not [string]::IsNullOrWhiteSpace($gateway) -and -not (Test-ValidIPv6Address -IP $gateway)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Invalid IPv6 default gateway address."
    }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        ConfigureIPv6 = $true
        IPv6Address = $address
        IPv6PrefixLength = $prefix
        IPv6Gateway = $gateway
    }
}

function Get-DnsPresetApplyTarget {
    param(
        [string]$PresetName,
        [object]$PresetData,
        [bool]$IncludeIPv6 = $false
    )

    $displayName = ([string]$PresetName).Trim()
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        return Get-ApplyValidationResult -IsValid $false -Message "DNS preset name is required."
    }
    if ($null -eq $PresetData) {
        return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$displayName' has no data."
    }

    if ([string]$PresetData.Primary -eq "DHCP") {
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            UseAutomatic = $true
            Servers = @()
            StatusMessage = "DNS preset '$displayName' set to automatic"
        }
    }

    $servers = @()
    foreach ($server in @($PresetData.Primary, $PresetData.Secondary)) {
        if ([string]::IsNullOrWhiteSpace($server)) { continue }
        if (-not (Test-ValidIP -IP $server)) {
            return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$displayName' contains invalid server '$server'."
        }
        $servers += $server
    }

    if ($IncludeIPv6) {
        foreach ($server in @($PresetData.PrimaryV6, $PresetData.SecondaryV6)) {
            if ([string]::IsNullOrWhiteSpace($server)) { continue }
            if (-not (Test-ValidIP -IP $server)) {
                return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$displayName' contains invalid IPv6 server '$server'."
            }
            $servers += $server
        }
    }

    $servers = @($servers | Select-Object -Unique)
    if ($servers.Count -eq 0) {
        return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$displayName' has no usable DNS servers."
    }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        UseAutomatic = $false
        Servers = $servers
        StatusMessage = "DNS preset '$displayName' applied"
    }
}

function Get-DNSApplyTarget {
    if ($script:rbDnsDHCP.IsChecked) {
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            UseAutomatic = $true
            Servers = @()
            StatusMessage = "DNS set to automatic"
        }
    }

    if ($script:rbDnsPreset.IsChecked) {
        $selected = $script:lstDnsPresets.SelectedItem
        if ($null -eq $selected) {
            return Get-ApplyValidationResult -IsValid $false -Message "Please select a DNS preset."
        }

        return Get-DnsPresetApplyTarget -PresetName $selected.Tag.Name -PresetData $selected.Tag.Data -IncludeIPv6 ([bool]$script:chkIPv6Dns.IsChecked)
    }

    $primary = $script:txtDnsPrimary.Text.Trim()
    $secondary = $script:txtDnsSecondary.Text.Trim()

    if (-not (Test-ValidIP -IP $primary)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Invalid primary DNS address."
    }
    if (-not [string]::IsNullOrWhiteSpace($secondary) -and -not (Test-ValidIP -IP $secondary)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Invalid secondary DNS address."
    }

    $servers = @($primary)
    if (-not [string]::IsNullOrWhiteSpace($secondary)) { $servers += $secondary }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        UseAutomatic = $false
        Servers = @($servers | Select-Object -Unique)
        StatusMessage = "Custom DNS applied"
    }
}

function Get-ProfileApplyTarget {
    param([pscustomobject]$ProfileData)

    $useDhcp = [bool]$ProfileData.UseDHCP
    $useDnsAutomatic = [bool]$ProfileData.UseDHCPForDNS
    $ipAddress = if ($ProfileData.IPAddress) { ([string]$ProfileData.IPAddress).Trim() } else { "" }
    $gateway = if ($ProfileData.Gateway) { ([string]$ProfileData.Gateway).Trim() } else { "" }
    $prefixText = if ($ProfileData.PrefixLength) { ([string]$ProfileData.PrefixLength).Trim() } else { "24" }
    $prefix = 0

    if (-not $useDhcp) {
        if (-not (Test-ValidIPv4Address -IP $ipAddress)) {
            return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has an invalid IPv4 address."
        }
        if (-not [int]::TryParse($prefixText, [ref]$prefix) -or -not (Test-ValidIPv4PrefixLength -PrefixLength $prefix)) {
            return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has an invalid prefix length."
        }
        if (-not [string]::IsNullOrWhiteSpace($gateway) -and -not (Test-ValidIPv4Address -IP $gateway)) {
            return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has an invalid gateway."
        }
    }

    $dnsServers = @()
    if (-not $useDnsAutomatic) {
        $primary = if ($ProfileData.PrimaryDNS) { ([string]$ProfileData.PrimaryDNS).Trim() } else { "" }
        $secondary = if ($ProfileData.SecondaryDNS) { ([string]$ProfileData.SecondaryDNS).Trim() } else { "" }

        if (-not (Test-ValidIP -IP $primary)) {
            return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has an invalid primary DNS server."
        }
        if (-not [string]::IsNullOrWhiteSpace($secondary) -and -not (Test-ValidIP -IP $secondary)) {
            return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has an invalid secondary DNS server."
        }

        $dnsServers += $primary
        if (-not [string]::IsNullOrWhiteSpace($secondary)) { $dnsServers += $secondary }
    }

    $configureNetworkCategory = [bool]$ProfileData.ConfigureNetworkCategory
    $networkCategory = if ($ProfileData.NetworkCategory) { ([string]$ProfileData.NetworkCategory).Trim() } else { "" }
    if ($configureNetworkCategory -and $networkCategory -notin @("Public", "Private")) {
        return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has an invalid network category."
    }

    $configureProxy = [bool]$ProfileData.ConfigureProxy
    $proxyEnabled = [bool]$ProfileData.ProxyEnabled
    $proxyServer = if ($ProfileData.ProxyServer) { ([string]$ProfileData.ProxyServer).Trim() } else { "" }
    $proxyBypass = if ($ProfileData.ProxyBypass) { ([string]$ProfileData.ProxyBypass).Trim() } else { "" }
    if ($configureProxy -and $proxyEnabled -and [string]::IsNullOrWhiteSpace($proxyServer)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' enables proxy but has no proxy server."
    }

    $configureDefaultPrinter = [bool]$ProfileData.ConfigureDefaultPrinter
    $defaultPrinterName = if ($ProfileData.DefaultPrinterName) { ([string]$ProfileData.DefaultPrinterName).Trim() } else { "" }
    if ($configureDefaultPrinter -and [string]::IsNullOrWhiteSpace($defaultPrinterName)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Profile '$($ProfileData.Name)' has no default printer name."
    }

    $configureMappedDrives = [bool]$ProfileData.ConfigureMappedDrives
    $mappedDriveValidation = Normalize-MappedDriveList -MappedDrives $ProfileData.MappedDrives
    if ($configureMappedDrives -and -not $mappedDriveValidation.IsValid) {
        return Get-ApplyValidationResult -IsValid $false -Message $mappedDriveValidation.Message
    }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        UseDHCP = $useDhcp
        IPAddress = $ipAddress
        Gateway = $gateway
        PrefixLength = if ($useDhcp) { 0 } else { $prefix }
        UseAutomatic = $useDnsAutomatic
        Servers = @($dnsServers | Select-Object -Unique)
        ConfigureNetworkCategory = $configureNetworkCategory
        NetworkCategory = $networkCategory
        ConfigureProxy = $configureProxy
        ProxyEnabled = $proxyEnabled
        ProxyServer = $proxyServer
        ProxyBypass = $proxyBypass
        ConfigureDefaultPrinter = $configureDefaultPrinter
        DefaultPrinterName = $defaultPrinterName
        ConfigureMappedDrives = $configureMappedDrives
        MappedDrives = [object[]]@($mappedDriveValidation.MappedDrives)
    }
}

function Invoke-AdapterIPTarget {
    param(
        $Adapter,
        [pscustomobject]$Target
    )

    if ($Target.UseDHCP) {
        Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
        Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -eq "Manual" } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
        Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction Stop
    } else {
        Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
        Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $Adapter.ifIndex -IPAddress $Target.IPAddress -PrefixLength $Target.PrefixLength -ErrorAction Stop | Out-Null

        if (Test-ValidIPv4Address -IP $Target.Gateway) {
            New-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop $Target.Gateway -ErrorAction Stop | Out-Null
        }
    }

    if ($Target.ConfigureIPv6) {
        Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.IPAddress -ne "::1" -and $_.IPAddress -notlike "fe80:*" } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "::/0" -ErrorAction SilentlyContinue |
            Where-Object { (-not $_.PSObject.Properties["RouteProtocol"]) -or [string]$_.RouteProtocol -eq "NetMgmt" } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $Adapter.ifIndex -IPAddress $Target.IPv6Address -PrefixLength $Target.IPv6PrefixLength -ErrorAction Stop | Out-Null

        if (Test-ValidIPv6Address -IP $Target.IPv6Gateway) {
            New-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "::/0" -NextHop $Target.IPv6Gateway -ErrorAction Stop | Out-Null
        }
    }
}

function Invoke-AdapterDNSTarget {
    param(
        $Adapter,
        [pscustomobject]$Target
    )

    if ($Target.UseAutomatic) {
        Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
        return
    }

    $servers = @($Target.Servers | Where-Object { Test-ValidIP $_ } | Select-Object -Unique)
    if ($servers.Count -eq 0) {
        throw "No valid DNS servers were supplied."
    }

    Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
}

function Test-ManualRouteRow {
    param([object]$Route)

    if ($null -eq $Route) { return $false }
    if ($Route.PSObject.Properties["RouteProtocol"]) {
        return ([string]$Route.RouteProtocol -eq "NetMgmt")
    }
    return $true
}

function Get-RoutePrefixInfo {
    param([string]$DestinationPrefix)

    $prefixText = ([string]$DestinationPrefix).Trim()
    if ([string]::IsNullOrWhiteSpace($prefixText) -or $prefixText -notmatch '^(.+)/(\d+)$') {
        return Get-ApplyValidationResult -IsValid $false -Message "Destination prefix must use CIDR format, for example 10.10.0.0/16 or 2001:db8::/64."
    }

    $address = $Matches[1].Trim()
    $prefixLength = [int]$Matches[2]
    if (Test-ValidIPv4Address -IP $address) {
        if ($prefixLength -lt 0 -or $prefixLength -gt 32) {
            return Get-ApplyValidationResult -IsValid $false -Message "IPv4 route prefix length must be from 0 to 32."
        }
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            AddressFamily = "IPv4"
            DestinationPrefix = "$address/$prefixLength"
            PrefixLength = $prefixLength
        }
    }

    if (Test-ValidIPv6Address -IP $address) {
        if ($prefixLength -lt 0 -or $prefixLength -gt 128) {
            return Get-ApplyValidationResult -IsValid $false -Message "IPv6 route prefix length must be from 0 to 128."
        }
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            AddressFamily = "IPv6"
            DestinationPrefix = "$address/$prefixLength"
            PrefixLength = $prefixLength
        }
    }

    return Get-ApplyValidationResult -IsValid $false -Message "Destination prefix must start with a valid IPv4 or IPv6 address."
}

function Get-StaticRouteTarget {
    param(
        [string]$DestinationPrefix,
        [string]$NextHop,
        [string]$MetricText
    )

    $prefix = Get-RoutePrefixInfo -DestinationPrefix $DestinationPrefix
    if (-not $prefix.IsValid) { return $prefix }

    $nextHopText = ([string]$NextHop).Trim()
    if ([string]::IsNullOrWhiteSpace($nextHopText)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Next hop is required."
    }

    if ($prefix.AddressFamily -eq "IPv4" -and -not (Test-ValidIPv4Address -IP $nextHopText)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Next hop must be a valid IPv4 address for an IPv4 route."
    }
    if ($prefix.AddressFamily -eq "IPv6" -and -not (Test-ValidIPv6Address -IP $nextHopText)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Next hop must be a valid IPv6 address for an IPv6 route."
    }

    $metric = $null
    $metricInput = ([string]$MetricText).Trim()
    if (-not [string]::IsNullOrWhiteSpace($metricInput)) {
        $metricValue = 0
        if (-not [int]::TryParse($metricInput, [ref]$metricValue) -or $metricValue -lt 0 -or $metricValue -gt 9999) {
            return Get-ApplyValidationResult -IsValid $false -Message "Route metric must be a number from 0 to 9999."
        }
        $metric = $metricValue
    }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        DestinationPrefix = $prefix.DestinationPrefix
        AddressFamily = $prefix.AddressFamily
        NextHop = $nextHopText
        RouteMetric = $metric
    }
}

function Format-StaticRouteRows {
    param([object[]]$Routes)

    $rows = @($Routes)
    if ($rows.Count -eq 0) {
        return "No manual static routes found for the selected adapter."
    }

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Destination prefix                 Next hop                         Metric  Family") | Out-Null
    $sb.AppendLine("----------------------------------  -------------------------------  ------  ------") | Out-Null
    foreach ($route in $rows) {
        $family = if ([string]$route.DestinationPrefix -match ':') { "IPv6" } else { "IPv4" }
        $metric = if ($null -ne $route.RouteMetric) { [string]$route.RouteMetric } else { "--" }
        $sb.AppendLine(("{0,-34}  {1,-31}  {2,6}  {3}" -f $route.DestinationPrefix, $route.NextHop, $metric, $family)) | Out-Null
    }
    return $sb.ToString()
}

function Get-HostsSectionBeginMarker {
    return "# NETFORGE HOSTS BEGIN"
}

function Get-HostsSectionEndMarker {
    return "# NETFORGE HOSTS END"
}

function Get-HostsFilePath {
    return (Join-Path $env:WinDir "System32\drivers\etc\hosts")
}

function Test-HostsGroupName {
    param([string]$Name)

    $value = ([string]$Name).Trim()
    return (-not [string]::IsNullOrWhiteSpace($value) -and $value.Length -le 64 -and $value -notmatch '[|#]')
}

function Test-HostsEntryHostName {
    param([string]$HostName)

    $value = ([string]$HostName).Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 253) { return $false }
    foreach ($label in @($value -split '\.')) {
        if ([string]::IsNullOrWhiteSpace($label) -or $label.Length -gt 63) { return $false }
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$') { return $false }
    }
    return $true
}

function ConvertTo-HostsEntryHostNames {
    param([string]$HostNames)

    return @(([string]$HostNames -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique))
}

function Get-HostsEntryTarget {
    param(
        [string]$GroupName,
        [string]$Address,
        [string]$HostNames
    )

    $group = ([string]$GroupName).Trim()
    $addressValue = ([string]$Address).Trim()
    $hostList = @(ConvertTo-HostsEntryHostNames -HostNames $HostNames)

    if (-not (Test-HostsGroupName -Name $group)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Hosts group name is required and cannot contain # or |."
    }
    if (-not (Test-ValidIP -IP $addressValue)) {
        return Get-ApplyValidationResult -IsValid $false -Message "Hosts entry address must be a valid IPv4 or IPv6 address."
    }
    if ($hostList.Count -eq 0) {
        return Get-ApplyValidationResult -IsValid $false -Message "Enter at least one hostname."
    }
    foreach ($hostName in $hostList) {
        if (-not (Test-HostsEntryHostName -HostName $hostName)) {
            return Get-ApplyValidationResult -IsValid $false -Message "Invalid hostname '$hostName'."
        }
    }

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        GroupName = $group
        Address = $addressValue
        HostNames = $hostList
    }
}

function ConvertFrom-HostsManagedSection {
    param([string]$Text)

    $begin = Get-HostsSectionBeginMarker
    $end = Get-HostsSectionEndMarker
    $groups = @()
    $current = $null
    $inside = $false

    foreach ($rawLine in @(([string]$Text) -split "`r?`n")) {
        $line = [string]$rawLine
        if ($line.Trim() -eq $begin) {
            $inside = $true
            continue
        }
        if ($line.Trim() -eq $end) {
            break
        }
        if (-not $inside) { continue }

        if ($line -match '^\s*#\s*NetForge group:\s*(.+?)\s*\|\s*(enabled|disabled)\s*$') {
            if ($current) { $groups += [pscustomobject]$current }
            $current = [ordered]@{
                Name = $Matches[1].Trim()
                Enabled = ($Matches[2].ToLowerInvariant() -eq "enabled")
                Entries = @()
            }
            continue
        }

        if ($null -eq $current) { continue }
        $entryLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($entryLine)) { continue }
        if ($entryLine.StartsWith("#")) { $entryLine = $entryLine.Substring(1).Trim() }
        if ([string]::IsNullOrWhiteSpace($entryLine) -or $entryLine.StartsWith("#")) { continue }
        if ($entryLine -match '^(\S+)\s+(.+)$') {
            $address = $Matches[1].Trim()
            $hostText = ($Matches[2] -split '\s+#', 2)[0].Trim()
            $hostList = @(ConvertTo-HostsEntryHostNames -HostNames $hostText)
            if ((Test-ValidIP -IP $address) -and $hostList.Count -gt 0) {
                $current.Entries += [pscustomobject]@{
                    Address = $address
                    HostNames = $hostList
                }
            }
        }
    }

    if ($current) { $groups += [pscustomobject]$current }
    return ,@($groups)
}

function ConvertTo-HostsManagedSection {
    param([object[]]$Groups)

    $lines = @((Get-HostsSectionBeginMarker))
    foreach ($group in @($Groups)) {
        $name = ([string]$group.Name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $state = if ([bool]$group.Enabled) { "enabled" } else { "disabled" }
        $lines += "# NetForge group: $name | $state"
        foreach ($entry in @($group.Entries)) {
            $address = ([string]$entry.Address).Trim()
            $hostText = (@($entry.HostNames) | Where-Object { $_ } | Select-Object -Unique) -join " "
            if ([string]::IsNullOrWhiteSpace($address) -or [string]::IsNullOrWhiteSpace($hostText)) { continue }
            $entryLine = "$address $hostText"
            if (-not [bool]$group.Enabled) { $entryLine = "# $entryLine" }
            $lines += $entryLine
        }
        $lines += ""
    }
    $lines += (Get-HostsSectionEndMarker)
    return ($lines -join "`r`n")
}

function Update-HostsManagedSection {
    param(
        [string]$CurrentText,
        [object[]]$Groups
    )

    $begin = Get-HostsSectionBeginMarker
    $end = Get-HostsSectionEndMarker
    $sectionLines = @((ConvertTo-HostsManagedSection -Groups $Groups) -split "`r?`n")
    $lines = @(([string]$CurrentText) -split "`r?`n")
    $beginIndex = -1
    $endIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $begin) { $beginIndex = $i }
        if ($beginIndex -ge 0 -and $lines[$i].Trim() -eq $end) {
            $endIndex = $i
            break
        }
    }

    $newLines = @()
    if ($beginIndex -ge 0 -and $endIndex -ge $beginIndex) {
        if ($beginIndex -gt 0) { $newLines += $lines[0..($beginIndex - 1)] }
        $newLines += $sectionLines
        if ($endIndex -lt ($lines.Count - 1)) { $newLines += $lines[($endIndex + 1)..($lines.Count - 1)] }
    } else {
        $newLines += $lines
        if ($newLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($newLines[-1])) { $newLines += "" }
        $newLines += $sectionLines
    }

    return (($newLines -join "`r`n").TrimEnd() + "`r`n")
}

function Format-HostsGroupRows {
    param([object[]]$Groups)

    $rows = @($Groups)
    if ($rows.Count -eq 0) {
        return "No NetForge-managed hosts groups found."
    }

    $sb = New-Object System.Text.StringBuilder
    foreach ($group in $rows) {
        $state = if ([bool]$group.Enabled) { "enabled" } else { "disabled" }
        $entries = @($group.Entries)
        $entryWord = if ($entries.Count -eq 1) { "entry" } else { "entries" }
        $sb.AppendLine("[$state] $($group.Name) ($($entries.Count) $entryWord)") | Out-Null
        foreach ($entry in $entries) {
            $sb.AppendLine(("  {0,-39} {1}" -f $entry.Address, ((@($entry.HostNames) -join " ")))) | Out-Null
        }
    }
    return $sb.ToString()
}

function Invoke-ProfileEnvironmentTarget {
    param(
        $Adapter,
        [pscustomobject]$Target
    )

    if ($Target.ConfigureNetworkCategory) {
        Set-NetConnectionProfile -InterfaceIndex $Adapter.ifIndex -NetworkCategory $Target.NetworkCategory -ErrorAction Stop
    }

    if ($Target.ConfigureProxy) {
        Set-SystemProxyState -Enabled ([bool]$Target.ProxyEnabled) -Server $Target.ProxyServer -Bypass $Target.ProxyBypass
    }

    if ($Target.ConfigureDefaultPrinter) {
        Set-DefaultPrinterByName -Name $Target.DefaultPrinterName
    }

    if ($Target.ConfigureMappedDrives) {
        Set-MappedDriveState -MappedDrives $Target.MappedDrives
    }
}

function ConvertTo-CleanMacAddress {
    param([string]$MacAddress)

    if ([string]::IsNullOrWhiteSpace($MacAddress)) { return "" }
    return ($MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
}

function Test-ValidMacAddress {
    param([string]$MacAddress)

    $clean = ConvertTo-CleanMacAddress -MacAddress $MacAddress
    if ($clean.Length -ne 12) { return $false }
    if ($clean -notmatch '^[0-9A-F]{12}$') { return $false }
    if ($clean -match '^(00){6}$' -or $clean -match '^(FF){6}$') { return $false }

    $firstOctet = [Convert]::ToInt32($clean.Substring(0, 2), 16)
    return (($firstOctet -band 1) -eq 0)
}

function Get-RandomMacAddress {
    $bytes = New-Object byte[] 6
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }

    $bytes[0] = [byte](($bytes[0] -bor 0x02) -band 0xFE)
    return (($bytes | ForEach-Object { $_.ToString("X2") }) -join "")
}

function Get-AdapterRegistryPath {
    param($Adapter)

    if ($null -eq $Adapter) { return $null }

    $adapterGuid = $Adapter.InterfaceGuid
    if (-not $adapterGuid) {
        $cimAdapter = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceIndex -eq $Adapter.ifIndex } | Select-Object -First 1
        if ($cimAdapter) {
            $adapterGuid = $cimAdapter.GUID
        }
    }

    if (-not $adapterGuid) { return $null }

    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
    $registryKey = Get-ChildItem -LiteralPath $classPath -ErrorAction SilentlyContinue | Where-Object {
        $properties = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $properties.NetCfgInstanceId -eq $adapterGuid
    } | Select-Object -First 1

    if ($registryKey) { return $registryKey.PSPath }
    return $null
}

function Get-MacOverride {
    param($Adapter)

    $registryPath = Get-AdapterRegistryPath -Adapter $Adapter
    if (-not $registryPath) { return $null }

    $properties = Get-ItemProperty -LiteralPath $registryPath -Name NetworkAddress -ErrorAction SilentlyContinue
    if ($properties -and $properties.NetworkAddress) {
        return $properties.NetworkAddress
    }

    return $null
}

function Show-MacOverrideDisplay {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        $script:txtMacOverrideCurrent.Text = "--"
        $script:txtMacOverrideStatus.Text = "No adapter selected"
        $script:txtMacOverride.Text = ""
        return
    }

    $script:txtMacOverrideCurrent.Text = if ($adapter.MacAddress) { $adapter.MacAddress } else { "--" }
    $override = Get-MacOverride -Adapter $adapter
    if ($override) {
        $script:txtMacOverrideStatus.Text = "Override active: $override"
        $script:txtMacOverrideStatus.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#d29922")
        $script:txtMacOverride.Text = $override
    } else {
        $script:txtMacOverrideStatus.Text = "No override"
        $script:txtMacOverrideStatus.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f0f6fc")
        $script:txtMacOverride.Text = ""
    }
}

function Invoke-AdapterRestartForMac {
    param($Adapter)

    if ($null -eq $Adapter) { return "No adapter selected." }
    if ($Adapter.Status -ne "Up") {
        return "Adapter is not active; change applies next time it is enabled."
    }

    Disable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
    Start-Sleep -Milliseconds 1200
    Enable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
    Start-Sleep -Milliseconds 1200
    return "Adapter restarted."
}

function Invoke-GenerateMacAddress {
    $script:txtMacOverride.Text = Get-RandomMacAddress
    Update-Status "Generated locally administered unicast MAC address"
}

function Invoke-MacOverride {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $cleanMac = ConvertTo-CleanMacAddress -MacAddress $script:txtMacOverride.Text
    if (-not (Test-ValidMacAddress -MacAddress $cleanMac)) {
        Show-MessageBox -Message "Enter a valid 12-character unicast MAC address." -Title "Invalid MAC Address" -Icon Error
        return
    }

    $registryPath = Get-AdapterRegistryPath -Adapter $adapter
    if (-not $registryPath) {
        Show-MessageBox -Message "Could not locate the Windows registry key for '$($adapter.Name)'." -Title "MAC Override Failed" -Icon Error
        return
    }

    Update-Status "Applying MAC override to $($adapter.Name)..."
    try {
        New-ItemProperty -LiteralPath $registryPath -Name NetworkAddress -Value $cleanMac -PropertyType String -Force -ErrorAction Stop | Out-Null
        $restartMessage = Invoke-AdapterRestartForMac -Adapter $adapter
        Update-Status "MAC override $cleanMac applied. $restartMessage" -Type Success
        Refresh-AdapterList
    } catch {
        Update-Status "MAC override failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to apply MAC override:`n$($_.Exception.Message)" -Title "MAC Override Failed" -Icon Error
    }
}

function Invoke-MacRevert {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $registryPath = Get-AdapterRegistryPath -Adapter $adapter
    if (-not $registryPath) {
        Show-MessageBox -Message "Could not locate the Windows registry key for '$($adapter.Name)'." -Title "MAC Revert Failed" -Icon Error
        return
    }

    Update-Status "Reverting MAC override on $($adapter.Name)..."
    try {
        Remove-ItemProperty -LiteralPath $registryPath -Name NetworkAddress -ErrorAction SilentlyContinue
        $restartMessage = Invoke-AdapterRestartForMac -Adapter $adapter
        Update-Status "MAC override removed. $restartMessage" -Type Success
        Refresh-AdapterList
    } catch {
        Update-Status "MAC revert failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to revert MAC override:`n$($_.Exception.Message)" -Title "MAC Revert Failed" -Icon Error
    }
}

function Get-InterfaceMetricSummary {
    param(
        $Adapter,
        [string]$AddressFamily
    )

    if ($null -eq $Adapter) { return "--" }

    $ipInterface = Get-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily $AddressFamily -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ipInterface) { return "--" }

    $mode = if ($ipInterface.AutomaticMetric -eq "Enabled") { "Auto" } else { "Manual" }
    return "$($ipInterface.InterfaceMetric) ($mode)"
}

function Show-InterfaceMetricDisplay {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        $script:txtMetricIPv4Current.Text = "--"
        $script:txtMetricIPv6Current.Text = "--"
        $script:txtInterfaceMetric.Text = "25"
        return
    }

    $script:txtMetricIPv4Current.Text = Get-InterfaceMetricSummary -Adapter $adapter -AddressFamily IPv4
    $script:txtMetricIPv6Current.Text = Get-InterfaceMetricSummary -Adapter $adapter -AddressFamily IPv6

    $ipv4 = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ipv4 -and $ipv4.InterfaceMetric) {
        $script:txtInterfaceMetric.Text = $ipv4.InterfaceMetric.ToString()
    }
}

function Test-ValidInterfaceMetric {
    param([string]$Metric)

    $value = 0
    if (-not [int]::TryParse($Metric, [ref]$value)) { return $false }
    return ($value -ge 1 -and $value -le 9999)
}

function Get-AdapterBindingPriorityPlan {
    param([string]$Mode)

    switch ($Mode) {
        "IPv4First" {
            return [pscustomobject]@{
                Mode = "IPv4First"
                IPv4Metric = 10
                IPv6Metric = 50
                Description = "IPv4 first"
            }
        }
        "IPv6First" {
            return [pscustomobject]@{
                Mode = "IPv6First"
                IPv4Metric = 50
                IPv6Metric = 10
                Description = "IPv6 first"
            }
        }
        default {
            throw "Unknown binding priority mode '$Mode'."
        }
    }
}

function Invoke-AdapterBindingPriority {
    param([string]$Mode)

    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    try {
        $plan = Get-AdapterBindingPriorityPlan -Mode $Mode
        Update-Status "Applying $($plan.Description) binding priority to $($adapter.Name)..."
        Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $plan.IPv4Metric -ErrorAction Stop
        Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -AutomaticMetric Disabled -InterfaceMetric $plan.IPv6Metric -ErrorAction Stop
        Show-InterfaceMetricDisplay
        Update-AdapterDetails
        Write-OperationLog -Action "Adapter binding priority" -Result "Succeeded" -Detail "Adapter=$($adapter.Name); Mode=$($plan.Mode); IPv4=$($plan.IPv4Metric); IPv6=$($plan.IPv6Metric)"
        Update-Status "$($plan.Description) binding priority applied to $($adapter.Name)" -Type Success
    } catch {
        Update-Status "Binding priority update failed: $($_.Exception.Message)" -Type Error
        Write-OperationLog -Action "Adapter binding priority" -Result "Failed" -Detail $_.Exception.Message
        Show-MessageBox -Message "Failed to apply adapter binding priority:`n$($_.Exception.Message)" -Title "Binding Priority Failed" -Icon Error
    }
}

function Invoke-ApplyInterfaceMetric {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $metricText = $script:txtInterfaceMetric.Text.Trim()
    if (-not (Test-ValidInterfaceMetric -Metric $metricText)) {
        Show-MessageBox -Message "Enter a metric from 1 to 9999. Lower metrics take priority." -Title "Invalid Metric" -Icon Error
        return
    }

    if (-not $script:chkMetricIPv4.IsChecked -and -not $script:chkMetricIPv6.IsChecked) {
        Show-MessageBox -Message "Choose IPv4, IPv6, or both before applying a metric." -Title "No Address Family Selected" -Icon Warning
        return
    }

    $metric = [int]$metricText
    Update-Status "Applying interface metric $metric to $($adapter.Name)..."

    try {
        if ($script:chkMetricIPv4.IsChecked) {
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $metric -ErrorAction Stop
        }
        if ($script:chkMetricIPv6.IsChecked) {
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -AutomaticMetric Disabled -InterfaceMetric $metric -ErrorAction Stop
        }

        Show-InterfaceMetricDisplay
        Update-AdapterDetails
        Update-Status "Interface metric $metric applied to $($adapter.Name)" -Type Success
    } catch {
        Update-Status "Metric update failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to apply interface metric:`n$($_.Exception.Message)" -Title "Metric Update Failed" -Icon Error
    }
}

function Invoke-AutomaticInterfaceMetric {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    if (-not $script:chkMetricIPv4.IsChecked -and -not $script:chkMetricIPv6.IsChecked) {
        Show-MessageBox -Message "Choose IPv4, IPv6, or both before restoring automatic metrics." -Title "No Address Family Selected" -Icon Warning
        return
    }

    Update-Status "Restoring automatic interface metric on $($adapter.Name)..."

    try {
        if ($script:chkMetricIPv4.IsChecked) {
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -AutomaticMetric Enabled -ErrorAction Stop
        }
        if ($script:chkMetricIPv6.IsChecked) {
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -AutomaticMetric Enabled -ErrorAction Stop
        }

        Show-InterfaceMetricDisplay
        Update-AdapterDetails
        Update-Status "Automatic interface metric restored on $($adapter.Name)" -Type Success
    } catch {
        Update-Status "Automatic metric restore failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to restore automatic metric:`n$($_.Exception.Message)" -Title "Metric Restore Failed" -Icon Error
    }
}

function Get-SubnetFromPrefix {
    param([int]$Prefix)
    $mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $Prefix))
    $bytes = [BitConverter]::GetBytes($mask)
    [Array]::Reverse($bytes)
    return "{0}.{1}.{2}.{3}" -f $bytes[0], $bytes[1], $bytes[2], $bytes[3]
}

function Get-PrefixFromSubnet {
    param([string]$Subnet)
    try {
        $ip = [System.Net.IPAddress]::Parse($Subnet)
        $bytes = $ip.GetAddressBytes()
        $binary = ""
        foreach ($b in $bytes) {
            $binary += [Convert]::ToString($b, 2).PadLeft(8, '0')
        }
        return ($binary.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    } catch {
        return 24
    }
}

# ============================================================================
# NETWORK ADAPTER FUNCTIONS
# ============================================================================
function Get-AdapterSearchText {
    param($Adapter)

    $parts = @($Adapter.Name, $Adapter.InterfaceDescription, $Adapter.InterfaceAlias, $Adapter.MediaType, $Adapter.InterfaceType)
    foreach ($propertyName in @("NdisPhysicalMedium", "PhysicalMediaType", "ComponentID", "PnPDeviceID")) {
        $property = $Adapter.PSObject.Properties[$propertyName]
        if ($property -and $property.Value) {
            $parts += $property.Value
        }
    }

    return ($parts | Where-Object { $_ }) -join " "
}

function Get-AdapterConnectionKind {
    param($Adapter)

    if ($null -eq $Adapter) { return "Unknown" }

    $text = Get-AdapterSearchText -Adapter $Adapter
    if ($text -match "Bluetooth|Personal Area Network|\bPAN\b|BthPan") {
        return "Bluetooth PAN"
    }
    if ($text -match "Cellular|WWAN|Mobile Broadband|LTE|5G|4G|MBIM|Modem|Broadband") {
        return "Cellular"
    }
    if ($text -match "Wi-Fi|WiFi|Wireless|802\.11|WLAN") {
        return "WiFi"
    }
    if ($text -match "VPN|TAP|TUN|WireGuard|OpenVPN") {
        return "VPN"
    }
    if ($text -match "Hyper-V|vEthernet|Default Switch") {
        return "Hyper-V"
    }
    if ($text -match "VMware|VMnet") {
        return "VMware"
    }
    if ($text -match "VirtualBox|VBox") {
        return "VirtualBox"
    }
    if ($text -match "Ethernet|802\.3" -or $Adapter.InterfaceType -eq 6) {
        return "Ethernet"
    }
    if ($Adapter.Virtual -eq $true) {
        return "Virtual"
    }

    return "Unknown"
}

function Test-NetForgeAdapter {
    param($Adapter)

    if ($null -eq $Adapter) { return $false }
    if ($Adapter.Virtual -eq $false) { return $true }

    $kind = Get-AdapterConnectionKind -Adapter $Adapter
    if ($kind -in @("Bluetooth PAN", "Cellular")) { return $true }
    if ($script:ShowAdvancedAdapters -and $kind -in @("VPN", "Hyper-V", "VMware", "VirtualBox", "Virtual")) { return $true }

    return $false
}

function Get-NetworkAdapters {
    try {
        $adapters = Get-NetAdapter | Where-Object { Test-NetForgeAdapter -Adapter $_ } | Sort-Object Name
        return $adapters
    } catch {
        return @()
    }
}

function Refresh-AdapterList {
    $script:lstAdapters.Items.Clear()
    $adapters = Get-NetworkAdapters

    foreach ($adapter in $adapters) {
        $status = if ($adapter.Status -eq "Up") { "[OK]" } else { "[--]" }
        $color = if ($adapter.Status -eq "Up") { "#3fb950" } else { "#6e7681" }

        $item = New-Object System.Windows.Controls.StackPanel
        $item.Orientation = "Vertical"
        $item.Tag = $adapter

        $namePanel = New-Object System.Windows.Controls.StackPanel
        $namePanel.Orientation = "Horizontal"

        $statusText = New-Object System.Windows.Controls.TextBlock
        $statusText.Text = $status
        $statusText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom($color)
        $statusText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $statusText.FontSize = 12
        $statusText.Margin = "0,0,8,0"
        $statusText.VerticalAlignment = "Center"

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $adapter.Name
        $nameText.FontSize = 13
        $nameText.FontWeight = "Medium"
        $nameText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f0f6fc")

        $namePanel.Children.Add($statusText) | Out-Null
        $namePanel.Children.Add($nameText) | Out-Null

        $descText = New-Object System.Windows.Controls.TextBlock
        $adapterKind = Get-AdapterConnectionKind -Adapter $adapter
        $descText.Text = "$adapterKind | $($adapter.InterfaceDescription)"
        $descText.FontSize = 11
        $descText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#8b949e")
        $descText.Margin = "22,4,0,0"

        $item.Children.Add($namePanel) | Out-Null
        $item.Children.Add($descText) | Out-Null

        $script:lstAdapters.Items.Add($item) | Out-Null
    }

    Update-Status "Found $($adapters.Count) network adapter(s)"
    if ($script:CompactModeEnabled) {
        Apply-CompactMode -Enabled $true
    }
}

function Get-SelectedAdapter {
    $selected = $script:lstAdapters.SelectedItem
    if ($null -eq $selected) { return $null }
    return $selected.Tag
}

function Set-IPv6ConfigurationControlState {
    if ($script:pnlIPv6StaticConfig -and $script:chkConfigureIPv6Address) {
        if ($script:chkConfigureIPv6Address.IsChecked) {
            $script:pnlIPv6StaticConfig.IsEnabled = $true
            $script:pnlIPv6StaticConfig.Opacity = 1.0
        } else {
            $script:pnlIPv6StaticConfig.IsEnabled = $false
            $script:pnlIPv6StaticConfig.Opacity = 0.6
        }
    }
}

function Update-AdapterDisplay {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        $script:txtAdapterName.Text = "Select an adapter"
        $script:txtCurrentIP.Text = "--"
        $script:txtMAC.Text = "--"
        $script:txtStatus.Text = "--"
        if ($script:chkConfigureIPv6Address) { $script:chkConfigureIPv6Address.IsChecked = $false }
        if ($script:txtIPv6Address) { $script:txtIPv6Address.Text = "" }
        if ($script:txtIPv6Prefix) { $script:txtIPv6Prefix.Text = "64" }
        if ($script:txtIPv6Gateway) { $script:txtIPv6Gateway.Text = "" }
        Set-IPv6ConfigurationControlState
        $script:statusIndicator.Fill = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#6e7681")
        Show-MacOverrideDisplay
        Show-InterfaceMetricDisplay
        return
    }

    $script:txtAdapterName.Text = $adapter.Name
    $script:txtMAC.Text = $adapter.MacAddress
    $script:txtStatus.Text = $adapter.Status

    if ($adapter.Status -eq "Up") {
        $script:statusIndicator.Fill = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#3fb950")
    } else {
        $script:statusIndicator.Fill = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f85149")
    }

    # Get IP configuration
    try {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ipConfig) {
            $script:txtCurrentIP.Text = $ipConfig.IPAddress
            $script:txtIPAddress.Text = $ipConfig.IPAddress
            $script:txtPrefix.Text = $ipConfig.PrefixLength.ToString()
            $script:txtSubnet.Text = Get-SubnetFromPrefix -Prefix $ipConfig.PrefixLength
        } else {
            $script:txtCurrentIP.Text = "Not configured"
        }

        # Get gateway
        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gateway) {
            $script:txtGateway.Text = $gateway.NextHop
        }

        # Check if DHCP
        $dhcpEnabled = (Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp -eq "Enabled"
        if ($dhcpEnabled) {
            $script:rbDHCP.IsChecked = $true
        } else {
            $script:rbStatic.IsChecked = $true
        }

        $ipv6Config = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.IPAddress -ne "::1" -and $_.IPAddress -notlike "fe80:*" } |
            Select-Object -First 1
        if ($ipv6Config) {
            $script:chkConfigureIPv6Address.IsChecked = $true
            $script:txtIPv6Address.Text = $ipv6Config.IPAddress
            $script:txtIPv6Prefix.Text = $ipv6Config.PrefixLength.ToString()
            $ipv6Gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "::/0" -ErrorAction SilentlyContinue |
                Where-Object { (-not $_.PSObject.Properties["RouteProtocol"]) -or [string]$_.RouteProtocol -eq "NetMgmt" } |
                Select-Object -First 1
            $script:txtIPv6Gateway.Text = if ($ipv6Gateway -and $ipv6Gateway.NextHop -ne "::") { $ipv6Gateway.NextHop } else { "" }
        } else {
            $script:chkConfigureIPv6Address.IsChecked = $false
            $script:txtIPv6Address.Text = ""
            $script:txtIPv6Prefix.Text = "64"
            $script:txtIPv6Gateway.Text = ""
        }
        Set-IPv6ConfigurationControlState
    } catch {
        $script:txtCurrentIP.Text = "Error"
        Write-OperationLog -Action "Update IP configuration display" -Result "Warning" -Detail $_.Exception.Message
    }

    Update-AdapterDetails
    Show-MacOverrideDisplay
    Show-InterfaceMetricDisplay
}

function Format-DhcpLeaseInfo {
    param([pscustomobject]$CimConfig)

    if ($null -eq $CimConfig) {
        return [pscustomobject]@{ ServerText = "--"; LeaseText = $null }
    }

    $server = if ($CimConfig.DHCPServer) { [string]$CimConfig.DHCPServer } else { $null }
    if ([string]::IsNullOrWhiteSpace($server)) {
        return [pscustomobject]@{ ServerText = "--"; LeaseText = $null }
    }

    $leaseObtained = $null
    $leaseExpires = $null
    if ($CimConfig.PSObject.Properties['DHCPLeaseObtained'] -and $null -ne $CimConfig.DHCPLeaseObtained) {
        try { $leaseObtained = [datetime]$CimConfig.DHCPLeaseObtained } catch { }
    }
    if ($CimConfig.PSObject.Properties['DHCPLeaseExpires'] -and $null -ne $CimConfig.DHCPLeaseExpires) {
        try { $leaseExpires = [datetime]$CimConfig.DHCPLeaseExpires } catch { }
    }

    $parts = @($server)

    if ($null -ne $leaseObtained -and $null -ne $leaseExpires) {
        $remaining = $leaseExpires - (Get-Date)
        $remainText = if ($remaining.TotalSeconds -le 0) {
            "EXPIRED"
        } elseif ($remaining.TotalHours -ge 24) {
            "{0:N0}d {1:N0}h" -f $remaining.Days, $remaining.Hours
        } elseif ($remaining.TotalMinutes -ge 60) {
            "{0:N0}h {1:N0}m" -f [Math]::Floor($remaining.TotalHours), $remaining.Minutes
        } else {
            "{0:N0}m" -f [Math]::Floor($remaining.TotalMinutes)
        }
        $parts += "Lease: $($leaseObtained.ToString('MMM d HH:mm')) - $($leaseExpires.ToString('MMM d HH:mm')) ($remainText)"
    } elseif ($null -ne $leaseExpires) {
        $parts += "Expires: $($leaseExpires.ToString('MMM d HH:mm'))"
    }

    $serverText = $parts -join "`n"
    $leaseText = if ($parts.Count -gt 1) { $parts[1] } else { $null }

    return [pscustomobject]@{ ServerText = $serverText; LeaseText = $leaseText }
}

function Update-AdapterDetails {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) { return }

    try {
        $script:txtInfoIndex.Text = $adapter.ifIndex.ToString()
        $adapterKind = Get-AdapterConnectionKind -Adapter $adapter
        $script:txtInfoType.Text = "$adapterKind ($($adapter.InterfaceType))"

        $speed = $adapter.LinkSpeed
        $script:txtInfoSpeed.Text = $speed

        $script:txtInfoMedia.Text = if ($adapter.MediaConnectionState -eq "Connected") { "Connected" } else { "Disconnected" }

        $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $script:txtInfoDHCP.Text = if ($ipInterface.Dhcp -eq "Enabled") { "Yes" } else { "No" }

        $cimConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }
        $dhcpInfo = Format-DhcpLeaseInfo -CimConfig $cimConfig
        $script:txtInfoDHCPServer.Text = $dhcpInfo.ServerText

        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $script:txtInfoDNS.Text = if ($dnsServers) { $dnsServers -join ", " } else { "--" }

        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
        $script:txtInfoGateway.Text = if ($gateway) { $gateway.NextHop } else { "--" }

        $ipv6 = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1
        $script:txtInfoIPv6.Text = if ($ipv6) { $ipv6.IPAddress } else { "--" }

        $script:txtInfoDriver.Text = $adapter.DriverDescription
        $script:txtInfoMAC.Text = $adapter.MacAddress
    } catch {
        Write-OperationLog -Action "Update adapter details" -Result "Warning" -Detail $_.Exception.Message
    }
}

# ============================================================================
# CONNECTION STATUS FUNCTIONS
# ============================================================================
function Update-ConnectionStatus {
    try {
        # Determine connection type and status
        $activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and (Test-NetForgeAdapter -Adapter $_) } | Select-Object -First 1

        if ($null -eq $activeAdapter) {
            $script:connStatusDot.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f85149")
            $script:txtConnStatus.Text = "Disconnected"
            $script:txtConnLocalIP.Text = "--"
            $script:txtConnGateway.Text = "--"
            $script:txtConnType.Text = "--"
            $script:pnlWifiInfo.Visibility = "Collapsed"
            return
        }

        $script:connStatusDot.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#3fb950")
        $script:txtConnStatus.Text = "Connected"

        # Local IP
        $localIP = Get-NetIPAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        $script:txtConnLocalIP.Text = if ($localIP) { $localIP.IPAddress } else { "--" }

        # Gateway
        $gw = Get-NetRoute -InterfaceIndex $activeAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
        $script:txtConnGateway.Text = if ($gw) { $gw.NextHop } else { "--" }

        # Connection type
        $connType = Get-AdapterConnectionKind -Adapter $activeAdapter
        $script:txtConnType.Text = $connType

        # WiFi info
        if ($connType -eq "WiFi") {
            $script:pnlWifiInfo.Visibility = "Visible"
            Update-WifiInfo
        } else {
            $script:pnlWifiInfo.Visibility = "Collapsed"
        }
    } catch {
        Write-OperationLog -Action "Update connection status" -Result "Warning" -Detail $_.Exception.Message
    }
}

function Update-WifiInfo {
    try {
        $wlanOutput = netsh wlan show interfaces 2>&1 | Out-String
        $lines = $wlanOutput -split "`n"

        $ssid = "--"
        $signal = "--"
        $channel = "--"
        $band = "--"
        $auth = "--"
        $speed = "--"

        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\s*SSID\s*:\s*(.+)$' -and $trimmed -notmatch 'BSSID') {
                $ssid = $Matches[1].Trim()
            }
            if ($trimmed -match '^\s*Signal\s*:\s*(.+)$') {
                $signal = $Matches[1].Trim()
            }
            if ($trimmed -match '^\s*Channel\s*:\s*(.+)$') {
                $channel = $Matches[1].Trim()
            }
            if ($trimmed -match '^\s*Band\s*:\s*(.+)$') {
                $band = $Matches[1].Trim()
            }
            if ($trimmed -match '^\s*Radio type\s*:\s*(.+)$') {
                $radioType = $Matches[1].Trim()
                if ($band -eq "--") {
                    if ($radioType -match '802\.11a' -or $radioType -match '802\.11ac' -or $radioType -match '802\.11ax' -or $radioType -match '802\.11n.*5') {
                        $band = "5 GHz"
                    } else {
                        $band = "2.4 GHz"
                    }
                }
            }
            if ($trimmed -match '^\s*Authentication\s*:\s*(.+)$') {
                $auth = $Matches[1].Trim()
            }
            if ($trimmed -match '^\s*Receive rate \(Mbps\)\s*:\s*(.+)$') {
                $speed = $Matches[1].Trim() + " Mbps"
            }
        }

        $script:txtWifiSSID.Text = $ssid
        $script:txtWifiSignal.Text = $signal
        $script:txtWifiChannel.Text = $channel
        $script:txtWifiBand.Text = $band
        $script:txtWifiAuth.Text = $auth
        $script:txtWifiSpeed.Text = $speed

        # Color signal strength
        $signalNum = 0
        if ($signal -match '(\d+)') { $signalNum = [int]$Matches[1] }
        if ($signalNum -ge 70) {
            $script:txtWifiSignal.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#3fb950")
        } elseif ($signalNum -ge 40) {
            $script:txtWifiSignal.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#d29922")
        } else {
            $script:txtWifiSignal.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f85149")
        }
    } catch {
        Write-OperationLog -Action "Update WiFi info" -Result "Warning" -Detail $_.Exception.Message
    }
}

function Get-WifiSignalColor {
    param([string]$Signal)

    $signalNum = 0
    if ($Signal -match '(\d+)') { $signalNum = [int]$Matches[1] }
    if ($signalNum -ge 70) { return "#3fb950" }
    if ($signalNum -ge 40) { return "#d29922" }
    return "#f85149"
}

function Get-WifiChannelBand {
    param([string]$Channel)

    $channelNumber = 0
    if (-not [int]::TryParse(([string]$Channel).Trim(), [ref]$channelNumber)) { return "--" }
    if ($channelNumber -le 14) { return "2.4 GHz" }
    if ($channelNumber -lt 180) { return "5 GHz" }
    return "6 GHz"
}

function Get-WifiChannelUtilization {
    param([object[]]$Networks)

    $channels = @{}
    foreach ($network in @($Networks)) {
        $details = @($network.BssidDetails)
        if ($details.Count -eq 0 -and $network.Channels) {
            foreach ($channel in @($network.Channels)) {
                $details += [pscustomobject]@{
                    BSSID = ""
                    Channel = [string]$channel
                    Signal = $network.Signal
                    Band = Get-WifiChannelBand -Channel $channel
                    SSID = $network.SSID
                }
            }
        }

        foreach ($detail in $details) {
            $channel = ([string]$detail.Channel).Trim()
            if ([string]::IsNullOrWhiteSpace($channel)) { continue }
            $band = if ([string]::IsNullOrWhiteSpace([string]$detail.Band)) { Get-WifiChannelBand -Channel $channel } else { [string]$detail.Band }
            $key = "$band|$channel"
            if (-not $channels.ContainsKey($key)) {
                $channels[$key] = [pscustomobject]@{
                    Channel = $channel
                    Band = $band
                    BssidCount = 0
                    StrongestSignal = 0
                    SSIDs = New-Object System.Collections.Generic.List[string]
                    BSSIDs = New-Object System.Collections.Generic.List[string]
                }
            }

            $row = $channels[$key]
            $row.BssidCount = [int]$row.BssidCount + 1
            $ssid = if ([string]::IsNullOrWhiteSpace([string]$detail.SSID)) { [string]$network.SSID } else { [string]$detail.SSID }
            if (-not [string]::IsNullOrWhiteSpace($ssid) -and -not $row.SSIDs.Contains($ssid)) { [void]$row.SSIDs.Add($ssid) }
            $bssid = [string]$detail.BSSID
            if (-not [string]::IsNullOrWhiteSpace($bssid) -and -not $row.BSSIDs.Contains($bssid)) { [void]$row.BSSIDs.Add($bssid) }
            $signalValue = 0
            if ([string]$detail.Signal -match '(\d+)') { $signalValue = [int]$Matches[1] }
            if ($signalValue -gt $row.StrongestSignal) { $row.StrongestSignal = $signalValue }
        }
    }

    $rows = @($channels.Values | Sort-Object Band, { [int]$_.Channel })
    return ,$rows
}

function Format-WifiSpectrumReport {
    param([object[]]$ChannelRows)

    $rows = @($ChannelRows)
    if ($rows.Count -eq 0) {
        return "No WiFi channel data available. Run Scan Networks to build channel utilization."
    }

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Channel utilization from visible BSSIDs") | Out-Null
    $sb.AppendLine("Channel  Band     BSSIDs  Strongest  SSIDs") | Out-Null
    $sb.AppendLine("-------  -------  ------  ---------  -----") | Out-Null
    foreach ($row in $rows) {
        $ssidText = (@($row.SSIDs) -join ", ")
        if ($ssidText.Length -gt 42) { $ssidText = $ssidText.Substring(0, 39) + "..." }
        $signal = if ($row.StrongestSignal -gt 0) { "$($row.StrongestSignal)%" } else { "--" }
        $sb.AppendLine(("{0,7}  {1,-7}  {2,6}  {3,9}  {4}" -f $row.Channel, $row.Band, $row.BssidCount, $signal, $ssidText)) | Out-Null
        if (@($row.BSSIDs).Count -gt 0) {
            $bssidText = (@($row.BSSIDs) -join ", ")
            $sb.AppendLine(("         BSSID: {0}" -f $bssidText)) | Out-Null
        }
    }

    return $sb.ToString()
}

function Get-WifiBadgeElement {
    param(
        [string]$Text,
        [string]$Color
    )

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = "4"
    $border.Padding = "6,2"
    $border.Margin = "8,0,0,0"
    $border.VerticalAlignment = "Center"
    $border.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("$Color" + "30")

    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = $Text
    $textBlock.FontSize = 10
    $textBlock.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom($Color)
    $border.Child = $textBlock

    return $border
}

function Get-WifiNetworkListItem {
    param($Network)

    $item = New-Object System.Windows.Controls.StackPanel
    $item.Orientation = "Vertical"
    $item.Tag = $Network

    $headerPanel = New-Object System.Windows.Controls.StackPanel
    $headerPanel.Orientation = "Horizontal"

    $signalText = New-Object System.Windows.Controls.TextBlock
    $signalText.Text = if ($Network.Signal) { "[$($Network.Signal)]" } else { "[--]" }
    $signalText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom((Get-WifiSignalColor -Signal $Network.Signal))
    $signalText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $signalText.FontSize = 12
    $signalText.Margin = "0,0,8,0"
    $signalText.VerticalAlignment = "Center"

    $ssidText = New-Object System.Windows.Controls.TextBlock
    $ssidText.Text = $Network.SSID
    $ssidText.FontSize = 13
    $ssidText.FontWeight = "Medium"
    $ssidText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f0f6fc")

    $authColor = if ($Network.Authentication -match "Open") { "#d29922" } else { "#58a6ff" }
    $profileColor = if ($Network.HasProfile) { "#3fb950" } else { "#8b949e" }
    $profileText = if ($Network.HasProfile) { "Saved" } else { "New" }

    $headerPanel.Children.Add($signalText) | Out-Null
    $headerPanel.Children.Add($ssidText) | Out-Null
    $headerPanel.Children.Add((Get-WifiBadgeElement -Text $Network.Authentication -Color $authColor)) | Out-Null
    $headerPanel.Children.Add((Get-WifiBadgeElement -Text $profileText -Color $profileColor)) | Out-Null

    $detailsText = New-Object System.Windows.Controls.TextBlock
    $channels = if ($Network.Channels -and $Network.Channels.Count -gt 0) { $Network.Channels -join ", " } else { "--" }
    $bands = if ($Network.Bands -and $Network.Bands.Count -gt 0) { $Network.Bands -join ", " } else { "--" }
    $detailsText.Text = "$($Network.Encryption) | $bands | Ch $channels | $($Network.BssidCount) BSSID(s)"
    $detailsText.FontSize = 11
    $detailsText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#8b949e")
    $detailsText.Margin = "22,4,0,0"

    $item.Children.Add($headerPanel) | Out-Null
    $item.Children.Add($detailsText) | Out-Null

    return $item
}

function Show-WifiActionState {
    $hasSelection = $null -ne $script:lstWifiNetworks.SelectedItem
    $script:btnWifiConnect.IsEnabled = $hasSelection -and (-not $script:WifiScanRunning)
    $script:btnWifiDisconnect.IsEnabled = -not $script:WifiScanRunning
}

function Show-WifiSelection {
    $selected = $script:lstWifiNetworks.SelectedItem
    if ($null -eq $selected) {
        $script:pnlWifiDetails.Visibility = "Collapsed"
        Show-WifiActionState
        return
    }

    $network = $selected.Tag
    $script:pnlWifiDetails.Visibility = "Visible"
    $script:txtWifiDetailSsid.Text = $network.SSID
    $script:txtWifiDetailProfile.Text = if ($network.HasProfile) { "Saved Windows profile" } else { "No saved profile" }
    $script:txtWifiDetailSecurity.Text = "$($network.Authentication) / $($network.Encryption)"
    $script:txtWifiDetailSignal.Text = $network.Signal
    $script:txtWifiDetailSignal.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom((Get-WifiSignalColor -Signal $network.Signal))

    $radio = if ($network.RadioTypes -and $network.RadioTypes.Count -gt 0) { $network.RadioTypes -join ", " } else { "--" }
    $bands = if ($network.Bands -and $network.Bands.Count -gt 0) { $network.Bands -join ", " } else { "--" }
    $channels = if ($network.Channels -and $network.Channels.Count -gt 0) { $network.Channels -join ", " } else { "--" }
    $script:txtWifiDetailRadio.Text = "$radio / $bands"
    $script:txtWifiDetailBssids.Text = "Channels $channels / $($network.BssidCount)"

    $needsPassword = (-not $network.HasProfile) -and ($network.Authentication -notmatch "Open")
    $script:txtWifiPassword.IsEnabled = $needsPassword
    if (-not $needsPassword) {
        $script:txtWifiPassword.Password = ""
    }

    Show-WifiActionState
}

function Show-WifiNetworkList {
    param(
        [object[]]$Networks,
        [string]$InterfaceName,
        [string]$Message
    )

    $script:lstWifiNetworks.Items.Clear()
    $script:WifiNetworks = @($Networks)
    $script:WifiInterfaceName = $InterfaceName

    foreach ($network in $script:WifiNetworks) {
        $script:lstWifiNetworks.Items.Add((Get-WifiNetworkListItem -Network $network)) | Out-Null
    }

    if ($script:txtWifiSpectrumOutput) {
        $script:txtWifiSpectrumOutput.Text = Format-WifiSpectrumReport -ChannelRows (Get-WifiChannelUtilization -Networks $script:WifiNetworks)
    }

    $interfaceLabel = if ($script:WifiInterfaceName) { $script:WifiInterfaceName } else { "default WiFi interface" }
    if ($script:WifiNetworks.Count -gt 0) {
        $script:txtWifiScanSummary.Text = "Found $($script:WifiNetworks.Count) network(s) on $interfaceLabel."
        Update-Status "WiFi scan found $($script:WifiNetworks.Count) network(s)" -Type Success
    } elseif ($Message) {
        $script:txtWifiScanSummary.Text = $Message
        Update-Status $Message -Type Warning
    } else {
        $script:txtWifiScanSummary.Text = "No WiFi networks found."
        Update-Status "No WiFi networks found" -Type Warning
    }

    $script:pnlWifiDetails.Visibility = "Collapsed"
    Show-WifiActionState
}

function Invoke-WifiNetworkScan {
    if ($script:WifiScanRunning) { return }

    $script:WifiScanRunning = $true
    $script:btnWifiRefresh.IsEnabled = $false
    $script:btnWifiConnect.IsEnabled = $false
    $script:btnWifiDisconnect.IsEnabled = $false
    $script:txtWifiScanSummary.Text = "Scanning nearby WiFi networks..."
    Update-Status "Scanning WiFi networks..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        function ConvertTo-NetworkObject {
            param(
                [hashtable]$Data,
                [string[]]$Profiles
            )

            $signals = @($Data.Signals | Where-Object { $_ })
            $signalValues = @()
            foreach ($signal in $signals) {
                if ($signal -match '(\d+)') { $signalValues += [int]$Matches[1] }
            }
            $bestSignal = if ($signalValues.Count -gt 0) { ($signalValues | Measure-Object -Maximum).Maximum } else { 0 }
            $signalText = if ($bestSignal -gt 0) { "$bestSignal%" } else { "--" }
            $channels = @($Data.Channels | Where-Object { $_ } | Sort-Object -Unique)
            $bands = @($Data.Bands | Where-Object { $_ } | Sort-Object -Unique)
            $radioTypes = @($Data.RadioTypes | Where-Object { $_ } | Sort-Object -Unique)
            $bssids = @($Data.Bssids | Where-Object { $_ } | Sort-Object -Unique)
            $bssidDetails = @($Data.BssidDetails | Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{
                    SSID = $Data.SSID
                    BSSID = [string]$_.BSSID
                    Signal = [string]$_.Signal
                    Channel = [string]$_.Channel
                    Band = [string]$_.Band
                    RadioType = [string]$_.RadioType
                }
            })
            $profileMatches = @($Profiles | Where-Object { $_ -eq $Data.SSID })

            [pscustomobject]@{
                SSID = $Data.SSID
                Authentication = $Data.Authentication
                Encryption = $Data.Encryption
                Signal = $signalText
                Channels = $channels
                Bands = $bands
                RadioTypes = $radioTypes
                Bssids = $bssids
                BssidDetails = $bssidDetails
                BssidCount = $bssids.Count
                HasProfile = $profileMatches.Count -gt 0
                ProfileName = if ($profileMatches.Count -gt 0) { $profileMatches[0] } else { $null }
            }
        }

        try {
            $profiles = @()
            $profileOutput = netsh wlan show profiles 2>&1 | Out-String
            foreach ($line in ($profileOutput -split "`n")) {
                if ($line -match '^\s*(All User Profile|User Profile|Group Policy Profile)\s*:\s*(.+)$') {
                    $profiles += $Matches[2].Trim()
                }
            }

            $netOutput = netsh wlan show networks mode=bssid 2>&1 | Out-String
            $netExit = $LASTEXITCODE
            $interfaceName = $null
            $networks = @()
            $current = $null
            $currentBssid = $null

            foreach ($rawLine in ($netOutput -split "`n")) {
                $line = $rawLine.Trim()
                if ($line -match '^Interface name\s*:\s*(.+)$') {
                    $interfaceName = $Matches[1].Trim()
                    continue
                }

                if ($line -match '^SSID\s+\d+\s*:\s*(.*)$') {
                    if ($null -ne $current) {
                        $networks += ConvertTo-NetworkObject -Data $current -Profiles $profiles
                    }

                    $ssid = $Matches[1].Trim()
                    if ([string]::IsNullOrWhiteSpace($ssid)) { $ssid = "<hidden network>" }
                    $current = @{
                        SSID = $ssid
                        Authentication = "--"
                        Encryption = "--"
                        Signals = @()
                        Channels = @()
                        Bands = @()
                        RadioTypes = @()
                        Bssids = @()
                        BssidDetails = @()
                    }
                    $currentBssid = $null
                    continue
                }

                if ($null -eq $current) { continue }

                if ($line -match '^Authentication\s*:\s*(.+)$') {
                    $current.Authentication = $Matches[1].Trim()
                } elseif ($line -match '^Encryption\s*:\s*(.+)$') {
                    $current.Encryption = $Matches[1].Trim()
                } elseif ($line -match '^BSSID\s+\d+\s*:\s*(.+)$') {
                    $bssid = $Matches[1].Trim()
                    $current.Bssids += $bssid
                    $currentBssid = @{
                        SSID = $current.SSID
                        BSSID = $bssid
                        Signal = ""
                        Channel = ""
                        Band = ""
                        RadioType = ""
                    }
                    $current.BssidDetails += $currentBssid
                } elseif ($line -match '^Signal\s*:\s*(.+)$') {
                    $signalValue = $Matches[1].Trim()
                    $current.Signals += $signalValue
                    if ($currentBssid) { $currentBssid.Signal = $signalValue }
                } elseif ($line -match '^Channel\s*:\s*(.+)$') {
                    $channelValue = $Matches[1].Trim()
                    $current.Channels += $channelValue
                    if ($currentBssid) { $currentBssid.Channel = $channelValue }
                } elseif ($line -match '^Band\s*:\s*(.+)$') {
                    $bandValue = $Matches[1].Trim()
                    $current.Bands += $bandValue
                    if ($currentBssid) { $currentBssid.Band = $bandValue }
                } elseif ($line -match '^Radio type\s*:\s*(.+)$') {
                    $radioValue = $Matches[1].Trim()
                    $current.RadioTypes += $radioValue
                    if ($currentBssid) { $currentBssid.RadioType = $radioValue }
                }
            }

            if ($null -ne $current) {
                $networks += ConvertTo-NetworkObject -Data $current -Profiles $profiles
            }

            $message = ""
            if ($networks.Count -eq 0) {
                $messageLines = @($netOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^Interface name\s*:' })
                if ($netExit -ne 0 -and $messageLines.Count -gt 0) {
                    $message = $messageLines[0]
                } elseif ($messageLines.Count -gt 0) {
                    $message = $messageLines[0]
                } else {
                    $message = "No WiFi networks found."
                }
            }
            ,([pscustomobject]@{
                Success = $true
                InterfaceName = $interfaceName
                Networks = @($networks)
                Message = $message
            })
        } catch {
            ,([pscustomobject]@{
                Success = $false
                InterfaceName = $null
                Networks = @()
                Message = $_.Exception.Message
            })
        }
    })

    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $result = $ps.EndInvoke($handle) | Select-Object -First 1
                if ($result.Success) {
                    Show-WifiNetworkList -Networks $result.Networks -InterfaceName $result.InterfaceName -Message $result.Message
                } else {
                    Show-WifiNetworkList -Networks @() -InterfaceName $null -Message "WiFi scan failed: $($result.Message)"
                }
            } catch {
                Show-WifiNetworkList -Networks @() -InterfaceName $null -Message "WiFi scan failed: $($_.Exception.Message)"
            }

            $script:WifiScanRunning = $false
            $script:btnWifiRefresh.IsEnabled = $true
            Show-WifiActionState
            $ps.Dispose()
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

function Invoke-WifiConnect {
    $selected = $script:lstWifiNetworks.SelectedItem
    if ($null -eq $selected) {
        Show-MessageBox -Message "Please select a WiFi network first." -Title "No Network Selected" -Icon Warning
        return
    }

    $network = $selected.Tag
    if ($network.SSID -eq "<hidden network>") {
        Show-MessageBox -Message "Hidden networks cannot be connected from scan results because the SSID is not advertised." -Title "Hidden Network" -Icon Warning
        return
    }

    $wifiKey = $script:txtWifiPassword.Password
    if ((-not $network.HasProfile) -and ($network.Authentication -notmatch "Open") -and [string]::IsNullOrWhiteSpace($wifiKey)) {
        Show-MessageBox -Message "Enter the WiFi password or choose a network that already has a saved Windows profile." -Title "Password Required" -Icon Warning
        return
    }

    $script:btnWifiConnect.IsEnabled = $false
    $script:btnWifiRefresh.IsEnabled = $false
    Update-Status "Connecting to WiFi network '$($network.SSID)'..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param($ssid, $profileName, $hasProfile, $authentication, $encryption, $wifiKey, $interfaceName)

        function ConvertTo-XmlText {
            param([string]$Text)
            return [System.Security.SecurityElement]::Escape($Text)
        }

        function Get-WlanSecurityProfile {
            param(
                [string]$Authentication,
                [string]$Encryption,
                [string]$KeyMaterial
            )

            if ($Authentication -match "Open") {
                return @{
                    Authentication = "open"
                    Encryption = "none"
                    SharedKey = ""
                }
            }

            if ($Authentication -match "WEP") {
                throw "WEP profile generation is not supported. Import a saved Windows WLAN profile first."
            }

            $authValue = "WPA2PSK"
            if ($Authentication -match "WPA3") {
                $authValue = "WPA3SAE"
            } elseif ($Authentication -match "WPA2") {
                $authValue = "WPA2PSK"
            } elseif ($Authentication -match "WPA") {
                $authValue = "WPAPSK"
            }

            $encryptionValue = "AES"
            if ($Encryption -match "TKIP") {
                $encryptionValue = "TKIP"
            } elseif ($Encryption -match "none") {
                $encryptionValue = "none"
            }

            return @{
                Authentication = $authValue
                Encryption = $encryptionValue
                SharedKey = @"
                <sharedKey>
                    <keyType>passPhrase</keyType>
                    <protected>false</protected>
                    <keyMaterial>$(ConvertTo-XmlText $KeyMaterial)</keyMaterial>
                </sharedKey>
"@
            }
        }

        function Get-WlanProfileXml {
            param(
                [string]$Ssid,
                [string]$Authentication,
                [string]$Encryption,
                [string]$KeyMaterial
            )

            $security = Get-WlanSecurityProfile -Authentication $Authentication -Encryption $Encryption -KeyMaterial $KeyMaterial
            $escapedSsid = ConvertTo-XmlText $Ssid
            return @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$escapedSsid</name>
    <SSIDConfig>
        <SSID>
            <name>$escapedSsid</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>manual</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$($security.Authentication)</authentication>
                <encryption>$($security.Encryption)</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
$($security.SharedKey)
        </security>
    </MSM>
</WLANProfile>
"@
        }

        try {
            $targetProfile = if ($profileName) { $profileName } else { $ssid }
            $output = @()

            if (-not $hasProfile) {
                $xml = Get-WlanProfileXml -Ssid $ssid -Authentication $authentication -Encryption $encryption -KeyMaterial $wifiKey
                $tempFile = Join-Path $env:TEMP ("NetForge_WiFi_{0}.xml" -f ([guid]::NewGuid().ToString("N")))
                Set-Content -LiteralPath $tempFile -Value $xml -Encoding UTF8

                $addArgs = @("wlan", "add", "profile", "filename=$tempFile", "user=current")
                if ($interfaceName) { $addArgs += "interface=$interfaceName" }
                $output += netsh @addArgs 2>&1
                $addExit = $LASTEXITCODE
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue

                if ($addExit -ne 0) {
                    throw ($output | Out-String)
                }
            }

            $connectArgs = @("wlan", "connect", "name=$targetProfile", "ssid=$ssid")
            if ($interfaceName) { $connectArgs += "interface=$interfaceName" }
            $output += netsh @connectArgs 2>&1
            $connectExit = $LASTEXITCODE
            $outputText = $output | Out-String

            if ($connectExit -ne 0 -or $outputText -match "failed|error|There is no profile") {
                throw $outputText
            }

            ,([pscustomobject]@{
                Success = $true
                Message = "Connection request sent for '$ssid'."
                Output = $outputText
            })
        } catch {
            ,([pscustomobject]@{
                Success = $false
                Message = $_.Exception.Message
                Output = ""
            })
        }
    }).AddArgument($network.SSID).AddArgument($network.ProfileName).AddArgument([bool]$network.HasProfile).AddArgument($network.Authentication).AddArgument($network.Encryption).AddArgument($wifiKey).AddArgument($script:WifiInterfaceName)

    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $result = $ps.EndInvoke($handle) | Select-Object -First 1
                if ($result.Success) {
                    $script:txtWifiPassword.Password = ""
                    Update-Status $result.Message -Type Success
                    Update-ConnectionStatus
                    Invoke-WifiNetworkScan
                } else {
                    Update-Status "WiFi connect failed: $($result.Message)" -Type Error
                    Show-MessageBox -Message "Failed to connect to WiFi network:`n$($result.Message)" -Title "WiFi Connect Failed" -Icon Error
                }
            } catch {
                Update-Status "WiFi connect failed: $($_.Exception.Message)" -Type Error
            }

            $script:btnWifiRefresh.IsEnabled = $true
            Show-WifiActionState
            $ps.Dispose()
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

function Invoke-WifiDisconnect {
    $script:btnWifiDisconnect.IsEnabled = $false
    Update-Status "Disconnecting WiFi..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param($interfaceName)

        try {
            $netshArgs = @("wlan", "disconnect")
            if ($interfaceName) { $netshArgs += "interface=$interfaceName" }
            $output = netsh @netshArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0 -or $output -match "failed|error") {
                throw $output
            }

            ,([pscustomobject]@{
                Success = $true
                Message = "WiFi disconnect request sent."
            })
        } catch {
            ,([pscustomobject]@{
                Success = $false
                Message = $_.Exception.Message
            })
        }
    }).AddArgument($script:WifiInterfaceName)

    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $result = $ps.EndInvoke($handle) | Select-Object -First 1
                if ($result.Success) {
                    Update-Status $result.Message -Type Success
                    Update-ConnectionStatus
                    Invoke-WifiNetworkScan
                } else {
                    Update-Status "WiFi disconnect failed: $($result.Message)" -Type Error
                    Show-MessageBox -Message "Failed to disconnect WiFi:`n$($result.Message)" -Title "WiFi Disconnect Failed" -Icon Error
                }
            } catch {
                Update-Status "WiFi disconnect failed: $($_.Exception.Message)" -Type Error
            }

            Show-WifiActionState
            $ps.Dispose()
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

function Update-PublicIP {
    if (-not $script:PublicIpLookupEnabled) {
        $script:CachedPublicIP = $null
        if ($script:txtConnPublicIP) {
            $script:txtConnPublicIP.Text = "Disabled"
        }
        Set-EndpointPolicyStatus -Message "Public IP lookup is disabled. No public-IP endpoint contacted."
        Write-OperationLog -Action "PublicIPLookup" -Result "Skipped" -Detail "Public IP lookup disabled by endpoint policy."
        return
    }

    $endpointList = @(Get-PublicIpEndpointList | Where-Object { Test-HttpsEndpointUri -Uri $_ })
    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param(
            [string[]]$EndpointList,
            [string]$AppVersion
        )

        $lastEndpoint = ""
        $lastError = ""
        foreach ($endpoint in $EndpointList) {
            $lastEndpoint = $endpoint
            $wc = $null
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "NetForge/$AppVersion")
                $ip = $wc.DownloadString($endpoint).Trim()
                return [pscustomobject]@{
                    Success = $true
                    IP = $ip
                    Endpoint = $endpoint
                    Error = ""
                }
            } catch {
                $lastError = $_.Exception.Message
            } finally {
                if ($wc) { $wc.Dispose() }
            }
        }

        return [pscustomobject]@{
            Success = $false
            IP = "Error"
            Endpoint = $lastEndpoint
            Error = $lastError
        }
    }).AddArgument($endpointList).AddArgument($script:AppVersion)

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $result = $ps.EndInvoke($handle)
                if ($result -and $result.Count -gt 0) {
                    $info = $result[0]
                    if ($info.Success) {
                        $script:CachedPublicIP = $info.IP
                        $script:txtConnPublicIP.Text = $info.IP
                        Write-OperationLog -Action "PublicIPLookup" -Result "Success" -Detail "Endpoint=$($info.Endpoint)"
                        Set-EndpointPolicyStatus -Message "Last public-IP endpoint: $($info.Endpoint)."
                    } else {
                        $script:txtConnPublicIP.Text = "Error"
                        Write-OperationLog -Action "PublicIPLookup" -Result "Error" -Detail "Endpoint=$($info.Endpoint); $($info.Error)"
                        Set-EndpointPolicyStatus -Message "Public-IP lookup failed. Last endpoint: $($info.Endpoint)."
                    }
                }
            } catch {
                $script:txtConnPublicIP.Text = "Error"
                Write-OperationLog -Action "PublicIPLookup" -Result "Error" -Detail $_.Exception.Message
            }
            $ps.Dispose()
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

# ============================================================================
# PING / LATENCY MONITOR FUNCTIONS
# ============================================================================
function Invoke-DiagPingTest {
    $target = $script:txtDiagPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    $script:btnDiagPing.IsEnabled = $false
    $script:txtPingLog.Text = "Pinging $target with 10 requests...`n"
    $script:pnlPingStats.Visibility = "Collapsed"
    Update-Status "Running ping test to $target..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param($t)
        $results = @()
        $lost = 0
        for ($i = 0; $i -lt 10; $i++) {
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send($t, 3000)
                if ($reply.Status -eq 'Success') {
                    $results += $reply.RoundtripTime
                } else {
                    $lost++
                    $results += -1
                }
                $ping.Dispose()
            } catch {
                $lost++
                $results += -1
            }
        }
        return @{
            Results = $results
            Lost = $lost
        }
    }).AddArgument($target)

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $data = $ps.EndInvoke($handle)
                if ($data -and $data.Count -gt 0) {
                    $info = $data[0]
                    $allResults = $info.Results
                    $lost = $info.Lost
                    $successful = $allResults | Where-Object { $_ -ge 0 }

                    $sb = New-Object System.Text.StringBuilder
                    $sb.AppendLine("Ping results for $target (10 pings):") | Out-Null
                    $sb.AppendLine("=" * 40) | Out-Null
                    $seq = 0
                    foreach ($r in $allResults) {
                        $seq++
                        if ($r -ge 0) {
                            $sb.AppendLine("  Seq $seq : ${r}ms") | Out-Null
                        } else {
                            $sb.AppendLine("  Seq $seq : Request timed out") | Out-Null
                        }
                    }
                    $script:txtPingLog.Text = $sb.ToString()

                    $script:pnlPingStats.Visibility = "Visible"
                    if ($successful -and @($successful).Count -gt 0) {
                        $successArr = @($successful)
                        $minVal = ($successArr | Measure-Object -Minimum).Minimum
                        $maxVal = ($successArr | Measure-Object -Maximum).Maximum
                        $avgVal = [math]::Round(($successArr | Measure-Object -Average).Average, 1)
                        $script:txtPingMin.Text = $minVal.ToString()
                        $script:txtPingAvg.Text = $avgVal.ToString()
                        $script:txtPingMax.Text = $maxVal.ToString()
                    } else {
                        $script:txtPingMin.Text = "--"
                        $script:txtPingAvg.Text = "--"
                        $script:txtPingMax.Text = "--"
                    }
                    $lossPercent = [math]::Round(($lost / 10) * 100, 0)
                    $script:txtPingLoss.Text = $lossPercent.ToString()
                }
            } catch {
                $script:txtPingLog.Text = "Error running ping test."
            }
            $ps.Dispose()
            $script:btnDiagPing.IsEnabled = $true
            Update-Status "Ping test complete"
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

function Resolve-LatencyHistogramDuration {
    param(
        [string]$Value,
        [int]$DefaultSeconds = 30,
        [int]$MinSeconds = 5,
        [int]$MaxSeconds = 300
    )

    $seconds = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$seconds)) {
        return [pscustomobject]@{
            IsValid = $false
            Seconds = $DefaultSeconds
            Message = "Enter a duration between $MinSeconds and $MaxSeconds seconds."
        }
    }

    if ($seconds -lt $MinSeconds -or $seconds -gt $MaxSeconds) {
        return [pscustomobject]@{
            IsValid = $false
            Seconds = $DefaultSeconds
            Message = "Duration must be between $MinSeconds and $MaxSeconds seconds."
        }
    }

    return [pscustomobject]@{
        IsValid = $true
        Seconds = $seconds
        Message = ""
    }
}

function Get-LatencyPercentile {
    param(
        [int[]]$Values,
        [double]$Percentile
    )

    $items = @($Values | Where-Object { $_ -ge 0 } | Sort-Object)
    if ($items.Count -eq 0) { return $null }

    $rank = [int][Math]::Ceiling(($Percentile / 100) * $items.Count)
    $index = [Math]::Max(0, [Math]::Min(($items.Count - 1), ($rank - 1)))
    return [int]$items[$index]
}

function Get-LatencyHistogramBucketDefinitions {
    return @(
        [pscustomobject]@{ Label = "0-19 ms"; Min = 0; Max = 19 },
        [pscustomobject]@{ Label = "20-49 ms"; Min = 20; Max = 49 },
        [pscustomobject]@{ Label = "50-99 ms"; Min = 50; Max = 99 },
        [pscustomobject]@{ Label = "100-199 ms"; Min = 100; Max = 199 },
        [pscustomobject]@{ Label = "200-499 ms"; Min = 200; Max = 499 },
        [pscustomobject]@{ Label = "500+ ms"; Min = 500; Max = [int]::MaxValue }
    )
}

function New-LatencyHistogramBucket {
    param(
        [string]$Label,
        [int]$Count,
        [int]$Total
    )

    $percent = 0
    if ($Total -gt 0) {
        $percent = [math]::Round(($Count / $Total) * 100, 1)
    }

    $barLength = 0
    if ($Count -gt 0) {
        $barLength = [Math]::Max(1, [Math]::Min(24, [int][Math]::Round($percent / 4)))
    }

    return [pscustomobject]@{
        Label = $Label
        Count = $Count
        Percent = $percent
        Bar = ("#" * $barLength)
    }
}

function Get-LatencyHistogramSummary {
    param(
        [object[]]$Samples,
        [string]$Target = "",
        [int]$DurationSeconds = 0
    )

    $sampleList = @($Samples)
    $latencies = New-Object System.Collections.Generic.List[int]
    $lossCount = 0

    foreach ($sample in $sampleList) {
        $success = $false
        if ($sample -and $sample.PSObject.Properties["Success"]) {
            $success = [bool]$sample.Success
        }

        $latency = -1
        if ($sample -and $sample.PSObject.Properties["LatencyMs"]) {
            [void][int]::TryParse(([string]$sample.LatencyMs), [ref]$latency)
        }

        if ($success -and $latency -ge 0) {
            [void]$latencies.Add($latency)
        } else {
            $lossCount++
        }
    }

    $total = $sampleList.Count
    $successCount = $latencies.Count
    $lossPercent = 0
    if ($total -gt 0) {
        $lossPercent = [math]::Round(($lossCount / $total) * 100, 1)
    }

    $latencyValues = @($latencies.ToArray())
    $minMs = $null
    $avgMs = $null
    $maxMs = $null
    if ($successCount -gt 0) {
        $minMs = [int](($latencyValues | Measure-Object -Minimum).Minimum)
        $maxMs = [int](($latencyValues | Measure-Object -Maximum).Maximum)
        $avgMs = [math]::Round((($latencyValues | Measure-Object -Average).Average), 1)
    }

    $buckets = @()
    foreach ($definition in Get-LatencyHistogramBucketDefinitions) {
        $count = @($latencyValues | Where-Object { $_ -ge $definition.Min -and $_ -le $definition.Max }).Count
        $buckets += New-LatencyHistogramBucket -Label $definition.Label -Count $count -Total $total
    }
    $buckets += New-LatencyHistogramBucket -Label "Timeout/loss" -Count $lossCount -Total $total

    return [pscustomobject]@{
        Target = $Target
        DurationSeconds = $DurationSeconds
        SampleCount = $total
        SuccessCount = $successCount
        LossCount = $lossCount
        LossPercent = $lossPercent
        MinMs = $minMs
        AvgMs = $avgMs
        MaxMs = $maxMs
        P50Ms = Get-LatencyPercentile -Values $latencyValues -Percentile 50
        P95Ms = Get-LatencyPercentile -Values $latencyValues -Percentile 95
        Buckets = $buckets
    }
}

function Format-LatencyHistogramValue {
    param([object]$Value)

    if ($null -eq $Value) { return "--" }
    return "$Value ms"
}

function Format-LatencyHistogramReport {
    param([object]$Summary)

    if ($null -eq $Summary) {
        return "No latency histogram data available."
    }

    $target = if ([string]::IsNullOrWhiteSpace([string]$Summary.Target)) { "target" } else { [string]$Summary.Target }
    $duration = [int]$Summary.DurationSeconds
    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Latency histogram for $target over ${duration}s") | Out-Null
    $sb.AppendLine("=" * 56) | Out-Null
    $sb.AppendLine(("Samples: {0} | Replies: {1} | Loss: {2} ({3}%)" -f $Summary.SampleCount, $Summary.SuccessCount, $Summary.LossCount, $Summary.LossPercent)) | Out-Null
    $sb.AppendLine(("Min/Avg/Max: {0} / {1} / {2}" -f (Format-LatencyHistogramValue $Summary.MinMs), (Format-LatencyHistogramValue $Summary.AvgMs), (Format-LatencyHistogramValue $Summary.MaxMs))) | Out-Null
    $sb.AppendLine(("P50/P95: {0} / {1}" -f (Format-LatencyHistogramValue $Summary.P50Ms), (Format-LatencyHistogramValue $Summary.P95Ms))) | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("Bucket        Count   Percent  Distribution") | Out-Null
    $sb.AppendLine("------------  ------  -------  ------------------------") | Out-Null
    foreach ($bucket in @($Summary.Buckets)) {
        $sb.AppendLine(("{0,-12}  {1,6}  {2,6}%  {3}" -f $bucket.Label, $bucket.Count, $bucket.Percent, $bucket.Bar)) | Out-Null
    }

    return $sb.ToString()
}

function Invoke-LatencyHistogram {
    if ($script:LatencyHistogramRunning) { return }

    $target = $script:txtDiagPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    $duration = Resolve-LatencyHistogramDuration -Value $script:txtLatencyHistogramSeconds.Text
    if (-not $duration.IsValid) {
        Show-MessageBox -Message $duration.Message -Title "Invalid Duration" -Icon Warning
        Update-Status $duration.Message -Type Warning
        return
    }

    if ($script:ContinuousPingRunning) {
        Toggle-ContinuousPing
    }

    $script:LatencyHistogramRunning = $true
    $script:btnLatencyHistogram.IsEnabled = $false
    $script:btnLatencyHistogram.Content = Get-UiString -Key "button.latencyHistogram.running" -DefaultValue "Running..."
    $script:pnlPingStats.Visibility = "Collapsed"
    $script:txtPingLog.Inlines.Clear()
    $script:txtPingLog.Text = "Building latency histogram for $target over $($duration.Seconds) seconds..."
    Update-Status "Running latency histogram to $target for $($duration.Seconds) seconds..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param(
            [string]$Target,
            [int]$Seconds
        )

        $samples = @()
        for ($i = 1; $i -le $Seconds; $i++) {
            $ping = $null
            $started = Get-Date
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send($Target, 1000)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $samples += [pscustomobject]@{
                        Sequence = $i
                        Success = $true
                        LatencyMs = [int]$reply.RoundtripTime
                        Status = $reply.Status.ToString()
                    }
                } else {
                    $samples += [pscustomobject]@{
                        Sequence = $i
                        Success = $false
                        LatencyMs = -1
                        Status = $reply.Status.ToString()
                    }
                }
            } catch {
                $samples += [pscustomobject]@{
                    Sequence = $i
                    Success = $false
                    LatencyMs = -1
                    Status = $_.Exception.Message
                }
            } finally {
                if ($ping) { $ping.Dispose() }
            }

            $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
            $remainingMs = 1000 - $elapsed
            if ($i -lt $Seconds -and $remainingMs -gt 0) {
                Start-Sleep -Milliseconds $remainingMs
            }
        }

        return $samples
    }).AddArgument($target).AddArgument($duration.Seconds)

    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $samples = @($ps.EndInvoke($handle))
                $summary = Get-LatencyHistogramSummary -Samples $samples -Target $target -DurationSeconds $duration.Seconds
                $script:txtPingLog.Text = Format-LatencyHistogramReport -Summary $summary
                $script:pnlPingStats.Visibility = "Visible"
                $script:txtPingMin.Text = if ($null -ne $summary.MinMs) { $summary.MinMs.ToString() } else { "--" }
                $script:txtPingAvg.Text = if ($null -ne $summary.AvgMs) { $summary.AvgMs.ToString() } else { "--" }
                $script:txtPingMax.Text = if ($null -ne $summary.MaxMs) { $summary.MaxMs.ToString() } else { "--" }
                $script:txtPingLoss.Text = $summary.LossPercent.ToString()
                Write-OperationLog -Action "LatencyHistogram" -Result "Complete" -Detail "Target=$target; Duration=$($duration.Seconds); Samples=$($summary.SampleCount); Loss=$($summary.LossPercent)%"
                Update-Status "Latency histogram complete for $target" -Type Success
                $script:svPingLog.ScrollToEnd()
            } catch {
                $script:txtPingLog.Text = "Error running latency histogram: $($_.Exception.Message)"
                Write-OperationLog -Action "LatencyHistogram" -Result "Error" -Detail $_.Exception.Message
                Update-Status "Latency histogram failed" -Type Error
            }

            $script:LatencyHistogramRunning = $false
            $script:btnLatencyHistogram.IsEnabled = $true
            $script:btnLatencyHistogram.Content = Get-UiString -Key "button.latencyHistogram.idle" -DefaultValue "Latency Histogram"
            $ps.Dispose()
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

function Toggle-ContinuousPing {
    if ($script:ContinuousPingRunning) {
        # Stop continuous ping
        $script:ContinuousPingRunning = $false
        $script:btnContinuousPing.Content = Get-UiString -Key "button.continuousPing.start" -DefaultValue "Start Continuous Ping"
        if ($script:ContinuousPingPS) {
            try {
                $script:ContinuousPingPS.Stop()
                $script:ContinuousPingPS.Dispose()
            } catch {
                Write-OperationLog -Action "Stop continuous ping" -Result "Warning" -Detail $_.Exception.Message
            }
            $script:ContinuousPingPS = $null
        }
        Update-Status "Continuous ping stopped"
        return
    }

    $target = $script:txtDiagPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    $script:ContinuousPingRunning = $true
    $script:btnContinuousPing.Content = Get-UiString -Key "button.continuousPing.stop" -DefaultValue "Stop Continuous Ping"
    $script:txtPingLog.Text = "Continuous ping to $target started...`n"
    $script:txtPingLog.Inlines.Clear()
    Update-Status "Continuous ping running to $target..."

    $script:PingCounter = 0

    $pingTimer = New-Object System.Windows.Threading.DispatcherTimer
    $pingTimer.Interval = [TimeSpan]::FromSeconds(2)
    $pingTimer.Tag = $target

    $pingTimer.Add_Tick({
        if (-not $script:ContinuousPingRunning) {
            $pingTimer.Stop()
            return
        }

        $t = $pingTimer.Tag
        $ps = [PowerShell]::Create()
        $ps.AddScript({
            param($target)
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send($target, 3000)
                $ping.Dispose()
                if ($reply.Status -eq 'Success') {
                    return @{ Time = $reply.RoundtripTime; Status = "OK" }
                } else {
                    return @{ Time = -1; Status = $reply.Status.ToString() }
                }
            } catch {
                return @{ Time = -1; Status = "Error" }
            }
        }).AddArgument($t)

        $handle = $ps.BeginInvoke()

        $resultTimer = New-Object System.Windows.Threading.DispatcherTimer
        $resultTimer.Interval = [TimeSpan]::FromMilliseconds(200)
        $resultTimer.Add_Tick({
            if ($handle.IsCompleted) {
                try {
                    $data = $ps.EndInvoke($handle)
                    if ($data -and $data.Count -gt 0) {
                        $info = $data[0]
                        $script:PingCounter++
                        $ts = Get-Date -Format "HH:mm:ss"

                        if ($info.Time -ge 0) {
                            $ms = $info.Time
                            $color = "#3fb950"
                            if ($ms -gt 100) { $color = "#f85149" }
                            elseif ($ms -gt 50) { $color = "#d29922" }

                            $run = New-Object System.Windows.Documents.Run
                            $run.Text = "[$ts] #$($script:PingCounter) Reply from $t : ${ms}ms`n"
                            $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom($color)
                        } else {
                            $run = New-Object System.Windows.Documents.Run
                            $run.Text = "[$ts] #$($script:PingCounter) Request timed out ($($info.Status))`n"
                            $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f85149")
                        }

                        # Convert TextBlock to use Inlines for color
                        $script:txtPingLog.Inlines.Add($run)

                        # Keep only last 100 lines
                        while ($script:txtPingLog.Inlines.Count -gt 100) {
                            $script:txtPingLog.Inlines.Remove($script:txtPingLog.Inlines.FirstInline)
                        }

                        # Auto-scroll
                        $script:svPingLog.ScrollToEnd()
                    }
                } catch {
                    Write-OperationLog -Action "Continuous ping result" -Result "Warning" -Detail $_.Exception.Message
                }
                $ps.Dispose()
                $resultTimer.Stop()
            }
        }.GetNewClosure())
        $resultTimer.Start()
    }.GetNewClosure())
    $pingTimer.Start()

    # Store reference so we can stop
    $script:ContinuousPingTimer = $pingTimer
}

# ============================================================================
# SPEED TEST FUNCTION
# ============================================================================
function Invoke-SpeedTest {
    if ($script:SpeedTestRunning) { return }
    if (-not $script:ExternalSpeedTestEnabled) {
        $script:txtSpeedDown.Text = "--"
        $script:txtSpeedSize.Text = "--"
        $script:txtSpeedTime.Text = "--"
        Set-EndpointPolicyStatus -Message "External speed test downloads are disabled. No speed-test endpoint contacted."
        Write-OperationLog -Action "SpeedTest" -Result "Skipped" -Detail "External speed test downloads disabled by endpoint policy."
        Update-Status "External speed test downloads disabled" -Type Warning
        return
    }

    $endpoint = Resolve-SpeedTestEndpoint -Endpoint $script:SpeedTestEndpoint
    if (-not (Test-HttpsEndpointUri -Uri $endpoint.Url)) {
        Update-Status "Speed test endpoint must use HTTPS" -Type Error
        Set-EndpointPolicyStatus -Message "Speed test endpoint rejected because it is not HTTPS."
        Write-OperationLog -Action "SpeedTest" -Result "Rejected" -Detail "Endpoint=$($endpoint.Url)"
        return
    }

    $script:SpeedTestRunning = $true
    $script:btnSpeedTest.IsEnabled = $false
    $script:btnSpeedTest.Content = Get-UiString -Key "button.speedTest.running" -DefaultValue "Testing..."
    Update-Status "Running speed test..."
    Set-EndpointPolicyStatus -Message "Last speed-test endpoint: $($endpoint.Url)."
    Write-OperationLog -Action "SpeedTestEndpoint" -Result "Contact" -Detail "Endpoint=$($endpoint.Url)"

    $script:txtSpeedDown.Text = "..."
    $script:txtSpeedSize.Text = "..."
    $script:txtSpeedTime.Text = "..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param(
            [string]$Url,
            [string]$AppVersion
        )

        $wc = $null
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "NetForge/$AppVersion")

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $data = $wc.DownloadData($Url)
            $sw.Stop()

            $sizeBytes = $data.Length
            $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
            $elapsed = $sw.Elapsed.TotalSeconds
            $speedMbps = [math]::Round(($sizeBytes * 8) / ($elapsed * 1000000), 2)

            return [pscustomobject]@{
                SpeedMbps = $speedMbps
                SizeMB = $sizeMB
                Seconds = [math]::Round($elapsed, 2)
                Success = $true
                Endpoint = $Url
                Error = ""
            }
        } catch {
            return [pscustomobject]@{
                Success = $false
                Error = $_.Exception.Message
                Endpoint = $Url
            }
        } finally {
            if ($wc) { $wc.Dispose() }
        }
    }).AddArgument($endpoint.Url).AddArgument($script:AppVersion)

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $data = $ps.EndInvoke($handle)
                if ($data -and $data.Count -gt 0) {
                    $info = $data[0]
                    if ($info.Success) {
                        $script:txtSpeedDown.Text = $info.SpeedMbps.ToString()
                        $script:txtSpeedSize.Text = $info.SizeMB.ToString()
                        $script:txtSpeedTime.Text = $info.Seconds.ToString()
                        Write-OperationLog -Action "SpeedTest" -Result "Success" -Detail "Endpoint=$($info.Endpoint); Mbps=$($info.SpeedMbps); SizeMB=$($info.SizeMB); Seconds=$($info.Seconds)"
                        Update-Status ("Speed test complete: " + $info.SpeedMbps.ToString() + " Mbps") -Type Success
                    } else {
                        $script:txtSpeedDown.Text = "ERR"
                        $script:txtSpeedSize.Text = "--"
                        $script:txtSpeedTime.Text = "--"
                        Write-OperationLog -Action "SpeedTest" -Result "Error" -Detail "Endpoint=$($info.Endpoint); $($info.Error)"
                        Update-Status "Speed test failed" -Type Error
                    }
                }
            } catch {
                $script:txtSpeedDown.Text = "ERR"
                Write-OperationLog -Action "SpeedTest" -Result "Error" -Detail $_.Exception.Message
                Update-Status "Speed test error" -Type Error
            }
            $ps.Dispose()
            $script:SpeedTestRunning = $false
            $script:btnSpeedTest.IsEnabled = $true
            $script:btnSpeedTest.Content = Get-UiString -Key "button.speedTest.idle" -DefaultValue "Speed Test"
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

# ============================================================================
# DNS LOOKUP FUNCTION
# ============================================================================
function Invoke-DnsLookup {
    $domain = $script:txtDnsLookupDomain.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($domain)) {
        Show-MessageBox -Message "Please enter a domain name." -Title "No Domain" -Icon Warning
        return
    }

    $script:btnDnsLookup.IsEnabled = $false
    $script:txtDnsLookupOutput.Text = "Resolving $domain ..."
    Update-Status "DNS lookup for $domain..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param($d)
        $sb = New-Object System.Text.StringBuilder

        try {
            # Get current DNS servers
            $dnsConfig = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -First 1
            $dnsServer = if ($dnsConfig) { $dnsConfig.ServerAddresses -join ", " } else { "System default" }

            $sb.AppendLine("DNS Lookup: $d") | Out-Null
            $sb.AppendLine("=" * 40) | Out-Null
            $sb.AppendLine("DNS Server: $dnsServer") | Out-Null
            $sb.AppendLine("") | Out-Null

            $results = [System.Net.Dns]::GetHostAddresses($d)

            if ($results.Count -gt 0) {
                $sb.AppendLine("Resolved addresses:") | Out-Null
                foreach ($addr in $results) {
                    $type = if ($addr.AddressFamily -eq 'InterNetwork') { "A (IPv4)" } else { "AAAA (IPv6)" }
                    $sb.AppendLine("  $type : $($addr.IPAddressToString)") | Out-Null
                }
            } else {
                $sb.AppendLine("No addresses found.") | Out-Null
            }

            # Also try to get hostname info
            try {
                $hostEntry = [System.Net.Dns]::GetHostEntry($d)
                if ($hostEntry.HostName -ne $d) {
                    $sb.AppendLine("") | Out-Null
                    $sb.AppendLine("Canonical name: $($hostEntry.HostName)") | Out-Null
                }
                if ($hostEntry.Aliases.Count -gt 0) {
                    $sb.AppendLine("Aliases: $($hostEntry.Aliases -join ', ')") | Out-Null
                }
            } catch {
                $sb.AppendLine("Canonical lookup failed: $($_.Exception.Message)") | Out-Null
            }

        } catch {
            $sb.AppendLine("DNS lookup failed: $($_.Exception.Message)") | Out-Null
        }

        return $sb.ToString()
    }).AddArgument($domain)

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $result = $ps.EndInvoke($handle)
                if ($result -and $result.Count -gt 0) {
                    $script:txtDnsLookupOutput.Text = $result[0]
                }
            } catch {
                $script:txtDnsLookupOutput.Text = "Error performing DNS lookup."
            }
            $ps.Dispose()
            $script:btnDnsLookup.IsEnabled = $true
            Update-Status "DNS lookup complete"
            $timer.Stop()
        }
    }.GetNewClosure())
    $timer.Start()
}

# ============================================================================
# RELEASE CHECK FUNCTIONS
# ============================================================================
function Compare-VersionStrings {
    param(
        [string]$Current,
        [string]$Latest
    )

    if ([string]::IsNullOrWhiteSpace($Current) -or [string]::IsNullOrWhiteSpace($Latest)) {
        return [pscustomobject]@{ Result = "Unknown"; Message = "Version comparison requires both current and latest values." }
    }

    $cleanCurrent = $Current.TrimStart('v', 'V')
    $cleanLatest = $Latest.TrimStart('v', 'V')

    try {
        $currentVersion = [version]$cleanCurrent
        $latestVersion = [version]$cleanLatest
    } catch {
        if ($cleanCurrent -eq $cleanLatest) {
            return [pscustomobject]@{ Result = "Current"; Message = "Running latest version ($cleanCurrent)." }
        }
        return [pscustomobject]@{ Result = "Unknown"; Message = "Could not parse version strings: $cleanCurrent vs $cleanLatest." }
    }

    if ($currentVersion -eq $latestVersion) {
        return [pscustomobject]@{ Result = "Current"; Message = "Running latest version ($cleanCurrent)." }
    } elseif ($currentVersion -lt $latestVersion) {
        return [pscustomobject]@{ Result = "UpdateAvailable"; Message = "Update available: $cleanCurrent -> $cleanLatest." }
    } else {
        return [pscustomobject]@{ Result = "Ahead"; Message = "Running ahead of latest release ($cleanCurrent > $cleanLatest)." }
    }
}

function Select-ReleaseAssets {
    param([object[]]$Assets)

    if ($null -eq $Assets -or $Assets.Count -eq 0) {
        return [pscustomobject]@{ ZipAsset = $null; ChecksumAsset = $null }
    }

    $zipAsset = $Assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
    $checksumAsset = $Assets | Where-Object { $_.name -match '\.sha256$' } | Select-Object -First 1

    return [pscustomobject]@{
        ZipAsset = if ($zipAsset) { [pscustomobject]@{ Name = $zipAsset.name; Size = $zipAsset.size; DownloadUrl = $zipAsset.browser_download_url } } else { $null }
        ChecksumAsset = if ($checksumAsset) { [pscustomobject]@{ Name = $checksumAsset.name; Size = $checksumAsset.size; DownloadUrl = $checksumAsset.browser_download_url } } else { $null }
    }
}

function Format-ReleaseCheckReport {
    param(
        [string]$CurrentVersion,
        [pscustomobject]$ReleaseData,
        [pscustomobject]$VersionComparison,
        [pscustomobject]$Assets
    )

    $lines = @()
    $lines += "Release check at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ""
    $lines += "Current version: $CurrentVersion"

    if ($null -ne $ReleaseData) {
        $lines += "Latest release: $($ReleaseData.TagName)"
        if ($ReleaseData.PublishedAt) { $lines += "Published: $($ReleaseData.PublishedAt)" }
    }

    $lines += ""
    $lines += "Status: $($VersionComparison.Message)"

    if ($null -ne $Assets) {
        $lines += ""
        if ($Assets.ZipAsset) {
            $sizeMb = if ($Assets.ZipAsset.Size -gt 0) { " ({0:N1} MB)" -f ($Assets.ZipAsset.Size / 1MB) } else { "" }
            $lines += "Package: $($Assets.ZipAsset.Name)$sizeMb"
        } else {
            $lines += "Package: No zip asset found in release."
        }
        if ($Assets.ChecksumAsset) {
            $lines += "Checksum: $($Assets.ChecksumAsset.Name)"
        } else {
            $lines += "Checksum: No .sha256 asset found in release."
        }
    }

    return ($lines -join "`n")
}

function Invoke-CheckRelease {
    $script:txtReleaseCheckVersion.Text = "Current version: $script:AppVersion"

    if (-not $script:PublicIpLookupEnabled) {
        $script:txtReleaseCheckOutput.Text = "Release check is unavailable when public IP / external endpoint policy is disabled."
        Update-Status "Release check skipped: endpoint policy disabled" -Type Warning
        return
    }

    $script:btnCheckRelease.IsEnabled = $false
    $script:txtReleaseCheckOutput.Text = "Checking latest release..."
    Update-Status "Checking latest GitHub release..."

    $currentVersion = $script:AppVersion

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($AppVersion)
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $url = "https://api.github.com/repos/SysAdminDoc/NetForge/releases/latest"
            $headers = @{ "User-Agent" = "NetForge/$AppVersion" }
            $response = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 15 -ErrorAction Stop

            return [pscustomobject]@{
                Success = $true
                TagName = [string]$response.tag_name
                PublishedAt = [string]$response.published_at
                HtmlUrl = [string]$response.html_url
                Assets = @($response.assets | ForEach-Object {
                    [pscustomobject]@{
                        name = [string]$_.name
                        size = [long]$_.size
                        browser_download_url = [string]$_.browser_download_url
                    }
                })
                Error = $null
            }
        } catch {
            return [pscustomobject]@{
                Success = $false
                TagName = $null
                PublishedAt = $null
                HtmlUrl = $null
                Assets = @()
                Error = $_.Exception.Message
            }
        }
    }).AddArgument($currentVersion)

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()

        try {
            $result = $ps.EndInvoke($handle)
            $ps.Dispose()

            if (-not $result -or -not $result.Success) {
                $errorMsg = if ($result -and $result.Error) { $result.Error } else { "No response from GitHub API." }
                $script:txtReleaseCheckOutput.Text = "Release check failed: $errorMsg"
                Write-OperationLog -Action "ReleaseCheck" -Result "Error" -Detail $errorMsg
                Update-Status "Release check failed" -Type Error
                return
            }

            $releaseData = [pscustomobject]@{
                TagName = $result.TagName
                PublishedAt = $result.PublishedAt
                HtmlUrl = $result.HtmlUrl
            }
            $versionComparison = Compare-VersionStrings -Current $currentVersion -Latest $result.TagName
            $assets = Select-ReleaseAssets -Assets $result.Assets
            $report = Format-ReleaseCheckReport -CurrentVersion $currentVersion -ReleaseData $releaseData -VersionComparison $versionComparison -Assets $assets

            $script:txtReleaseCheckOutput.Text = $report
            Write-OperationLog -Action "ReleaseCheck" -Result "Info" -Detail "$($versionComparison.Result): current=$currentVersion latest=$($result.TagName)"

            if ($versionComparison.Result -eq "UpdateAvailable") {
                Update-Status "Update available: $($result.TagName)" -Type Warning
            } else {
                Update-Status "Release check complete: $($versionComparison.Message)" -Type Success
            }
        } catch {
            $script:txtReleaseCheckOutput.Text = "Release check error: $($_.Exception.Message)"
            Update-Status "Release check failed" -Type Error
        } finally {
            $script:btnCheckRelease.IsEnabled = $true
        }
    }.GetNewClosure())
    $timer.Start()
}

# ============================================================================
# DNS PRESET FUNCTIONS
# ============================================================================
function Test-DnsCatalogIntegrity {
    param(
        [string]$CatalogPath,
        [string]$HashPath
    )

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog file was not found."; Hash = "" }
    }
    if (-not (Test-Path -LiteralPath $HashPath -PathType Leaf)) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog hash file was not found."; Hash = "" }
    }

    $actualHash = Get-FileSha256 -Path $CatalogPath
    $hashText = Get-Content -Raw -LiteralPath $HashPath
    $expectedHash = ""
    if ($hashText -match '(?im)^\s*([a-f0-9]{64})\s+') {
        $expectedHash = $Matches[1].ToLowerInvariant()
    }

    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog hash file does not contain a SHA256 hash."; Hash = $actualHash }
    }
    if ($actualHash -ne $expectedHash) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog hash mismatch."; Hash = $actualHash }
    }

    return [pscustomobject]@{ IsValid = $true; Message = "DNS catalog hash verified."; Hash = $actualHash }
}

function ConvertFrom-DnsProviderCatalog {
    param($Catalog)

    $errors = @()
    $presets = [ordered]@{}

    if ($null -eq $Catalog) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog is empty."; Presets = $presets }
    }
    if ([int]$Catalog.SchemaVersion -ne 1) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog schema version is not supported."; Presets = $presets }
    }

    $providers = @($Catalog.Providers)
    if ($providers.Count -eq 0) {
        return [pscustomobject]@{ IsValid = $false; Message = "DNS catalog has no providers."; Presets = $presets }
    }

    $seenNames = @{}
    $allowedCapabilities = @('default', 'dhcp', 'ipv4', 'ipv6', 'doh', 'dot', 'doq', 'public', 'security', 'privacy', 'family', 'ad-blocking')

    foreach ($provider in $providers) {
        $name = ([string]$provider.Name).Trim()
        $category = ([string]$provider.Category).Trim()
        $description = ([string]$provider.Description).Trim()
        $capabilities = @($provider.Capabilities | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
        $ipv4 = @($provider.IPv4 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        $ipv6 = @($provider.IPv6 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        $doh = ([string]$provider.DoH).Trim()
        $dot = ([string]$provider.DoT).Trim()
        $doq = ([string]$provider.DoQ).Trim()

        if ([string]::IsNullOrWhiteSpace($name)) {
            $errors += "Provider name is required."
            continue
        }
        $nameKey = $name.ToLowerInvariant()
        if ($seenNames.ContainsKey($nameKey)) {
            $errors += "Provider '$name' is duplicated."
            continue
        }
        $seenNames[$nameKey] = $true

        if ([string]::IsNullOrWhiteSpace($category)) { $errors += "Provider '$name' is missing a category." }
        if ([string]::IsNullOrWhiteSpace($description)) { $errors += "Provider '$name' is missing a description." }
        if ($capabilities.Count -eq 0) { $errors += "Provider '$name' is missing capabilities." }

        foreach ($capability in $capabilities) {
            if ($allowedCapabilities -notcontains $capability) {
                $errors += "Provider '$name' has unknown capability '$capability'."
            }
        }

        $isDhcp = ($ipv4.Count -gt 0 -and $ipv4[0] -eq "DHCP")
        if ($isDhcp) {
            if ($capabilities -notcontains 'dhcp') { $errors += "Provider '$name' uses DHCP but lacks dhcp capability." }
        } else {
            if ($ipv4.Count -eq 0 -and $ipv6.Count -eq 0) { $errors += "Provider '$name' has no DNS servers." }
            foreach ($server in $ipv4) {
                if (-not (Test-ValidIPv4Address -IP $server)) { $errors += "Provider '$name' has invalid IPv4 server '$server'." }
            }
        }

        foreach ($server in $ipv6) {
            $parsed = $null
            if (-not [System.Net.IPAddress]::TryParse($server, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                $errors += "Provider '$name' has invalid IPv6 server '$server'."
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($doh) -and -not (Test-DohTemplate -Template $doh)) {
            $errors += "Provider '$name' has invalid DoH template."
        }
        if (-not [string]::IsNullOrWhiteSpace($dot) -and -not (Test-DotHost -HostName $dot)) {
            $errors += "Provider '$name' has invalid DoT host."
        }
        if (-not [string]::IsNullOrWhiteSpace($doq) -and $doq -notmatch '^quic://[^\s]+$') {
            $errors += "Provider '$name' has invalid DoQ upstream."
        }

        $entry = [ordered]@{
            Primary = if ($isDhcp) { "DHCP" } elseif ($ipv4.Count -ge 1) { $ipv4[0] } else { "" }
            Secondary = if ($isDhcp) { "DHCP" } elseif ($ipv4.Count -ge 2) { $ipv4[1] } else { "" }
            PrimaryV6 = if ($ipv6.Count -ge 1) { $ipv6[0] } else { "" }
            SecondaryV6 = if ($ipv6.Count -ge 2) { $ipv6[1] } else { "" }
            DoHTemplate = $doh
            DoTHost = $dot
            DoQUpstream = $doq
            Description = $description
            Category = $category
            Capabilities = @($capabilities)
        }

        $presets[$name] = $entry
    }

    if ($errors.Count -gt 0) {
        return [pscustomobject]@{ IsValid = $false; Message = ($errors -join " "); Presets = $presets }
    }

    return [pscustomobject]@{ IsValid = $true; Message = "Loaded $($presets.Count) DNS providers."; Presets = $presets }
}

function Test-DnsProviderEntry {
    param([pscustomobject]$Provider)

    $issues = @()
    $name = ([string]$Provider.Name).Trim()

    if ([string]::IsNullOrWhiteSpace($name)) {
        return @("Provider entry is missing a name.")
    }

    $ipv4 = @($Provider.IPv4 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $ipv6 = @($Provider.IPv6 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $doh = ([string]$Provider.DoH).Trim()
    $dot = ([string]$Provider.DoT).Trim()
    $doq = ([string]$Provider.DoQ).Trim()
    $capabilities = @($Provider.Capabilities | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })

    if ($capabilities -contains 'doh' -and [string]::IsNullOrWhiteSpace($doh)) {
        $issues += "$name claims doh capability but has no DoH template."
    }
    if (-not [string]::IsNullOrWhiteSpace($doh) -and $capabilities -notcontains 'doh') {
        $issues += "$name has DoH template but missing doh capability."
    }
    if ($capabilities -contains 'dot' -and [string]::IsNullOrWhiteSpace($dot)) {
        $issues += "$name claims dot capability but has no DoT host."
    }
    if (-not [string]::IsNullOrWhiteSpace($dot) -and $capabilities -notcontains 'dot') {
        $issues += "$name has DoT host but missing dot capability."
    }
    if ($capabilities -contains 'doq' -and [string]::IsNullOrWhiteSpace($doq)) {
        $issues += "$name claims doq capability but has no DoQ upstream."
    }
    if (-not [string]::IsNullOrWhiteSpace($doq) -and $capabilities -notcontains 'doq') {
        $issues += "$name has DoQ upstream but missing doq capability."
    }
    if ($capabilities -contains 'ipv6' -and $ipv6.Count -eq 0) {
        $issues += "$name claims ipv6 capability but has no IPv6 servers."
    }
    if ($ipv6.Count -gt 0 -and $capabilities -notcontains 'ipv6') {
        $issues += "$name has IPv6 servers but missing ipv6 capability."
    }

    return $issues
}

function Test-VendoredDependencyManifest {
    param(
        [pscustomobject]$Manifest,
        [string]$LibDirectory,
        [string]$LicenseDirectory
    )

    $issues = @()
    $entries = @()

    if ($null -eq $Manifest -or $null -eq $Manifest.Dependencies) {
        return [pscustomobject]@{ Issues = @("Dependency manifest is empty or missing Dependencies array."); Entries = @() }
    }
    if ([int]$Manifest.SchemaVersion -ne 1) {
        return [pscustomobject]@{ Issues = @("Unsupported manifest schema version."); Entries = @() }
    }

    foreach ($dep in $Manifest.Dependencies) {
        $name = [string]$dep.Name
        $fileName = [string]$dep.FileName
        $expectedVersion = [string]$dep.Version
        $licenseFile = [string]$dep.LicenseFile

        $dllPath = Join-Path $LibDirectory $fileName
        $licensePath = Join-Path $LicenseDirectory $licenseFile

        $actualVersion = $null
        $dllExists = Test-Path -LiteralPath $dllPath -PathType Leaf
        $licenseExists = (-not [string]::IsNullOrWhiteSpace($licenseFile)) -and (Test-Path -LiteralPath $licensePath -PathType Leaf)

        if (-not $dllExists) {
            $issues += "$($name): DLL '$fileName' not found in lib directory."
        } else {
            try {
                $assembly = [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $dllPath).Path)
                $actualVersion = $assembly.GetName().Version.ToString()
            } catch {
                $issues += "$($name): Failed to read DLL version from '$fileName'."
            }

            if ($actualVersion -and $actualVersion -ne $expectedVersion) {
                $issues += "$($name): DLL version drift ($actualVersion != manifest $expectedVersion)."
            }
        }

        if (-not $licenseExists) {
            $issues += "$($name): License file '$licenseFile' not found."
        }

        $entries += [pscustomobject]@{
            Name = $name
            FileName = $fileName
            ExpectedVersion = $expectedVersion
            ActualVersion = $actualVersion
            License = [string]$dep.License
            SourceUrl = [string]$dep.SourceUrl
            DllExists = $dllExists
            LicenseExists = $licenseExists
            VersionMatch = ($actualVersion -eq $expectedVersion)
        }
    }

    $libFiles = @(Get-ChildItem -LiteralPath $LibDirectory -Filter '*.dll' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $manifestFiles = @($Manifest.Dependencies | ForEach-Object { [string]$_.FileName })
    foreach ($libFile in $libFiles) {
        if ($manifestFiles -notcontains $libFile) {
            $issues += "Unknown DLL '$libFile' not listed in dependency manifest."
        }
    }

    return [pscustomobject]@{ Issues = $issues; Entries = $entries }
}

function Format-DnsCatalogFreshnessReport {
    param(
        [int]$TotalProviders,
        [string[]]$Issues,
        [string]$CatalogHash
    )

    $lines = @()
    $lines += "DNS provider catalog freshness report"
    $lines += "Providers: $TotalProviders"
    $lines += "Hash: $CatalogHash"
    $lines += ""

    if ($Issues.Count -eq 0) {
        $lines += "No capability/endpoint mismatches found."
    } else {
        $lines += "Issues ($($Issues.Count)):"
        foreach ($issue in $Issues) {
            $lines += "  - $issue"
        }
    }

    return ($lines -join "`n")
}

function Import-DnsPresetCatalog {
    param(
        [string]$CatalogPath = $script:DnsCatalogPath,
        [string]$HashPath = $script:DnsCatalogHashPath
    )

    $integrity = Test-DnsCatalogIntegrity -CatalogPath $CatalogPath -HashPath $HashPath
    if (-not $integrity.IsValid) {
        $script:DnsCatalogStatus = "$($integrity.Message) Using embedded DNS preset defaults."
        Write-OperationLog -Action "DNS catalog" -Result "Fallback" -Detail $script:DnsCatalogStatus
        return $false
    }

    try {
        $catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
        $conversion = ConvertFrom-DnsProviderCatalog -Catalog $catalog
        if (-not $conversion.IsValid) {
            $script:DnsCatalogStatus = "$($conversion.Message) Using embedded DNS preset defaults."
            Write-OperationLog -Action "DNS catalog" -Result "Fallback" -Detail $script:DnsCatalogStatus
            return $false
        }

        $script:DnsPresets = $conversion.Presets
        $script:DnsCatalogStatus = "$($conversion.Message) Catalog hash $($integrity.Hash.Substring(0, 12))."
        Write-OperationLog -Action "DNS catalog" -Result "Loaded" -Detail $script:DnsCatalogStatus
        return $true
    } catch {
        $script:DnsCatalogStatus = "DNS catalog load failed: $($_.Exception.Message). Using embedded DNS preset defaults."
        Write-OperationLog -Action "DNS catalog" -Result "Fallback" -Detail $script:DnsCatalogStatus
        return $false
    }
}

function Initialize-DnsPresetCatalog {
    [void](Import-DnsPresetCatalog -CatalogPath $script:DnsCatalogPath -HashPath $script:DnsCatalogHashPath)
}

function Refresh-DnsPresets {
    param([string]$Filter = "", [string]$Category = "All Categories")

    $script:lstDnsPresets.Items.Clear()

    foreach ($preset in $script:DnsPresets.GetEnumerator()) {
        $name = $preset.Key
        $data = $preset.Value

        # Apply filters
        if ($Filter -and $name -notlike "*$Filter*" -and $data.Description -notlike "*$Filter*") { continue }
        if ($Category -ne "All Categories" -and $data.Category -ne $Category) { continue }

        $item = New-Object System.Windows.Controls.StackPanel
        $item.Orientation = "Vertical"
        $item.Tag = @{ Name = $name; Data = $data }

        $headerPanel = New-Object System.Windows.Controls.StackPanel
        $headerPanel.Orientation = "Horizontal"

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $name
        $nameText.FontSize = 13
        $nameText.FontWeight = "Medium"
        $nameText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f0f6fc")

        $categoryBorder = New-Object System.Windows.Controls.Border
        $categoryBorder.CornerRadius = "4"
        $categoryBorder.Padding = "6,2"
        $categoryBorder.Margin = "10,0,0,0"
        $categoryBorder.VerticalAlignment = "Center"

        $categoryColor = switch ($data.Category) {
            "Public"      { "#1f6feb" }
            "Security"    { "#f85149" }
            "Privacy"     { "#a371f7" }
            "Family"      { "#3fb950" }
            "Ad-Blocking" { "#d29922" }
            default       { "#6e7681" }
        }
        $categoryBorder.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("$categoryColor" + "30")

        $categoryText = New-Object System.Windows.Controls.TextBlock
        $categoryText.Text = $data.Category
        $categoryText.FontSize = 10
        $categoryText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom($categoryColor)
        $categoryBorder.Child = $categoryText

        $headerPanel.Children.Add($nameText) | Out-Null
        $headerPanel.Children.Add($categoryBorder) | Out-Null

        $descText = New-Object System.Windows.Controls.TextBlock
        $capabilityText = if ($data.Capabilities -and $data.Capabilities.Count -gt 0) { " [$($data.Capabilities -join ', ')]" } else { "" }
        $descText.Text = "$($data.Description)$capabilityText"
        $descText.FontSize = 11
        $descText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#8b949e")
        $descText.Margin = "0,4,0,0"

        $dnsText = New-Object System.Windows.Controls.TextBlock
        if ($data.Primary -eq "DHCP") {
            $dnsText.Text = "Automatic"
        } else {
            $secondary = if ($data.Secondary) { ", $($data.Secondary)" } else { "" }
            $dnsText.Text = "$($data.Primary)$secondary"
        }
        $dnsText.FontSize = 11
        $dnsText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $dnsText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#58a6ff")
        $dnsText.Margin = "0,4,0,0"

        $item.Children.Add($headerPanel) | Out-Null
        $item.Children.Add($descText) | Out-Null
        $item.Children.Add($dnsText) | Out-Null

        $script:lstDnsPresets.Items.Add($item) | Out-Null
    }

    if ($script:TrayIcon) {
        Update-TrayMenu
    }
    if ($script:CompactModeEnabled) {
        Apply-CompactMode -Enabled $true
    }
}

function Update-SelectedDnsDisplay {
    $selected = $script:lstDnsPresets.SelectedItem
    if ($null -eq $selected) {
        $script:pnlSelectedDns.Visibility = "Collapsed"
        Show-DohConfiguration
        Show-DotConfiguration
        return
    }

    $presetData = $selected.Tag
    $script:pnlSelectedDns.Visibility = "Visible"
    $script:txtSelectedDnsName.Text = $presetData.Name
    $script:txtSelectedDnsDesc.Text = $presetData.Data.Description

    if ($presetData.Data.Primary -eq "DHCP") {
        $script:txtSelectedDnsPrimary.Text = "Automatic"
        $script:txtSelectedDnsSecondary.Text = "Automatic"
    } else {
        $script:txtSelectedDnsPrimary.Text = $presetData.Data.Primary
        $script:txtSelectedDnsSecondary.Text = if ($presetData.Data.Secondary) { $presetData.Data.Secondary } else { "Not set" }
    }

    # Auto-fill custom fields
    if ($presetData.Data.Primary -ne "DHCP") {
        $script:txtDnsPrimary.Text = $presetData.Data.Primary
        $script:txtDnsSecondary.Text = if ($presetData.Data.Secondary) { $presetData.Data.Secondary } else { "" }
    }

    Show-DohConfiguration
    Show-DotConfiguration
}

function Test-DohTemplate {
    param([string]$Template)

    if ([string]::IsNullOrWhiteSpace($Template)) { return $false }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Template, [System.UriKind]::Absolute, [ref]$uri)) { return $false }
    return ($uri.Scheme -eq "https")
}

function ConvertTo-DotHostValue {
    param([string]$HostName)

    if ([string]::IsNullOrWhiteSpace($HostName)) { return "" }

    $value = $HostName.Trim()
    $hostPart = ""
    $hostOutput = ""
    $portText = ""

    if ($value -match '^\[(?<host>[0-9A-Fa-f:]+)\](?::(?<port>\d+))?$') {
        $hostPart = $Matches.host
        $hostOutput = "[$hostPart]"
        $portText = $Matches.port
    } elseif ($value -match '^(?<host>[^:\s]+)(?::(?<port>\d+))?$') {
        $hostPart = $Matches.host
        $hostOutput = $hostPart
        $portText = $Matches.port
    } else {
        return ""
    }

    $ipAddress = $null
    $isIpAddress = [System.Net.IPAddress]::TryParse($hostPart, [ref]$ipAddress)
    $isDnsName = $hostPart -match '^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
    if (-not $isIpAddress -and -not $isDnsName) { return "" }

    if ([string]::IsNullOrWhiteSpace($portText)) {
        $portText = "853"
    }

    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port)) { return "" }
    if ($port -lt 1 -or $port -gt 65535) { return "" }

    return "$hostOutput`:$port"
}

function Test-DotHost {
    param([string]$HostName)

    return (-not [string]::IsNullOrWhiteSpace((ConvertTo-DotHostValue -HostName $HostName)))
}

function New-DnsQueryMessage {
    param([string]$QueryName = "example.com")

    $bytes = New-Object 'System.Collections.Generic.List[byte]'

    function Add-UInt16BytePair {
        param([int]$Value)
        $bytes.Add([byte](($Value -shr 8) -band 0xff))
        $bytes.Add([byte]($Value -band 0xff))
    }

    Add-UInt16BytePair 0x4e46
    Add-UInt16BytePair 0x0100
    Add-UInt16BytePair 1
    Add-UInt16BytePair 0
    Add-UInt16BytePair 0
    Add-UInt16BytePair 0

    foreach ($label in $QueryName.Trim(".").Split(".")) {
        if ([string]::IsNullOrWhiteSpace($label) -or $label.Length -gt 63) {
            throw "Invalid DNS query label '$label'."
        }

        $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($label)
        $bytes.Add([byte]$labelBytes.Length)
        foreach ($labelByte in $labelBytes) {
            $bytes.Add($labelByte)
        }
    }

    $bytes.Add([byte]0)
    Add-UInt16BytePair 1
    Add-UInt16BytePair 1

    return $bytes.ToArray()
}

function Invoke-DnsUdpProbe {
    param(
        [string]$Server,
        [int]$Port = 53,
        [int]$TimeoutMs = 900,
        [string]$QueryName = "example.com"
    )

    if (-not (Test-ValidIP -IP $Server)) {
        return [pscustomobject]@{
            Server = $Server
            Port = $Port
            Success = $false
            LatencyMs = $null
            Message = "Not an IP address"
        }
    }
    if ($Port -lt 1 -or $Port -gt 65535) {
        return [pscustomobject]@{
            Server = $Server
            Port = $Port
            Success = $false
            LatencyMs = $null
            Message = "Invalid port"
        }
    }

    $client = $null
    try {
        $ipAddress = [System.Net.IPAddress]::Parse($Server)
        $client = New-Object System.Net.Sockets.UdpClient($ipAddress.AddressFamily)
        $client.Client.SendTimeout = $TimeoutMs
        $client.Client.ReceiveTimeout = $TimeoutMs

        $endpoint = New-Object System.Net.IPEndPoint($ipAddress, $Port)
        $query = New-DnsQueryMessage -QueryName $QueryName
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $client.Connect($endpoint)
        [void]$client.Send($query, $query.Length)

        $anyAddress = if ($ipAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            [System.Net.IPAddress]::IPv6Any
        } else {
            [System.Net.IPAddress]::Any
        }
        $remoteEndpoint = New-Object System.Net.IPEndPoint($anyAddress, 0)
        $response = $client.Receive([ref]$remoteEndpoint)
        $stopwatch.Stop()

        if ($response.Length -lt 12) {
            throw "short DNS response ($($response.Length) bytes)"
        }

        return [pscustomobject]@{
            Server = $Server
            Port = $Port
            Success = $true
            LatencyMs = [int][Math]::Max(1, [Math]::Round($stopwatch.Elapsed.TotalMilliseconds))
            Message = "UDP response $($response.Length) bytes"
        }
    } catch {
        return [pscustomobject]@{
            Server = $Server
            Port = $Port
            Success = $false
            LatencyMs = $null
            Message = $_.Exception.Message
        }
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-AdapterDnsServerSummary {
    param($Adapter)

    if ($null -eq $Adapter) { return @() }

    try {
        $rows = @(Get-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ErrorAction SilentlyContinue)
        return @(
            $rows |
                ForEach-Object { $_.ServerAddresses } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
    } catch {
        return @()
    }
}

function Get-DnsResolverLatencyRows {
    param(
        [string[]]$Servers,
        [int]$TimeoutMs = 900
    )

    $rows = @()
    foreach ($server in @($Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $probe = Invoke-DnsUdpProbe -Server $server -Port 53 -TimeoutMs $TimeoutMs
        $rows += [pscustomobject]@{
            Resolver = $server
            Protocol = "UDP/53"
            Success = [bool]$probe.Success
            LatencyMs = $probe.LatencyMs
            Message = $probe.Message
        }
    }
    return $rows
}

function Format-DnsLatencyRows {
    param([object[]]$Rows)

    if ($null -eq $Rows -or $Rows.Count -eq 0) {
        return @("Resolver latency (UDP/53): no static resolver target.")
    }

    $lines = @("Resolver latency (UDP/53):")
    foreach ($row in $Rows) {
        $state = if ($row.Success) { "OK" } else { "FAIL" }
        $latency = if ($null -ne $row.LatencyMs) { "$($row.LatencyMs) ms" } else { "--" }
        $lines += "  $($row.Resolver) | $state | $latency | $($row.Message)"
    }
    return $lines
}

function Get-DnsConfigLeakResult {
    param(
        [string[]]$AdapterServers,
        [string[]]$TargetServers,
        [string]$LocalProxyAddress = ""
    )

    $configured = @($AdapterServers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $targetList = @($TargetServers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not [string]::IsNullOrWhiteSpace($LocalProxyAddress)) {
        $targetList += $LocalProxyAddress
    }
    $targets = @($targetList | Select-Object -Unique)

    if ($configured.Count -eq 0) {
        return [pscustomobject]@{
            Success = $null
            Message = "Adapter DNS is automatic or unavailable."
        }
    }
    if ($targets.Count -eq 0) {
        return [pscustomobject]@{
            Success = $false
            Message = "No selected resolver target to compare with current adapter DNS: $($configured -join ', ')"
        }
    }

    $unexpected = @($configured | Where-Object { $targets -notcontains $_ })
    if ($unexpected.Count -gt 0) {
        return [pscustomobject]@{
            Success = $false
            Message = "Adapter currently uses non-target resolver(s): $($unexpected -join ', ')"
        }
    }

    return [pscustomobject]@{
        Success = $true
        Message = "Adapter DNS matches the selected/local resolver target."
    }
}

function Format-DnsHealthResultLines {
    param([object[]]$Results)

    if ($null -eq $Results -or $Results.Count -eq 0) {
        return @("No DNS health results returned.")
    }

    $lines = @()
    $currentSection = ""
    foreach ($result in @($Results | Sort-Object Sort, Section, Name)) {
        if ($result.Section -ne $currentSection) {
            if ($lines.Count -gt 0) { $lines += "" }
            $lines += "$($result.Section):"
            $currentSection = $result.Section
        }

        $state = if ($null -eq $result.Success) {
            "INFO"
        } elseif ($result.Success) {
            "OK"
        } else {
            "FAIL"
        }
        $latency = if ($null -ne $result.LatencyMs) { " [$($result.LatencyMs) ms]" } else { "" }
        $lines += "  $state $($result.Name): $($result.Message)$latency"
    }

    return $lines
}

function Update-DnsHealthOutput {
    param(
        [string[]]$Lines,
        [string]$Header = "Encrypted DNS health"
    )

    $body = if ($Lines.Count -gt 0) { $Lines -join "`n" } else { "No DNS health output." }
    if ($script:txtEncryptedDnsHealthStatus) {
        $script:txtEncryptedDnsHealthStatus.Text = $body
    }
    if ($script:txtDiagOutput) {
        $script:txtDiagOutput.Text = "$Header`n$('=' * $Header.Length)`n$body"
    }
    Write-OperationLog -Action $Header -Result "Updated" -Detail (($Lines | Select-Object -First 6) -join " | ")
}

function Invoke-DnsApplyHealthPreview {
    param(
        $Adapter,
        [pscustomobject]$Target
    )

    $adapterDns = Get-AdapterDnsServerSummary -Adapter $Adapter
    $adapterText = if ($adapterDns.Count -gt 0) { $adapterDns -join ", " } else { "Automatic or unavailable" }
    $lines = @("Configured adapter DNS: $adapterText")

    if ($Target.UseAutomatic) {
        $lines += "Target DNS: Automatic from DHCP"
        $lines += "Resolver latency (UDP/53): no static resolver target."
        Update-DnsHealthOutput -Lines $lines -Header "DNS apply preview"
        return $lines
    }

    $targetServers = @($Target.Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $lines += "Target resolver(s): $($targetServers -join ', ')"

    $leak = Get-DnsConfigLeakResult -AdapterServers $adapterDns -TargetServers $targetServers
    $leakState = if ($null -eq $leak.Success) { "INFO" } elseif ($leak.Success) { "OK" } else { "WARN" }
    $lines += "Config leak guard: $leakState - $($leak.Message)"

    $latencyRows = Get-DnsResolverLatencyRows -Servers $targetServers -TimeoutMs 900
    $lines += Format-DnsLatencyRows -Rows $latencyRows

    $reachable = @($latencyRows | Where-Object { $_.Success }).Count
    $lines += "UDP fallback state: $reachable of $($latencyRows.Count) target resolver(s) answered UDP/53."

    Update-DnsHealthOutput -Lines $lines -Header "DNS apply preview"
    return $lines
}

function Get-DohConfigurationTarget {
    $servers = @()
    $template = $script:txtDohTemplate.Text.Trim()
    $source = "Custom DNS"

    if ($script:rbDnsPreset.IsChecked) {
        $selected = $script:lstDnsPresets.SelectedItem
        if ($selected) {
            $preset = $selected.Tag.Data
            $source = $selected.Tag.Name
            if ($preset.Primary -and $preset.Primary -ne "DHCP") { $servers += $preset.Primary }
            if ($preset.Secondary -and $preset.Secondary -ne "DHCP") { $servers += $preset.Secondary }
            if ($script:chkIPv6Dns.IsChecked) {
                if ($preset.PrimaryV6) { $servers += $preset.PrimaryV6 }
                if ($preset.SecondaryV6) { $servers += $preset.SecondaryV6 }
            }
            if ([string]::IsNullOrWhiteSpace($template) -and $preset.DoHTemplate) {
                $template = $preset.DoHTemplate
            }
        }
    } elseif ($script:rbDnsCustom.IsChecked) {
        $primary = $script:txtDnsPrimary.Text.Trim()
        $secondary = $script:txtDnsSecondary.Text.Trim()
        if (Test-ValidIP $primary) { $servers += $primary }
        if (Test-ValidIP $secondary) { $servers += $secondary }
    }

    $servers = @($servers | Where-Object { $_ } | Select-Object -Unique)
    return [pscustomobject]@{
        Source = $source
        Servers = $servers
        Template = $template
    }
}

function Get-DotConfigurationTarget {
    $baseTarget = Get-DohConfigurationTarget
    $dotHost = if ($script:txtDotHost) { $script:txtDotHost.Text.Trim() } else { "" }

    if ($script:rbDnsPreset.IsChecked) {
        $selected = $script:lstDnsPresets.SelectedItem
        if ($selected) {
            $preset = $selected.Tag.Data
            if ([string]::IsNullOrWhiteSpace($dotHost) -and $preset.DoTHost) {
                $dotHost = $preset.DoTHost
            }
        }
    }

    return [pscustomobject]@{
        Source = $baseTarget.Source
        Servers = $baseTarget.Servers
        RawDoTHost = $dotHost
        DoTHost = ConvertTo-DotHostValue -HostName $dotHost
    }
}

function Show-DohConfiguration {
    if (-not $script:txtDohServers -or -not $script:txtDohTemplate) { return }

    $target = Get-DohConfigurationTarget
    if ($script:rbDnsPreset.IsChecked) {
        $selected = $script:lstDnsPresets.SelectedItem
        if ($selected) {
            if ($selected.Tag.Data.DoHTemplate) {
                $script:txtDohTemplate.Text = $selected.Tag.Data.DoHTemplate
            } else {
                $script:txtDohTemplate.Text = ""
            }
            $target = Get-DohConfigurationTarget
        }
    }

    if ($target.Servers.Count -gt 0) {
        $script:txtDohServers.Text = "$($target.Source): $($target.Servers -join ', ')"
    } else {
        $script:txtDohServers.Text = "Select a DNS preset or enter custom DNS servers."
    }
}

function Show-DotConfiguration {
    if (-not $script:txtDotHost -or -not $script:txtDotStatus) { return }

    $target = Get-DotConfigurationTarget
    if ($script:rbDnsPreset.IsChecked) {
        $selected = $script:lstDnsPresets.SelectedItem
        if ($selected) {
            if ($selected.Tag.Data.DoTHost) {
                $script:txtDotHost.Text = $selected.Tag.Data.DoTHost
            } else {
                $script:txtDotHost.Text = ""
            }
            $target = Get-DotConfigurationTarget
        }
    }

    if ($target.Servers.Count -eq 0) {
        $script:txtDotStatus.Text = "Select a DNS preset or enter custom DNS servers."
    } elseif ([string]::IsNullOrWhiteSpace($target.DoTHost)) {
        $script:txtDotStatus.Text = "Enter a DoT host such as dns.google:853."
    } else {
        $script:txtDotStatus.Text = "Ready: $($target.DoTHost)"
    }
}

function Register-DohEncryption {
    $target = Get-DohConfigurationTarget
    if ($target.Servers.Count -eq 0) {
        Show-MessageBox -Message "Select a DNS preset or enter valid custom DNS servers before registering DoH." -Title "No DNS Servers" -Icon Warning
        return
    }

    if (-not (Test-DohTemplate -Template $target.Template)) {
        Show-MessageBox -Message "Enter a valid HTTPS DoH template URL." -Title "Invalid DoH Template" -Icon Error
        return
    }

    $autoUpgrade = if ($script:chkDohAutoUpgrade.IsChecked) { "yes" } else { "no" }
    $udpFallback = if ($script:chkDohUdpFallback.IsChecked) { "yes" } else { "no" }
    $failures = @()

    Update-Status "Registering DoH encryption for $($target.Servers.Count) DNS server(s)..."

    foreach ($server in $target.Servers) {
        $commonArgs = @(
            "dns", "add", "encryption",
            "server=$server",
            "dohtemplate=$($target.Template)",
            "autoupgrade=$autoUpgrade",
            "udpfallback=$udpFallback"
        )

        $output = netsh @commonArgs 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or $output -match "already exists|cannot create|failed|error") {
            $setArgs = @(
                "dns", "set", "encryption",
                "server=$server",
                "dohtemplate=$($target.Template)",
                "autoupgrade=$autoUpgrade",
                "udpfallback=$udpFallback"
            )
            $output = netsh @setArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }

        if ($exitCode -ne 0 -or $output -match "failed|error") {
            $failures += "$server`: $($output.Trim())"
        }
    }

    if ($failures.Count -gt 0) {
        $message = $failures -join "`n"
        $script:txtDohStatus.Text = "Registration failed for $($failures.Count) server(s)."
        Update-Status "DoH registration failed for $($failures.Count) server(s)" -Type Error
        Show-MessageBox -Message $message -Title "DoH Registration Failed" -Icon Error
    } else {
        $script:txtDohStatus.Text = "Registered: $($target.Servers -join ', ')"
        Update-Status "DoH encryption registered for $($target.Servers.Count) DNS server(s)" -Type Success
    }
}

function Register-DotEncryption {
    $target = Get-DotConfigurationTarget
    if ($target.Servers.Count -eq 0) {
        Show-MessageBox -Message "Select a DNS preset or enter valid custom DNS servers before registering DoT." -Title "No DNS Servers" -Icon Warning
        return
    }

    if (-not (Test-DotHost -HostName $target.RawDoTHost)) {
        Show-MessageBox -Message "Enter a valid DoT hostname with optional port, such as dns.google:853." -Title "Invalid DoT Host" -Icon Error
        return
    }

    $autoUpgrade = if ($script:chkDohAutoUpgrade.IsChecked) { "yes" } else { "no" }
    $udpFallback = if ($script:chkDohUdpFallback.IsChecked) { "yes" } else { "no" }
    $failures = @()

    Update-Status "Registering DoT encryption for $($target.Servers.Count) DNS server(s)..."

    foreach ($server in $target.Servers) {
        $commonArgs = @(
            "dns", "add", "encryption",
            "server=$server",
            "dothost=$($target.DoTHost)",
            "autoupgrade=$autoUpgrade",
            "udpfallback=$udpFallback"
        )

        $output = netsh @commonArgs 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or $output -match "already exists|cannot create|failed|error") {
            $setArgs = @(
                "dns", "set", "encryption",
                "server=$server",
                "dothost=$($target.DoTHost)",
                "autoupgrade=$autoUpgrade",
                "udpfallback=$udpFallback"
            )
            $output = netsh @setArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }

        if ($exitCode -ne 0 -or $output -match "failed|error") {
            $failures += "$server`: $($output.Trim())"
        }
    }

    if ($failures.Count -gt 0) {
        $message = $failures -join "`n"
        $script:txtDotStatus.Text = "Registration failed for $($failures.Count) server(s)."
        Update-Status "DoT registration failed for $($failures.Count) server(s)" -Type Error
        Show-MessageBox -Message $message -Title "DoT Registration Failed" -Icon Error
    } else {
        $script:txtDotStatus.Text = "Registered: $($target.Servers -join ', ')"
        Update-Status "DoT encryption registered for $($target.Servers.Count) DNS server(s)" -Type Success
    }
}

function Invoke-EncryptedDnsHealthTest {
    if ($script:EncryptedDnsHealthRunning) { return }

    $adapter = Get-SelectedAdapter
    $dohTarget = Get-DohConfigurationTarget
    $dotTarget = Get-DotConfigurationTarget
    $applyTarget = Get-DNSApplyTarget
    $dohTemplate = if (Test-DohTemplate -Template $dohTarget.Template) { $dohTarget.Template } else { "" }
    $dotHost = if (Test-DotHost -HostName $dotTarget.RawDoTHost) { $dotTarget.DoTHost } else { "" }
    $targetServers = @()
    $targetMode = "No DNS target selected"

    if ($applyTarget.IsValid -and -not $applyTarget.UseAutomatic) {
        $targetServers = @($applyTarget.Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $targetMode = $applyTarget.StatusMessage
    } elseif ($applyTarget.IsValid -and $applyTarget.UseAutomatic) {
        $targetMode = $applyTarget.StatusMessage
    } elseif ($dohTarget.Servers.Count -gt 0) {
        $targetServers = @($dohTarget.Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $targetMode = "$($dohTarget.Source) encrypted DNS metadata"
    }

    $adapterDns = Get-AdapterDnsServerSummary -Adapter $adapter
    $doqConfig = Get-DoqProxyConfiguration
    $doqListenAddress = if (Test-ValidIP -IP $doqConfig.ListenAddress) { $doqConfig.ListenAddress } else { "" }
    $doqListenPort = if ($doqConfig.ListenPort -ge 1 -and $doqConfig.ListenPort -le 65535) { $doqConfig.ListenPort } else { 0 }
    $doqHealthState = Format-DoqProxyHealthState -Process $script:DoqProxyProcess -StderrPath $script:DoqProxyStderrPath
    $doqProcessRunning = ($doqHealthState.State -eq "Running")
    $doqProcessId = if ($doqProcessRunning -and $script:DoqProxyProcess) { $script:DoqProxyProcess.Id } else { $null }
    $localProxyCompareAddress = if ($doqListenPort -eq 53) { $doqListenAddress } else { "" }
    $leakResult = Get-DnsConfigLeakResult -AdapterServers $adapterDns -TargetServers $targetServers -LocalProxyAddress $localProxyCompareAddress

    if ([string]::IsNullOrWhiteSpace($dohTemplate) -and [string]::IsNullOrWhiteSpace($dotHost) -and $targetServers.Count -eq 0 -and $adapterDns.Count -eq 0 -and [string]::IsNullOrWhiteSpace($doqListenAddress)) {
        Show-MessageBox -Message "Select a DNS preset, enter custom DNS servers, select an adapter, or configure the local DoQ proxy before testing DNS health." -Title "No DNS Health Target" -Icon Warning
        return
    }

    $script:EncryptedDnsHealthRunning = $true
    $script:btnTestEncryptedDns.IsEnabled = $false
    $script:txtEncryptedDnsHealthStatus.Text = "Testing DNS health..."
    Update-Status "Testing encrypted DNS health..."

    $healthContext = [pscustomobject]@{
        AdapterName = if ($adapter) { $adapter.Name } else { "" }
        AdapterDnsServers = @($adapterDns)
        TargetMode = $targetMode
        TargetServers = @($targetServers)
        LeakSuccess = $leakResult.Success
        LeakMessage = $leakResult.Message
        UdpFallbackAllowed = [bool]$script:chkDohUdpFallback.IsChecked
        DohTemplate = $dohTemplate
        DotHost = $dotHost
        DoqListenAddress = $doqListenAddress
        DoqListenPort = $doqListenPort
        DoqProcessRunning = [bool]$doqProcessRunning
        DoqProcessId = $doqProcessId
        DoqProcessState = $doqHealthState.State
        DoqProcessStateMessage = $doqHealthState.Message
        DoqLastError = $doqHealthState.LastError
    }

    $healthScript = {
        param($Context)

        function New-HealthResult {
            param(
                [int]$Sort,
                [string]$Section,
                [string]$Name,
                [object]$Success,
                [string]$Message,
                [object]$LatencyMs = $null
            )

            return [pscustomobject]@{
                Sort = $Sort
                Section = $Section
                Name = $Name
                Success = $Success
                Message = $Message
                LatencyMs = $LatencyMs
            }
        }

        function ConvertTo-DnsQueryMessage {
            $bytes = New-Object 'System.Collections.Generic.List[byte]'

            function Add-UInt16BytePair {
                param([int]$Value)
                $bytes.Add([byte](($Value -shr 8) -band 0xff))
                $bytes.Add([byte]($Value -band 0xff))
            }

            Add-UInt16BytePair 0x4e46
            Add-UInt16BytePair 0x0100
            Add-UInt16BytePair 1
            Add-UInt16BytePair 0
            Add-UInt16BytePair 0
            Add-UInt16BytePair 0

            foreach ($label in "example.com".Split(".")) {
                $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($label)
                $bytes.Add([byte]$labelBytes.Length)
                foreach ($labelByte in $labelBytes) {
                    $bytes.Add($labelByte)
                }
            }

            $bytes.Add([byte]0)
            Add-UInt16BytePair 1
            Add-UInt16BytePair 1

            return $bytes.ToArray()
        }

        function Invoke-UdpDnsProbe {
            param(
                [string]$Server,
                [int]$Port = 53,
                [int]$TimeoutMs = 1200
            )

            $client = $null
            try {
                $ipAddress = [System.Net.IPAddress]::Parse($Server)
                $client = New-Object System.Net.Sockets.UdpClient($ipAddress.AddressFamily)
                $client.Client.SendTimeout = $TimeoutMs
                $client.Client.ReceiveTimeout = $TimeoutMs

                $endpoint = New-Object System.Net.IPEndPoint($ipAddress, $Port)
                $query = ConvertTo-DnsQueryMessage
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $client.Connect($endpoint)
                [void]$client.Send($query, $query.Length)

                $anyAddress = if ($ipAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                    [System.Net.IPAddress]::IPv6Any
                } else {
                    [System.Net.IPAddress]::Any
                }
                $remoteEndpoint = New-Object System.Net.IPEndPoint($anyAddress, 0)
                $response = $client.Receive([ref]$remoteEndpoint)
                $stopwatch.Stop()

                if ($response.Length -lt 12) {
                    throw "short DNS response ($($response.Length) bytes)"
                }

                return [pscustomobject]@{
                    Success = $true
                    LatencyMs = [int][Math]::Max(1, [Math]::Round($stopwatch.Elapsed.TotalMilliseconds))
                    Message = "UDP response $($response.Length) bytes"
                }
            } catch {
                return [pscustomobject]@{
                    Success = $false
                    LatencyMs = $null
                    Message = $_.Exception.Message
                }
            } finally {
                if ($client) { $client.Close() }
            }
        }

        function ConvertTo-DnsBase64Url {
            param([byte[]]$Bytes)
            return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
        }

        function Invoke-DohHealthProbe {
            param([string]$Template)

            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                $query = ConvertTo-DnsBase64Url -Bytes (ConvertTo-DnsQueryMessage)
                $separator = if ($Template.Contains("?")) { "&" } else { "?" }
                $uri = "$Template$separator" + "dns=$query"

                $request = [System.Net.HttpWebRequest]::Create($uri)
                $request.Method = "GET"
                $request.Accept = "application/dns-message"
                $request.UserAgent = "NetForge"
                $request.Timeout = 7000
                $request.ReadWriteTimeout = 7000
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                $response = $request.GetResponse()
                try {
                    $stream = $response.GetResponseStream()
                    $memory = New-Object System.IO.MemoryStream
                    $stream.CopyTo($memory)
                    $stopwatch.Stop()
                    $length = $memory.Length

                    if ([int]$response.StatusCode -ne 200) {
                        throw "HTTP $([int]$response.StatusCode)"
                    }
                    if ($length -lt 12) {
                        throw "short DNS response ($length bytes)"
                    }

                    return [pscustomobject]@{
                        Protocol = "DoH"
                        Success = $true
                        Message = "HTTPS 200, DNS response $length bytes"
                        LatencyMs = [int][Math]::Max(1, [Math]::Round($stopwatch.Elapsed.TotalMilliseconds))
                    }
                } finally {
                    if ($response) { $response.Close() }
                }
            } catch {
                return [pscustomobject]@{
                    Protocol = "DoH"
                    Success = $false
                    Message = $_.Exception.Message
                    LatencyMs = $null
                }
            }
        }

        function Get-DotHostEndpoint {
            param([string]$HostValue)

            if ($HostValue -match '^\[(?<host>[^\]]+)\]:(?<port>\d+)$') {
                return [pscustomobject]@{ Host = $Matches.host; Port = [int]$Matches.port }
            }
            if ($HostValue -match '^(?<host>.+):(?<port>\d+)$') {
                return [pscustomobject]@{ Host = $Matches.host; Port = [int]$Matches.port }
            }
            throw "Invalid DoT host."
        }

        function Get-StreamByteBlock {
            param(
                [System.IO.Stream]$Stream,
                [int]$Count
            )

            $buffer = New-Object byte[] $Count
            $offset = 0
            while ($offset -lt $Count) {
                $read = $Stream.Read($buffer, $offset, $Count - $offset)
                if ($read -le 0) { throw "connection closed before DNS response" }
                $offset += $read
            }
            return $buffer
        }

        function Invoke-DotHealthProbe {
            param([string]$HostValue)

            $client = $null
            $sslStream = $null

            try {
                $endpoint = Get-DotHostEndpoint -HostValue $HostValue
                $client = New-Object System.Net.Sockets.TcpClient
                $connect = $client.BeginConnect($endpoint.Host, $endpoint.Port, $null, $null)
                if (-not $connect.AsyncWaitHandle.WaitOne(7000)) {
                    $client.Close()
                    throw "TCP connect timed out"
                }
                $client.EndConnect($connect)
                $client.ReceiveTimeout = 7000
                $client.SendTimeout = 7000

                $callback = [System.Net.Security.RemoteCertificateValidationCallback]{
                    param($certSender, $serverCertificate, $certificateChain, $policyErrors)
                    [void]$certSender
                    [void]$serverCertificate
                    [void]$certificateChain
                    return ($policyErrors -eq [System.Net.Security.SslPolicyErrors]::None)
                }
                $sslStream = New-Object System.Net.Security.SslStream($client.GetStream(), $false, $callback)
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $sslStream.AuthenticateAsClient($endpoint.Host)

                $query = ConvertTo-DnsQueryMessage
                $prefix = [byte[]]@(
                    [byte](($query.Length -shr 8) -band 0xff),
                    [byte]($query.Length -band 0xff)
                )
                $sslStream.Write($prefix, 0, $prefix.Length)
                $sslStream.Write($query, 0, $query.Length)
                $sslStream.Flush()

                $lengthBytes = Get-StreamByteBlock -Stream $sslStream -Count 2
                $responseLength = ([int]$lengthBytes[0] -shl 8) -bor [int]$lengthBytes[1]
                if ($responseLength -lt 12) {
                    throw "short DNS response ($responseLength bytes)"
                }
                [void](Get-StreamByteBlock -Stream $sslStream -Count $responseLength)
                $stopwatch.Stop()

                return [pscustomobject]@{
                    Protocol = "DoT"
                    Success = $true
                    Message = "TLS handshake and DNS response $responseLength bytes"
                    LatencyMs = [int][Math]::Max(1, [Math]::Round($stopwatch.Elapsed.TotalMilliseconds))
                }
            } catch {
                return [pscustomobject]@{
                    Protocol = "DoT"
                    Success = $false
                    Message = $_.Exception.Message
                    LatencyMs = $null
                }
            } finally {
                if ($sslStream) { $sslStream.Dispose() }
                if ($client) { $client.Close() }
            }
        }

        $results = @()

        $adapterName = if ([string]::IsNullOrWhiteSpace($Context.AdapterName)) { "No adapter selected" } else { $Context.AdapterName }
        $adapterDnsText = if ($Context.AdapterDnsServers.Count -gt 0) { $Context.AdapterDnsServers -join ", " } else { "Automatic or unavailable" }
        $results += New-HealthResult -Sort 10 -Section "Configured adapter DNS" -Name $adapterName -Success $null -Message $adapterDnsText

        $targetText = if ($Context.TargetServers.Count -gt 0) { $Context.TargetServers -join ", " } else { "No static resolver target" }
        $results += New-HealthResult -Sort 20 -Section "Selected target" -Name $Context.TargetMode -Success $null -Message $targetText
        $results += New-HealthResult -Sort 30 -Section "Config leak guard" -Name "Adapter vs target" -Success $Context.LeakSuccess -Message $Context.LeakMessage

        if (-not [string]::IsNullOrWhiteSpace($Context.DohTemplate)) {
            $probe = Invoke-DohHealthProbe -Template $Context.DohTemplate
            $results += New-HealthResult -Sort 40 -Section "Encrypted endpoint probe" -Name "DoH" -Success $probe.Success -Message $probe.Message -LatencyMs $probe.LatencyMs
        } else {
            $results += New-HealthResult -Sort 40 -Section "Encrypted endpoint probe" -Name "DoH" -Success $null -Message "No DoH template selected."
        }
        if (-not [string]::IsNullOrWhiteSpace($Context.DotHost)) {
            $probe = Invoke-DotHealthProbe -HostValue $Context.DotHost
            $results += New-HealthResult -Sort 41 -Section "Encrypted endpoint probe" -Name "DoT" -Success $probe.Success -Message $probe.Message -LatencyMs $probe.LatencyMs
        } else {
            $results += New-HealthResult -Sort 41 -Section "Encrypted endpoint probe" -Name "DoT" -Success $null -Message "No DoT host selected."
        }

        $fallbackPolicy = if ($Context.UdpFallbackAllowed) { "Allowed by current DoH/DoT registration option." } else { "Disabled by current DoH/DoT registration option." }
        $results += New-HealthResult -Sort 50 -Section "UDP fallback state" -Name "Registration policy" -Success $null -Message $fallbackPolicy

        if ($Context.TargetServers.Count -eq 0) {
            $results += New-HealthResult -Sort 60 -Section "Resolver latency" -Name "UDP/53" -Success $null -Message "No static resolver target to probe."
        } else {
            $index = 0
            foreach ($server in $Context.TargetServers) {
                $probe = Invoke-UdpDnsProbe -Server $server -Port 53 -TimeoutMs 1200
                $results += New-HealthResult -Sort (60 + $index) -Section "Resolver latency" -Name "$server UDP/53" -Success $probe.Success -Message $probe.Message -LatencyMs $probe.LatencyMs
                $index++
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($Context.DoqListenAddress) -and $Context.DoqListenPort -gt 0) {
            $proxyProbe = Invoke-UdpDnsProbe -Server $Context.DoqListenAddress -Port $Context.DoqListenPort -TimeoutMs 1200
            $stateLabel = "$($Context.DoqProcessState): $($Context.DoqProcessStateMessage)"
            $errorSuffix = if ($Context.DoqLastError) { " Last error: $($Context.DoqLastError)" } else { "" }
            $results += New-HealthResult -Sort 80 -Section "Local proxy listener" -Name "$($Context.DoqListenAddress):$($Context.DoqListenPort)" -Success $proxyProbe.Success -Message "$stateLabel$errorSuffix; $($proxyProbe.Message)" -LatencyMs $proxyProbe.LatencyMs
        } else {
            $results += New-HealthResult -Sort 80 -Section "Local proxy listener" -Name "DoQ proxy" -Success $null -Message "No valid listen address and port configured."
        }

        return $results
    }

    $script:EncryptedDnsHealthJob = Start-Job -ScriptBlock $healthScript -ArgumentList $healthContext

    $script:EncryptedDnsHealthTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:EncryptedDnsHealthTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:EncryptedDnsHealthTimer.Add_Tick({
        if ($script:EncryptedDnsHealthJob.State -notin @("Completed", "Failed", "Stopped")) { return }

        $script:EncryptedDnsHealthTimer.Stop()

        try {
            $results = @(Receive-Job $script:EncryptedDnsHealthJob -ErrorAction Stop)
            $lines = Format-DnsHealthResultLines -Results $results

            if ($lines.Count -eq 0) {
                Update-DnsHealthOutput -Lines @("No health results returned.") -Header "Encrypted DNS health"
                Update-Status "Encrypted DNS health test returned no results" -Type Warning
            } else {
                Update-DnsHealthOutput -Lines $lines -Header "Encrypted DNS health"
                $failed = @($results | Where-Object { $null -ne $_.Success -and -not $_.Success })
                if ($failed.Count -eq 0) {
                    Update-Status "Encrypted DNS health test passed" -Type Success
                } else {
                    Update-Status "Encrypted DNS health test found $($failed.Count) failure(s)" -Type Warning
                }
            }
        } catch {
            Update-DnsHealthOutput -Lines @("Health test failed: $($_.Exception.Message)") -Header "Encrypted DNS health"
            Update-Status "Encrypted DNS health test failed" -Type Error
        } finally {
            Remove-Job $script:EncryptedDnsHealthJob -Force -ErrorAction SilentlyContinue
            $script:EncryptedDnsHealthJob = $null
            $script:EncryptedDnsHealthTimer = $null
            $script:EncryptedDnsHealthRunning = $false
            $script:btnTestEncryptedDns.IsEnabled = $true
        }
    })
    $script:EncryptedDnsHealthTimer.Start()
}

function Test-NextDnsConfigId {
    param([string]$ConfigId)

    if ([string]::IsNullOrWhiteSpace($ConfigId)) { return $false }
    $value = $ConfigId.Trim()
    return ($value -match '^[A-Za-z0-9](?:[A-Za-z0-9-]{4,62}[A-Za-z0-9])$')
}

function Invoke-ApplyNextDnsEndpoint {
    $configId = $script:txtNextDnsConfigId.Text.Trim().ToLowerInvariant()

    if (-not (Test-NextDnsConfigId -ConfigId $configId)) {
        Show-MessageBox -Message "Enter a valid NextDNS configuration ID before applying account-specific endpoints." -Title "Invalid NextDNS ID" -Icon Error
        $script:txtNextDnsEndpointStatus.Text = "Invalid NextDNS configuration ID."
        Update-Status "Invalid NextDNS configuration ID" -Type Error
        return
    }

    $dohTemplate = "https://dns.nextdns.io/$configId"
    $dotHost = "$configId.dns.nextdns.io:853"
    $doqUpstream = "quic://$configId.dns.nextdns.io:853"

    $script:txtDohTemplate.Text = $dohTemplate
    $script:txtDotHost.Text = $dotHost
    $script:txtDoqUpstream.Text = $doqUpstream
    $script:txtNextDnsEndpointStatus.Text = "Applied NextDNS endpoints: DoH, DoT, and DoQ upstream."
    $script:txtEncryptedDnsHealthStatus.Text = "NextDNS endpoints ready for health testing."
    $script:txtDoqProxyStatus.Text = "NextDNS DoQ upstream applied. Validate dnsproxy before starting."

    Update-Status "NextDNS encrypted endpoints applied" -Type Success
}

function Resolve-DoqProxyPath {
    $pathText = $script:txtDoqProxyPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($pathText)) { return $null }

    if (Test-Path -LiteralPath $pathText -PathType Leaf) {
        return (Resolve-Path -LiteralPath $pathText).Path
    }

    $command = Get-Command $pathText -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    return $null
}

function Get-DoqProxyConfiguration {
    $port = 0
    [void][int]::TryParse($script:txtDoqListenPort.Text.Trim(), [ref]$port)

    return [pscustomobject]@{
        ProxyPathText = $script:txtDoqProxyPath.Text.Trim()
        ProxyPath = Resolve-DoqProxyPath
        Upstream = $script:txtDoqUpstream.Text.Trim()
        ListenAddress = $script:txtDoqListenAddress.Text.Trim()
        ListenPort = $port
        Bootstrap = $script:txtDoqBootstrap.Text.Trim()
    }
}

function Test-DoqProxyConfiguration {
    param([pscustomobject]$Config)

    $errors = @()

    if ([string]::IsNullOrWhiteSpace($Config.ProxyPath)) {
        $errors += "dnsproxy.exe was not found. Enter a full path or place it on PATH."
    }
    if ($Config.Upstream -notmatch '^quic://[^\s]+$') {
        $errors += "DoQ upstream must start with quic://."
    }
    if (-not (Test-ValidIP -IP $Config.ListenAddress)) {
        $errors += "Listen address must be a valid local IP address."
    }
    if ($Config.ListenPort -lt 1 -or $Config.ListenPort -gt 65535) {
        $errors += "Listen port must be between 1 and 65535."
    }
    if ($Config.Bootstrap -and $Config.Bootstrap -notmatch '^[^\s:]+(?::\d{1,5})?$') {
        $errors += "Bootstrap DNS must be a host or host:port value."
    }

    return $errors
}

function Get-DoqProxyTrustReport {
    param([string]$ProxyPath)

    $report = [pscustomobject]@{
        FullPath = $ProxyPath
        Version = $null
        SHA256 = $null
        Authenticode = $null
        ModifiedTime = $null
    }

    if ([string]::IsNullOrWhiteSpace($ProxyPath) -or -not (Test-Path -LiteralPath $ProxyPath -PathType Leaf)) {
        return $report
    }

    try {
        $item = Get-Item -LiteralPath $ProxyPath -ErrorAction Stop
        $report.ModifiedTime = $item.LastWriteTime.ToString('o')
    } catch { }

    try {
        if (Get-Command 'Get-FileHash' -ErrorAction SilentlyContinue) {
            $hash = Get-FileHash -LiteralPath $ProxyPath -Algorithm SHA256 -ErrorAction Stop
            $report.SHA256 = $hash.Hash
        }
    } catch { }

    try {
        if (Get-Command 'Get-AuthenticodeSignature' -ErrorAction SilentlyContinue) {
            $sig = Get-AuthenticodeSignature -LiteralPath $ProxyPath -ErrorAction Stop
            $report.Authenticode = $sig.Status.ToString()
        }
    } catch { }

    try {
        $versionOutput = & $ProxyPath --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionOutput.Trim())) {
            $report.Version = $versionOutput.Trim()
        }
    } catch { }

    return $report
}

function Format-DoqProxyTrustLines {
    param([pscustomobject]$Report)

    $lines = @()
    if ($Report.FullPath) { $lines += "Path: $($Report.FullPath)" }
    if ($Report.Version) { $lines += "Version: $($Report.Version)" }
    if ($Report.SHA256) { $lines += "SHA256: $($Report.SHA256)" }
    if ($Report.Authenticode) { $lines += "Authenticode: $($Report.Authenticode)" }
    if ($Report.ModifiedTime) { $lines += "Modified: $($Report.ModifiedTime)" }
    if ($lines.Count -eq 0) { $lines += "No binary trust information available." }
    return $lines
}

function Get-DoqProxyLogPaths {
    param(
        [string]$LogsDirectory,
        [datetime]$Timestamp = (Get-Date)
    )

    $stamp = $Timestamp.ToString('yyyyMMdd-HHmmss')
    return [pscustomobject]@{
        StdoutPath = Join-Path $LogsDirectory "doqproxy-stdout-$stamp.log"
        StderrPath = Join-Path $LogsDirectory "doqproxy-stderr-$stamp.log"
    }
}

function Format-DoqProxyHealthState {
    param(
        [pscustomobject]$Process,
        [string]$StderrPath = $null
    )

    if ($null -eq $Process) {
        return [pscustomobject]@{
            State = "Stopped"
            Message = "No NetForge-managed DoQ proxy session."
            LastError = $null
        }
    }

    $lastError = $null
    if (-not [string]::IsNullOrWhiteSpace($StderrPath) -and (Test-Path -LiteralPath $StderrPath -PathType Leaf)) {
        try {
            $stderrLines = @(Get-Content -LiteralPath $StderrPath -Tail 3 -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($stderrLines.Count -gt 0) {
                $lastError = ($stderrLines -join " ").Substring(0, [Math]::Min(($stderrLines -join " ").Length, 300))
            }
        } catch { }
    }

    if ($Process.HasExited) {
        $exitCode = try { $Process.ExitCode } catch { $null }
        $exitText = if ($null -ne $exitCode) { "exit code $exitCode" } else { "exit code unknown" }
        return [pscustomobject]@{
            State = "Exited"
            Message = "DoQ proxy exited ($exitText). PID was $($Process.Id)."
            LastError = $lastError
        }
    }

    $responding = try { -not $Process.HasExited } catch { $false }
    if (-not $responding) {
        return [pscustomobject]@{
            State = "Stale"
            Message = "DoQ proxy process state is indeterminate. PID $($Process.Id)."
            LastError = $lastError
        }
    }

    return [pscustomobject]@{
        State = "Running"
        Message = "DoQ proxy running. PID $($Process.Id)."
        LastError = $lastError
    }
}

function Invoke-ValidateDoqProxy {
    $config = Get-DoqProxyConfiguration
    $errors = Test-DoqProxyConfiguration -Config $config

    if ($errors.Count -gt 0) {
        $script:txtDoqProxyStatus.Text = $errors -join "`n"
        Update-Status "DoQ proxy configuration needs attention" -Type Warning
        return $false
    }

    try {
        $trustReport = Get-DoqProxyTrustReport -ProxyPath $config.ProxyPath
        $trustLines = Format-DoqProxyTrustLines -Report $trustReport

        if ($null -eq $trustReport.Version) {
            $script:txtDoqProxyStatus.Text = "dnsproxy found but --version failed.`n" + ($trustLines -join "`n")
            Update-Status "DoQ proxy validation: version check failed" -Type Warning
            return $false
        }

        $script:txtDoqProxyStatus.Text = "Ready.`n" + ($trustLines -join "`n")
        Write-OperationLog -Action "DoQ proxy validated" -Result "Info" -Detail ($trustLines -join " | ")
        Update-Status "DoQ proxy configuration validated" -Type Success
        return $true
    } catch {
        $script:txtDoqProxyStatus.Text = "dnsproxy validation failed: $($_.Exception.Message)"
        Update-Status "DoQ proxy validation failed" -Type Error
        return $false
    }
}

function Invoke-StartDoqProxy {
    if ($script:DoqProxyProcess -and -not $script:DoqProxyProcess.HasExited) {
        $script:txtDoqProxyStatus.Text = "DoQ proxy already running. PID $($script:DoqProxyProcess.Id)."
        Update-Status "DoQ proxy already running" -Type Warning
        return
    }

    $config = Get-DoqProxyConfiguration
    $errors = Test-DoqProxyConfiguration -Config $config
    if ($errors.Count -gt 0) {
        $script:txtDoqProxyStatus.Text = $errors -join "`n"
        Update-Status "DoQ proxy configuration needs attention" -Type Warning
        return
    }

    $arguments = @(
        "-l", $config.ListenAddress,
        "-p", $config.ListenPort.ToString(),
        "-u", $config.Upstream
    )
    if (-not [string]::IsNullOrWhiteSpace($config.Bootstrap)) {
        $arguments += @("-b", $config.Bootstrap)
    }

    try {
        if (-not (Test-Path -LiteralPath $script:LogsPath)) {
            New-Item -Path $script:LogsPath -ItemType Directory -Force | Out-Null
        }

        $logPaths = Get-DoqProxyLogPaths -LogsDirectory $script:LogsPath
        $script:DoqProxyStderrPath = $logPaths.StderrPath

        $startParams = @{
            FilePath = $config.ProxyPath
            ArgumentList = $arguments
            WindowStyle = 'Hidden'
            PassThru = $true
            RedirectStandardOutput = $logPaths.StdoutPath
            RedirectStandardError = $logPaths.StderrPath
        }
        $script:DoqProxyProcess = Start-Process @startParams
        Start-Sleep -Milliseconds 600

        if ($script:DoqProxyProcess.HasExited) {
            $exitCode = $script:DoqProxyProcess.ExitCode
            $stderrSnippet = ""
            if (Test-Path -LiteralPath $logPaths.StderrPath) {
                $stderrSnippet = (Get-Content -LiteralPath $logPaths.StderrPath -Raw -ErrorAction SilentlyContinue)
                if ($stderrSnippet) { $stderrSnippet = " stderr: $($stderrSnippet.Trim().Substring(0, [Math]::Min($stderrSnippet.Trim().Length, 200)))" }
            }
            $script:DoqProxyProcess = $null
            throw "dnsproxy exited immediately with code $exitCode.$stderrSnippet"
        }

        $trustReport = Get-DoqProxyTrustReport -ProxyPath $config.ProxyPath
        Write-OperationLog -Action "DoQ proxy started" -Result "Info" -Detail "PID $($script:DoqProxyProcess.Id) path=$($config.ProxyPath) SHA256=$($trustReport.SHA256) stdout=$($logPaths.StdoutPath)"

        $script:txtDoqProxyStatus.Text = "DoQ proxy running on $($config.ListenAddress):$($config.ListenPort). PID $($script:DoqProxyProcess.Id).`nLogs: $($logPaths.StdoutPath)"
        Update-Status "DoQ proxy started" -Type Success
    } catch {
        $script:txtDoqProxyStatus.Text = "Failed to start DoQ proxy: $($_.Exception.Message)"
        Update-Status "DoQ proxy start failed" -Type Error
    }
}

function Invoke-StopDoqProxy {
    if (-not $script:DoqProxyProcess -or $script:DoqProxyProcess.HasExited) {
        $script:txtDoqProxyStatus.Text = "No NetForge-managed DoQ proxy is running."
        Update-Status "No DoQ proxy process to stop" -Type Warning
        return
    }

    try {
        Stop-Process -Id $script:DoqProxyProcess.Id -Force -ErrorAction Stop
        $script:txtDoqProxyStatus.Text = "DoQ proxy stopped."
        Update-Status "DoQ proxy stopped" -Type Success
    } catch {
        $script:txtDoqProxyStatus.Text = "Failed to stop DoQ proxy: $($_.Exception.Message)"
        Update-Status "DoQ proxy stop failed" -Type Error
    } finally {
        $script:DoqProxyProcess = $null
    }
}

function Invoke-ApplyDoqLocalResolver {
    $adapter = Get-SelectedAdapter
    $config = Get-DoqProxyConfiguration

    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    if (-not (Test-ValidIP -IP $config.ListenAddress)) {
        Show-MessageBox -Message "Enter a valid local proxy listen address before applying local DNS." -Title "Invalid Listen Address" -Icon Error
        return
    }

    if ($config.ListenPort -ne 53) {
        Show-MessageBox -Message "Windows DNS client settings cannot include a custom DNS port. Use listen port 53 before applying local DNS." -Title "Port 53 Required" -Icon Warning
        return
    }

    try {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($config.ListenAddress) -ErrorAction Stop
        $script:txtDoqProxyStatus.Text = "Adapter '$($adapter.Name)' now uses local DoQ proxy DNS at $($config.ListenAddress)."
        Update-Status "Local DoQ proxy DNS applied to $($adapter.Name)" -Type Success
        Update-AdapterDetails
    } catch {
        $script:txtDoqProxyStatus.Text = "Failed to apply local DNS: $($_.Exception.Message)"
        Update-Status "Local DoQ proxy DNS apply failed" -Type Error
    }
}

# ============================================================================
# PROFILE FUNCTIONS
# ============================================================================
function Get-ProfileProperty {
    param(
        [pscustomobject]$ProfileData,
        [string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $ProfileData) { return $DefaultValue }
    $property = $ProfileData.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    if ($null -eq $property.Value) { return $DefaultValue }
    return $property.Value
}

function ConvertTo-ProfileBoolean {
    param(
        $Value,
        [bool]$DefaultValue = $false
    )

    if ($null -eq $Value) { return $DefaultValue }
    if ($Value -is [bool]) { return $Value }

    $text = ([string]$Value).Trim()
    if ($text -match '^(true|1|yes)$') { return $true }
    if ($text -match '^(false|0|no)$') { return $false }
    return $DefaultValue
}

function Get-ProfileScheduleDayAliases {
    $aliases = @{
        mon = "Monday"; monday = "Monday"
        tue = "Tuesday"; tues = "Tuesday"; tuesday = "Tuesday"
        wed = "Wednesday"; weds = "Wednesday"; wednesday = "Wednesday"
        thu = "Thursday"; thur = "Thursday"; thurs = "Thursday"; thursday = "Thursday"
        fri = "Friday"; friday = "Friday"
        sat = "Saturday"; saturday = "Saturday"
        sun = "Sunday"; sunday = "Sunday"
    }

    return $aliases
}

function Normalize-ProfileScheduleDays {
    param(
        $Days,
        [switch]$DefaultToEveryDay
    )

    $orderedDays = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    $tokens = @()

    if ($null -ne $Days) {
        if ($Days -is [string]) {
            $dayText = (([string]$Days).Trim() -replace '(?i)\bevery\s+day\b', 'everyday')
            $tokens = @($dayText -split '[,;|\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        } else {
            foreach ($day in @($Days)) {
                if ($null -eq $day) { continue }
                $dayText = (([string]$day).Trim() -replace '(?i)\bevery\s+day\b', 'everyday')
                $tokens += @($dayText -split '[,;|\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }
    }

    if ($tokens.Count -eq 0) {
        return [pscustomobject]@{
            IsValid = $true
            Days = if ($DefaultToEveryDay) { [object[]]@($orderedDays) } else { [object[]]@() }
            Message = ""
        }
    }

    $aliases = Get-ProfileScheduleDayAliases
    $selected = New-Object System.Collections.Generic.List[string]
    $errors = @()

    foreach ($token in $tokens) {
        $key = $token.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        if ($key -in @("daily", "everyday", "every-day", "all", "*")) {
            foreach ($day in $orderedDays) {
                if (-not $selected.Contains($day)) { [void]$selected.Add($day) }
            }
            continue
        }

        if ($key -in @("weekday", "weekdays", "workday", "workdays")) {
            foreach ($day in @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")) {
                if (-not $selected.Contains($day)) { [void]$selected.Add($day) }
            }
            continue
        }

        if ($key -in @("weekend", "weekends")) {
            foreach ($day in @("Saturday", "Sunday")) {
                if (-not $selected.Contains($day)) { [void]$selected.Add($day) }
            }
            continue
        }

        if ($aliases.ContainsKey($key)) {
            $dayName = $aliases[$key]
            if (-not $selected.Contains($dayName)) { [void]$selected.Add($dayName) }
        } else {
            $errors += "Unknown schedule day '$token'."
        }
    }

    $normalized = @($orderedDays | Where-Object { $selected.Contains($_) })
    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0 -and $normalized.Count -gt 0)
        Days = [object[]]@($normalized)
        Message = if ($errors.Count -gt 0) {
            ($errors -join " ")
        } elseif ($normalized.Count -eq 0) {
            "Schedule days must include at least one day."
        } else {
            ""
        }
    }
}

function Normalize-ProfileScheduleTime {
    param([string]$Time)

    $text = ([string]$Time).Trim()
    if ($text -notmatch '^(\d{1,2}):(\d{2})$') {
        return [pscustomobject]@{ IsValid = $false; Time = ""; Message = "Schedule time must use HH:mm format." }
    }

    $hour = [int]$Matches[1]
    $minute = [int]$Matches[2]
    if ($hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59) {
        return [pscustomobject]@{ IsValid = $false; Time = ""; Message = "Schedule time must be a valid 24-hour clock time." }
    }

    return [pscustomobject]@{
        IsValid = $true
        Time = ("{0:D2}:{1:D2}" -f $hour, $minute)
        Message = ""
    }
}

function ConvertTo-ProfileScheduleDaysText {
    param($Days)

    $normalized = Normalize-ProfileScheduleDays -Days $Days
    if (-not $normalized.IsValid -or $normalized.Days.Count -eq 0) { return "" }

    $joined = (@($normalized.Days) -join ",")
    if ($joined -eq "Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday") { return "Every day" }
    if ($joined -eq "Monday,Tuesday,Wednesday,Thursday,Friday") { return "Weekdays" }
    if ($joined -eq "Saturday,Sunday") { return "Weekends" }
    return $joined
}

function Get-ProfileScheduleDescription {
    param([pscustomobject]$ProfileData)

    if (-not [bool](Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleEnabled" -DefaultValue $false)) {
        return "Disabled"
    }

    $time = [string](Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleTime" -DefaultValue "")
    $daysText = ConvertTo-ProfileScheduleDaysText -Days (Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleDays" -DefaultValue @())
    if ([string]::IsNullOrWhiteSpace($daysText)) { $daysText = "Every day" }
    return "$time $daysText"
}

function Test-ProfileScheduleDue {
    param(
        [pscustomobject]$ProfileData,
        [datetime]$Now = (Get-Date)
    )

    if (-not [bool](Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleEnabled" -DefaultValue $false)) { return $false }

    $timeResult = Normalize-ProfileScheduleTime -Time ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleTime" -DefaultValue ""))
    if (-not $timeResult.IsValid) { return $false }

    $daysResult = Normalize-ProfileScheduleDays -Days (Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleDays" -DefaultValue @()) -DefaultToEveryDay
    if (-not $daysResult.IsValid) { return $false }
    if (@($daysResult.Days) -notcontains $Now.DayOfWeek.ToString()) { return $false }

    return ($timeResult.Time -eq ("{0:D2}:{1:D2}" -f $Now.Hour, $Now.Minute))
}

function Get-ProfileScheduleDueKey {
    param(
        [pscustomobject]$ProfileData,
        [datetime]$Now = (Get-Date)
    )

    return "$($ProfileData.Name)|$($Now.ToString('yyyyMMdd'))|$([string](Get-ProfileProperty -ProfileData $ProfileData -Name 'ScheduleTime' -DefaultValue ''))"
}

function Get-WlanXmlElementText {
    param(
        [System.Xml.XmlNode]$RootNode,
        [string[]]$LocalPath
    )

    $current = $RootNode
    foreach ($segment in $LocalPath) {
        if ($null -eq $current) { return "" }

        $current = @($current.ChildNodes | Where-Object {
            $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.LocalName -eq $segment
        } | Select-Object -First 1)[0]
    }

    if ($null -eq $current) { return "" }
    return ([string]$current.InnerText).Trim()
}

function ConvertFrom-WlanSsidHex {
    param([string]$Hex)

    $cleanHex = ([string]$Hex).Trim() -replace '\s', ''
    if ([string]::IsNullOrWhiteSpace($cleanHex)) { return "" }
    if (($cleanHex.Length % 2) -ne 0 -or $cleanHex -notmatch '^[0-9A-Fa-f]+$') { return "" }

    try {
        $bytes = New-Object byte[] ([int]($cleanHex.Length / 2))
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            $bytes[$i] = [Convert]::ToByte($cleanHex.Substring($i * 2, 2), 16)
        }

        return ([System.Text.Encoding]::UTF8.GetString($bytes)).Trim([char]0).Trim()
    } catch {
        return ""
    }
}

function ConvertFrom-WlanProfileXmlDocument {
    param(
        [xml]$Document,
        [string]$SourcePath = ""
    )

    if ($null -eq $Document -or $null -eq $Document.DocumentElement -or $Document.DocumentElement.LocalName -ne "WLANProfile") {
        throw "File is not a Windows WLAN profile XML export."
    }

    $root = $Document.DocumentElement
    $profileName = Get-WlanXmlElementText -RootNode $root -LocalPath @("name")
    $ssid = Get-WlanXmlElementText -RootNode $root -LocalPath @("SSIDConfig", "SSID", "name")
    if ([string]::IsNullOrWhiteSpace($ssid)) {
        $ssidHex = Get-WlanXmlElementText -RootNode $root -LocalPath @("SSIDConfig", "SSID", "hex")
        $ssid = ConvertFrom-WlanSsidHex -Hex $ssidHex
    }

    if ([string]::IsNullOrWhiteSpace($ssid)) {
        throw "WLAN profile XML is missing an SSID name."
    }
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        $profileName = $ssid
    }

    $connectionMode = Get-WlanXmlElementText -RootNode $root -LocalPath @("connectionMode")
    $authentication = Get-WlanXmlElementText -RootNode $root -LocalPath @("MSM", "security", "authEncryption", "authentication")
    $encryption = Get-WlanXmlElementText -RootNode $root -LocalPath @("MSM", "security", "authEncryption", "encryption")
    $sourceName = if ([string]::IsNullOrWhiteSpace($SourcePath)) { "WLAN XML" } else { [System.IO.Path]::GetFileName($SourcePath) }

    $descriptionParts = @(
        "Imported from Windows WLAN profile XML '$sourceName'.",
        "SSID: $ssid."
    )
    if (-not [string]::IsNullOrWhiteSpace($authentication)) {
        $descriptionParts += "Authentication: $authentication."
    }
    if (-not [string]::IsNullOrWhiteSpace($encryption)) {
        $descriptionParts += "Encryption: $encryption."
    }
    if (-not [string]::IsNullOrWhiteSpace($connectionMode)) {
        $descriptionParts += "Connection mode: $connectionMode."
    }
    $descriptionParts += "Wireless key material is not stored in NetForge."

    return [pscustomobject]@{
        SchemaVersion = $script:ProfileSchemaVersion
        Name = "Wi-Fi - $profileName"
        Description = ($descriptionParts -join " ")
        AutoApply = $true
        MatchSSID = $ssid
        MatchGatewayMac = ""
        ScheduleEnabled = $false
        ScheduleTime = ""
        ScheduleDays = @()
        UseDHCP = $true
        IPAddress = ""
        SubnetMask = "255.255.255.0"
        Gateway = ""
        PrefixLength = ""
        UseDHCPForDNS = $true
        PrimaryDNS = ""
        SecondaryDNS = ""
        ConfigureNetworkCategory = $false
        NetworkCategory = ""
        ConfigureProxy = $false
        ProxyEnabled = $false
        ProxyServer = ""
        ProxyBypass = ""
        ConfigureDefaultPrinter = $false
        DefaultPrinterName = ""
        ConfigureMappedDrives = $false
        MappedDrives = @()
        CreatedAt = (Get-Date).ToString("o")
        UpdatedAt = (Get-Date).ToString("o")
    }
}

function Get-ProfileImportRecords {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Import file was not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq ".xml") {
        try {
            [xml]$wlanXml = Get-Content -LiteralPath $Path -Raw
        } catch {
            throw "Could not read WLAN profile XML: $($_.Exception.Message)"
        }

        return [pscustomobject]@{
            SourceKind = "WLAN XML"
            SourcePath = $Path
            Profiles = @((ConvertFrom-WlanProfileXmlDocument -Document $wlanXml -SourcePath $Path))
        }
    }

    $import = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $incomingProfiles = @()

    if ($import.Profiles) {
        $incomingProfiles = @($import.Profiles)
    } elseif ($import.Name) {
        $incomingProfiles = @($import)
    } else {
        throw "No profile records were found in $Path."
    }

    return [pscustomobject]@{
        SourceKind = "JSON"
        SourcePath = $Path
        Profiles = @($incomingProfiles)
    }
}

function Get-ConfigExportManifest {
    param(
        [pscustomobject[]]$Profiles,
        [string]$Mode = "full"
    )

    $redactedFields = @('MatchGatewayMac', 'ProxyServer', 'ProxyBypassList', 'MappedDrives')
    $included = @()
    $suppressed = @()

    foreach ($profile in $Profiles) {
        $entry = [pscustomobject]@{
            Name = [string]$profile.Name
            HasAutoApply = [bool]$profile.AutoApply
        }
        $included += $entry
    }

    if ($Mode -eq "shareable") {
        $suppressed = $redactedFields
    }

    return [pscustomobject]@{
        Mode = $Mode
        ProfileCount = $Profiles.Count
        IncludedProfiles = $included
        SuppressedFields = $suppressed
    }
}

function Get-ProfileImportPreview {
    param(
        [pscustomobject[]]$IncomingProfiles,
        [string[]]$ExistingProfileNames
    )

    $accepted = @()
    $conflicting = @()
    $rejected = @()

    foreach ($profile in $IncomingProfiles) {
        $name = [string]$profile.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $rejected += [pscustomobject]@{ Name = "(unnamed)"; Reason = "Missing profile name." }
            continue
        }

        if ($ExistingProfileNames -contains $name) {
            $conflicting += [pscustomobject]@{ Name = $name; Reason = "Profile already exists." }
        } else {
            $accepted += [pscustomobject]@{ Name = $name }
        }
    }

    return [pscustomobject]@{
        AcceptedCount = $accepted.Count
        ConflictingCount = $conflicting.Count
        RejectedCount = $rejected.Count
        Accepted = $accepted
        Conflicting = $conflicting
        Rejected = $rejected
    }
}

function Format-ImportPreviewReport {
    param([pscustomobject]$Preview)

    $lines = @()
    $lines += "Import preview:"
    $lines += "  Accept: $($Preview.AcceptedCount) profile(s)"
    $lines += "  Conflict: $($Preview.ConflictingCount) profile(s) already exist"
    $lines += "  Rejected: $($Preview.RejectedCount) profile(s) invalid"

    if ($Preview.ConflictingCount -gt 0) {
        $lines += ""
        $lines += "Conflicting profiles (will be skipped):"
        foreach ($c in $Preview.Conflicting) {
            $lines += "  - $($c.Name): $($c.Reason)"
        }
    }

    if ($Preview.RejectedCount -gt 0) {
        $lines += ""
        $lines += "Rejected profiles:"
        foreach ($r in $Preview.Rejected) {
            $lines += "  - $($r.Name): $($r.Reason)"
        }
    }

    return ($lines -join "`n")
}

function Get-SafeProfileFileName {
    param([string]$Name)

    $safeName = ([string]$Name).Trim() -replace '[^\w\-]', '_'
    $safeName = $safeName.Trim("_")
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "Profile" }
    return "$safeName.json"
}

function Get-ProfileFilePath {
    param([string]$Name)

    return (Join-Path $script:ProfilesPath (Get-SafeProfileFileName -Name $Name))
}

function ConvertFrom-MappedDriveText {
    param([string]$Text)

    $drives = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $drives }

    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -notmatch '^([A-Za-z]):?\s*(?:=|->)?\s*(\\\\[^\s\\]+\\[^\s]+)\s*$') {
            throw "Mapped drive line '$trimmed' must look like Z: \\server\share."
        }

        $driveLetter = $Matches[1].ToUpperInvariant()
        $remotePath = $Matches[2].Trim()
        $drives += [pscustomobject]@{
            DriveLetter = $driveLetter
            RemotePath = $remotePath
            Persistent = $true
        }
    }

    return @($drives)
}

function ConvertTo-MappedDriveText {
    param($MappedDrives)

    $lines = @()
    foreach ($drive in @($MappedDrives)) {
        if ($null -eq $drive) { continue }
        $letter = ([string](Get-ProfileProperty -ProfileData $drive -Name "DriveLetter" -DefaultValue "")).Trim().TrimEnd(":").ToUpperInvariant()
        $remote = ([string](Get-ProfileProperty -ProfileData $drive -Name "RemotePath" -DefaultValue "")).Trim()
        if ([string]::IsNullOrWhiteSpace($letter) -or [string]::IsNullOrWhiteSpace($remote)) { continue }
        $lines += "$letter`: $remote"
    }

    return ($lines -join "`r`n")
}

function Normalize-MappedDriveList {
    param($MappedDrives)

    $errors = @()
    $normalized = @()

    if ($null -eq $MappedDrives) {
        return [pscustomobject]@{ IsValid = $true; MappedDrives = @(); Message = "" }
    }

    if ($MappedDrives -is [string]) {
        try {
            $MappedDrives = ConvertFrom-MappedDriveText -Text $MappedDrives
        } catch {
            return [pscustomobject]@{ IsValid = $false; MappedDrives = @(); Message = $_.Exception.Message }
        }
    }

    foreach ($drive in @($MappedDrives)) {
        if ($null -eq $drive) { continue }

        $driveLetter = ([string](Get-ProfileProperty -ProfileData $drive -Name "DriveLetter" -DefaultValue "")).Trim().TrimEnd(":").ToUpperInvariant()
        $remotePath = ([string](Get-ProfileProperty -ProfileData $drive -Name "RemotePath" -DefaultValue "")).Trim()
        $persistent = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $drive -Name "Persistent" -DefaultValue $true) -DefaultValue $true

        if ($driveLetter -notmatch '^[A-Z]$') {
            $errors += "Mapped drive letters must be A-Z."
            continue
        }
        if ($remotePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
            $errors += "Mapped drive $driveLetter`: must target a UNC path."
            continue
        }
        if ($normalized | Where-Object { $_.DriveLetter -eq $driveLetter }) {
            $errors += "Mapped drive $driveLetter`: is duplicated."
            continue
        }

        $normalized += [pscustomobject]@{
            DriveLetter = $driveLetter
            RemotePath = $remotePath
            Persistent = $persistent
        }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        MappedDrives = [object[]]@($normalized)
        Message = ($errors -join " ")
    }
}

function Get-SystemProxySnapshot {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $values = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        Enabled = ($values -and [int]$values.ProxyEnable -eq 1)
        Server = if ($values -and $values.ProxyServer) { [string]$values.ProxyServer } else { "" }
        Bypass = if ($values -and $values.ProxyOverride) { [string]$values.ProxyOverride } else { "" }
    }
}

function Set-SystemProxyState {
    param(
        [bool]$Enabled,
        [string]$Server = "",
        [string]$Bypass = ""
    )

    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -LiteralPath $path -Name ProxyEnable -Value ($(if ($Enabled) { 1 } else { 0 })) -ErrorAction Stop
    Set-ItemProperty -LiteralPath $path -Name ProxyServer -Value $Server -ErrorAction Stop
    Set-ItemProperty -LiteralPath $path -Name ProxyOverride -Value $Bypass -ErrorAction Stop
}

function Get-DefaultPrinterName {
    $printer = Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Default } | Select-Object -First 1
    if ($printer) { return [string]$printer.Name }
    return ""
}

function Set-DefaultPrinterByName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $printer = Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $printer) {
        throw "Printer '$Name' was not found."
    }

    $result = Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop
    if ($result.ReturnValue -ne 0) {
        throw "SetDefaultPrinter returned $($result.ReturnValue)."
    }
}

function Get-MappedDriveState {
    $drives = @()
    $rows = @(Get-CimInstance -ClassName Win32_MappedLogicalDisk -ErrorAction SilentlyContinue)
    foreach ($row in $rows) {
        $letter = ([string]$row.DeviceID).Trim().TrimEnd(":").ToUpperInvariant()
        $remote = ([string]$row.ProviderName).Trim()
        if ($letter -match '^[A-Z]$' -and $remote -match '^\\\\') {
            $drives += [pscustomobject]@{
                DriveLetter = $letter
                RemotePath = $remote
                Persistent = $true
            }
        }
    }

    return @($drives)
}

function Set-MappedDriveState {
    param($MappedDrives)

    $targetValidation = Normalize-MappedDriveList -MappedDrives $MappedDrives
    if (-not $targetValidation.IsValid) {
        throw $targetValidation.Message
    }

    $targetDrives = @($targetValidation.MappedDrives)
    $currentDrives = @(Get-MappedDriveState)
    $targetLetters = @($targetDrives | ForEach-Object { $_.DriveLetter })

    foreach ($current in $currentDrives) {
        if ($targetLetters -notcontains $current.DriveLetter) {
            & net.exe use "$($current.DriveLetter):" /delete /y | Out-Null
        }
    }

    foreach ($drive in $targetDrives) {
        $existing = $currentDrives | Where-Object { $_.DriveLetter -eq $drive.DriveLetter } | Select-Object -First 1
        if ($existing -and $existing.RemotePath -ne $drive.RemotePath) {
            & net.exe use "$($drive.DriveLetter):" /delete /y | Out-Null
        }

        $persistentArg = if ($drive.Persistent) { "/persistent:yes" } else { "/persistent:no" }
        & net.exe use "$($drive.DriveLetter):" $drive.RemotePath $persistentArg | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to map drive $($drive.DriveLetter): to $($drive.RemotePath)."
        }
    }
}

function Get-ProfileValidationResult {
    param([pscustomobject]$ProfileData)

    $errors = @()
    $name = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "Name" -DefaultValue "")).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $errors += "Profile name is required."
    }

    $schemaRaw = Get-ProfileProperty -ProfileData $ProfileData -Name "SchemaVersion" -DefaultValue $script:ProfileSchemaVersion
    $schemaVersion = 0
    if (-not [int]::TryParse(([string]$schemaRaw), [ref]$schemaVersion)) {
        $errors += "SchemaVersion must be a number."
    } elseif ($schemaVersion -gt $script:ProfileSchemaVersion) {
        $errors += "SchemaVersion $schemaVersion is newer than this NetForge build supports."
    } elseif ($schemaVersion -lt 1) {
        $schemaVersion = $script:ProfileSchemaVersion
    }

    $useDhcp = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "UseDHCP" -DefaultValue $true) -DefaultValue $true
    $useDnsAutomatic = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "UseDHCPForDNS" -DefaultValue $true) -DefaultValue $true
    $autoApply = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "AutoApply" -DefaultValue $false) -DefaultValue $false

    $description = [string](Get-ProfileProperty -ProfileData $ProfileData -Name "Description" -DefaultValue "")
    $matchSsid = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "MatchSSID" -DefaultValue "")).Trim()
    $matchGatewayMacRaw = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "MatchGatewayMac" -DefaultValue "")).Trim()
    $matchGatewayMac = ""
    if (-not [string]::IsNullOrWhiteSpace($matchGatewayMacRaw)) {
        if (Test-ValidMacAddress -MacAddress $matchGatewayMacRaw) {
            $matchGatewayMac = ConvertTo-CleanMacAddress -MacAddress $matchGatewayMacRaw
        } else {
            $errors += "Gateway MAC must be a valid unicast MAC address."
        }
    }

    if ($autoApply -and [string]::IsNullOrWhiteSpace($matchSsid) -and [string]::IsNullOrWhiteSpace($matchGatewayMac)) {
        $errors += "Auto-apply profiles need a match SSID or gateway MAC."
    }

    $scheduleEnabled = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleEnabled" -DefaultValue $false) -DefaultValue $false
    $scheduleTime = ""
    $scheduleDays = @()
    if ($scheduleEnabled) {
        $scheduleTimeResult = Normalize-ProfileScheduleTime -Time ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleTime" -DefaultValue ""))
        if ($scheduleTimeResult.IsValid) {
            $scheduleTime = $scheduleTimeResult.Time
        } else {
            $errors += $scheduleTimeResult.Message
        }

        $scheduleDaysResult = Normalize-ProfileScheduleDays -Days (Get-ProfileProperty -ProfileData $ProfileData -Name "ScheduleDays" -DefaultValue @()) -DefaultToEveryDay
        if ($scheduleDaysResult.IsValid) {
            $scheduleDays = @($scheduleDaysResult.Days)
        } else {
            $errors += $scheduleDaysResult.Message
        }
    }

    $ipAddress = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "IPAddress" -DefaultValue "")).Trim()
    $subnetMask = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "SubnetMask" -DefaultValue "255.255.255.0")).Trim()
    $gateway = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "Gateway" -DefaultValue "")).Trim()
    $prefixText = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "PrefixLength" -DefaultValue "24")).Trim()
    $prefix = 24

    if (-not $useDhcp) {
        if (-not (Test-ValidIPv4Address -IP $ipAddress)) {
            $errors += "Static profiles need a valid IPv4 address."
        }
        if (-not [string]::IsNullOrWhiteSpace($subnetMask) -and -not (Test-ValidIPv4Address -IP $subnetMask)) {
            $errors += "Subnet mask must be a valid IPv4 mask."
        }
        if (-not [int]::TryParse($prefixText, [ref]$prefix) -or -not (Test-ValidIPv4PrefixLength -PrefixLength $prefix)) {
            $errors += "Prefix length must be a number from 1 to 32."
        }
        if (-not [string]::IsNullOrWhiteSpace($gateway) -and -not (Test-ValidIPv4Address -IP $gateway)) {
            $errors += "Gateway must be a valid IPv4 address."
        }
    }

    $primaryDns = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "PrimaryDNS" -DefaultValue "")).Trim()
    $secondaryDns = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "SecondaryDNS" -DefaultValue "")).Trim()
    if (-not $useDnsAutomatic) {
        if (-not (Test-ValidIP -IP $primaryDns)) {
            $errors += "Static DNS profiles need a valid primary DNS server."
        }
        if (-not [string]::IsNullOrWhiteSpace($secondaryDns) -and -not (Test-ValidIP -IP $secondaryDns)) {
            $errors += "Secondary DNS must be a valid IP address."
        }
    }

    $configureNetworkCategory = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "ConfigureNetworkCategory" -DefaultValue $false) -DefaultValue $false
    $networkCategory = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "NetworkCategory" -DefaultValue "Private")).Trim()
    if ($configureNetworkCategory -and $networkCategory -notin @("Public", "Private")) {
        $errors += "Network category must be Public or Private."
    }

    $configureProxy = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "ConfigureProxy" -DefaultValue $false) -DefaultValue $false
    $proxyEnabled = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "ProxyEnabled" -DefaultValue $false) -DefaultValue $false
    $proxyServer = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "ProxyServer" -DefaultValue "")).Trim()
    $proxyBypass = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "ProxyBypass" -DefaultValue "")).Trim()
    if ($configureProxy -and $proxyEnabled) {
        if ([string]::IsNullOrWhiteSpace($proxyServer)) {
            $errors += "Enabled proxy profiles need a proxy server."
        } elseif ($proxyServer -match '\s') {
            $errors += "Proxy server cannot contain whitespace."
        }
    }

    $configureDefaultPrinter = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "ConfigureDefaultPrinter" -DefaultValue $false) -DefaultValue $false
    $defaultPrinterName = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "DefaultPrinterName" -DefaultValue "")).Trim()
    if ($configureDefaultPrinter -and [string]::IsNullOrWhiteSpace($defaultPrinterName)) {
        $errors += "Default printer profiles need a printer name."
    }

    $configureMappedDrives = ConvertTo-ProfileBoolean -Value (Get-ProfileProperty -ProfileData $ProfileData -Name "ConfigureMappedDrives" -DefaultValue $false) -DefaultValue $false
    $mappedDriveInput = Get-ProfileProperty -ProfileData $ProfileData -Name "MappedDrives" -DefaultValue @()
    $mappedDriveValidation = Normalize-MappedDriveList -MappedDrives $mappedDriveInput
    if ($configureMappedDrives -and -not $mappedDriveValidation.IsValid) {
        $errors += $mappedDriveValidation.Message
    }

    $createdAt = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "CreatedAt" -DefaultValue "")).Trim()
    if ([string]::IsNullOrWhiteSpace($createdAt)) {
        $createdAt = (Get-Date).ToString("o")
    }
    $updatedAt = ([string](Get-ProfileProperty -ProfileData $ProfileData -Name "UpdatedAt" -DefaultValue "")).Trim()
    if ([string]::IsNullOrWhiteSpace($updatedAt)) {
        $updatedAt = $createdAt
    }

    if ($errors.Count -gt 0) {
        return [pscustomobject]@{
            IsValid = $false
            Message = ($errors -join " ")
            Profile = $null
            SafeFileName = ""
        }
    }

    $normalized = [ordered]@{
        SchemaVersion = $script:ProfileSchemaVersion
        Name = $name
        Description = $description
        AutoApply = $autoApply
        MatchSSID = $matchSsid
        MatchGatewayMac = $matchGatewayMac
        ScheduleEnabled = $scheduleEnabled
        ScheduleTime = if ($scheduleEnabled) { $scheduleTime } else { "" }
        ScheduleDays = if ($scheduleEnabled) { ,([object[]]@($scheduleDays)) } else { ,([object[]]@()) }
        UseDHCP = $useDhcp
        IPAddress = $ipAddress
        SubnetMask = $subnetMask
        Gateway = $gateway
        PrefixLength = if ($useDhcp) { "" } else { [string]$prefix }
        UseDHCPForDNS = $useDnsAutomatic
        PrimaryDNS = $primaryDns
        SecondaryDNS = $secondaryDns
        ConfigureNetworkCategory = $configureNetworkCategory
        NetworkCategory = if ($configureNetworkCategory) { $networkCategory } else { "" }
        ConfigureProxy = $configureProxy
        ProxyEnabled = $proxyEnabled
        ProxyServer = if ($configureProxy) { $proxyServer } else { "" }
        ProxyBypass = if ($configureProxy) { $proxyBypass } else { "" }
        ConfigureDefaultPrinter = $configureDefaultPrinter
        DefaultPrinterName = if ($configureDefaultPrinter) { $defaultPrinterName } else { "" }
        ConfigureMappedDrives = $configureMappedDrives
        MappedDrives = if ($configureMappedDrives) { ,([object[]]@($mappedDriveValidation.MappedDrives)) } else { ,([object[]]@()) }
        CreatedAt = $createdAt
        UpdatedAt = $updatedAt
    }

    return [pscustomobject]@{
        IsValid = $true
        Message = ""
        Profile = [pscustomobject]$normalized
        SafeFileName = (Get-SafeProfileFileName -Name $name)
    }
}

function Write-ProfileFileAtomic {
    param(
        [pscustomobject]$ProfileData,
        [string]$FilePath
    )

    $directory = Split-Path -Path $FilePath -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $tempPath = Join-Path $directory ".$fileName.$([guid]::NewGuid().ToString('N')).tmp"
    $backupPath = Join-Path $directory ".$fileName.bak"

    try {
        $ProfileData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tempPath -Encoding UTF8

        if (Test-Path -LiteralPath $FilePath) {
            [System.IO.File]::Replace($tempPath, $FilePath, $backupPath, $true)
            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            [System.IO.File]::Move($tempPath, $FilePath)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Import-NetForgeQrAssembly {
    param(
        [switch]$Encoder,
        [switch]$Decoder
    )

    if ($Encoder -and -not [type]::GetType("QRCoder.QRCodeGenerator, QRCoder", $false)) {
        $encoderPath = Join-Path $script:LibraryPath "QRCoder.dll"
        if (-not (Test-Path -LiteralPath $encoderPath)) {
            throw "QRCoder.dll was not found in $script:LibraryPath."
        }
        Add-Type -Path $encoderPath
    }

    if ($Decoder -and -not [type]::GetType("ZXing.BarcodeReader, zxing", $false)) {
        $decoderPath = Join-Path $script:LibraryPath "zxing.dll"
        if (-not (Test-Path -LiteralPath $decoderPath)) {
            throw "zxing.dll was not found in $script:LibraryPath."
        }
        Add-Type -Path $decoderPath
    }
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes) { return "" }
    return ([Convert]::ToBase64String($Bytes).TrimEnd("=") -replace "\+", "-" -replace "/", "_")
}

function ConvertFrom-Base64Url {
    param([string]$Text)

    $normalized = ([string]$Text).Trim() -replace "-", "+" -replace "_", "/"
    switch ($normalized.Length % 4) {
        2 { $normalized += "==" }
        3 { $normalized += "=" }
        1 { throw "Invalid Base64URL payload length." }
    }

    return [Convert]::FromBase64String($normalized)
}

function ConvertTo-GzipBase64Url {
    param([string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
    $stream = New-Object System.IO.MemoryStream
    $gzip = $null
    try {
        $gzip = New-Object System.IO.Compression.GzipStream -ArgumentList $stream, ([System.IO.Compression.CompressionMode]::Compress)
        $gzip.Write($bytes, 0, $bytes.Length)
        $gzip.Dispose()
        $gzip = $null
        return ConvertTo-Base64Url -Bytes $stream.ToArray()
    } finally {
        if ($gzip) { $gzip.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function ConvertFrom-GzipBase64Url {
    param([string]$Text)

    $bytes = ConvertFrom-Base64Url -Text $Text
    $inputStream = New-Object System.IO.MemoryStream -ArgumentList @(,$bytes)
    $gzip = $null
    $outputStream = New-Object System.IO.MemoryStream
    try {
        $gzip = New-Object System.IO.Compression.GzipStream -ArgumentList $inputStream, ([System.IO.Compression.CompressionMode]::Decompress)
        $buffer = New-Object byte[] 4096
        while (($read = $gzip.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
        }
        return [System.Text.Encoding]::UTF8.GetString($outputStream.ToArray())
    } finally {
        if ($gzip) { $gzip.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($outputStream) { $outputStream.Dispose() }
    }
}

function ConvertTo-ProfileQrPayload {
    param([pscustomobject]$ProfileData)

    $validation = Get-ProfileValidationResult -ProfileData $ProfileData
    if (-not $validation.IsValid) {
        throw $validation.Message
    }

    $envelope = [ordered]@{
        Kind = "NetForgeProfile"
        PayloadVersion = 1
        AppVersion = $script:AppVersion
        ExportedAt = (Get-Date).ToString("o")
        Profile = $validation.Profile
    }

    $json = ([pscustomobject]$envelope | ConvertTo-Json -Depth 12 -Compress)
    $payload = "$script:ProfileQrPayloadPrefix$(ConvertTo-GzipBase64Url -Text $json)"
    if ($payload.Length -gt $script:ProfileQrMaxPayloadLength) {
        throw "Profile QR payload is $($payload.Length) characters, above the $script:ProfileQrMaxPayloadLength character limit. Use JSON export for this profile."
    }

    return $payload
}

function ConvertFrom-ProfileQrPayload {
    param([string]$Payload)

    $text = ([string]$Payload).Trim()
    if (-not $text.StartsWith($script:ProfileQrPayloadPrefix, [System.StringComparison]::Ordinal)) {
        throw "QR payload is not a NetForge profile QR code."
    }

    $encoded = $text.Substring($script:ProfileQrPayloadPrefix.Length)
    $json = ConvertFrom-GzipBase64Url -Text $encoded
    $envelope = $json | ConvertFrom-Json
    if ($envelope.Kind -ne "NetForgeProfile" -or [int]$envelope.PayloadVersion -ne 1) {
        throw "Unsupported NetForge profile QR payload."
    }

    $validation = Get-ProfileValidationResult -ProfileData $envelope.Profile
    if (-not $validation.IsValid) {
        throw $validation.Message
    }

    return [pscustomobject]@{
        Profile = $validation.Profile
        SafeFileName = $validation.SafeFileName
        ExportedAt = $envelope.ExportedAt
        AppVersion = $envelope.AppVersion
    }
}

function Write-ProfileImportLog {
    param([string[]]$Lines)

    if ($script:txtDiagOutput) {
        $script:txtDiagOutput.Text = ($Lines -join "`n")
    }
}

function Resolve-ProfileStorePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
        if (-not [System.IO.Path]::IsPathRooted($expanded)) { return "" }
        return [System.IO.Path]::GetFullPath($expanded)
    } catch {
        return ""
    }
}

function Test-SamePath {
    param(
        [string]$PathA,
        [string]$PathB
    )

    $resolvedA = Resolve-ProfileStorePath -Path $PathA
    $resolvedB = Resolve-ProfileStorePath -Path $PathB
    if ([string]::IsNullOrWhiteSpace($resolvedA) -or [string]::IsNullOrWhiteSpace($resolvedB)) { return $false }

    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $normalizedA = $resolvedA.TrimEnd($trimChars)
    $normalizedB = $resolvedB.TrimEnd($trimChars)
    return $normalizedA.Equals($normalizedB, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-FileSha256 {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $hashBytes = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hashBytes) -replace "-", "").ToLowerInvariant()
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($sha) { $sha.Dispose() }
    }
}

function Get-KnownSettingNames {
    return @(
        'SettingsSchemaVersion',
        'ProfileStorePath',
        'UiLocale',
        'UiTheme',
        'CompactMode',
        'PublicIpLookupEnabled',
        'ExternalSpeedTestEnabled',
        'SpeedTestEndpoint',
        'DiscordWebhookEnabled',
        'DiscordWebhookUrl',
        'DiscordWebhookUrlProtected',
        'AppRoutingPolicies',
        'UpdatedAt'
    )
}

function Test-SettingsSchema {
    param($Settings)

    $issues = @()
    $known = Get-KnownSettingNames

    foreach ($key in @($Settings.Keys)) {
        if ($key -eq 'SettingsReadWarning') { continue }
        if ($known -notcontains $key) {
            $issues += "Unknown setting key: $key"
        }
    }

    $schemaVersion = 0
    if ($Settings.Contains('SettingsSchemaVersion')) {
        [void][int]::TryParse([string]$Settings['SettingsSchemaVersion'], [ref]$schemaVersion)
    }

    if ($schemaVersion -gt $script:SettingsSchemaVersion) {
        $issues += "Settings schema version $schemaVersion is newer than supported version $($script:SettingsSchemaVersion)."
    }

    return [pscustomobject]@{
        IsValid = ($issues.Count -eq 0)
        SchemaVersion = $schemaVersion
        Issues = $issues
    }
}

function Backup-SettingsFile {
    param(
        [string]$SettingsPath,
        [string]$ConfigDirectory,
        [string]$Reason = "migration"
    )

    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return $null }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupName = "settings-backup-$stamp-$Reason.json"
    $backupPath = Join-Path $ConfigDirectory $backupName

    try {
        Copy-Item -LiteralPath $SettingsPath -Destination $backupPath -Force -ErrorAction Stop
        return $backupPath
    } catch {
        return $null
    }
}

function Get-AppSettings {
    $settings = [ordered]@{}
    if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return $settings }

    try {
        $rawJson = Get-Content -Raw -LiteralPath $script:SettingsFile
        if ([string]::IsNullOrWhiteSpace($rawJson)) { return $settings }

        $json = $rawJson | ConvertFrom-Json
        foreach ($property in $json.PSObject.Properties) {
            $settings[$property.Name] = $property.Value
        }
    } catch {
        $quarantinePath = Backup-SettingsFile -SettingsPath $script:SettingsFile -ConfigDirectory $script:ConfigPath -Reason "corrupt"
        $quarantineNote = if ($quarantinePath) { " Quarantined to $([System.IO.Path]::GetFileName($quarantinePath))." } else { "" }
        $settings["SettingsReadWarning"] = "Settings file is corrupt: $($_.Exception.Message).$quarantineNote"
    }

    if ($settings.Count -gt 0 -and -not $settings.Contains('SettingsReadWarning')) {
        $validation = Test-SettingsSchema -Settings $settings
        if (-not $validation.IsValid) {
            foreach ($issue in $validation.Issues) {
                Write-OperationLog -Action "SettingsValidation" -Result "Warning" -Detail $issue
            }
        }
    }

    return $settings
}

function Save-AppSetting {
    param(
        [string]$Name,
        $Value
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Setting name is required."
    }
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        New-Item -Path $script:ConfigPath -ItemType Directory -Force | Out-Null
    }

    $settings = Get-AppSettings
    if (Test-ProtectedAppSettingName -Name $Name) {
        $protectedName = Get-ProtectedAppSettingName -Name $Name
        if ([string]::IsNullOrWhiteSpace([string]$Value)) {
            [void]$settings.Remove($Name)
            [void]$settings.Remove($protectedName)
        } else {
            $settings[$protectedName] = Protect-AppSettingSecret -Value ([string]$Value)
            [void]$settings.Remove($Name)
        }
    } else {
        $settings[$Name] = $Value
    }
    $hasSchema = try { $settings.Contains('SettingsSchemaVersion') } catch { $false }
    if (-not $hasSchema) {
        Backup-SettingsFile -SettingsPath $script:SettingsFile -ConfigDirectory $script:ConfigPath -Reason "schema-upgrade" | Out-Null
    }
    $settings["SettingsSchemaVersion"] = $script:SettingsSchemaVersion
    $settings["UpdatedAt"] = (Get-Date).ToString("o")

    $tempPath = Join-Path $script:ConfigPath "settings.$([guid]::NewGuid().ToString('N')).tmp"
    $backupPath = Join-Path $script:ConfigPath "settings.bak"

    try {
        [pscustomobject]$settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        if (Test-Path -LiteralPath $script:SettingsFile) {
            [System.IO.File]::Replace($tempPath, $script:SettingsFile, $backupPath, $true)
            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            [System.IO.File]::Move($tempPath, $script:SettingsFile)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Complete-PendingProtectedSettingMigrations {
    if ($null -eq $script:PendingProtectedSettingMigrations -or $script:PendingProtectedSettingMigrations.Count -eq 0) {
        return
    }

    foreach ($settingName in @($script:PendingProtectedSettingMigrations.Keys)) {
        try {
            Save-AppSetting -Name $settingName -Value $script:PendingProtectedSettingMigrations[$settingName]
        } catch {
            $script:SecretSettingLoadWarning = "Could not migrate protected setting '$settingName'. $($_.Exception.Message)"
        }
    }

    $script:PendingProtectedSettingMigrations = [ordered]@{}
}

Complete-PendingProtectedSettingMigrations

function Test-CapabilityAvailable {
    param(
        [string]$Name,
        [string]$Type = "Cmdlet"
    )

    switch ($Type) {
        "Cmdlet" {
            $cmd = Get-Command $Name -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Name = $Name; Type = $Type; Available = ($null -ne $cmd); Detail = if ($cmd) { "Available" } else { "Not found" } }
        }
        "Module" {
            $mod = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
            return [pscustomobject]@{ Name = $Name; Type = $Type; Available = ($null -ne $mod); Detail = if ($mod) { "v$($mod.Version)" } else { "Not installed" } }
        }
        "Executable" {
            $exe = Get-Command $Name -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Name = $Name; Type = $Type; Available = ($null -ne $exe); Detail = if ($exe) { $exe.Source } else { "Not found" } }
        }
        "Admin" {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            return [pscustomobject]@{ Name = $Name; Type = $Type; Available = $isAdmin; Detail = if ($isAdmin) { "Elevated" } else { "Standard user" } }
        }
        default {
            return [pscustomobject]@{ Name = $Name; Type = $Type; Available = $false; Detail = "Unknown check type" }
        }
    }
}

function Get-CapabilityMatrix {
    $checks = @(
        Test-CapabilityAvailable -Name "Administrator" -Type "Admin"
        Test-CapabilityAvailable -Name "NetTCPIP" -Type "Module"
        Test-CapabilityAvailable -Name "DnsClient" -Type "Module"
        Test-CapabilityAvailable -Name "NetSecurity" -Type "Module"
        Test-CapabilityAvailable -Name "DhcpServer" -Type "Module"
        Test-CapabilityAvailable -Name "Get-FileHash" -Type "Cmdlet"
        Test-CapabilityAvailable -Name "Get-AuthenticodeSignature" -Type "Cmdlet"
        Test-CapabilityAvailable -Name "pktmon" -Type "Executable"
        Test-CapabilityAvailable -Name "netsh" -Type "Executable"
    )

    return $checks
}

function Format-CapabilityMatrixReport {
    param([pscustomobject[]]$Checks)

    $lines = @()
    $lines += "Capability matrix:"
    foreach ($check in $Checks) {
        $label = if ($check.Available) { "OK" } else { "UNAVAILABLE" }
        $lines += "  [$label] $($check.Name) ($($check.Type)): $($check.Detail)"
    }

    $unavailable = @($Checks | Where-Object { -not $_.Available })
    $lines += ""
    if ($unavailable.Count -eq 0) {
        $lines += "All capabilities available."
    } else {
        $lines += "$($unavailable.Count) capability(ies) unavailable. Some features may be limited."
    }

    return ($lines -join "`n")
}

function Get-AvailableLocales {
    $locales = @()
    if (-not (Test-Path -LiteralPath $script:StringsPath)) { return $locales }

    $files = @(Get-ChildItem -LiteralPath $script:StringsPath -Filter '*.json' -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $locale = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($locale -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$') {
            $locales += $locale
        }
    }
    return @($locales | Sort-Object)
}

function Initialize-LocaleSelector {
    if (-not $script:cmbLocaleSelector) { return }

    $script:cmbLocaleSelector.Items.Clear()
    $available = Get-AvailableLocales

    foreach ($locale in $available) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $locale
        $item.Tag = $locale
        [void]$script:cmbLocaleSelector.Items.Add($item)
        if ($locale -eq $script:UiLocale) {
            $script:cmbLocaleSelector.SelectedItem = $item
        }
    }

    $script:txtLocaleStatus.Text = "Current locale: $($script:UiLocale). $($script:LocalizationStatus)"
}

function Save-LocaleSelection {
    $selected = $null
    if ($script:cmbLocaleSelector -and $script:cmbLocaleSelector.SelectedItem) {
        $selected = [string]$script:cmbLocaleSelector.SelectedItem.Tag
    }

    if ([string]::IsNullOrWhiteSpace($selected)) {
        $script:txtLocaleStatus.Text = "Select a locale before saving."
        Update-Status "No locale selected" -Type Warning
        return
    }

    try {
        Save-AppSetting -Name 'UiLocale' -Value $selected
        $script:txtLocaleStatus.Text = "Locale set to $selected. Restart NetForge to apply the new language."
        Update-Status "Locale saved: $selected (restart required)" -Type Success
    } catch {
        $script:txtLocaleStatus.Text = "Failed to save locale: $($_.Exception.Message)"
        Update-Status "Locale save failed" -Type Error
    }
}

function Set-EndpointPolicyStatus {
    param([string]$Message)

    if ($script:txtEndpointPolicyStatus) {
        $script:txtEndpointPolicyStatus.Text = $Message
    }
}

function Initialize-EndpointPolicyControls {
    if ($script:chkPublicIpLookup) {
        $script:chkPublicIpLookup.IsChecked = [bool]$script:PublicIpLookupEnabled
    }
    if ($script:chkExternalSpeedTest) {
        $script:chkExternalSpeedTest.IsChecked = [bool]$script:ExternalSpeedTestEnabled
    }
    if ($script:cmbSpeedTestEndpoint) {
        $script:cmbSpeedTestEndpoint.Items.Clear()
        $selectedEndpoint = Resolve-SpeedTestEndpoint -Endpoint $script:SpeedTestEndpoint

        foreach ($endpoint in Get-SpeedTestEndpointCatalog) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $endpoint.Name
            $item.Tag = $endpoint.Url
            [void]$script:cmbSpeedTestEndpoint.Items.Add($item)
            if ($endpoint.Url -eq $selectedEndpoint.Url) {
                $script:cmbSpeedTestEndpoint.SelectedItem = $item
            }
        }

        $script:SpeedTestEndpoint = $selectedEndpoint.Url
    }

    if ($script:btnSpeedTest) {
        $script:btnSpeedTest.IsEnabled = [bool]$script:ExternalSpeedTestEnabled
    }

    $speedLabel = if ($script:ExternalSpeedTestEnabled) { (Resolve-SpeedTestEndpoint -Endpoint $script:SpeedTestEndpoint).Name } else { "disabled" }
    $publicLabel = if ($script:PublicIpLookupEnabled) { "enabled" } else { "disabled" }
    Set-EndpointPolicyStatus -Message "Public IP lookup: $publicLabel. Speed test endpoint: $speedLabel."
}

function Save-EndpointPolicySettings {
    $publicEnabled = ($script:chkPublicIpLookup -and $script:chkPublicIpLookup.IsChecked -eq $true)
    $speedEnabled = ($script:chkExternalSpeedTest -and $script:chkExternalSpeedTest.IsChecked -eq $true)
    $endpointUrl = $script:SpeedTestEndpoint

    if ($script:cmbSpeedTestEndpoint -and $script:cmbSpeedTestEndpoint.SelectedItem) {
        $endpointUrl = [string]$script:cmbSpeedTestEndpoint.SelectedItem.Tag
    }

    $endpoint = Resolve-SpeedTestEndpoint -Endpoint $endpointUrl
    if (-not (Test-HttpsEndpointUri -Uri $endpoint.Url)) {
        $endpoint = Resolve-SpeedTestEndpoint -Endpoint ""
    }

    $script:PublicIpLookupEnabled = $publicEnabled
    $script:ExternalSpeedTestEnabled = $speedEnabled
    $script:SpeedTestEndpoint = $endpoint.Url

    Save-AppSetting -Name "PublicIpLookupEnabled" -Value $publicEnabled
    Save-AppSetting -Name "ExternalSpeedTestEnabled" -Value $speedEnabled
    Save-AppSetting -Name "SpeedTestEndpoint" -Value $endpoint.Url

    if ($script:btnSpeedTest) {
        $script:btnSpeedTest.IsEnabled = $speedEnabled
    }
    if (-not $publicEnabled -and $script:txtConnPublicIP) {
        $script:CachedPublicIP = $null
        $script:txtConnPublicIP.Text = "Disabled"
    } elseif ($publicEnabled -and $script:txtConnPublicIP -and $script:txtConnPublicIP.Text -eq "Disabled") {
        Update-PublicIP
    }

    Write-OperationLog -Action "EndpointPolicy" -Result "Saved" -Detail "PublicIpLookupEnabled=$publicEnabled; ExternalSpeedTestEnabled=$speedEnabled; SpeedTestEndpoint=$($endpoint.Url)"
    Set-EndpointPolicyStatus -Message "Policy saved. Public IP lookup: $publicEnabled. Speed test endpoint: $($endpoint.Name)."
    Update-Status "Endpoint policy saved" -Type Success
}

function ConvertTo-DiscordWebhookSafeText {
    param(
        $Value,
        [int]$MaxLength = 256
    )

    if ($null -eq $Value) { return "Unknown" }
    if ($MaxLength -lt 4) { $MaxLength = 4 }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return "Unknown" }

    $text = [regex]::Replace($text, '[\x00-\x1F\x7F]', ' ')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if ($text.Length -le $MaxLength) { return $text }

    return ($text.Substring(0, $MaxLength - 3) + "...")
}

function Test-DiscordWebhookUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url.Trim(), [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    $webhookHost = $parsedUri.Host.ToLowerInvariant()
    if ($parsedUri.Scheme -ne [System.Uri]::UriSchemeHttps) { return $false }
    if ($webhookHost -notin @("discord.com", "discordapp.com")) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($parsedUri.Query)) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($parsedUri.Fragment)) { return $false }

    $path = $parsedUri.AbsolutePath.TrimEnd("/")
    return ($path -match '^/api/webhooks/[0-9]{15,25}/[A-Za-z0-9_\.-]+$')
}

function Get-DiscordWebhookRedactedUrl {
    param([string]$Url)

    if (-not (Test-DiscordWebhookUrl -Url $Url)) {
        return "invalid Discord webhook URL"
    }

    $parsedUri = [System.Uri]$Url.Trim()
    $segments = @($parsedUri.AbsolutePath.Trim("/").Split("/"))
    $webhookId = if ($segments.Count -ge 3) { $segments[2] } else { "unknown" }
    return "$($parsedUri.Scheme)://$($parsedUri.Host)/api/webhooks/$webhookId/[redacted]"
}

function New-DiscordProfileWebhookPayload {
    param(
        [pscustomobject]$ProfileData,
        $Adapter,
        [string]$Source = "Manual"
    )

    $profileName = "Unknown"
    if ($ProfileData -and $ProfileData.PSObject.Properties["Name"]) {
        $profileName = ConvertTo-DiscordWebhookSafeText -Value $ProfileData.Name -MaxLength 256
    }

    $adapterName = "Unknown"
    if ($Adapter -and $Adapter.PSObject.Properties["Name"]) {
        $adapterName = ConvertTo-DiscordWebhookSafeText -Value $Adapter.Name -MaxLength 256
    }

    $adapterIndex = "Unknown"
    if ($Adapter -and $Adapter.PSObject.Properties["ifIndex"]) {
        $adapterIndex = ConvertTo-DiscordWebhookSafeText -Value $Adapter.ifIndex -MaxLength 32
    } elseif ($Adapter -and $Adapter.PSObject.Properties["InterfaceIndex"]) {
        $adapterIndex = ConvertTo-DiscordWebhookSafeText -Value $Adapter.InterfaceIndex -MaxLength 32
    }

    $hostName = ConvertTo-DiscordWebhookSafeText -Value $env:COMPUTERNAME -MaxLength 128
    $sourceName = ConvertTo-DiscordWebhookSafeText -Value $Source -MaxLength 64
    $utcNow = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture)

    $fields = @(
        [ordered]@{ name = "Profile"; value = $profileName; inline = $true },
        [ordered]@{ name = "Adapter"; value = "$adapterName [$adapterIndex]"; inline = $true },
        [ordered]@{ name = "Source"; value = $sourceName; inline = $true },
        [ordered]@{ name = "Host"; value = $hostName; inline = $true },
        [ordered]@{ name = "Version"; value = $script:AppVersion; inline = $true },
        [ordered]@{ name = "Time"; value = $utcNow; inline = $true }
    )

    $payload = [ordered]@{
        username = "NetForge"
        content = "NetForge applied profile '$profileName' on $hostName."
        allowed_mentions = [ordered]@{
            parse = @()
        }
        embeds = @(
            [ordered]@{
                title = "Profile applied"
                color = 16753920
                timestamp = $utcNow
                fields = $fields
            }
        )
    }

    return ($payload | ConvertTo-Json -Depth 8 -Compress)
}

function Invoke-DiscordWebhookPost {
    param(
        [string]$WebhookUrl,
        [string]$PayloadJson,
        [string]$AppVersion
    )

    $request = $null
    $requestStream = $null
    $response = $null

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    } catch {
        [void]$_.Exception
    }

    try {
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($WebhookUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.UserAgent = "NetForge/$AppVersion"
        $request.Timeout = 5000
        $request.ReadWriteTimeout = 5000

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($PayloadJson)
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Dispose()
        $requestStream = $null

        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        return [pscustomobject]@{
            Success = $true
            StatusCode = [int]$response.StatusCode
            Error = ""
        }
    } catch [System.Net.WebException] {
        $statusCode = 0
        if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        return [pscustomobject]@{
            Success = $false
            StatusCode = $statusCode
            Error = $_.Exception.Message
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            StatusCode = 0
            Error = $_.Exception.Message
        }
    } finally {
        if ($requestStream) { $requestStream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Set-DiscordWebhookStatus {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Discord webhook notifications are disabled."
    }

    $script:DiscordWebhookLastStatus = $Message
    if ($script:txtDiscordWebhookStatus) {
        $script:txtDiscordWebhookStatus.Text = $Message
    }
}

function Complete-DiscordWebhookResult {
    param(
        $Result,
        [string]$RedactedUrl
    )

    if ($Result -and $Result.Success) {
        Set-DiscordWebhookStatus -Message "Last Discord webhook sent to $RedactedUrl."
        Write-OperationLog -Action "Discord profile webhook" -Result "Succeeded" -Detail "Endpoint=$RedactedUrl; StatusCode=$($Result.StatusCode)"
        return
    }

    $errorText = if ($Result -and $Result.Error) { [string]$Result.Error } else { "Unknown webhook error." }
    Set-DiscordWebhookStatus -Message "Discord webhook failed: $errorText"
    Write-OperationLog -Action "Discord profile webhook" -Result "Failed" -Detail "Endpoint=$RedactedUrl; $errorText"
}

function Initialize-DiscordWebhookControls {
    if ($script:chkDiscordWebhook) {
        $script:chkDiscordWebhook.IsChecked = [bool]$script:DiscordWebhookEnabled
    }
    if ($script:txtDiscordWebhookUrl) {
        $script:txtDiscordWebhookUrl.Text = [string]$script:DiscordWebhookUrl
    }

    if (-not $script:DiscordWebhookEnabled) {
        Set-DiscordWebhookStatus -Message "Discord webhook notifications are disabled."
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$script:SecretSettingLoadWarning)) {
        Set-DiscordWebhookStatus -Message "Discord webhook secret could not be read: $script:SecretSettingLoadWarning"
    } elseif (Test-DiscordWebhookUrl -Url $script:DiscordWebhookUrl) {
        Set-DiscordWebhookStatus -Message "Discord webhook enabled for $(Get-DiscordWebhookRedactedUrl -Url $script:DiscordWebhookUrl)."
    } else {
        Set-DiscordWebhookStatus -Message "Discord webhook is enabled, but the saved URL is invalid."
    }
}

function Save-DiscordWebhookSettings {
    $enabled = ($script:chkDiscordWebhook -and $script:chkDiscordWebhook.IsChecked -eq $true)
    $url = ""
    if ($script:txtDiscordWebhookUrl) {
        $url = ([string]$script:txtDiscordWebhookUrl.Text).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($url) -and -not (Test-DiscordWebhookUrl -Url $url)) {
        Set-DiscordWebhookStatus -Message "Discord webhook URL must be an HTTPS discord.com/api/webhooks URL."
        Write-OperationLog -Action "Discord profile webhook" -Result "Rejected" -Detail "Invalid webhook URL was not saved."
        Update-Status "Discord webhook URL rejected" -Type Warning
        return
    }

    if ($enabled -and [string]::IsNullOrWhiteSpace($url)) {
        Set-DiscordWebhookStatus -Message "Discord webhook URL is required before enabling notifications."
        Write-OperationLog -Action "Discord profile webhook" -Result "Rejected" -Detail "Webhook enable requested without a URL."
        Update-Status "Discord webhook URL required" -Type Warning
        return
    }

    $script:DiscordWebhookEnabled = $enabled
    $script:DiscordWebhookUrl = $url

    try {
        Save-AppSetting -Name "DiscordWebhookUrl" -Value $url
        Save-AppSetting -Name "DiscordWebhookEnabled" -Value $enabled
    } catch {
        $errorText = $_.Exception.Message
        Set-DiscordWebhookStatus -Message "Discord webhook settings could not be saved: $errorText"
        Write-OperationLog -Action "Discord profile webhook" -Result "Failed" -Detail "Settings save failed. $errorText"
        Update-Status "Discord webhook settings save failed" -Type Error
        return
    }

    if ($enabled) {
        $redactedUrl = Get-DiscordWebhookRedactedUrl -Url $url
        Set-DiscordWebhookStatus -Message "Discord webhook enabled for $redactedUrl."
        Write-OperationLog -Action "Discord profile webhook" -Result "Saved" -Detail "Enabled=True; Endpoint=$redactedUrl"
    } else {
        Set-DiscordWebhookStatus -Message "Discord webhook notifications are disabled."
        Write-OperationLog -Action "Discord profile webhook" -Result "Saved" -Detail "Enabled=False"
    }

    Update-Status "Discord webhook settings saved" -Type Success
}

function Send-DiscordProfileWebhook {
    param(
        [pscustomobject]$ProfileData,
        $Adapter,
        [string]$Source = "Manual",
        [switch]$Synchronous
    )

    if (-not $script:DiscordWebhookEnabled) { return }
    if (-not (Test-DiscordWebhookUrl -Url $script:DiscordWebhookUrl)) {
        Set-DiscordWebhookStatus -Message "Discord webhook skipped because the saved URL is invalid."
        Write-OperationLog -Action "Discord profile webhook" -Result "Rejected" -Detail "Saved webhook URL is invalid."
        return
    }

    $url = [string]$script:DiscordWebhookUrl
    $redactedUrl = Get-DiscordWebhookRedactedUrl -Url $url
    $payloadJson = New-DiscordProfileWebhookPayload -ProfileData $ProfileData -Adapter $Adapter -Source $Source

    if ($Synchronous) {
        Set-DiscordWebhookStatus -Message "Sending Discord webhook to $redactedUrl..."
        $result = Invoke-DiscordWebhookPost -WebhookUrl $url -PayloadJson $payloadJson -AppVersion $script:AppVersion
        Complete-DiscordWebhookResult -Result $result -RedactedUrl $redactedUrl
        return
    }

    Set-DiscordWebhookStatus -Message "Sending Discord webhook to $redactedUrl..."

    try {
        $ps = [PowerShell]::Create()
        $postFunction = ${function:Invoke-DiscordWebhookPost}.ToString()
        $asyncScript = @"
param(
    [string]`$WebhookUrl,
    [string]`$PayloadJson,
    [string]`$AppVersion
)

function Invoke-DiscordWebhookPost {
$postFunction
}

Invoke-DiscordWebhookPost -WebhookUrl `$WebhookUrl -PayloadJson `$PayloadJson -AppVersion `$AppVersion
"@
        $ps.AddScript($asyncScript).AddArgument($url).AddArgument($payloadJson).AddArgument($script:AppVersion)

        $handle = $ps.BeginInvoke()
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Add_Tick({
            if ($handle.IsCompleted) {
                try {
                    $result = $ps.EndInvoke($handle)
                    $info = if ($result -and $result.Count -gt 0) { $result[0] } else { $null }
                    Complete-DiscordWebhookResult -Result $info -RedactedUrl $redactedUrl
                } catch {
                    Set-DiscordWebhookStatus -Message "Discord webhook failed: $($_.Exception.Message)"
                    Write-OperationLog -Action "Discord profile webhook" -Result "Failed" -Detail "Endpoint=$redactedUrl; $($_.Exception.Message)"
                } finally {
                    $ps.Dispose()
                    $timer.Stop()
                }
            }
        }.GetNewClosure())
        $timer.Start()
    } catch {
        Set-DiscordWebhookStatus -Message "Discord webhook failed to start: $($_.Exception.Message)"
        Write-OperationLog -Action "Discord profile webhook" -Result "Failed" -Detail "Endpoint=$redactedUrl; $($_.Exception.Message)"
    }
}

function Test-ProfileStorePath {
    param(
        [string]$Path,
        [switch]$Create
    )

    $resolved = Resolve-ProfileStorePath -Path $Path
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return [pscustomobject]@{ IsValid = $false; Path = ""; Message = "Profile store path must be a rooted folder path." }
    }
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        return [pscustomobject]@{ IsValid = $false; Path = $resolved; Message = "Profile store path points to a file." }
    }

    try {
        if (-not (Test-Path -LiteralPath $resolved)) {
            if ($Create) {
                New-Item -Path $resolved -ItemType Directory -Force | Out-Null
            } else {
                return [pscustomobject]@{ IsValid = $false; Path = $resolved; Message = "Profile store path does not exist." }
            }
        }

        $probePath = Join-Path $resolved ".netforge-write-test-$([guid]::NewGuid().ToString('N')).tmp"
        Set-Content -LiteralPath $probePath -Value "write-test" -Encoding UTF8
        Remove-Item -LiteralPath $probePath -Force

        return [pscustomobject]@{ IsValid = $true; Path = $resolved; Message = "Profile store is writable." }
    } catch {
        return [pscustomobject]@{ IsValid = $false; Path = $resolved; Message = "Profile store is not writable: $($_.Exception.Message)" }
    }
}

function Get-ProfileStoreHealth {
    param([string]$Path = $script:ProfilesPath)

    $pathResult = Test-ProfileStorePath -Path $Path
    $profileCount = 0
    $invalidCount = 0
    $profileFiles = @()

    if ($pathResult.IsValid) {
        $profileFiles = @(Get-ChildItem -Path $pathResult.Path -Filter "*.json" -ErrorAction SilentlyContinue)
        $profileCount = $profileFiles.Count
        foreach ($file in $profileFiles) {
            try {
                $content = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
                $validation = Get-ProfileValidationResult -ProfileData $content
                if (-not $validation.IsValid) { $invalidCount++ }
            } catch {
                $invalidCount++
            }
        }
    }

    $isDefault = Test-SamePath -PathA $pathResult.Path -PathB $script:DefaultProfilesPath
    $mode = if ($isDefault) { "Local" } else { "Custom/synced" }
    $message = if ($pathResult.IsValid) {
        "$mode store healthy. $profileCount profile file(s), $invalidCount invalid."
    } else {
        "$mode store problem: $($pathResult.Message)"
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ProfileStoreLoadWarning)) {
        $message = "$message Startup warning: $script:ProfileStoreLoadWarning"
    }

    return [pscustomobject]@{
        IsValid = [bool]$pathResult.IsValid
        Path = $pathResult.Path
        IsDefault = $isDefault
        ProfileCount = $profileCount
        InvalidCount = $invalidCount
        Message = $message
    }
}

function Get-ProfileStoreMigrationPlan {
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )

    $source = Resolve-ProfileStorePath -Path $SourcePath
    $target = Resolve-ProfileStorePath -Path $TargetPath
    $copyFiles = @()
    $skipped = @()
    $conflicts = @()
    $invalid = @()

    if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($target)) {
        return [pscustomobject]@{
            CanMigrate = $false
            SourcePath = $source
            TargetPath = $target
            CopyFiles = @()
            Skipped = @()
            Conflicts = @("Source and target paths must be rooted folder paths.")
            InvalidProfiles = @()
        }
    }

    if (-not (Test-Path -LiteralPath $source)) {
        return [pscustomobject]@{
            CanMigrate = $true
            SourcePath = $source
            TargetPath = $target
            CopyFiles = @()
            Skipped = @("Source path does not exist; no profiles to copy.")
            Conflicts = @()
            InvalidProfiles = @()
        }
    }

    foreach ($file in @(Get-ChildItem -Path $source -Filter "*.json" -ErrorAction SilentlyContinue)) {
        try {
            $content = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
            $validation = Get-ProfileValidationResult -ProfileData $content
            if (-not $validation.IsValid) {
                $invalid += "$($file.Name): $($validation.Message)"
                continue
            }

            $targetFile = Join-Path $target $validation.SafeFileName
            if (Test-Path -LiteralPath $targetFile) {
                $sourceHash = Get-FileSha256 -Path $file.FullName
                $targetHash = Get-FileSha256 -Path $targetFile
                if ($sourceHash -eq $targetHash) {
                    $skipped += "$($validation.Profile.Name): identical file already exists at target."
                } else {
                    $conflicts += "$($validation.Profile.Name): target already has $($validation.SafeFileName)."
                }
                continue
            }

            $copyFiles += [pscustomobject]@{
                Name = $validation.Profile.Name
                SafeFileName = $validation.SafeFileName
                SourcePath = $file.FullName
                TargetPath = $targetFile
                Sha256 = Get-FileSha256 -Path $file.FullName
            }
        } catch {
            $invalid += "$($file.Name): $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        CanMigrate = ($conflicts.Count -eq 0)
        SourcePath = $source
        TargetPath = $target
        CopyFiles = $copyFiles
        Skipped = $skipped
        Conflicts = $conflicts
        InvalidProfiles = $invalid
    }
}

function Write-ProfileStoreBackupManifest {
    param(
        [pscustomobject]$Plan,
        [string]$ActionName
    )

    $manifestRoot = Join-Path $script:ConfigPath "ProfileStoreBackups"
    if (-not (Test-Path -LiteralPath $manifestRoot)) {
        New-Item -Path $manifestRoot -ItemType Directory -Force | Out-Null
    }

    $manifestPath = Join-Path $manifestRoot "profile-store-$((Get-Date).ToString('yyyyMMdd-HHmmss'))-$([guid]::NewGuid().ToString('N').Substring(0, 8)).json"
    $manifest = [ordered]@{
        Version = $script:AppVersion
        Action = $ActionName
        CreatedAt = (Get-Date).ToString("o")
        SourcePath = $Plan.SourcePath
        TargetPath = $Plan.TargetPath
        CanMigrate = $Plan.CanMigrate
        Copied = @($Plan.CopyFiles)
        Skipped = @($Plan.Skipped)
        Conflicts = @($Plan.Conflicts)
        InvalidProfiles = @($Plan.InvalidProfiles)
    }

    [pscustomobject]$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    return $manifestPath
}

function Update-ProfileStoreDisplay {
    if (-not $script:txtProfileStorePath -or -not $script:txtProfileStoreStatus) { return }

    $health = Get-ProfileStoreHealth -Path $script:ProfilesPath
    $script:txtProfileStorePath.Text = if ([string]::IsNullOrWhiteSpace($health.Path)) { $script:ProfilesPath } else { $health.Path }
    $script:txtProfileStoreStatus.Text = $health.Message
    $script:txtProfileStoreStatus.Foreground = if ($health.IsValid -and $health.InvalidCount -eq 0) {
        [System.Windows.Media.Brushes]::LightGreen
    } elseif ($health.IsValid) {
        [System.Windows.Media.Brushes]::Orange
    } else {
        [System.Windows.Media.Brushes]::Salmon
    }
}

function Invoke-ProfileStoreChange {
    param(
        [string]$TargetPath,
        [string]$Source = "Manual"
    )

    $targetHealth = Test-ProfileStorePath -Path $TargetPath -Create
    if (-not $targetHealth.IsValid) {
        Write-ProfileImportLog -Lines @("Profile storage change rejected:", $targetHealth.Message)
        Update-Status "Profile storage change rejected" -Type Error
        Show-MessageBox -Message $targetHealth.Message -Title "Profile Storage" -Icon Error
        Update-ProfileStoreDisplay
        return $false
    }

    if (Test-SamePath -PathA $script:ProfilesPath -PathB $targetHealth.Path) {
        Save-AppSetting -Name "ProfileStorePath" -Value $targetHealth.Path
        Update-ProfileStoreDisplay
        Update-Status "Profile storage already uses $($targetHealth.Path)" -Type Success
        return $true
    }

    $plan = Get-ProfileStoreMigrationPlan -SourcePath $script:ProfilesPath -TargetPath $targetHealth.Path
    $manifestPath = Write-ProfileStoreBackupManifest -Plan $plan -ActionName $Source

    if ($plan.Conflicts.Count -gt 0) {
        $lines = @(
            "Profile storage migration blocked.",
            "Source: $($plan.SourcePath)",
            "Target: $($plan.TargetPath)",
            "Manifest: $manifestPath",
            "",
            "Conflicts:"
        ) + $plan.Conflicts
        Write-ProfileImportLog -Lines $lines
        Update-Status "Profile storage migration blocked by same-name conflicts" -Type Error
        Show-MessageBox -Message "Profile storage migration blocked by same-name conflicts. See diagnostics output for details.`n`nManifest: $manifestPath" -Title "Profile Storage Conflict" -Icon Error
        return $false
    }

    try {
        foreach ($item in $plan.CopyFiles) {
            Copy-Item -LiteralPath $item.SourcePath -Destination $item.TargetPath -ErrorAction Stop
        }

        Save-AppSetting -Name "ProfileStorePath" -Value $targetHealth.Path
        $script:ProfilesPath = $targetHealth.Path
        Refresh-ProfileList
        Update-ProfileStoreDisplay

        $lines = @(
            "Profile storage migration complete.",
            "Source: $($plan.SourcePath)",
            "Target: $($plan.TargetPath)",
            "Copied: $($plan.CopyFiles.Count)",
            "Skipped: $($plan.Skipped.Count)",
            "Invalid skipped: $($plan.InvalidProfiles.Count)",
            "Manifest: $manifestPath"
        )
        if ($plan.Skipped.Count -gt 0) {
            $lines += "Skipped:"
            $lines += $plan.Skipped
        }
        if ($plan.InvalidProfiles.Count -gt 0) {
            $lines += "Invalid profiles:"
            $lines += $plan.InvalidProfiles
        }
        Write-ProfileImportLog -Lines $lines
        Write-OperationLog -Action "Profile store migration" -Result "Succeeded" -Detail "Source=$($plan.SourcePath); Target=$($plan.TargetPath); Manifest=$manifestPath"
        Update-Status "Profile storage changed; copied $($plan.CopyFiles.Count) profile(s)" -Type Success
        return $true
    } catch {
        Write-OperationLog -Action "Profile store migration" -Result "Failed" -Detail $_.Exception.Message
        Write-ProfileImportLog -Lines @("Profile storage migration failed:", $_.Exception.Message, "Manifest: $manifestPath")
        Update-Status "Profile storage migration failed" -Type Error
        Show-MessageBox -Message "Profile storage migration failed:`n$($_.Exception.Message)`n`nOriginal profile store is still active." -Title "Profile Storage" -Icon Error
        Update-ProfileStoreDisplay
        return $false
    }
}

function Get-OneDriveProfileStore {
    $candidates = @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Join-Path $candidate "NetForge\Profiles")
        }
    }

    return ""
}

function Invoke-ChooseProfileStore {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Choose the folder NetForge should use for profile JSON files."
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $script:ProfilesPath -PathType Container) {
        $dialog.SelectedPath = $script:ProfilesPath
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [void](Invoke-ProfileStoreChange -TargetPath $dialog.SelectedPath -Source "ChooseFolder")
    }
}

function Invoke-OneDriveProfileStore {
    $oneDriveStore = Get-OneDriveProfileStore
    if ([string]::IsNullOrWhiteSpace($oneDriveStore)) {
        Update-Status "OneDrive folder was not found" -Type Warning
        Show-MessageBox -Message "No OneDrive folder was found in the current user environment." -Title "Profile Storage" -Icon Warning
        return
    }

    [void](Invoke-ProfileStoreChange -TargetPath $oneDriveStore -Source "OneDrive")
}

function Invoke-RevertProfileStore {
    [void](Invoke-ProfileStoreChange -TargetPath $script:DefaultProfilesPath -Source "RevertLocal")
}

function Get-Profiles {
    $profiles = @()
    $script:LastProfileLoadWarnings = @()
    if (Test-Path $script:ProfilesPath) {
        Get-ChildItem -Path $script:ProfilesPath -Filter "*.json" | ForEach-Object {
            try {
                $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $validation = Get-ProfileValidationResult -ProfileData $content
                if ($validation.IsValid) {
                    $profiles += $validation.Profile
                } else {
                    $script:LastProfileLoadWarnings += "$($_.Name): $($validation.Message)"
                }
            } catch {
                $script:LastProfileLoadWarnings += "$($_.Name): $($_.Exception.Message)"
            }
        }
    }
    return $profiles
}

function Refresh-ProfileList {
    $script:lstProfiles.Items.Clear()
    $profiles = Get-Profiles

    foreach ($profile in $profiles) {
        $item = New-Object System.Windows.Controls.StackPanel
        $item.Orientation = "Vertical"
        $item.Tag = $profile

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $profile.Name
        $nameText.FontSize = 13
        $nameText.FontWeight = "Medium"
        $nameText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#f0f6fc")

        $descText = New-Object System.Windows.Controls.TextBlock
        $descText.Text = if ($profile.Description) { $profile.Description } else { "No description" }
        $descText.FontSize = 11
        $descText.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom("#8b949e")
        $descText.Margin = "0,4,0,0"

        $item.Children.Add($nameText) | Out-Null
        $item.Children.Add($descText) | Out-Null

        $script:lstProfiles.Items.Add($item) | Out-Null
    }

    if ($script:LastProfileLoadWarnings.Count -gt 0) {
        Write-ProfileImportLog -Lines (@("Profile load skipped $($script:LastProfileLoadWarnings.Count) invalid file(s):") + $script:LastProfileLoadWarnings)
        Update-Status "Skipped $($script:LastProfileLoadWarnings.Count) invalid profile file(s); see diagnostics output" -Type Warning
    }

    Update-ProfileStoreDisplay
    if ($script:TrayIcon) {
        Update-TrayMenu
    }
    if ($script:CompactModeEnabled) {
        Apply-CompactMode -Enabled $true
    }
}

function Load-ProfileToEditor {
    $selected = $script:lstProfiles.SelectedItem
    if ($null -eq $selected) { return }

    $profile = $selected.Tag
    $script:txtProfileName.Text = $profile.Name
    $script:txtProfileDesc.Text = $profile.Description
    $script:chkProfileAutoApply.IsChecked = [bool]$profile.AutoApply
    $script:txtProfileMatchSsid.Text = if ($profile.MatchSSID) { $profile.MatchSSID } else { "" }
    $script:txtProfileGatewayMac.Text = if ($profile.MatchGatewayMac) { $profile.MatchGatewayMac } else { "" }
    $script:chkProfileSchedule.IsChecked = [bool]$profile.ScheduleEnabled
    $script:txtProfileScheduleTime.Text = if ($profile.ScheduleTime) { $profile.ScheduleTime } else { "08:00" }
    $scheduleDaysText = ConvertTo-ProfileScheduleDaysText -Days $profile.ScheduleDays
    $script:txtProfileScheduleDays.Text = if ([string]::IsNullOrWhiteSpace($scheduleDaysText)) { "Every day" } else { $scheduleDaysText }
    $script:chkProfileDHCP.IsChecked = $profile.UseDHCP
    $script:txtProfileIP.Text = $profile.IPAddress
    $script:txtProfileSubnet.Text = $profile.SubnetMask
    $script:txtProfileGateway.Text = $profile.Gateway
    $script:txtProfilePrefix.Text = $profile.PrefixLength
    $script:chkProfileDnsDHCP.IsChecked = $profile.UseDHCPForDNS
    $script:txtProfileDns1.Text = $profile.PrimaryDNS
    $script:txtProfileDns2.Text = $profile.SecondaryDNS
    $script:chkProfileNetworkCategory.IsChecked = [bool]$profile.ConfigureNetworkCategory
    foreach ($item in @($script:cmbProfileNetworkCategory.Items)) {
        if ([string]$item.Content -eq [string]$profile.NetworkCategory) {
            $script:cmbProfileNetworkCategory.SelectedItem = $item
            break
        }
    }
    $script:chkProfileProxy.IsChecked = [bool]$profile.ConfigureProxy
    $script:chkProfileProxyEnabled.IsChecked = [bool]$profile.ProxyEnabled
    $script:txtProfileProxyServer.Text = if ($profile.ProxyServer) { $profile.ProxyServer } else { "" }
    $script:txtProfileProxyBypass.Text = if ($profile.ProxyBypass) { $profile.ProxyBypass } else { "" }
    $script:chkProfilePrinter.IsChecked = [bool]$profile.ConfigureDefaultPrinter
    $script:txtProfilePrinterName.Text = if ($profile.DefaultPrinterName) { $profile.DefaultPrinterName } else { "" }
    $script:chkProfileMappedDrives.IsChecked = [bool]$profile.ConfigureMappedDrives
    $script:txtProfileMappedDrives.Text = ConvertTo-MappedDriveText -MappedDrives $profile.MappedDrives
}

function Save-Profile {
    $name = $script:txtProfileName.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        Show-MessageBox -Message "Please enter a profile name." -Title "Validation Error" -Icon Warning
        return
    }

    $profile = @{
        SchemaVersion = $script:ProfileSchemaVersion
        Name = $name
        Description = $script:txtProfileDesc.Text
        AutoApply = [bool]$script:chkProfileAutoApply.IsChecked
        MatchSSID = $script:txtProfileMatchSsid.Text.Trim()
        MatchGatewayMac = $script:txtProfileGatewayMac.Text.Trim()
        ScheduleEnabled = [bool]$script:chkProfileSchedule.IsChecked
        ScheduleTime = $script:txtProfileScheduleTime.Text.Trim()
        ScheduleDays = $script:txtProfileScheduleDays.Text.Trim()
        UseDHCP = $script:chkProfileDHCP.IsChecked
        IPAddress = $script:txtProfileIP.Text
        SubnetMask = $script:txtProfileSubnet.Text
        Gateway = $script:txtProfileGateway.Text
        PrefixLength = $script:txtProfilePrefix.Text
        UseDHCPForDNS = $script:chkProfileDnsDHCP.IsChecked
        PrimaryDNS = $script:txtProfileDns1.Text
        SecondaryDNS = $script:txtProfileDns2.Text
        ConfigureNetworkCategory = [bool]$script:chkProfileNetworkCategory.IsChecked
        NetworkCategory = if ($script:cmbProfileNetworkCategory.SelectedItem) { [string]$script:cmbProfileNetworkCategory.SelectedItem.Content } else { "Private" }
        ConfigureProxy = [bool]$script:chkProfileProxy.IsChecked
        ProxyEnabled = [bool]$script:chkProfileProxyEnabled.IsChecked
        ProxyServer = $script:txtProfileProxyServer.Text
        ProxyBypass = $script:txtProfileProxyBypass.Text
        ConfigureDefaultPrinter = [bool]$script:chkProfilePrinter.IsChecked
        DefaultPrinterName = $script:txtProfilePrinterName.Text
        ConfigureMappedDrives = [bool]$script:chkProfileMappedDrives.IsChecked
        MappedDrives = $script:txtProfileMappedDrives.Text
        CreatedAt = (Get-Date).ToString("o")
        UpdatedAt = (Get-Date).ToString("o")
    }

    $selected = $script:lstProfiles.SelectedItem
    if ($selected -and $selected.Tag -and $selected.Tag.CreatedAt) {
        $profile.CreatedAt = $selected.Tag.CreatedAt
    }

    $validation = Get-ProfileValidationResult -ProfileData ([pscustomobject]$profile)
    if (-not $validation.IsValid) {
        Update-Status "Profile validation failed: $($validation.Message)" -Type Error
        Show-MessageBox -Message $validation.Message -Title "Profile Validation Failed" -Icon Error
        return
    }

    $filePath = Join-Path $script:ProfilesPath $validation.SafeFileName
    $selectedSafeName = ""
    if ($selected -and $selected.Tag -and $selected.Tag.Name) {
        $selectedSafeName = Get-SafeProfileFileName -Name $selected.Tag.Name
    }

    if ((Test-Path -LiteralPath $filePath) -and $selectedSafeName -ne $validation.SafeFileName) {
        Update-Status "Profile '$name' already exists; select it before updating or choose another name" -Type Warning
        Write-ProfileImportLog -Lines @("Profile save rejected:", "Profile '$name' already exists at $filePath.", "Select the existing profile before updating, or choose another name.")
        return
    }

    Write-ProfileFileAtomic -ProfileData $validation.Profile -FilePath $filePath

    if (-not [string]::IsNullOrWhiteSpace($selectedSafeName) -and $selectedSafeName -ne $validation.SafeFileName) {
        $oldPath = Join-Path $script:ProfilesPath $selectedSafeName
        if (Test-Path -LiteralPath $oldPath) {
            Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
        }
    }

    Update-Status "Profile '$name' saved successfully" -Type Success
    Refresh-ProfileList
}

function Delete-Profile {
    $selected = $script:lstProfiles.SelectedItem
    if ($null -eq $selected) {
        Show-MessageBox -Message "Please select a profile to delete." -Title "No Selection" -Icon Warning
        return
    }

    $profile = $selected.Tag
    $result = Show-MessageBox -Message "Are you sure you want to delete profile '$($profile.Name)'?" -Title "Confirm Delete" -Buttons YesNo -Icon Question

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        $filePath = Get-ProfileFilePath -Name $profile.Name
        if (Test-Path $filePath) {
            Remove-Item -LiteralPath $filePath -Force
        }
        Update-Status "Profile '$($profile.Name)' deleted" -Type Success
        Refresh-ProfileList
    }
}

function Export-SelectedProfileQrCode {
    $selected = $script:lstProfiles.SelectedItem
    if ($null -eq $selected) {
        Update-Status "Select a profile before exporting a QR code" -Type Warning
        Show-MessageBox -Message "Please select a profile to export as a QR code." -Title "No Profile Selected" -Icon Warning
        return
    }

    $profile = $selected.Tag
    $safeName = ([System.IO.Path]::GetFileNameWithoutExtension((Get-SafeProfileFileName -Name $profile.Name)))

    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "PNG Images (*.png)|*.png"
    $saveDialog.FileName = "$safeName-qr.png"
    $saveDialog.Title = "Export Profile QR"

    if ($saveDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $payload = ConvertTo-ProfileQrPayload -ProfileData $profile
        Import-NetForgeQrAssembly -Encoder

        $generator = New-Object QRCoder.QRCodeGenerator
        $qrData = $null
        $qrCode = $null
        try {
            $qrData = $generator.CreateQrCode($payload, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
            $qrCode = New-Object QRCoder.PngByteQRCode -ArgumentList $qrData
            $bytes = $qrCode.GetGraphic(16)
            [System.IO.File]::WriteAllBytes($saveDialog.FileName, $bytes)
        } finally {
            if ($qrCode -and ($qrCode -is [System.IDisposable])) { $qrCode.Dispose() }
            if ($qrData -and ($qrData -is [System.IDisposable])) { $qrData.Dispose() }
            if ($generator -and ($generator -is [System.IDisposable])) { $generator.Dispose() }
        }

        Write-OperationLog -Action "Export profile QR" -Result "Succeeded" -Detail "Profile=$($profile.Name); Path=$($saveDialog.FileName); PayloadLength=$($payload.Length)"
        Update-Status "Profile QR exported to $($saveDialog.FileName)" -Type Success
    } catch {
        Write-OperationLog -Action "Export profile QR" -Result "Failed" -Detail $_.Exception.Message
        Update-Status "Profile QR export failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Profile QR export failed:`n$($_.Exception.Message)" -Title "QR Export Failed" -Icon Error
    }
}

function Import-ProfileQrCode {
    $openDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openDialog.Filter = "QR Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|All Files (*.*)|*.*"
    $openDialog.Title = "Import Profile QR"

    if ($openDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        Import-NetForgeQrAssembly -Decoder

        $bitmap = $null
        try {
            $bitmap = [System.Drawing.Bitmap]::FromFile($openDialog.FileName)
            $reader = New-Object ZXing.BarcodeReader
            $result = $reader.Decode($bitmap)
        } finally {
            if ($bitmap) { $bitmap.Dispose() }
        }

        if ($null -eq $result -or [string]::IsNullOrWhiteSpace($result.Text)) {
            throw "No QR code payload was found in the selected image."
        }

        $record = ConvertFrom-ProfileQrPayload -Payload $result.Text
        $filePath = Join-Path $script:ProfilesPath $record.SafeFileName
        if (Test-Path -LiteralPath $filePath) {
            throw "Profile '$($record.Profile.Name)' already exists. Delete or rename the existing profile before importing."
        }

        Write-ProfileFileAtomic -ProfileData $record.Profile -FilePath $filePath
        Write-ProfileImportLog -Lines @(
            "QR profile import complete.",
            "Source: $($openDialog.FileName)",
            "Profile: $($record.Profile.Name)",
            "ExportedAt: $($record.ExportedAt)",
            "AppVersion: $($record.AppVersion)"
        )
        Refresh-ProfileList
        Write-OperationLog -Action "Import profile QR" -Result "Succeeded" -Detail "Profile=$($record.Profile.Name); Source=$($openDialog.FileName)"
        Update-Status "Imported profile '$($record.Profile.Name)' from QR" -Type Success
    } catch {
        Write-OperationLog -Action "Import profile QR" -Result "Failed" -Detail $_.Exception.Message
        Update-Status "Profile QR import failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Profile QR import failed:`n$($_.Exception.Message)" -Title "QR Import Failed" -Icon Error
    }
}

function Get-NetworkListManagerIdentity {
    try {
        $nlm = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([guid]'DCB00C01-570F-4A9B-8D69-199FDBA5723B'))
        $networks = $nlm.GetNetworks(1)

        $results = @()
        foreach ($network in $networks) {
            $name = try { [string]$network.GetName() } catch { "" }
            $networkId = try { [string]$network.GetNetworkId() } catch { "" }
            $category = try {
                switch ([int]$network.GetCategory()) {
                    0 { "Public" }
                    1 { "Private" }
                    2 { "DomainAuthenticated" }
                    default { "Unknown" }
                }
            } catch { "Unknown" }

            $results += [pscustomobject]@{
                Name = $name
                NetworkId = $networkId
                Category = $category
            }
        }
        return [pscustomobject]@{ Available = $true; Networks = $results; Error = $null }
    } catch {
        return [pscustomobject]@{ Available = $false; Networks = @(); Error = $_.Exception.Message }
    }
}

function Test-NetworkListManagerMatch {
    param(
        [pscustomobject]$ProfileData,
        [pscustomobject[]]$NlmNetworks
    )

    $matchNetworkName = if ($ProfileData.PSObject.Properties['MatchNetworkName']) { ([string]$ProfileData.MatchNetworkName).Trim() } else { "" }
    $matchNetworkId = if ($ProfileData.PSObject.Properties['MatchNetworkId']) { ([string]$ProfileData.MatchNetworkId).Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($matchNetworkName) -and [string]::IsNullOrWhiteSpace($matchNetworkId)) {
        return [pscustomobject]@{ Matched = $false; MatchedBy = $null; MatchedNetwork = $null }
    }

    foreach ($network in $NlmNetworks) {
        $nameMatch = (-not [string]::IsNullOrWhiteSpace($matchNetworkName)) -and ($network.Name -ieq $matchNetworkName)
        $idMatch = (-not [string]::IsNullOrWhiteSpace($matchNetworkId)) -and ($network.NetworkId -ieq $matchNetworkId)

        if ($nameMatch -or $idMatch) {
            $matchedBy = @()
            if ($nameMatch) { $matchedBy += "NetworkName" }
            if ($idMatch) { $matchedBy += "NetworkId" }
            return [pscustomobject]@{ Matched = $true; MatchedBy = ($matchedBy -join "+"); MatchedNetwork = $network }
        }
    }

    return [pscustomobject]@{ Matched = $false; MatchedBy = $null; MatchedNetwork = $null }
}

function Get-CurrentNetworkSignature {
    $activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and (Test-NetForgeAdapter -Adapter $_) } | Select-Object -First 1
    if ($null -eq $activeAdapter) { return $null }

    $gateway = Get-NetRoute -InterfaceIndex $activeAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
    $gatewayIp = if ($gateway) { $gateway.NextHop } else { "" }
    $gatewayMac = ""

    if (Test-ValidIP -IP $gatewayIp) {
        $neighbor = Get-NetNeighbor -InterfaceIndex $activeAdapter.ifIndex -IPAddress $gatewayIp -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $neighbor -or [string]::IsNullOrWhiteSpace($neighbor.LinkLayerAddress)) {
            [void](Test-Connection -ComputerName $gatewayIp -Count 1 -Quiet -ErrorAction SilentlyContinue)
            $neighbor = Get-NetNeighbor -InterfaceIndex $activeAdapter.ifIndex -IPAddress $gatewayIp -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($neighbor -and $neighbor.LinkLayerAddress) {
            $gatewayMac = ConvertTo-CleanMacAddress -MacAddress $neighbor.LinkLayerAddress
        }
    }

    $ssid = ""
    if ((Get-AdapterConnectionKind -Adapter $activeAdapter) -eq "WiFi") {
        $wlanOutput = netsh wlan show interfaces 2>&1 | Out-String
        foreach ($line in ($wlanOutput -split "`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\s*SSID\s*:\s*(.+)$' -and $trimmed -notmatch 'BSSID') {
                $ssid = $Matches[1].Trim()
                break
            }
        }
    }

    return [pscustomobject]@{
        Adapter = $activeAdapter
        SSID = $ssid
        Gateway = $gatewayIp
        GatewayMac = $gatewayMac
    }
}

function Invoke-CaptureProfileMatch {
    $signature = Get-CurrentNetworkSignature
    if ($null -eq $signature) {
        Show-MessageBox -Message "No active network signature is available to capture." -Title "No Active Network" -Icon Warning
        return
    }

    $script:chkProfileAutoApply.IsChecked = $true
    $script:txtProfileMatchSsid.Text = $signature.SSID
    $script:txtProfileGatewayMac.Text = $signature.GatewayMac
    Update-Status "Captured current network match fields" -Type Success
}

function Test-ProfileAutoApplyMatch {
    param(
        [pscustomobject]$ProfileData,
        [pscustomobject]$Signature
    )

    if (-not [bool]$ProfileData.AutoApply) { return $false }
    if ($null -eq $Signature) { return $false }

    $matchSsid = if ($ProfileData.MatchSSID) { $ProfileData.MatchSSID.Trim() } else { "" }
    $matchGatewayMac = if ($ProfileData.MatchGatewayMac) { ConvertTo-CleanMacAddress -MacAddress $ProfileData.MatchGatewayMac } else { "" }

    $ssidMatches = (-not [string]::IsNullOrWhiteSpace($matchSsid)) -and ($Signature.SSID -ieq $matchSsid)
    $gatewayMatches = (-not [string]::IsNullOrWhiteSpace($matchGatewayMac)) -and ($Signature.GatewayMac -eq $matchGatewayMac)

    return ($ssidMatches -or $gatewayMatches)
}

function Get-NetworkSignatureKey {
    param([pscustomobject]$Signature)

    if ($null -eq $Signature) { return "" }
    $adapterIndex = if ($Signature.Adapter) { [string]$Signature.Adapter.ifIndex } else { "" }
    return (@($adapterIndex, $Signature.SSID, $Signature.Gateway, $Signature.GatewayMac) | ForEach-Object { [string]$_ }) -join "|"
}

function Invoke-ApplyProfileObject {
    param(
        [pscustomobject]$ProfileData,
        $Adapter,
        [string]$Source = "Manual"
    )

    $target = Get-ProfileApplyTarget -ProfileData $ProfileData
    if (-not $target.IsValid) {
        Update-Status $target.Message -Type Error
        if ($Source -notin @("Auto", "Scheduled", "Tray", "Cli", "Rdp")) {
            Show-MessageBox -Message $target.Message -Title "Profile Validation Failed" -Icon Error
        }
        return $false
    }

    Update-Status "Applying profile '$($ProfileData.Name)'..."

    $quietApply = ($Source -in @("Auto", "Scheduled", "Tray", "Cli", "Rdp"))
    $success = Invoke-NetworkMutation -Adapter $Adapter -ActionName "Apply profile '$($ProfileData.Name)'" -Quiet:$quietApply -ScriptBlock {
        Invoke-AdapterIPTarget -Adapter $Adapter -Target $target
        Invoke-AdapterDNSTarget -Adapter $Adapter -Target $target
        Invoke-ProfileEnvironmentTarget -Adapter $Adapter -Target $target
    }

    if ($success) {
        $script:LastAutoAppliedProfile = if ($Source -eq "Auto") { $ProfileData.Name } else { $script:LastAutoAppliedProfile }
        Update-Status "Profile '$($ProfileData.Name)' applied successfully" -Type Success
        Send-DiscordProfileWebhook -ProfileData $ProfileData -Adapter $Adapter -Source $Source -Synchronous:($Source -eq "Cli")
        if ($Source -ne "Cli" -and $script:txtAdapterName) {
            Start-Sleep -Milliseconds 500
            Update-AdapterDisplay
        }
        return $true
    }

    return $false
}

function Invoke-AutoApplyProfile {
    param([string]$Trigger = "FallbackTimer")

    $signature = Get-CurrentNetworkSignature
    if ($null -eq $signature) {
        $script:LastAutoAppliedProfile = ""
        $script:LastAutoApplySignature = ""
        $script:LastAutoApplyAttemptKey = ""
        Write-OperationLog -Action "Profile auto-apply" -Result "NoActiveNetwork" -Detail "Trigger=$Trigger"
        return
    }

    $signatureKey = Get-NetworkSignatureKey -Signature $signature
    $profiles = Get-Profiles
    foreach ($candidate in $profiles) {
        if (-not (Test-ProfileAutoApplyMatch -ProfileData $candidate -Signature $signature)) { continue }

        $attemptKey = "$($candidate.Name)|$signatureKey"
        if ($script:LastAutoApplyAttemptKey -eq $attemptKey) {
            Write-OperationLog -Action "Profile auto-apply" -Result "Skipped" -Detail "Trigger=$Trigger; Profile=$($candidate.Name); unchanged signature"
            return
        }

        Write-OperationLog -Action "Profile auto-apply" -Result "Matched" -Detail "Trigger=$Trigger; Profile=$($candidate.Name); Signature=$signatureKey"
        $applied = Invoke-ApplyProfileObject -ProfileData $candidate -Adapter $signature.Adapter -Source "Auto"
        if ($applied) {
            $script:LastAutoApplyAttemptKey = $attemptKey
            $script:LastAutoApplySignature = $signatureKey
        }
        return
    }

    $script:LastAutoAppliedProfile = ""
    $script:LastAutoApplySignature = ""
    $script:LastAutoApplyAttemptKey = ""
    Write-OperationLog -Action "Profile auto-apply" -Result "NoMatch" -Detail "Trigger=$Trigger; Signature=$signatureKey"
}

function Get-ScheduledProfileAdapter {
    $signature = Get-CurrentNetworkSignature
    if ($signature -and $signature.Adapter) { return $signature.Adapter }

    $selected = Get-SelectedAdapter
    if ($selected) { return $selected }

    return (Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and (Test-NetForgeAdapter -Adapter $_) } | Select-Object -First 1)
}

function Invoke-ScheduledProfileSwitch {
    param(
        [datetime]$Now = (Get-Date),
        [string]$Trigger = "ScheduleTimer"
    )

    $dueProfiles = @()
    foreach ($candidate in Get-Profiles) {
        if (Test-ProfileScheduleDue -ProfileData $candidate -Now $Now) {
            $dueProfiles += $candidate
        }
    }

    if ($dueProfiles.Count -eq 0) { return }

    $profile = $dueProfiles[0]
    $dueKey = Get-ProfileScheduleDueKey -ProfileData $profile -Now $Now
    if ($script:LastScheduledProfileKey -eq $dueKey) {
        Write-OperationLog -Action "Profile schedule" -Result "Skipped" -Detail "Trigger=$Trigger; Profile=$($profile.Name); already applied for this minute"
        return
    }

    $adapter = Get-ScheduledProfileAdapter
    if ($null -eq $adapter) {
        Write-OperationLog -Action "Profile schedule" -Result "NoAdapter" -Detail "Trigger=$Trigger; Profile=$($profile.Name)"
        Update-Status "Scheduled profile '$($profile.Name)' skipped: no active adapter" -Type Warning
        return
    }

    if ($dueProfiles.Count -gt 1) {
        $skipped = @($dueProfiles | Select-Object -Skip 1 | ForEach-Object { $_.Name }) -join ", "
        Write-OperationLog -Action "Profile schedule" -Result "MultipleDue" -Detail "Trigger=$Trigger; Applying=$($profile.Name); Skipped=$skipped"
    }

    Write-OperationLog -Action "Profile schedule" -Result "Due" -Detail "Trigger=$Trigger; Profile=$($profile.Name); Adapter=$($adapter.Name); Time=$($Now.ToString('o'))"
    $applied = Invoke-ApplyProfileObject -ProfileData $profile -Adapter $adapter -Source "Scheduled"
    if ($applied) {
        $script:LastScheduledProfileKey = $dueKey
    }
}

function Format-AutoApplyInspectorLine {
    param(
        [pscustomobject]$ProfileData,
        [pscustomobject]$Signature,
        [string]$LastAppliedName = ""
    )

    $name = [string]$ProfileData.Name
    $autoApply = [bool]$ProfileData.AutoApply
    $matchSsid = if ($ProfileData.MatchSSID) { $ProfileData.MatchSSID.Trim() } else { "" }
    $matchGateway = if ($ProfileData.MatchGatewayMac) { ConvertTo-CleanMacAddress -MacAddress $ProfileData.MatchGatewayMac } else { "" }

    if (-not $autoApply) {
        return [pscustomobject]@{ Name = $name; Status = "Disabled"; Reason = "Auto-apply not enabled." }
    }

    if ($null -eq $Signature) {
        return [pscustomobject]@{ Name = $name; Status = "NoNetwork"; Reason = "No active network signature." }
    }

    $ssidMatch = (-not [string]::IsNullOrWhiteSpace($matchSsid)) -and ($Signature.SSID -ieq $matchSsid)
    $gatewayMatch = (-not [string]::IsNullOrWhiteSpace($matchGateway)) -and ($Signature.GatewayMac -eq $matchGateway)
    $matched = $ssidMatch -or $gatewayMatch

    if (-not $matched) {
        $ruleParts = @()
        if (-not [string]::IsNullOrWhiteSpace($matchSsid)) { $ruleParts += "SSID=$matchSsid" }
        if (-not [string]::IsNullOrWhiteSpace($matchGateway)) { $ruleParts += "GW=$matchGateway" }
        $ruleText = if ($ruleParts.Count -gt 0) { $ruleParts -join ", " } else { "No match rules" }
        return [pscustomobject]@{ Name = $name; Status = "NoMatch"; Reason = "Rules: $ruleText" }
    }

    $matchParts = @()
    if ($ssidMatch) { $matchParts += "SSID" }
    if ($gatewayMatch) { $matchParts += "Gateway MAC" }
    $matchText = $matchParts -join " + "

    $isLast = ($name -eq $LastAppliedName)
    $status = if ($isLast) { "Active" } else { "Matched" }
    return [pscustomobject]@{ Name = $name; Status = $status; Reason = "Matched by $matchText." }
}

function Format-AutoApplyInspectorReport {
    param(
        [pscustomobject[]]$Lines,
        [pscustomobject]$Signature,
        [string]$LastAppliedName = "",
        [pscustomobject]$NextScheduled = $null,
        [pscustomobject]$NlmIdentity = $null
    )

    $parts = @()

    if ($null -ne $Signature) {
        $sigParts = @()
        if ($Signature.SSID) { $sigParts += "SSID: $($Signature.SSID)" }
        if ($Signature.Gateway) { $sigParts += "GW: $($Signature.Gateway)" }
        if ($Signature.GatewayMac) { $sigParts += "GW MAC: $($Signature.GatewayMac)" }
        $parts += "Network: " + ($sigParts -join " | ")
    } else {
        $parts += "Network: No active connection."
    }

    if ($null -ne $NlmIdentity -and $NlmIdentity.Available -and $NlmIdentity.Networks.Count -gt 0) {
        foreach ($nlmNet in $NlmIdentity.Networks) {
            $parts += "NLM: $($nlmNet.Name) [$($nlmNet.Category)]"
        }
    } elseif ($null -ne $NlmIdentity -and -not $NlmIdentity.Available) {
        $parts += "NLM: unavailable"
    }

    if (-not [string]::IsNullOrWhiteSpace($LastAppliedName)) {
        $parts += "Last applied: $LastAppliedName"
    }

    if ($null -ne $NextScheduled) {
        $parts += "Next scheduled: $($NextScheduled.Name) at $($NextScheduled.ScheduleDescription)"
    }

    $parts += ""

    foreach ($line in $Lines) {
        $label = switch ($line.Status) {
            "Active"    { "[ACTIVE]" }
            "Matched"   { "[MATCH]" }
            "NoMatch"   { "[--]" }
            "Disabled"  { "[OFF]" }
            "NoNetwork" { "[--]" }
            default     { "[--]" }
        }
        $parts += "$label $($line.Name): $($line.Reason)"
    }

    return ($parts -join "`n")
}

function Invoke-RefreshAutoApplyInspector {
    try {
        $signature = Get-CurrentNetworkSignature
        $profiles = Get-Profiles
        $lastApplied = $script:LastAutoAppliedProfile

        $lines = @()
        foreach ($profile in $profiles) {
            $lines += Format-AutoApplyInspectorLine -ProfileData $profile -Signature $signature -LastAppliedName $lastApplied
        }

        $nextScheduled = $null
        foreach ($candidate in $profiles) {
            if (Test-ProfileScheduleDue -ProfileData $candidate -Now (Get-Date)) {
                $nextScheduled = [pscustomobject]@{
                    Name = $candidate.Name
                    ScheduleDescription = Get-ProfileScheduleDescription -ProfileData $candidate
                }
                break
            }
        }

        $nlmIdentity = Get-NetworkListManagerIdentity
        $report = Format-AutoApplyInspectorReport -Lines $lines -Signature $signature -LastAppliedName $lastApplied -NextScheduled $nextScheduled -NlmIdentity $nlmIdentity
        $script:txtAutoApplyInspector.Text = $report
        Update-Status "Auto-apply inspector refreshed" -Type Success
    } catch {
        $script:txtAutoApplyInspector.Text = "Inspector refresh failed: $($_.Exception.Message)"
        Update-Status "Auto-apply inspector failed" -Type Error
    }
}

function Register-NetworkChangeAutoApply {
    if ($script:NetworkChangeSubscribed) { return }

    try {
        $addressHandler = [System.Net.NetworkInformation.NetworkAddressChangedEventHandler]{
            $window.Dispatcher.BeginInvoke([action]{
                Invoke-AutoApplyProfile -Trigger "NetworkAddressChanged"
                [void](Invoke-AppRoutingPolicyRepair -Trigger "NetworkAddressChanged")
            }) | Out-Null
        }.GetNewClosure()

        $availabilityHandler = [System.Net.NetworkInformation.NetworkAvailabilityChangedEventHandler]{
            param($eventSource, $networkEvent)
            [void]$eventSource
            $availabilityTrigger = "NetworkAvailabilityChanged"
            if ($networkEvent) {
                $availabilityTrigger = "NetworkAvailabilityChanged:$($networkEvent.IsAvailable)"
            }
            $triggerText = $availabilityTrigger
            $window.Dispatcher.BeginInvoke(([action]{
                Invoke-AutoApplyProfile -Trigger $triggerText
                [void](Invoke-AppRoutingPolicyRepair -Trigger $triggerText)
            }).GetNewClosure()) | Out-Null
        }.GetNewClosure()

        [System.Net.NetworkInformation.NetworkChange]::add_NetworkAddressChanged($addressHandler)
        [System.Net.NetworkInformation.NetworkChange]::add_NetworkAvailabilityChanged($availabilityHandler)
        $script:NetworkChangeHandlers = @{
            Address = $addressHandler
            Availability = $availabilityHandler
        }
        $script:NetworkChangeSubscribed = $true
        Write-OperationLog -Action "Profile auto-apply events" -Result "Subscribed" -Detail "NetworkChange handlers registered"
    } catch {
        $script:NetworkChangeSubscribed = $false
        Write-OperationLog -Action "Profile auto-apply events" -Result "Failed" -Detail $_.Exception.Message
        Update-Status "Network change event subscription failed; timer fallback remains active" -Type Warning
    }
}

function Unregister-NetworkChangeAutoApply {
    if (-not $script:NetworkChangeSubscribed) { return }

    try {
        if ($script:NetworkChangeHandlers.Address) {
            [System.Net.NetworkInformation.NetworkChange]::remove_NetworkAddressChanged($script:NetworkChangeHandlers.Address)
        }
        if ($script:NetworkChangeHandlers.Availability) {
            [System.Net.NetworkInformation.NetworkChange]::remove_NetworkAvailabilityChanged($script:NetworkChangeHandlers.Availability)
        }
        Write-OperationLog -Action "Profile auto-apply events" -Result "Unsubscribed" -Detail "NetworkChange handlers removed"
    } catch {
        Write-OperationLog -Action "Profile auto-apply events" -Result "UnsubscribeWarning" -Detail $_.Exception.Message
    } finally {
        $script:NetworkChangeHandlers = @{}
        $script:NetworkChangeSubscribed = $false
    }
}

function Show-ProfileDiff {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:txtProfileName.Text.Trim())) {
        Show-MessageBox -Message "Enter or select a profile before previewing differences." -Title "No Profile" -Icon Warning
        return
    }

    $currentIp = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $currentGateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
    $currentDns = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $currentInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1

    $currentIpMode = if ($currentInterface -and $currentInterface.Dhcp -eq "Enabled") { "DHCP" } else { "Static" }
    $targetIpMode = if ($script:chkProfileDHCP.IsChecked) { "DHCP" } else { "Static" }
    $currentDnsMode = if (-not $currentDns -or -not $currentDns.ServerAddresses -or $currentDns.ServerAddresses.Count -eq 0) { "DHCP" } else { "Static" }
    $targetDnsMode = if ($script:chkProfileDnsDHCP.IsChecked) { "DHCP" } else { "Static" }

    $lines = @("Profile: $($script:txtProfileName.Text.Trim())", "Adapter: $($adapter.Name)", "")

    function Add-DiffLine {
        param(
            [string]$Label,
            [string]$CurrentValue,
            [string]$TargetValue
        )

        $currentText = if ([string]::IsNullOrWhiteSpace($CurrentValue)) { "--" } else { $CurrentValue }
        $targetText = if ([string]::IsNullOrWhiteSpace($TargetValue)) { "--" } else { $TargetValue }
        $marker = if ($currentText -eq $targetText) { "same" } else { "change" }
        $script:profileDiffLines += "[$marker] $Label`: $currentText => $targetText"
    }

    $script:profileDiffLines = $lines
    Add-DiffLine -Label "IP Mode" -CurrentValue $currentIpMode -TargetValue $targetIpMode
    Add-DiffLine -Label "IP Address" -CurrentValue $(if ($currentIp) { $currentIp.IPAddress } else { "" }) -TargetValue $(if ($script:chkProfileDHCP.IsChecked) { "Automatic" } else { $script:txtProfileIP.Text.Trim() })
    Add-DiffLine -Label "Prefix" -CurrentValue $(if ($currentIp) { [string]$currentIp.PrefixLength } else { "" }) -TargetValue $(if ($script:chkProfileDHCP.IsChecked) { "Automatic" } else { $script:txtProfilePrefix.Text.Trim() })
    Add-DiffLine -Label "Gateway" -CurrentValue $(if ($currentGateway) { $currentGateway.NextHop } else { "" }) -TargetValue $(if ($script:chkProfileDHCP.IsChecked) { "Automatic" } else { $script:txtProfileGateway.Text.Trim() })
    Add-DiffLine -Label "DNS Mode" -CurrentValue $currentDnsMode -TargetValue $targetDnsMode
    Add-DiffLine -Label "DNS Servers" -CurrentValue $(if ($currentDns -and $currentDns.ServerAddresses) { $currentDns.ServerAddresses -join ", " } else { "" }) -TargetValue $(if ($script:chkProfileDnsDHCP.IsChecked) { "Automatic" } else { (@($script:txtProfileDns1.Text.Trim(), $script:txtProfileDns2.Text.Trim()) | Where-Object { $_ }) -join ", " })
    Add-DiffLine -Label "Auto-Apply" -CurrentValue "--" -TargetValue $(if ($script:chkProfileAutoApply.IsChecked) { "Enabled" } else { "Disabled" })
    $schedulePreview = if ($script:chkProfileSchedule.IsChecked) {
        $dayPreview = ConvertTo-ProfileScheduleDaysText -Days $script:txtProfileScheduleDays.Text
        if ([string]::IsNullOrWhiteSpace($dayPreview)) { $dayPreview = "Every day" }
        "$($script:txtProfileScheduleTime.Text.Trim()) $dayPreview"
    } else {
        "Disabled"
    }
    Add-DiffLine -Label "Schedule" -CurrentValue "--" -TargetValue $schedulePreview
    Add-DiffLine -Label "Match SSID" -CurrentValue "--" -TargetValue $script:txtProfileMatchSsid.Text.Trim()
    Add-DiffLine -Label "Gateway MAC" -CurrentValue "--" -TargetValue (ConvertTo-CleanMacAddress -MacAddress $script:txtProfileGatewayMac.Text)
    if ($script:chkProfileNetworkCategory.IsChecked) {
        $currentProfile = Get-NetConnectionProfile -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue | Select-Object -First 1
        $currentCategory = if ($currentProfile) { [string]$currentProfile.NetworkCategory } else { "" }
        $targetCategory = if ($script:cmbProfileNetworkCategory.SelectedItem) { [string]$script:cmbProfileNetworkCategory.SelectedItem.Content } else { "Private" }
        Add-DiffLine -Label "Network Category" -CurrentValue $currentCategory -TargetValue $targetCategory
    }
    if ($script:chkProfileProxy.IsChecked) {
        $proxy = Get-SystemProxySnapshot
        $currentProxy = if ($proxy.Enabled) { "Enabled $($proxy.Server)" } else { "Disabled" }
        $targetProxy = if ($script:chkProfileProxyEnabled.IsChecked) { "Enabled $($script:txtProfileProxyServer.Text.Trim())" } else { "Disabled" }
        Add-DiffLine -Label "System Proxy" -CurrentValue $currentProxy -TargetValue $targetProxy
        Add-DiffLine -Label "Proxy Bypass" -CurrentValue $proxy.Bypass -TargetValue $script:txtProfileProxyBypass.Text.Trim()
    }
    if ($script:chkProfilePrinter.IsChecked) {
        Add-DiffLine -Label "Default Printer" -CurrentValue (Get-DefaultPrinterName) -TargetValue $script:txtProfilePrinterName.Text.Trim()
    }
    if ($script:chkProfileMappedDrives.IsChecked) {
        Add-DiffLine -Label "Mapped Drives" -CurrentValue (ConvertTo-MappedDriveText -MappedDrives (Get-MappedDriveState)) -TargetValue $script:txtProfileMappedDrives.Text.Trim()
    }

    $script:txtProfileDiffOutput.Text = $script:profileDiffLines -join "`n"
    $script:profileDiffLines = $null
    Update-Status "Profile diff generated" -Type Success
}

# ============================================================================
# APPLY FUNCTIONS
# ============================================================================
function Apply-IPConfiguration {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $target = Get-IPApplyTarget
    if (-not $target.IsValid) {
        Show-MessageBox -Message $target.Message -Title "Validation Error" -Icon Error
        Update-Status $target.Message -Type Error
        return
    }

    $result = Show-MessageBox -Message "Apply IP configuration to '$($adapter.Name)'?" -Title "Confirm" -Buttons YesNo -Icon Question
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Update-Status "Applying IP configuration..."

    $success = Invoke-NetworkMutation -Adapter $adapter -ActionName "Apply IP configuration" -ScriptBlock {
        Invoke-AdapterIPTarget -Adapter $adapter -Target $target
    }

    if ($success) {
        Update-Status "$($target.StatusMessage) on $($adapter.Name)" -Type Success
        Start-Sleep -Milliseconds 500
        Update-AdapterDisplay
    }
}

function Apply-DNSConfiguration {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $target = Get-DNSApplyTarget
    if (-not $target.IsValid) {
        Show-MessageBox -Message $target.Message -Title "Validation Error" -Icon Error
        Update-Status $target.Message -Type Error
        return
    }

    $previewLines = @()
    try {
        $previewLines = @(Invoke-DnsApplyHealthPreview -Adapter $adapter -Target $target)
    } catch {
        $previewLines = @("DNS apply preview failed: $($_.Exception.Message)")
        Update-DnsHealthOutput -Lines $previewLines -Header "DNS apply preview"
    }

    $previewText = ($previewLines | Select-Object -First 10) -join "`n"
    if ($previewLines.Count -gt 10) {
        $previewText += "`n..."
    }

    $result = Show-MessageBox -Message "Apply DNS configuration to '$($adapter.Name)'?`n`n$previewText" -Title "Confirm" -Buttons YesNo -Icon Question
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Update-Status "Applying DNS configuration..."

    $success = Invoke-NetworkMutation -Adapter $adapter -ActionName "Apply DNS configuration" -ScriptBlock {
        Invoke-AdapterDNSTarget -Adapter $adapter -Target $target
    }

    if ($success) {
        Update-Status "$($target.StatusMessage) to $($adapter.Name)" -Type Success
        Update-AdapterDetails
    }
}

function Apply-Profile {
    $adapter = Get-SelectedAdapter
    $selected = $script:lstProfiles.SelectedItem

    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    if ($null -eq $selected) {
        Show-MessageBox -Message "Please select a profile to apply." -Title "No Profile Selected" -Icon Warning
        return
    }

    $profile = $selected.Tag
    $result = Show-MessageBox -Message "Apply profile '$($profile.Name)' to adapter '$($adapter.Name)'?" -Title "Confirm" -Buttons YesNo -Icon Question
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    [void](Invoke-ApplyProfileObject -ProfileData $profile -Adapter $adapter -Source "Manual")
}

function Resolve-CliProfile {
    param(
        [string]$ProfileName,
        [object[]]$Profiles = $null
    )

    $name = ([string]$ProfileName).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Use -ApplyProfile with a saved profile name."
    }

    if ($null -eq $Profiles) {
        $Profiles = @(Get-Profiles)
    }

    $matches = @($Profiles | Where-Object { $_.Name -ieq $name })
    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    if ($matches.Count -gt 1) {
        throw "Profile '$name' is ambiguous; remove duplicate profile files before using CLI apply."
    }

    $available = @($Profiles | ForEach-Object { $_.Name } | Sort-Object)
    $availableText = if ($available.Count -gt 0) { $available -join ", " } else { "none" }
    throw "Profile '$name' was not found in $script:ProfilesPath. Available profiles: $availableText."
}

function Resolve-CliAdapter {
    param(
        [string]$AdapterName = "",
        [object[]]$Adapters = $null
    )

    $selector = ([string]$AdapterName).Trim()
    if ($null -eq $Adapters) {
        if ([string]::IsNullOrWhiteSpace($selector)) {
            $Adapters = @(Get-NetworkAdapters)
        } else {
            $Adapters = @(Get-NetAdapter | Sort-Object Name)
        }
    }

    if ([string]::IsNullOrWhiteSpace($selector)) {
        $active = @($Adapters | Where-Object { $_.Status -eq "Up" })
        if ($active.Count -gt 0) { return $active[0] }
        if ($Adapters.Count -gt 0) { return $Adapters[0] }
        throw "No network adapters are available."
    }

    $matches = @($Adapters | Where-Object {
        $_.Name -ieq $selector -or
        [string]$_.ifIndex -eq $selector -or
        $_.InterfaceDescription -ieq $selector
    })

    if ($matches.Count -eq 0) {
        $matches = @($Adapters | Where-Object {
            $_.Name -like "*$selector*" -or $_.InterfaceDescription -like "*$selector*"
        })
    }

    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    if ($matches.Count -gt 1) {
        $matchText = @($matches | ForEach-Object { "$($_.Name) [$($_.ifIndex)]" }) -join ", "
        throw "Adapter '$selector' is ambiguous: $matchText."
    }

    $available = @($Adapters | ForEach-Object { "$($_.Name) [$($_.ifIndex)]" })
    $availableText = if ($available.Count -gt 0) { $available -join ", " } else { "none" }
    throw "Adapter '$selector' was not found. Available adapters: $availableText."
}

function Invoke-CliApplyProfile {
    param(
        [string]$ProfileName,
        [string]$AdapterSelector = "",
        [switch]$Quiet
    )

    try {
        $profile = Resolve-CliProfile -ProfileName $ProfileName
        $adapter = Resolve-CliAdapter -AdapterName $AdapterSelector
        $success = Invoke-ApplyProfileObject -ProfileData $profile -Adapter $adapter -Source "Cli"

        if (-not $success) {
            Write-OperationLog -Action "CLI apply profile" -Result "Failed" -Detail "Profile=$($profile.Name); Adapter=$($adapter.Name)"
            exit 1
        }

        Write-OperationLog -Action "CLI apply profile" -Result "Succeeded" -Detail "Profile=$($profile.Name); Adapter=$($adapter.Name)"
        if (-not $Quiet) {
            Write-Host "Applied profile '$($profile.Name)' to adapter '$($adapter.Name)'."
        }
        exit 0
    } catch {
        $message = $_.Exception.Message
        Write-OperationLog -Action "CLI apply profile" -Result "Failed" -Detail $message
        Write-Error $message
        exit 1
    }
}

function Get-RdpLaunchPlan {
    param([string]$Target)

    $text = ([string]$Target).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{
            IsValid = $false
            Message = "Enter a Remote Desktop host or .rdp file path."
            FilePath = "mstsc.exe"
            ArgumentList = ""
            DisplayTarget = ""
        }
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($text)
    if ($expanded.EndsWith(".rdp", [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) {
            return [pscustomobject]@{
                IsValid = $false
                Message = "RDP file was not found: $expanded"
                FilePath = "mstsc.exe"
                ArgumentList = ""
                DisplayTarget = $expanded
            }
        }

        $fullPath = [System.IO.Path]::GetFullPath($expanded)
        return [pscustomobject]@{
            IsValid = $true
            Message = ""
            FilePath = "mstsc.exe"
            ArgumentList = '"' + ($fullPath -replace '"', '\"') + '"'
            DisplayTarget = $fullPath
        }
    }

    if ($text -notmatch '^[A-Za-z0-9._:\-\[\]]+$') {
        return [pscustomobject]@{
            IsValid = $false
            Message = "RDP host may contain only letters, numbers, dots, dashes, underscores, colons, and brackets. Use a saved .rdp file for advanced options."
            FilePath = "mstsc.exe"
            ArgumentList = ""
            DisplayTarget = $text
        }
    }

    return [pscustomobject]@{
        IsValid = $true
        Message = ""
        FilePath = "mstsc.exe"
        ArgumentList = "/v:$text"
        DisplayTarget = $text
    }
}

function Set-RdpLaunchStatus {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )

    if ($script:txtRdpStatus) {
        $script:txtRdpStatus.Text = $Message
        switch ($Type) {
            "Success" { $script:txtRdpStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen }
            "Error"   { $script:txtRdpStatus.Foreground = [System.Windows.Media.Brushes]::Salmon }
            "Warning" { $script:txtRdpStatus.Foreground = [System.Windows.Media.Brushes]::Orange }
            default   { $script:txtRdpStatus.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(139,148,158))) }
        }
    }

    Update-Status $Message -Type $Type
}

function Update-RdpProfileControls {
    if ($script:btnRevertRdpProfile) {
        $script:btnRevertRdpProfile.IsEnabled = ($null -ne $script:RdpRestoreSnapshot)
    }
}

function Get-RdpProfileNameSelection {
    if ($script:txtRdpProfileName -and -not [string]::IsNullOrWhiteSpace($script:txtRdpProfileName.Text)) {
        return $script:txtRdpProfileName.Text.Trim()
    }

    if ($script:lstProfiles -and $script:lstProfiles.SelectedItem -and $script:lstProfiles.SelectedItem.Tag) {
        return [string]$script:lstProfiles.SelectedItem.Tag.Name
    }

    return ""
}

function Get-RdpAdapterSelection {
    $selector = if ($script:txtRdpAdapterName) { $script:txtRdpAdapterName.Text.Trim() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($selector)) {
        return Resolve-CliAdapter -AdapterName $selector
    }

    $selected = Get-SelectedAdapter
    if ($selected) { return $selected }

    return Resolve-CliAdapter
}

function Stop-RdpMonitor {
    if ($script:RdpMonitorTimer) {
        $script:RdpMonitorTimer.Stop()
    }
}

function Invoke-RdpProfileRevert {
    param([string]$Reason = "Manual")

    if ($null -eq $script:RdpRestoreSnapshot) {
        Set-RdpLaunchStatus -Message "No RDP profile snapshot is available to revert." -Type Warning
        return $false
    }

    $snapshot = $script:RdpRestoreSnapshot
    $target = $script:RdpLaunchTarget
    $script:RdpRestoreSnapshot = $null
    $script:RdpProcess = $null
    $script:RdpLaunchTarget = ""
    Stop-RdpMonitor
    Update-RdpProfileControls

    $result = Restore-NetworkSnapshot -Snapshot $snapshot
    if ($result.Restored) {
        Write-OperationLog -Action "RDP profile revert" -Result "Succeeded" -Detail "Reason=$Reason; Target=$target; $($result.Message)"
        Set-RdpLaunchStatus -Message "RDP profile reverted after $Reason. $($result.Message)" -Type Success
        return $true
    }

    Write-OperationLog -Action "RDP profile revert" -Result "Failed" -Detail "Reason=$Reason; Target=$target; $($result.Message)"
    Set-RdpLaunchStatus -Message "RDP profile revert failed: $($result.Message)" -Type Error
    return $false
}

function Watch-RdpProcess {
    if ($null -eq $script:RdpProcess) {
        Stop-RdpMonitor
        return
    }

    try {
        if ($script:RdpProcess.HasExited) {
            [void](Invoke-RdpProfileRevert -Reason "disconnect")
        }
    } catch {
        Write-OperationLog -Action "RDP process monitor" -Result "Failed" -Detail $_.Exception.Message
        [void](Invoke-RdpProfileRevert -Reason "monitor failure")
    }
}

function Start-RdpMonitor {
    if ($null -eq $script:RdpMonitorTimer) {
        $script:RdpMonitorTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:RdpMonitorTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:RdpMonitorTimer.Add_Tick({ Watch-RdpProcess })
    }

    $script:RdpMonitorTimer.Start()
}

function Invoke-RdpProfileLaunch {
    if ($script:RdpProcess -and -not $script:RdpProcess.HasExited) {
        Set-RdpLaunchStatus -Message "An RDP profile launch is already being monitored for $script:RdpLaunchTarget." -Type Warning
        return
    }

    $plan = Get-RdpLaunchPlan -Target $script:txtRdpTarget.Text
    if (-not $plan.IsValid) {
        Set-RdpLaunchStatus -Message $plan.Message -Type Error
        return
    }

    $profileName = Get-RdpProfileNameSelection
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        Set-RdpLaunchStatus -Message "Enter a profile name or select a saved profile before launching RDP." -Type Error
        return
    }

    try {
        $profile = Resolve-CliProfile -ProfileName $profileName
        $adapter = Get-RdpAdapterSelection
        $applied = Invoke-ApplyProfileObject -ProfileData $profile -Adapter $adapter -Source "Rdp"
        if (-not $applied) {
            Set-RdpLaunchStatus -Message "RDP launch stopped because profile '$($profile.Name)' could not be applied." -Type Error
            return
        }

        $script:RdpRestoreSnapshot = $script:LastNetworkSnapshot
        if ($null -eq $script:RdpRestoreSnapshot) {
            throw "No rollback snapshot was captured for the RDP profile apply."
        }

        $script:RdpLaunchTarget = $plan.DisplayTarget
        $script:RdpProcess = Start-Process -FilePath $plan.FilePath -ArgumentList $plan.ArgumentList -PassThru
        Start-RdpMonitor
        Update-RdpProfileControls
        Write-OperationLog -Action "RDP profile launch" -Result "Succeeded" -Detail "Target=$($plan.DisplayTarget); Profile=$($profile.Name); Adapter=$($adapter.Name); ProcessId=$($script:RdpProcess.Id)"
        Set-RdpLaunchStatus -Message "Launched RDP to $($plan.DisplayTarget) with profile '$($profile.Name)'. Network state will revert when RDP exits." -Type Success
    } catch {
        $message = $_.Exception.Message
        if ($script:RdpRestoreSnapshot) {
            $restoreResult = Restore-NetworkSnapshot -Snapshot $script:RdpRestoreSnapshot
            $script:RdpRestoreSnapshot = $null
            Update-RdpProfileControls
            $message = "$message Previous network restore: $($restoreResult.Message)"
        }
        $script:RdpProcess = $null
        $script:RdpLaunchTarget = ""
        Stop-RdpMonitor
        Write-OperationLog -Action "RDP profile launch" -Result "Failed" -Detail $message
        Set-RdpLaunchStatus -Message "RDP launch failed: $message" -Type Error
    }
}

function ConvertTo-AppRoutingSafeRuleText {
    param(
        $Value,
        [int]$MaxLength = 96
    )

    if ($MaxLength -lt 8) { $MaxLength = 8 }
    $text = if ($null -eq $Value) { "" } else { ([string]$Value).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) { return "App interface guard" }

    $text = [regex]::Replace($text, '[\x00-\x1F\x7F]', ' ')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if ($text.Length -le $MaxLength) { return $text }

    return ($text.Substring(0, $MaxLength - 3) + "...")
}

function Get-AppRoutingFirewallRuleName {
    param(
        [string]$ProgramPath,
        [string]$InterfaceAlias
    )

    $seed = "$ProgramPath|$InterfaceAlias"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").Substring(0, 16).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }

    $safeAlias = ([string]$InterfaceAlias -replace '[^A-Za-z0-9_-]', '_')
    if ($safeAlias.Length -gt 28) { $safeAlias = $safeAlias.Substring(0, 28) }
    return "NetForge-AppRoute-$hash-$safeAlias"
}

function Get-AppRoutingPolicyPlan {
    param(
        [string]$ProgramPath,
        [string]$InterfaceAlias,
        [string]$RuleName = "",
        [object[]]$Adapters = @()
    )

    $messages = New-Object System.Collections.Generic.List[string]
    $resolvedProgram = ""
    $programText = ([string]$ProgramPath).Trim()
    if ([string]::IsNullOrWhiteSpace($programText)) {
        $messages.Add("Program path is required.")
    } else {
        try {
            $expanded = [Environment]::ExpandEnvironmentVariables($programText)
            if (-not [System.IO.Path]::IsPathRooted($expanded)) {
                $messages.Add("Program path must be a rooted path to an executable.")
            } else {
                $resolvedProgram = [System.IO.Path]::GetFullPath($expanded)
                if (-not (Test-Path -LiteralPath $resolvedProgram -PathType Leaf)) {
                    $messages.Add("Program path was not found.")
                } elseif ([System.IO.Path]::GetExtension($resolvedProgram) -ine ".exe") {
                    $messages.Add("Program path must point to an .exe file.")
                }
            }
        } catch {
            $messages.Add("Program path is not valid: $($_.Exception.Message)")
        }
    }

    $interfaceText = ([string]$InterfaceAlias).Trim()
    if ([string]::IsNullOrWhiteSpace($interfaceText)) {
        $messages.Add("Allowed interface is required.")
    }

    $adapterList = @($Adapters | Where-Object { $_ -and $_.PSObject.Properties["Name"] })
    if ($adapterList.Count -eq 0) {
        try {
            $adapterList = @(Get-NetAdapter -ErrorAction Stop | Sort-Object Name)
        } catch {
            $messages.Add("Could not enumerate network adapters: $($_.Exception.Message)")
        }
    }

    $matchedAdapter = $null
    if (-not [string]::IsNullOrWhiteSpace($interfaceText) -and $adapterList.Count -gt 0) {
        $matchedAdapter = @($adapterList | Where-Object { [string]$_.Name -ieq $interfaceText } | Select-Object -First 1)
        if ($matchedAdapter.Count -gt 0) {
            $matchedAdapter = $matchedAdapter[0]
            $interfaceText = [string]$matchedAdapter.Name
        } else {
            $messages.Add("Allowed interface '$interfaceText' was not found.")
        }
    }

    $blockedAliases = @()
    if ($matchedAdapter) {
        $blockedAliases = @(
            $adapterList |
                Where-Object { $_.Name -and ([string]$_.Name -ine $interfaceText) } |
                ForEach-Object { [string]$_.Name } |
                Select-Object -Unique
        )
    }

    $programLeaf = if ([string]::IsNullOrWhiteSpace($resolvedProgram)) { "app" } else { [System.IO.Path]::GetFileNameWithoutExtension($resolvedProgram) }
    $displayName = if ([string]::IsNullOrWhiteSpace($RuleName)) {
        "$programLeaf via $interfaceText"
    } else {
        [string]$RuleName
    }
    $displayName = ConvertTo-AppRoutingSafeRuleText -Value $displayName -MaxLength 96

    return [pscustomobject]@{
        IsValid = ($messages.Count -eq 0)
        Message = ($messages -join " ")
        ProgramPath = $resolvedProgram
        InterfaceAlias = $interfaceText
        RuleName = $displayName
        RuleGroup = $script:AppRoutingRuleGroup
        BlockedAliases = @($blockedAliases)
    }
}

function New-AppRoutingPolicyRecord {
    param(
        $Plan,
        $ExistingPolicy = $null,
        [datetime]$Now = (Get-Date)
    )

    $createdAt = $Now.ToString("o")
    if ($ExistingPolicy -and $ExistingPolicy.PSObject.Properties["CreatedAt"] -and -not [string]::IsNullOrWhiteSpace([string]$ExistingPolicy.CreatedAt)) {
        $createdAt = [string]$ExistingPolicy.CreatedAt
    }

    return [pscustomobject]@{
        SchemaVersion = 1
        ProgramPath = [string]$Plan.ProgramPath
        InterfaceAlias = [string]$Plan.InterfaceAlias
        CreatedAt = $createdAt
        UpdatedAt = $Now.ToString("o")
    }
}

function Get-AppRoutingPolicies {
    $settings = Get-AppSettings
    $policies = @()
    if ($null -eq $settings -or -not $settings.Contains($script:AppRoutingPolicySettingName)) {
        return @($policies)
    }

    foreach ($policy in @($settings[$script:AppRoutingPolicySettingName])) {
        if ($null -eq $policy) { continue }
        $programPath = if ($policy.PSObject.Properties["ProgramPath"]) { ([string]$policy.ProgramPath).Trim() } else { "" }
        $interfaceAlias = if ($policy.PSObject.Properties["InterfaceAlias"]) { ([string]$policy.InterfaceAlias).Trim() } else { "" }
        if ([string]::IsNullOrWhiteSpace($programPath) -or [string]::IsNullOrWhiteSpace($interfaceAlias)) { continue }

        $policies += [pscustomobject]@{
            SchemaVersion = if ($policy.PSObject.Properties["SchemaVersion"]) { [int]$policy.SchemaVersion } else { 1 }
            ProgramPath = $programPath
            InterfaceAlias = $interfaceAlias
            CreatedAt = if ($policy.PSObject.Properties["CreatedAt"]) { [string]$policy.CreatedAt } else { "" }
            UpdatedAt = if ($policy.PSObject.Properties["UpdatedAt"]) { [string]$policy.UpdatedAt } else { "" }
        }
    }

    return @($policies)
}

function Save-AppRoutingPolicies {
    param([object[]]$Policies)

    $records = @($Policies | Where-Object { $_ -and $_.ProgramPath -and $_.InterfaceAlias })
    Save-AppSetting -Name $script:AppRoutingPolicySettingName -Value @($records)
}

function Save-AppRoutingPolicyRecord {
    param($Plan)

    $policies = @(Get-AppRoutingPolicies)
    $existing = @($policies | Where-Object { [string]$_.ProgramPath -ieq [string]$Plan.ProgramPath } | Select-Object -First 1)
    $remaining = @($policies | Where-Object { [string]$_.ProgramPath -ine [string]$Plan.ProgramPath })
    $existingPolicy = if ($existing.Count -gt 0) { $existing[0] } else { $null }
    $remaining += New-AppRoutingPolicyRecord -Plan $Plan -ExistingPolicy $existingPolicy
    Save-AppRoutingPolicies -Policies $remaining
}

function Remove-AppRoutingStoredPolicy {
    param([string]$ProgramPath)

    $programText = ([string]$ProgramPath).Trim()
    if ([string]::IsNullOrWhiteSpace($programText)) { return 0 }

    try {
        $programText = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($programText))
    } catch {
        $programText = ([string]$ProgramPath).Trim()
    }

    $policies = @(Get-AppRoutingPolicies)
    $remaining = @($policies | Where-Object { [string]$_.ProgramPath -ine $programText })
    $removed = $policies.Count - $remaining.Count
    if ($removed -gt 0) {
        Save-AppRoutingPolicies -Policies $remaining
    }

    return $removed
}

function Get-AppRoutingRuleSpec {
    param(
        $Plan,
        [string]$BlockedAlias
    )

    $ruleName = Get-AppRoutingFirewallRuleName -ProgramPath $Plan.ProgramPath -InterfaceAlias $BlockedAlias
    $displayName = "$($Plan.RuleName) - block $BlockedAlias"
    $description = "NetForge app interface guard: allows $($Plan.ProgramPath) only on $($Plan.InterfaceAlias) by blocking outbound traffic on $BlockedAlias."

    return [pscustomobject]@{
        RuleName = $ruleName
        DisplayName = $displayName
        RuleGroup = $script:AppRoutingRuleGroup
        Description = $description
        ProgramPath = [string]$Plan.ProgramPath
        AllowedInterfaceAlias = [string]$Plan.InterfaceAlias
        InterfaceAlias = [string]$BlockedAlias
    }
}

function Test-AppRoutingFirewallRuleMatchesSpec {
    param(
        $Rule,
        $Spec
    )

    if ($null -eq $Rule -or $null -eq $Spec) { return $false }
    if ([string]$Rule.RuleName -ine [string]$Spec.RuleName) { return $false }
    if ([string]$Rule.Program -ine [string]$Spec.ProgramPath) { return $false }
    if ([string]$Rule.InterfaceAlias -ine [string]$Spec.InterfaceAlias) { return $false }
    if ($Rule.PSObject.Properties["Action"] -and -not [string]::IsNullOrWhiteSpace([string]$Rule.Action) -and [string]$Rule.Action -ine "Block") { return $false }
    if ($Rule.PSObject.Properties["Direction"] -and -not [string]::IsNullOrWhiteSpace([string]$Rule.Direction) -and [string]$Rule.Direction -ine "Outbound") { return $false }
    if ($Rule.PSObject.Properties["Enabled"] -and -not [string]::IsNullOrWhiteSpace([string]$Rule.Enabled) -and [string]$Rule.Enabled -notmatch '^(True|Enabled)$') { return $false }

    return $true
}

function Get-AppRoutingPolicyRepairPlan {
    param(
        [object[]]$Policies,
        [object[]]$ExistingRules = @(),
        [object[]]$Adapters = @()
    )

    $rulesToCreate = @()
    $rulesToRemove = @()
    $desiredRules = @()
    $skippedPolicies = @()
    $existingRuleList = @($ExistingRules | Where-Object { $_ })

    foreach ($policy in @($Policies | Where-Object { $_ })) {
        $programPath = if ($policy.PSObject.Properties["ProgramPath"]) { [string]$policy.ProgramPath } else { "" }
        $interfaceAlias = if ($policy.PSObject.Properties["InterfaceAlias"]) { [string]$policy.InterfaceAlias } else { "" }
        $plan = Get-AppRoutingPolicyPlan -ProgramPath $programPath -InterfaceAlias $interfaceAlias -Adapters $Adapters
        if (-not $plan.IsValid) {
            $skippedPolicies += [pscustomobject]@{
                ProgramPath = $programPath
                InterfaceAlias = $interfaceAlias
                Message = $plan.Message
            }
            continue
        }

        $ownedRules = @($existingRuleList | Where-Object { [string]$_.Program -ieq [string]$plan.ProgramPath })
        $policyDesiredRules = @()
        foreach ($blockedAlias in @($plan.BlockedAliases)) {
            $policyDesiredRules += Get-AppRoutingRuleSpec -Plan $plan -BlockedAlias $blockedAlias
        }
        $desiredRules += $policyDesiredRules

        foreach ($rule in $ownedRules) {
            $matchingSpec = @($policyDesiredRules | Where-Object { [string]$_.RuleName -ieq [string]$rule.RuleName } | Select-Object -First 1)
            if ($matchingSpec.Count -eq 0 -or -not (Test-AppRoutingFirewallRuleMatchesSpec -Rule $rule -Spec $matchingSpec[0])) {
                $rulesToRemove += $rule
            }
        }

        foreach ($spec in $policyDesiredRules) {
            $matchingRule = @($ownedRules | Where-Object { [string]$_.RuleName -ieq [string]$spec.RuleName } | Select-Object -First 1)
            if ($matchingRule.Count -eq 0 -or -not (Test-AppRoutingFirewallRuleMatchesSpec -Rule $matchingRule[0] -Spec $spec)) {
                $rulesToCreate += $spec
            }
        }
    }

    return [pscustomobject]@{
        PoliciesEvaluated = @($Policies).Count
        DesiredRules = @($desiredRules)
        RulesToCreate = @($rulesToCreate)
        RulesToRemove = @($rulesToRemove | Sort-Object RuleName -Unique)
        SkippedPolicies = @($skippedPolicies)
        HasChanges = (($rulesToCreate.Count + $rulesToRemove.Count) -gt 0)
    }
}

function Format-AppRoutingRuleRows {
    param([object[]]$Rules)

    $ruleList = @($Rules)
    if ($ruleList.Count -eq 0) {
        return "No NetForge app interface guards are installed."
    }

    $sb = New-Object System.Text.StringBuilder
    foreach ($rule in $ruleList) {
        $program = if ($rule.Program) { [string]$rule.Program } else { "Any program" }
        $interfaceAlias = if ($rule.InterfaceAlias) { [string]$rule.InterfaceAlias } else { "Any interface" }
        $enabled = if ($rule.Enabled) { [string]$rule.Enabled } else { "Unknown" }
        $sb.AppendLine([string]$rule.DisplayName) | Out-Null
        $sb.AppendLine("  Program: $program") | Out-Null
        $sb.AppendLine("  Blocked interface: $interfaceAlias") | Out-Null
        $sb.AppendLine("  Enabled: $enabled") | Out-Null
    }

    return $sb.ToString()
}

function Get-AppRoutingFirewallRules {
    $results = @()
    try {
        $rules = @(Get-NetFirewallRule -Group $script:AppRoutingRuleGroup -ErrorAction SilentlyContinue | Sort-Object DisplayName)
        foreach ($rule in $rules) {
            $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | Select-Object -First 1
            $interfaceFilter = $rule | Get-NetFirewallInterfaceFilter -ErrorAction SilentlyContinue | Select-Object -First 1
            $results += [pscustomobject]@{
                RuleName = [string]$rule.Name
                DisplayName = [string]$rule.DisplayName
                Program = if ($appFilter) { [string]$appFilter.Program } else { "" }
                InterfaceAlias = if ($interfaceFilter -and $interfaceFilter.InterfaceAlias) { (@($interfaceFilter.InterfaceAlias) -join ", ") } else { "" }
                Enabled = [string]$rule.Enabled
                Action = [string]$rule.Action
                Direction = [string]$rule.Direction
            }
        }
    } catch {
        Write-OperationLog -Action "App interface guard" -Result "RefreshFailed" -Detail $_.Exception.Message
    }

    return @($results)
}

function Invoke-AppRoutingPolicyRepair {
    param([string]$Trigger = "Manual")

    $policies = @(Get-AppRoutingPolicies)
    if ($policies.Count -eq 0) {
        return [pscustomobject]@{
            Succeeded = $true
            RulesCreated = 0
            RulesRemoved = 0
            SkippedPolicies = @()
            Message = "No persisted app interface guard policies."
        }
    }

    try {
        $existingRules = @(Get-AppRoutingFirewallRules)
        $repairPlan = Get-AppRoutingPolicyRepairPlan -Policies $policies -ExistingRules $existingRules
        $removed = 0
        $created = 0

        foreach ($rule in @($repairPlan.RulesToRemove)) {
            Remove-NetFirewallRule -Name $rule.RuleName -Confirm:$false -ErrorAction Stop
            $removed++
            Write-OperationLog -Action "App interface guard repair" -Result "RemovedStale" -Detail "Trigger=$Trigger; Program=$($rule.Program); Blocked=$($rule.InterfaceAlias); Rule=$($rule.RuleName)"
        }

        foreach ($spec in @($repairPlan.RulesToCreate)) {
            New-NetFirewallRule -Name $spec.RuleName -DisplayName $spec.DisplayName -Group $spec.RuleGroup -Description $spec.Description -Enabled True -Profile Any -Direction Outbound -Action Block -Program $spec.ProgramPath -InterfaceAlias $spec.InterfaceAlias -ErrorAction Stop | Out-Null
            $created++
            Write-OperationLog -Action "App interface guard repair" -Result "CreatedMissing" -Detail "Trigger=$Trigger; Program=$($spec.ProgramPath); Allowed=$($spec.AllowedInterfaceAlias); Blocked=$($spec.InterfaceAlias); Rule=$($spec.RuleName)"
        }

        foreach ($skipped in @($repairPlan.SkippedPolicies)) {
            Write-OperationLog -Action "App interface guard repair" -Result "SkippedPolicy" -Detail "Trigger=$Trigger; Program=$($skipped.ProgramPath); Allowed=$($skipped.InterfaceAlias); $($skipped.Message)"
        }

        if ($created -gt 0 -or $removed -gt 0 -or @($repairPlan.SkippedPolicies).Count -gt 0) {
            Refresh-AppRoutingRuleList
        }

        $message = "App interface guards reconciled: created $created, removed $removed"
        if (@($repairPlan.SkippedPolicies).Count -gt 0) {
            $message += ", skipped $(@($repairPlan.SkippedPolicies).Count)"
        }
        Write-OperationLog -Action "App interface guard repair" -Result "Completed" -Detail "Trigger=$Trigger; $message"

        return [pscustomobject]@{
            Succeeded = $true
            RulesCreated = $created
            RulesRemoved = $removed
            SkippedPolicies = @($repairPlan.SkippedPolicies)
            Message = $message
        }
    } catch {
        $message = "App interface guard repair failed: $($_.Exception.Message)"
        Write-OperationLog -Action "App interface guard repair" -Result "Failed" -Detail "Trigger=$Trigger; $message"
        Set-AppRoutingStatus -Message $message -Type Error
        return [pscustomobject]@{
            Succeeded = $false
            RulesCreated = 0
            RulesRemoved = 0
            SkippedPolicies = @()
            Message = $message
        }
    }
}

function Set-AppRoutingStatus {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )

    if ($script:txtAppRoutingStatus) {
        $script:txtAppRoutingStatus.Text = $Message
    }
    if ($Type -ne "Info") {
        Update-Status $Message -Type $Type
    }
}

function Refresh-AppRoutingInterfaceList {
    if (-not $script:cmbAppRoutingInterface) { return }

    $selectedAlias = ""
    if ($script:cmbAppRoutingInterface.SelectedItem -and $script:cmbAppRoutingInterface.SelectedItem.Tag) {
        $selectedAlias = [string]$script:cmbAppRoutingInterface.SelectedItem.Tag
    } else {
        try {
            $selectedAdapter = Get-SelectedAdapter
            if ($selectedAdapter) { $selectedAlias = [string]$selectedAdapter.Name }
        } catch {
            $selectedAlias = ""
        }
    }

    $script:cmbAppRoutingInterface.Items.Clear()
    try {
        foreach ($adapter in @(Get-NetAdapter -ErrorAction Stop | Sort-Object Name)) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "$($adapter.Name) ($($adapter.Status))"
            $item.Tag = [string]$adapter.Name
            [void]$script:cmbAppRoutingInterface.Items.Add($item)
            if (-not [string]::IsNullOrWhiteSpace($selectedAlias) -and [string]$adapter.Name -ieq $selectedAlias) {
                $script:cmbAppRoutingInterface.SelectedItem = $item
            }
        }
        if (-not $script:cmbAppRoutingInterface.SelectedItem -and $script:cmbAppRoutingInterface.Items.Count -gt 0) {
            $script:cmbAppRoutingInterface.SelectedIndex = 0
        }
    } catch {
        Set-AppRoutingStatus -Message "Could not enumerate adapters for app interface guard: $($_.Exception.Message)" -Type Warning
    }
}

function Refresh-AppRoutingRuleList {
    if ($script:lstAppRoutingRules) {
        $script:lstAppRoutingRules.Items.Clear()
    }

    $rules = @(Get-AppRoutingFirewallRules)
    if ($script:lstAppRoutingRules) {
        foreach ($rule in $rules) {
            $item = New-Object System.Windows.Controls.ListBoxItem
            $programLeaf = if ($rule.Program) { [System.IO.Path]::GetFileName($rule.Program) } else { "Any program" }
            $item.Content = "$programLeaf blocked on $($rule.InterfaceAlias)"
            $item.Tag = $rule
            [void]$script:lstAppRoutingRules.Items.Add($item)
        }
    }

    if ($rules.Count -eq 0) {
        Set-AppRoutingStatus -Message "No NetForge app interface guards are installed."
    } else {
        Set-AppRoutingStatus -Message "$($rules.Count) NetForge app interface guard rule(s) installed."
    }
}

function Initialize-AppRoutingControls {
    Refresh-AppRoutingInterfaceList
    [void](Invoke-AppRoutingPolicyRepair -Trigger "Startup")
    Refresh-AppRoutingRuleList
}

function Get-SelectedAppRoutingInterfaceAlias {
    if ($script:cmbAppRoutingInterface -and $script:cmbAppRoutingInterface.SelectedItem -and $script:cmbAppRoutingInterface.SelectedItem.Tag) {
        return [string]$script:cmbAppRoutingInterface.SelectedItem.Tag
    }
    return ""
}

function Browse-AppRoutingProgram {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Executable Files (*.exe)|*.exe|All Files (*.*)|*.*"
    $dialog.Title = "Select application executable"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:txtAppRoutingProgram.Text = $dialog.FileName
    }
}

function Remove-AppRoutingPolicyByProgram {
    param([string]$ProgramPath)

    $resolvedProgram = ""
    if (-not [string]::IsNullOrWhiteSpace($ProgramPath)) {
        try {
            $resolvedProgram = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables(([string]$ProgramPath).Trim()))
        } catch {
            $resolvedProgram = ([string]$ProgramPath).Trim()
        }
    }

    $removed = 0
    foreach ($rule in @(Get-AppRoutingFirewallRules | Where-Object { [string]$_.Program -ieq $resolvedProgram })) {
        Remove-NetFirewallRule -Name $rule.RuleName -Confirm:$false -ErrorAction Stop
        $removed++
    }

    return $removed
}

function Apply-AppRoutingPolicy {
    $programPath = if ($script:txtAppRoutingProgram) { [string]$script:txtAppRoutingProgram.Text } else { "" }
    $interfaceAlias = Get-SelectedAppRoutingInterfaceAlias
    $plan = Get-AppRoutingPolicyPlan -ProgramPath $programPath -InterfaceAlias $interfaceAlias
    if (-not $plan.IsValid) {
        Set-AppRoutingStatus -Message $plan.Message -Type Error
        return
    }

    try {
        Save-AppRoutingPolicyRecord -Plan $plan
        $repair = Invoke-AppRoutingPolicyRepair -Trigger "ManualApply"
        if (-not $repair.Succeeded) {
            return
        }
        Refresh-AppRoutingRuleList
        $created = [int]$repair.RulesCreated
        $removed = [int]$repair.RulesRemoved
        $message = "App interface guard applied for $([System.IO.Path]::GetFileName($plan.ProgramPath)): allowed on $($plan.InterfaceAlias), repaired $created missing and $removed stale firewall rule(s)."
        if ($plan.BlockedAliases.Count -eq 0) {
            $message = "App interface guard saved no firewall rules because no other current adapters were found."
        }
        Write-OperationLog -Action "App interface guard" -Result "Applied" -Detail "Program=$($plan.ProgramPath); Allowed=$($plan.InterfaceAlias); Created=$created; Removed=$removed; Persisted=True"
        Set-AppRoutingStatus -Message $message -Type Success
    } catch {
        $message = "App interface guard failed: $($_.Exception.Message)"
        Write-OperationLog -Action "App interface guard" -Result "Failed" -Detail $message
        Set-AppRoutingStatus -Message $message -Type Error
    }
}

function Remove-SelectedAppRoutingPolicy {
    $programPath = ""
    if ($script:lstAppRoutingRules -and $script:lstAppRoutingRules.SelectedItem -and $script:lstAppRoutingRules.SelectedItem.Tag) {
        $programPath = [string]$script:lstAppRoutingRules.SelectedItem.Tag.Program
    } elseif ($script:txtAppRoutingProgram) {
        $programPath = [string]$script:txtAppRoutingProgram.Text
    }

    if ([string]::IsNullOrWhiteSpace($programPath)) {
        Set-AppRoutingStatus -Message "Select an app interface guard rule or enter a program path to remove." -Type Warning
        return
    }

    try {
        $storedRemoved = Remove-AppRoutingStoredPolicy -ProgramPath $programPath
        $removed = Remove-AppRoutingPolicyByProgram -ProgramPath $programPath
        Refresh-AppRoutingRuleList
        Write-OperationLog -Action "App interface guard" -Result "Removed" -Detail "Program=$programPath; Removed=$removed; StoredPoliciesRemoved=$storedRemoved"
        Set-AppRoutingStatus -Message "Removed $removed app interface guard rule(s) and $storedRemoved stored policy record(s) for $([System.IO.Path]::GetFileName($programPath))." -Type Success
    } catch {
        $message = "App interface guard removal failed: $($_.Exception.Message)"
        Write-OperationLog -Action "App interface guard" -Result "RemoveFailed" -Detail $message
        Set-AppRoutingStatus -Message $message -Type Error
    }
}

function Invoke-TrayDispatcherAction {
    param([scriptblock]$Action)

    if ($null -eq $Action) { return }

    $runner = {
        try {
            & $Action
        } catch {
            $message = $_.Exception.Message
            Write-OperationLog -Action "System tray action" -Result "Failed" -Detail $message
            Update-Status "System tray action failed: $message" -Type Error
            Show-TrayBalloon -Title "NetForge action failed" -Message $message -Icon Error
        }
    }.GetNewClosure()

    if ($window.Dispatcher.CheckAccess()) {
        & $runner
    } else {
        [void]$window.Dispatcher.BeginInvoke([action]$runner)
    }
}

function New-TrayMenuItem {
    param(
        [string]$Text,
        [scriptblock]$Action = $null,
        [bool]$Enabled = $true
    )

    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $Text
    $item.Enabled = $Enabled

    if ($Action) {
        $menuAction = $Action.GetNewClosure()
        $item.Add_Click({
            Invoke-TrayDispatcherAction -Action $menuAction
        }.GetNewClosure())
    }

    return $item
}

function Show-TrayBalloon {
    param(
        [string]$Title,
        [string]$Message,
        [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info
    )

    if ($null -eq $script:TrayIcon) { return }

    try {
        $script:TrayIcon.BalloonTipTitle = $Title
        $script:TrayIcon.BalloonTipText = $Message
        $script:TrayIcon.BalloonTipIcon = $Icon
        $script:TrayIcon.ShowBalloonTip(4000)
    } catch {
        Write-OperationLog -Action "System tray balloon" -Result "Failed" -Detail $_.Exception.Message
    }
}

function Show-MainWindowFromTray {
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    }
    $window.Show()
    [void]$window.Activate()
    Update-Status "NetForge restored from system tray" -Type Info
}

function Set-MainWindowTrayHidden {
    if ($null -eq $script:TrayIcon) { return }

    $window.Hide()
    Update-Status "NetForge hidden to system tray" -Type Info
    Show-TrayBalloon -Title "NetForge" -Message "NetForge is running in the system tray. Double-click the icon to reopen it." -Icon Info
}

function Get-TrayApplyAdapter {
    $selected = Get-SelectedAdapter
    if ($null -ne $selected) { return $selected }

    $adapters = @(Get-NetworkAdapters)
    $active = $adapters | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($null -ne $active) { return $active }

    return ($adapters | Select-Object -First 1)
}

function Invoke-TrayDnsPreset {
    param(
        [string]$PresetName,
        [object]$PresetData
    )

    $adapter = Get-TrayApplyAdapter
    if ($null -eq $adapter) {
        Update-Status "Tray DNS apply skipped: no adapter available" -Type Warning
        Show-TrayBalloon -Title "NetForge DNS" -Message "No network adapter is available." -Icon Warning
        return
    }

    $includeIPv6 = $false
    if ($script:chkIPv6Dns -and $script:chkIPv6Dns.IsChecked) {
        $includeIPv6 = $true
    }

    $target = Get-DnsPresetApplyTarget -PresetName $PresetName -PresetData $PresetData -IncludeIPv6 $includeIPv6
    if (-not $target.IsValid) {
        Update-Status $target.Message -Type Error
        Show-TrayBalloon -Title "NetForge DNS" -Message $target.Message -Icon Error
        return
    }

    Update-Status "Applying tray DNS preset '$PresetName'..."
    $success = Invoke-NetworkMutation -Adapter $adapter -ActionName "Tray DNS preset '$PresetName'" -Quiet -ScriptBlock {
        Invoke-AdapterDNSTarget -Adapter $adapter -Target $target
    }

    if ($success) {
        Update-AdapterDetails
        $message = "$($target.StatusMessage) to $($adapter.Name)"
        Update-Status $message -Type Success
        Show-TrayBalloon -Title "NetForge DNS applied" -Message $message -Icon Info
    } else {
        Show-TrayBalloon -Title "NetForge DNS failed" -Message "Could not apply '$PresetName' to $($adapter.Name). Previous state was restored when possible." -Icon Error
    }
}

function Invoke-TrayProfile {
    param([pscustomobject]$ProfileData)

    $adapter = Get-TrayApplyAdapter
    if ($null -eq $adapter) {
        Update-Status "Tray profile apply skipped: no adapter available" -Type Warning
        Show-TrayBalloon -Title "NetForge profile" -Message "No network adapter is available." -Icon Warning
        return
    }

    if ($null -eq $ProfileData) {
        Update-Status "Tray profile apply skipped: no profile selected" -Type Warning
        Show-TrayBalloon -Title "NetForge profile" -Message "No profile data is available." -Icon Warning
        return
    }

    $applied = Invoke-ApplyProfileObject -ProfileData $ProfileData -Adapter $adapter -Source "Tray"
    if ($applied) {
        $message = "Profile '$($ProfileData.Name)' applied to $($adapter.Name)"
        Update-Status $message -Type Success
        Show-TrayBalloon -Title "NetForge profile applied" -Message $message -Icon Info
    } else {
        Show-TrayBalloon -Title "NetForge profile failed" -Message "Could not apply profile '$($ProfileData.Name)' to $($adapter.Name)." -Icon Error
    }
}

function Update-TrayMenu {
    if ($null -eq $script:TrayIcon) { return }

    $oldMenu = $script:TrayContextMenu
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false

    [void]$menu.Items.Add((New-TrayMenuItem -Text "Open NetForge" -Action { Show-MainWindowFromTray }))
    [void]$menu.Items.Add((New-TrayMenuItem -Text "Hide Window" -Action { Set-MainWindowTrayHidden }))
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $dnsRoot = New-TrayMenuItem -Text "Quick DNS"
    $dnsEntries = @($script:DnsPresets.GetEnumerator() | Sort-Object @{ Expression = { if ($_.Value.Category) { [string]$_.Value.Category } else { "Other" } } }, @{ Expression = { [string]$_.Key } })
    if ($dnsEntries.Count -eq 0) {
        [void]$dnsRoot.DropDownItems.Add((New-TrayMenuItem -Text "No DNS presets available" -Enabled $false))
    } else {
        $categoryMenus = [ordered]@{}
        foreach ($entry in $dnsEntries) {
            $category = if ($entry.Value.Category) { [string]$entry.Value.Category } else { "Other" }
            if (-not $categoryMenus.Contains($category)) {
                $categoryItem = New-TrayMenuItem -Text $category
                $categoryMenus[$category] = $categoryItem
                [void]$dnsRoot.DropDownItems.Add($categoryItem)
            }

            $presetName = [string]$entry.Key
            $presetData = $entry.Value
            $presetAction = { Invoke-TrayDnsPreset -PresetName $presetName -PresetData $presetData }.GetNewClosure()
            [void]$categoryMenus[$category].DropDownItems.Add((New-TrayMenuItem -Text $presetName -Action $presetAction))
        }
    }
    [void]$menu.Items.Add($dnsRoot)

    $profileRoot = New-TrayMenuItem -Text "Profiles"
    $profiles = @(Get-Profiles | Sort-Object Name)
    if ($profiles.Count -eq 0) {
        [void]$profileRoot.DropDownItems.Add((New-TrayMenuItem -Text "No saved profiles" -Enabled $false))
    } else {
        foreach ($profile in $profiles) {
            $profileData = $profile
            $profileAction = { Invoke-TrayProfile -ProfileData $profileData }.GetNewClosure()
            [void]$profileRoot.DropDownItems.Add((New-TrayMenuItem -Text $profile.Name -Action $profileAction))
        }
    }
    [void]$menu.Items.Add($profileRoot)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add((New-TrayMenuItem -Text "Refresh Menu" -Action { Update-TrayMenu }))
    [void]$menu.Items.Add((New-TrayMenuItem -Text "Exit NetForge" -Action { $window.Close() }))

    $script:TrayContextMenu = $menu
    $script:TrayIcon.ContextMenuStrip = $menu

    if ($oldMenu) {
        $oldMenu.Dispose()
    }
}

function Initialize-SystemTray {
    if ($script:TrayIcon) { return }

    $icon = [System.Drawing.SystemIcons]::Application
    $iconPath = Join-Path $script:ScriptRoot "icon.ico"
    if (Test-Path -LiteralPath $iconPath) {
        try {
            $icon = New-Object System.Drawing.Icon($iconPath)
        } catch {
            Write-OperationLog -Action "System tray icon" -Result "Fallback" -Detail $_.Exception.Message
        }
    }

    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Icon = $icon
    $script:TrayIcon.Text = "NetForge v$script:AppVersion"
    $script:TrayIcon.Visible = $true
    $script:TrayIcon.Add_DoubleClick({
        Invoke-TrayDispatcherAction -Action { Show-MainWindowFromTray }
    })

    $window.Add_StateChanged({
        if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
            Set-MainWindowTrayHidden
        }
    })

    Update-TrayMenu
    Write-OperationLog -Action "System tray" -Result "Started" -Detail "Quick DNS/profile menu initialized"
}

function Remove-SystemTray {
    if ($script:TrayIcon) {
        try {
            $script:TrayIcon.Visible = $false
            $script:TrayIcon.Dispose()
        } catch {
            Write-OperationLog -Action "System tray" -Result "DisposeFailed" -Detail $_.Exception.Message
        }
        $script:TrayIcon = $null
    }

    if ($script:TrayContextMenu) {
        $script:TrayContextMenu.Dispose()
        $script:TrayContextMenu = $null
    }
}

# ============================================================================
# NETWORK TOOLS FUNCTIONS
# ============================================================================
function Invoke-FlushDns {
    Update-Status "Flushing DNS cache..."
    try {
        $output = ipconfig /flushdns 2>&1
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "DNS cache flushed successfully" -Type Success
    } catch {
        Update-Status "Error flushing DNS: $($_.Exception.Message)" -Type Error
    }
}

function Invoke-ReleaseIP {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    Update-Status "Releasing IP address..."
    try {
        $output = ipconfig /release $adapter.Name 2>&1
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "IP released on $($adapter.Name)" -Type Success
        Update-AdapterDisplay
    } catch {
        Update-Status "Error releasing IP: $($_.Exception.Message)" -Type Error
    }
}

function Invoke-RenewIP {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    Update-Status "Renewing IP address..."
    try {
        $output = ipconfig /renew $adapter.Name 2>&1
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "IP renewed on $($adapter.Name)" -Type Success
        Update-AdapterDisplay
    } catch {
        Update-Status "Error renewing IP: $($_.Exception.Message)" -Type Error
    }
}

function Invoke-ResetWinsock {
    $result = Show-MessageBox -Message "This will reset Winsock catalog. A restart may be required.`n`nContinue?" -Title "Confirm Winsock Reset" -Buttons YesNo -Icon Warning
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Update-Status "Resetting Winsock..."
    try {
        $output = netsh winsock reset 2>&1
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "Winsock reset complete - restart may be required" -Type Warning
    } catch {
        Update-Status "Error resetting Winsock: $($_.Exception.Message)" -Type Error
    }
}

function Invoke-ResetTCP {
    $result = Show-MessageBox -Message "This will reset TCP/IP stack. A restart may be required.`n`nContinue?" -Title "Confirm TCP/IP Reset" -Buttons YesNo -Icon Warning
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Update-Status "Resetting TCP/IP stack..."
    try {
        $output = netsh int ip reset 2>&1
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "TCP/IP stack reset complete - restart may be required" -Type Warning
    } catch {
        Update-Status "Error resetting TCP/IP: $($_.Exception.Message)" -Type Error
    }
}

function Invoke-NetworkReset {
    $result = Show-MessageBox -Message "This will perform a full network reset including:`n- Winsock reset`n- TCP/IP reset`n- Firewall reset`n`nA restart WILL be required.`n`nContinue?" -Title "Full Network Reset" -Buttons YesNo -Icon Warning
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Update-Status "Performing full network reset..."
    try {
        $output = @()
        $output += "=== Winsock Reset ==="
        $output += netsh winsock reset 2>&1
        $output += "`n=== TCP/IP Reset ==="
        $output += netsh int ip reset 2>&1
        $output += "`n=== Firewall Reset ==="
        $output += netsh advfirewall reset 2>&1

        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "Full network reset complete - RESTART REQUIRED" -Type Warning

        Show-MessageBox -Message "Network reset complete.`n`nPlease restart your computer for changes to take effect." -Title "Restart Required" -Icon Information
    } catch {
        Update-Status "Error during network reset: $($_.Exception.Message)" -Type Error
    }
}

function Invoke-Ping {
    $target = $script:txtPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    Update-Status "Pinging $target..."
    $script:txtDiagOutput.Text = "Pinging $target...`n"

    $job = Start-Job -ScriptBlock {
        param($t)
        ping -n 4 $t 2>&1
    } -ArgumentList $target

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($job.State -eq "Completed") {
            $result = Receive-Job $job
            $script:txtDiagOutput.Text = $result | Out-String
            Update-Status "Ping complete"
            $timer.Stop()
            Remove-Job $job
        }
    })
    $timer.Start()
}

function Invoke-Traceroute {
    $target = $script:txtPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    Update-Status "Running traceroute to $target..."
    $script:txtDiagOutput.Text = "Tracing route to $target...`n(This may take a moment)`n"

    $job = Start-Job -ScriptBlock {
        param($t)
        tracert -d -h 15 $t 2>&1
    } -ArgumentList $target

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($job.State -eq "Completed") {
            $result = Receive-Job $job
            $script:txtDiagOutput.Text = $result | Out-String
            Update-Status "Traceroute complete"
            $timer.Stop()
            Remove-Job $job
        }
    })
    $timer.Start()
}

function New-MtrHopRecord {
    param([int]$Hop)

    return [pscustomobject]@{
        Hop = $Hop
        Address = ""
        Sent = 0
        Received = 0
        LossPercent = 100
        LastMs = -1
        BestMs = -1
        AvgMs = -1
        WorstMs = -1
        TotalMs = 0
        LastStatus = ""
        IsDestination = $false
    }
}

function Update-MtrHopHistory {
    param(
        [hashtable]$History,
        [object[]]$ProbeResults
    )

    if ($null -eq $History) { $History = @{} }

    foreach ($probe in @($ProbeResults)) {
        if ($null -eq $probe) { continue }
        $hop = [int]$probe.Hop
        if ($hop -le 0) { continue }

        if (-not $History.ContainsKey($hop)) {
            $History[$hop] = New-MtrHopRecord -Hop $hop
        }

        $record = $History[$hop]
        $record.Sent = [int]$record.Sent + 1
        $record.LastStatus = [string]$probe.Status
        $record.IsDestination = [bool]$probe.IsDestination
        if (-not [string]::IsNullOrWhiteSpace([string]$probe.Address)) {
            $record.Address = [string]$probe.Address
        }

        $latency = [int]$probe.LatencyMs
        if ($latency -ge 0) {
            $record.Received = [int]$record.Received + 1
            $record.LastMs = $latency
            $record.TotalMs = [int]$record.TotalMs + $latency
            if ($record.BestMs -lt 0 -or $latency -lt $record.BestMs) { $record.BestMs = $latency }
            if ($record.WorstMs -lt 0 -or $latency -gt $record.WorstMs) { $record.WorstMs = $latency }
            $record.AvgMs = [math]::Round(([double]$record.TotalMs / [double]$record.Received), 1)
        } else {
            $record.LastMs = -1
        }

        if ($record.Sent -gt 0) {
            $record.LossPercent = [math]::Round((([double]($record.Sent - $record.Received) / [double]$record.Sent) * 100), 0)
        }
    }

    return $History
}

function Format-MtrLatency {
    param($Value)

    if ($null -eq $Value -or [double]$Value -lt 0) { return "*" }
    return ([string]$Value)
}

function Format-MtrHistoryRows {
    param(
        [hashtable]$History,
        [string]$Target,
        [int]$Cycle = 0
    )

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("MTR-style trace to $Target") | Out-Null
    $sb.AppendLine("Cycle: $Cycle    Updated: $((Get-Date).ToString('HH:mm:ss'))") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("Hop  Address             Sent Recv Loss  Last  Best  Avg   Worst Status") | Out-Null
    $sb.AppendLine("---  ------------------  ---- ---- ----- ----- ----- ----- ----- ------") | Out-Null

    foreach ($hop in @($History.Keys | Sort-Object {[int]$_})) {
        $record = $History[$hop]
        $address = if ([string]::IsNullOrWhiteSpace($record.Address)) { "*" } else { $record.Address }
        if ($address.Length -gt 18) { $address = $address.Substring(0, 18) }
        $status = if ($record.IsDestination) { "dest" } elseif ([string]::IsNullOrWhiteSpace($record.LastStatus)) { "--" } else { $record.LastStatus }
        if ($status.Length -gt 6) { $status = $status.Substring(0, 6) }

        $line = "{0,3}  {1,-18}  {2,4} {3,4} {4,4}% {5,5} {6,5} {7,5} {8,5} {9}" -f `
            $record.Hop,
            $address,
            $record.Sent,
            $record.Received,
            $record.LossPercent,
            (Format-MtrLatency -Value $record.LastMs),
            (Format-MtrLatency -Value $record.BestMs),
            (Format-MtrLatency -Value $record.AvgMs),
            (Format-MtrLatency -Value $record.WorstMs),
            $status
        $sb.AppendLine($line) | Out-Null
    }

    return $sb.ToString()
}

function Invoke-MtrProbeCycle {
    if (-not $script:MtrRunning -or $script:MtrProbeRunning) { return }

    $target = $script:MtrTarget
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    $script:MtrProbeRunning = $true
    $script:MtrCycle++
    $cycle = $script:MtrCycle

    $ps = [PowerShell]::Create()
    $script:MtrPowerShell = $ps
    $ps.AddScript({
        param($targetHost, $maxHops, $timeoutMs)

        $results = @()
        $buffer = New-Object byte[] 32

        for ($ttl = 1; $ttl -le $maxHops; $ttl++) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $options = New-Object System.Net.NetworkInformation.PingOptions
            $options.Ttl = $ttl
            $options.DontFragment = $true

            try {
                $reply = $ping.Send($targetHost, $timeoutMs, $buffer, $options)
                $status = $reply.Status.ToString()
                $address = if ($reply.Address) { $reply.Address.ToString() } else { "" }
                $latency = if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success -or $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TtlExpired) {
                    [int]$reply.RoundtripTime
                } else {
                    -1
                }
                $isDestination = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
                $results += [pscustomobject]@{
                    Hop = $ttl
                    Address = $address
                    LatencyMs = $latency
                    Status = $status
                    IsDestination = $isDestination
                }
                if ($isDestination) { break }
            } catch {
                $results += [pscustomobject]@{
                    Hop = $ttl
                    Address = ""
                    LatencyMs = -1
                    Status = "Error"
                    IsDestination = $false
                }
            } finally {
                $ping.Dispose()
            }
        }

        return $results
    }).AddArgument($target).AddArgument(15).AddArgument(1000) | Out-Null

    $handle = $ps.BeginInvoke()
    $resultTimer = New-Object System.Windows.Threading.DispatcherTimer
    $resultTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $resultTimer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $results = @($ps.EndInvoke($handle))
                $script:MtrHistory = Update-MtrHopHistory -History $script:MtrHistory -ProbeResults $results
                $script:txtDiagOutput.Text = Format-MtrHistoryRows -History $script:MtrHistory -Target $target -Cycle $cycle
            } catch {
                Write-OperationLog -Action "MTR trace" -Result "Warning" -Detail $_.Exception.Message
                $script:txtDiagOutput.Text = "MTR trace failed: $($_.Exception.Message)"
            } finally {
                $script:MtrProbeRunning = $false
                if ($script:MtrPowerShell -eq $ps) { $script:MtrPowerShell = $null }
                $ps.Dispose()
                $resultTimer.Stop()
            }
        }
    }.GetNewClosure())
    $resultTimer.Start()
}

function Stop-MtrTrace {
    if (-not $script:MtrRunning) { return }

    $script:MtrRunning = $false
    $script:MtrProbeRunning = $false
    if ($script:MtrTimer) {
        $script:MtrTimer.Stop()
        $script:MtrTimer = $null
    }
    if ($script:MtrPowerShell) {
        try {
            $script:MtrPowerShell.Stop()
        } catch {
            Write-OperationLog -Action "MTR trace stop" -Result "Warning" -Detail $_.Exception.Message
        }
    }

    $script:btnMtrTrace.Content = Get-UiString -Key "button.mtr.start" -DefaultValue "Start MTR"
    Update-Status "MTR trace stopped"
}

function Toggle-MtrTrace {
    if ($script:MtrRunning) {
        Stop-MtrTrace
        return
    }

    $target = $script:txtPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    $script:MtrTarget = $target
    $script:MtrHistory = @{}
    $script:MtrCycle = 0
    $script:MtrRunning = $true
    $script:MtrProbeRunning = $false
    $script:btnMtrTrace.Content = Get-UiString -Key "button.mtr.stop" -DefaultValue "Stop MTR"
    $script:txtDiagOutput.Text = "Starting MTR-style trace to $target..."
    Update-Status "MTR trace running to $target..."
    Write-OperationLog -Action "MTR trace" -Result "Started" -Detail "Target=$target"

    $script:MtrTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:MtrTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:MtrTimer.Add_Tick({
        Invoke-MtrProbeCycle
    })
    $script:MtrTimer.Start()
    Invoke-MtrProbeCycle
}

function ConvertTo-UInt32IPv4 {
    param([string]$Address)

    $ip = [System.Net.IPAddress]::Parse($Address)
    $bytes = $ip.GetAddressBytes()
    if ($bytes.Length -ne 4) {
        throw "Only IPv4 targets are supported for CIDR port scans."
    }
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-UInt32IPv4 {
    param([uint32]$Value)

    $bytes = [BitConverter]::GetBytes($Value)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-PortScanTargetList {
    param([string]$Target)

    $text = ([string]$Target).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Port scan target is required."
    }

    if ($text -notmatch '/') {
        return @($text)
    }

    if ($text -notmatch '^(.+)/(\d{1,2})$') {
        throw "CIDR target must look like 192.168.1.0/24."
    }

    $baseAddress = $Matches[1].Trim()
    $prefix = [int]$Matches[2]
    if ($prefix -lt 24 -or $prefix -gt 32) {
        throw "CIDR port scans are limited to /24 through /32."
    }

    $baseInt = [uint64](ConvertTo-UInt32IPv4 -Address $baseAddress)
    $size = [uint64][math]::Pow(2, (32 - $prefix))
    $network = [uint64]([math]::Floor([double]($baseInt / $size)) * $size)
    $first = $network
    $last = $network + $size - 1
    if ($prefix -le 30) {
        $first++
        $last--
    }

    $targets = @()
    for ($value = $first; $value -le $last; $value++) {
        $targets += (ConvertFrom-UInt32IPv4 -Value ([uint32]$value))
    }

    return @($targets)
}

function Get-DefaultPortScanPorts {
    param([int]$TargetCount = 1)

    if ($TargetCount -gt 1) {
        return @(80, 443, 445, 3389)
    }

    return @(22, 53, 80, 135, 139, 443, 445, 3389, 5985, 5986, 8080, 8443)
}

function Get-PortServiceName {
    param([int]$Port)

    $services = @{
        22 = "SSH"
        53 = "DNS"
        80 = "HTTP"
        135 = "RPC"
        139 = "NetBIOS"
        443 = "HTTPS"
        445 = "SMB"
        3389 = "RDP"
        5985 = "WinRM"
        5986 = "WinRM TLS"
        8080 = "HTTP alt"
        8443 = "HTTPS alt"
    }

    if ($services.ContainsKey($Port)) { return $services[$Port] }
    return "tcp/$Port"
}

function Format-PortScanRows {
    param(
        [object[]]$Results,
        [string]$Target,
        [int]$TargetCount,
        [int[]]$Ports,
        [int]$ElapsedMs
    )

    $openResults = @($Results | Where-Object { $_.Status -eq "Open" } | Sort-Object Target, Port)
    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Port scan for $Target") | Out-Null
    $sb.AppendLine("Targets: $TargetCount    Ports: $($Ports -join ', ')    Duration: $ElapsedMs ms") | Out-Null
    $sb.AppendLine("") | Out-Null

    if ($openResults.Count -eq 0) {
        $sb.AppendLine("No open ports found in the scanned set.") | Out-Null
        return $sb.ToString()
    }

    $sb.AppendLine("Target              Port  Service     Latency") | Out-Null
    $sb.AppendLine("------------------  ----  ----------  -------") | Out-Null
    foreach ($item in $openResults) {
        $service = Get-PortServiceName -Port ([int]$item.Port)
        $line = "{0,-18}  {1,4}  {2,-10}  {3,5}ms" -f $item.Target, $item.Port, $service, $item.LatencyMs
        $sb.AppendLine($line) | Out-Null
    }

    return $sb.ToString()
}

function Resolve-ReachabilityTarget {
    param([string]$Target)

    $text = ([string]$Target).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{ IsValid = $false; Message = "Enter a host, IP address, URL, or host:port target."; Original = ""; Host = ""; Port = 0; Scheme = ""; DisplayTarget = "" }
    }

    $targetHost = ""
    $port = 0
    $scheme = ""

    if ($text -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
        $uri = $null
        if (-not [System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref]$uri) -or [string]::IsNullOrWhiteSpace($uri.Host)) {
            return [pscustomobject]@{ IsValid = $false; Message = "Target URL is not valid."; Original = $text; Host = ""; Port = 0; Scheme = ""; DisplayTarget = $text }
        }

        $targetHost = $uri.Host
        $scheme = $uri.Scheme
        if (-not $uri.IsDefaultPort) {
            $port = [int]$uri.Port
        } elseif ($scheme -eq "https") {
            $port = 443
        } elseif ($scheme -eq "http") {
            $port = 80
        } elseif ($scheme -eq "rdp") {
            $port = 3389
        }
    } elseif ($text -match '^\[(.+)\]:(\d{1,5})$') {
        $targetHost = $Matches[1]
        $port = [int]$Matches[2]
    } elseif (($text -split ':').Count -eq 2 -and $text -match '^(.+):(\d{1,5})$') {
        $targetHost = $Matches[1]
        $port = [int]$Matches[2]
    } else {
        $targetHost = $text
    }

    $targetHost = ([string]$targetHost).Trim()
    if ([string]::IsNullOrWhiteSpace($targetHost)) {
        return [pscustomobject]@{ IsValid = $false; Message = "Target host is empty."; Original = $text; Host = ""; Port = 0; Scheme = $scheme; DisplayTarget = $text }
    }

    if ($targetHost -match '[\\/\s]') {
        return [pscustomobject]@{ IsValid = $false; Message = "Target host cannot contain spaces, slashes, or backslashes. Use only a host, IP address, URL, or host:port."; Original = $text; Host = $targetHost; Port = $port; Scheme = $scheme; DisplayTarget = $text }
    }

    if ($port -lt 0 -or $port -gt 65535) {
        return [pscustomobject]@{ IsValid = $false; Message = "Target port must be from 1 to 65535."; Original = $text; Host = $host; Port = $port; Scheme = $scheme; DisplayTarget = $text }
    }

    $display = if ($port -gt 0 -and $text -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://') { "$targetHost`:$port" } else { $text }
    return [pscustomobject]@{
        IsValid = $true
        Message = ""
        Original = $text
        Host = $targetHost
        Port = $port
        Scheme = $scheme
        DisplayTarget = $display
        IsIpAddress = (Test-ValidIP -IP $targetHost)
    }
}

function Format-ReachabilityProbeReport {
    param([pscustomobject]$Result)

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Reachability wizard for $($Result.DisplayTarget)") | Out-Null
    $sb.AppendLine("Checked: $($Result.CheckedAt)") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("1. DNS") | Out-Null
    $sb.AppendLine("   $($Result.DnsStatus): $($Result.DnsMessage)") | Out-Null
    if ($Result.Addresses -and @($Result.Addresses).Count -gt 0) {
        $sb.AppendLine("   Addresses: $((@($Result.Addresses) | Select-Object -First 8) -join ', ')") | Out-Null
    }
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("2. Gateway") | Out-Null
    $sb.AppendLine("   $($Result.GatewayStatus): $($Result.GatewayMessage)") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("3. Route") | Out-Null
    $sb.AppendLine("   $($Result.RouteStatus): $($Result.RouteMessage)") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("4. Firewall / Port") | Out-Null
    $sb.AppendLine("   $($Result.PortStatus): $($Result.PortMessage)") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("5. MTU") | Out-Null
    $sb.AppendLine("   $($Result.MtuStatus): $($Result.MtuMessage)") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("Summary") | Out-Null
    foreach ($line in @($Result.Summary)) {
        $sb.AppendLine(" - $line") | Out-Null
    }

    return $sb.ToString()
}

function Invoke-ReachabilityWizard {
    if ($script:ReachabilityWizardRunning) { return }

    $targetText = $script:txtPingTarget.Text.Trim()
    $targetInfo = Resolve-ReachabilityTarget -Target $targetText
    if (-not $targetInfo.IsValid) {
        Update-Status "Reachability wizard rejected target: $($targetInfo.Message)" -Type Error
        Show-MessageBox -Message $targetInfo.Message -Title "Reachability Wizard" -Icon Warning
        return
    }

    $script:ReachabilityWizardRunning = $true
    $script:btnReachabilityWizard.IsEnabled = $false
    $script:btnReachabilityWizard.Content = Get-UiString -Key "button.reachabilityWizard.running" -DefaultValue "Checking..."
    $script:txtDiagOutput.Text = "Checking reachability for $($targetInfo.DisplayTarget)..."
    Update-Status "Running reachability wizard..."
    Write-OperationLog -Action "Reachability wizard" -Result "Started" -Detail "Target=$($targetInfo.DisplayTarget); Host=$($targetInfo.Host); Port=$($targetInfo.Port)"

    $ps = [PowerShell]::Create()
    $script:ReachabilityWizardPowerShell = $ps
    $ps.AddScript({
        param($target)

        function Test-IpText {
            param([string]$Value)
            $address = $null
            return [System.Net.IPAddress]::TryParse(([string]$Value), [ref]$address)
        }

        function Invoke-PingProbe {
            param(
                [string]$HostName,
                [int]$TimeoutMs = 1200,
                [int]$PayloadBytes = 32,
                [bool]$DontFragment = $false
            )

            $ping = New-Object System.Net.NetworkInformation.Ping
            try {
                $buffer = New-Object byte[] $PayloadBytes
                $options = New-Object System.Net.NetworkInformation.PingOptions
                $options.DontFragment = $DontFragment
                $reply = $ping.Send($HostName, $TimeoutMs, $buffer, $options)
                return [pscustomobject]@{
                    Status = $reply.Status.ToString()
                    Success = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
                    Address = if ($reply.Address) { $reply.Address.ToString() } else { "" }
                    LatencyMs = [int]$reply.RoundtripTime
                }
            } catch {
                return [pscustomobject]@{
                    Status = "Error"
                    Success = $false
                    Address = ""
                    LatencyMs = -1
                    Error = $_.Exception.Message
                }
            } finally {
                $ping.Dispose()
            }
        }

        function Test-TcpPortProbe {
            param(
                [string]$HostName,
                [int]$Port,
                [int]$TimeoutMs = 1800
            )

            $client = New-Object System.Net.Sockets.TcpClient
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $async = $client.BeginConnect($HostName, $Port, $null, $null)
                if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
                    return [pscustomobject]@{ Success = $false; LatencyMs = [int]$watch.ElapsedMilliseconds; Message = "TCP $Port timed out after $TimeoutMs ms." }
                }
                $client.EndConnect($async)
                return [pscustomobject]@{ Success = $true; LatencyMs = [int]$watch.ElapsedMilliseconds; Message = "TCP $Port connected in $([int]$watch.ElapsedMilliseconds) ms." }
            } catch {
                return [pscustomobject]@{ Success = $false; LatencyMs = [int]$watch.ElapsedMilliseconds; Message = "TCP $Port failed: $($_.Exception.Message)" }
            } finally {
                $client.Close()
                $watch.Stop()
            }
        }

        $addresses = @()
        $dnsStatus = "OK"
        $dnsMessage = ""
        if ([bool]$target.IsIpAddress -or (Test-IpText -Value $target.Host)) {
            $addresses = @([string]$target.Host)
            $dnsStatus = "SKIP"
            $dnsMessage = "Target is already an IP address."
        } else {
            try {
                $addresses = @([System.Net.Dns]::GetHostAddresses([string]$target.Host) | ForEach-Object { $_.ToString() } | Select-Object -Unique)
                if ($addresses.Count -gt 0) {
                    $dnsMessage = "$($target.Host) resolved to $($addresses.Count) address(es)."
                } else {
                    $dnsStatus = "FAIL"
                    $dnsMessage = "DNS returned no addresses for $($target.Host)."
                }
            } catch {
                $dnsStatus = "FAIL"
                $dnsMessage = $_.Exception.Message
            }
        }

        $gatewayStatus = "WARN"
        $gatewayMessage = "No IPv4 default gateway was found."
        try {
            $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" } |
                Sort-Object RouteMetric, InterfaceMetric |
                Select-Object -First 1
            if ($route) {
                $gateway = [string]$route.NextHop
                $gatewayPing = Invoke-PingProbe -HostName $gateway -TimeoutMs 900
                if ($gatewayPing.Success) {
                    $gatewayStatus = "OK"
                    $gatewayMessage = "Default gateway $gateway answered in $($gatewayPing.LatencyMs) ms on interface $($route.InterfaceAlias)."
                } else {
                    $gatewayStatus = "WARN"
                    $gatewayMessage = "Default gateway $gateway on interface $($route.InterfaceAlias) did not answer ICMP ($($gatewayPing.Status))."
                }
            }
        } catch {
            $gatewayStatus = "WARN"
            $gatewayMessage = "Gateway check failed: $($_.Exception.Message)"
        }

        $routeStatus = "WARN"
        $routeMessage = "Route check was skipped because DNS failed."
        if ($addresses.Count -gt 0) {
            $routePing = Invoke-PingProbe -HostName ([string]$target.Host) -TimeoutMs 1400
            if ($routePing.Success) {
                $routeStatus = "OK"
                $routeMessage = "Target answered ICMP from $($routePing.Address) in $($routePing.LatencyMs) ms."
            } else {
                $routeStatus = "WARN"
                $routeMessage = "Target did not answer ICMP ($($routePing.Status)). This may be normal if ICMP is filtered."
            }
        }

        $portStatus = "SKIP"
        $portMessage = "No TCP port was provided. Use host:port or an http/https URL to test firewall/port reachability."
        if ([int]$target.Port -gt 0) {
            $tcp = Test-TcpPortProbe -HostName ([string]$target.Host) -Port ([int]$target.Port)
            if ($tcp.Success) {
                $portStatus = "OK"
            } else {
                $portStatus = "FAIL"
            }
            $portMessage = $tcp.Message
        }

        $mtuStatus = "WARN"
        $mtuMessage = "MTU probe was skipped because DNS failed."
        if ($addresses.Count -gt 0) {
            $mtu = Invoke-PingProbe -HostName ([string]$target.Host) -TimeoutMs 1400 -PayloadBytes 1472 -DontFragment $true
            if ($mtu.Success) {
                $mtuStatus = "OK"
                $mtuMessage = "1472-byte ICMP payload with Don't Fragment succeeded."
            } else {
                $small = Invoke-PingProbe -HostName ([string]$target.Host) -TimeoutMs 1400 -PayloadBytes 1200 -DontFragment $true
                if ($small.Success) {
                    $mtuStatus = "WARN"
                    $mtuMessage = "1472-byte DF probe failed ($($mtu.Status)), but 1200-byte DF probe succeeded. Path MTU may be below 1500."
                } else {
                    $mtuStatus = "WARN"
                    $mtuMessage = "DF MTU probes failed or ICMP is filtered (1472=$($mtu.Status), 1200=$($small.Status))."
                }
            }
        }

        $summary = @()
        if ($dnsStatus -eq "FAIL") { $summary += "Fix DNS resolution before testing route or firewall behavior." }
        if ($gatewayStatus -ne "OK") { $summary += "Gateway did not confirm local egress; verify adapter, DHCP/static gateway, VLAN, or WiFi association." }
        if ($routeStatus -ne "OK" -and $portStatus -ne "OK") { $summary += "No positive route or TCP signal was observed; check upstream routing and firewall policy." }
        if ($portStatus -eq "FAIL") { $summary += "The target resolved, but TCP port $($target.Port) did not open; check host firewall, service binding, or intermediate filtering." }
        if ($mtuStatus -eq "WARN") { $summary += "MTU result is inconclusive or degraded; compare VPN, tunnel, and interface MTU settings if large transfers fail." }
        if ($summary.Count -eq 0) { $summary += "Core checks passed for this target." }

        return [pscustomobject]@{
            DisplayTarget = [string]$target.DisplayTarget
            Host = [string]$target.Host
            Port = [int]$target.Port
            CheckedAt = (Get-Date).ToString("o")
            DnsStatus = $dnsStatus
            DnsMessage = $dnsMessage
            Addresses = @($addresses)
            GatewayStatus = $gatewayStatus
            GatewayMessage = $gatewayMessage
            RouteStatus = $routeStatus
            RouteMessage = $routeMessage
            PortStatus = $portStatus
            PortMessage = $portMessage
            MtuStatus = $mtuStatus
            MtuMessage = $mtuMessage
            Summary = @($summary)
        }
    }).AddArgument($targetInfo) | Out-Null

    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $data = @($ps.EndInvoke($handle))
                $result = $data[0]
                $script:txtDiagOutput.Text = Format-ReachabilityProbeReport -Result $result
                Update-Status "Reachability wizard complete" -Type Success
                Write-OperationLog -Action "Reachability wizard" -Result "Succeeded" -Detail "Target=$($result.DisplayTarget); DNS=$($result.DnsStatus); Gateway=$($result.GatewayStatus); Route=$($result.RouteStatus); Port=$($result.PortStatus); MTU=$($result.MtuStatus)"
            } catch {
                Update-Status "Reachability wizard failed: $($_.Exception.Message)" -Type Error
                $script:txtDiagOutput.Text = "Reachability wizard failed: $($_.Exception.Message)"
                Write-OperationLog -Action "Reachability wizard" -Result "Failed" -Detail $_.Exception.Message
            } finally {
                $script:ReachabilityWizardRunning = $false
                $script:btnReachabilityWizard.IsEnabled = $true
                $script:btnReachabilityWizard.Content = Get-UiString -Key "button.reachabilityWizard.idle" -DefaultValue "Why Can't I Reach X?"
                if ($script:ReachabilityWizardPowerShell -eq $ps) { $script:ReachabilityWizardPowerShell = $null }
                $ps.Dispose()
                $timer.Stop()
            }
        }
    }.GetNewClosure())
    $timer.Start()
}

function Invoke-PortScan {
    if ($script:PortScanRunning) { return }

    $target = $script:txtPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    try {
        $targets = @(Get-PortScanTargetList -Target $target)
        $ports = @(Get-DefaultPortScanPorts -TargetCount $targets.Count)
        $scanCount = $targets.Count * $ports.Count
        if ($scanCount -gt 1024) {
            throw "Port scan is capped at 1024 TCP probes; narrow the CIDR target."
        }
    } catch {
        Update-Status "Port scan rejected: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message $_.Exception.Message -Title "Port Scan" -Icon Warning
        return
    }

    $script:PortScanRunning = $true
    $script:btnPortScan.IsEnabled = $false
    $script:btnPortScan.Content = Get-UiString -Key "button.portScan.running" -DefaultValue "Scanning..."
    $script:txtDiagOutput.Text = "Scanning $($targets.Count) target(s) across $($ports.Count) TCP port(s)..."
    Update-Status "Running port scan..."
    Write-OperationLog -Action "Port scan" -Result "Started" -Detail "Target=$target; Targets=$($targets.Count); Ports=$($ports -join ',')"

    $ps = [PowerShell]::Create()
    $script:PortScanPowerShell = $ps
    $ps.AddScript({
        param($scanTargets, $scanPorts, $timeoutMs)

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $pending = New-Object System.Collections.ArrayList
        $open = @()

        foreach ($scanTarget in @($scanTargets)) {
            foreach ($scanPort in @($scanPorts)) {
                $client = New-Object System.Net.Sockets.TcpClient
                $probeWatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $async = $client.BeginConnect([string]$scanTarget, [int]$scanPort, $null, $null)
                    [void]$pending.Add([pscustomobject]@{
                        Target = [string]$scanTarget
                        Port = [int]$scanPort
                        Client = $client
                        Async = $async
                        Watch = $probeWatch
                    })
                } catch {
                    $client.Close()
                }
            }
        }

        while ($pending.Count -gt 0) {
            for ($i = $pending.Count - 1; $i -ge 0; $i--) {
                $probe = $pending[$i]
                if ($probe.Async.IsCompleted) {
                    try {
                        $probe.Client.EndConnect($probe.Async)
                        if ($probe.Client.Connected) {
                            $open += [pscustomobject]@{
                                Target = $probe.Target
                                Port = $probe.Port
                                Status = "Open"
                                LatencyMs = [math]::Max(0, [int]$probe.Watch.ElapsedMilliseconds)
                            }
                        }
                    } catch {
                        [void]$_.Exception.Message
                    } finally {
                        $probe.Client.Close()
                        $pending.RemoveAt($i)
                    }
                } elseif ($probe.Watch.ElapsedMilliseconds -ge $timeoutMs) {
                    $probe.Client.Close()
                    $pending.RemoveAt($i)
                }
            }
            Start-Sleep -Milliseconds 25
        }

        $stopwatch.Stop()
        return [pscustomobject]@{
            Results = @($open)
            ElapsedMs = [int]$stopwatch.ElapsedMilliseconds
        }
    }).AddArgument($targets).AddArgument($ports).AddArgument(700) | Out-Null

    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $data = @($ps.EndInvoke($handle))
                $scanResult = $data[0]
                $script:txtDiagOutput.Text = Format-PortScanRows -Results @($scanResult.Results) -Target $target -TargetCount $targets.Count -Ports $ports -ElapsedMs $scanResult.ElapsedMs
                Update-Status "Port scan complete"
                Write-OperationLog -Action "Port scan" -Result "Succeeded" -Detail "Target=$target; Open=$(@($scanResult.Results).Count); DurationMs=$($scanResult.ElapsedMs)"
            } catch {
                Update-Status "Port scan failed: $($_.Exception.Message)" -Type Error
                $script:txtDiagOutput.Text = "Port scan failed: $($_.Exception.Message)"
                Write-OperationLog -Action "Port scan" -Result "Failed" -Detail $_.Exception.Message
            } finally {
                $script:PortScanRunning = $false
                $script:btnPortScan.IsEnabled = $true
                $script:btnPortScan.Content = Get-UiString -Key "button.portScan.idle" -DefaultValue "Port Scan"
                if ($script:PortScanPowerShell -eq $ps) { $script:PortScanPowerShell = $null }
                $ps.Dispose()
                $timer.Stop()
            }
        }
    }.GetNewClosure())
    $timer.Start()
}

function Get-AdapterStaticRouteRows {
    param($Adapter)

    if ($null -eq $Adapter) { return @() }
    return @(Get-NetRoute -InterfaceIndex $Adapter.ifIndex -ErrorAction SilentlyContinue |
        Where-Object { Test-ManualRouteRow -Route $_ } |
        Sort-Object AddressFamily, DestinationPrefix, NextHop |
        ForEach-Object {
            [pscustomobject]@{
                InterfaceIndex = $_.InterfaceIndex
                DestinationPrefix = $_.DestinationPrefix
                NextHop = $_.NextHop
                RouteMetric = $_.RouteMetric
                AddressFamily = [string]$_.AddressFamily
            }
        })
}

function Refresh-StaticRouteList {
    $adapter = Get-SelectedAdapter
    if ($script:lstStaticRoutes) { $script:lstStaticRoutes.Items.Clear() }

    if ($null -eq $adapter) {
        if ($script:txtStaticRouteStatus) { $script:txtStaticRouteStatus.Text = "Select an adapter to view manual static routes." }
        return
    }

    try {
        $routes = @(Get-AdapterStaticRouteRows -Adapter $adapter)
        foreach ($route in $routes) {
            $metric = if ($null -ne $route.RouteMetric) { [string]$route.RouteMetric } else { "--" }
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = "$($route.DestinationPrefix) -> $($route.NextHop) | metric $metric | $($route.AddressFamily)"
            $item.Tag = $route
            [void]$script:lstStaticRoutes.Items.Add($item)
        }

        if ($script:txtStaticRouteStatus) {
            $script:txtStaticRouteStatus.Text = "Manual static routes for $($adapter.Name): $($routes.Count)."
        }
        if ($script:txtDiagOutput) {
            $script:txtDiagOutput.Text = Format-StaticRouteRows -Routes $routes
        }
    } catch {
        if ($script:txtStaticRouteStatus) { $script:txtStaticRouteStatus.Text = "Route refresh failed: $($_.Exception.Message)" }
        Write-OperationLog -Action "Refresh static routes" -Result "Failed" -Detail $_.Exception.Message
    }
}

function Add-StaticRoute {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $target = Get-StaticRouteTarget -DestinationPrefix $script:txtRouteDestination.Text -NextHop $script:txtRouteNextHop.Text -MetricText $script:txtRouteMetric.Text
    if (-not $target.IsValid) {
        Show-MessageBox -Message $target.Message -Title "Static Route" -Icon Warning
        Update-Status $target.Message -Type Error
        return
    }

    $success = Invoke-NetworkMutation -Adapter $adapter -ActionName "Add static route" -ScriptBlock {
        $routeParams = @{
            InterfaceIndex = $adapter.ifIndex
            DestinationPrefix = $target.DestinationPrefix
            NextHop = $target.NextHop
            ErrorAction = "Stop"
        }
        if ($null -ne $target.RouteMetric) {
            $routeParams.RouteMetric = [int]$target.RouteMetric
        }
        New-NetRoute @routeParams | Out-Null
    } -Quiet

    if ($success) {
        Update-Status "Static route added: $($target.DestinationPrefix) via $($target.NextHop)" -Type Success
        Write-OperationLog -Action "Add static route" -Result "Succeeded" -Detail "Adapter=$($adapter.Name); Prefix=$($target.DestinationPrefix); NextHop=$($target.NextHop)"
        Refresh-StaticRouteList
    }
}

function Remove-SelectedStaticRoute {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }
    if ($null -eq $script:lstStaticRoutes.SelectedItem) {
        Show-MessageBox -Message "Select a static route to remove." -Title "Static Route" -Icon Warning
        return
    }

    $route = $script:lstStaticRoutes.SelectedItem.Tag
    $success = Invoke-NetworkMutation -Adapter $adapter -ActionName "Remove static route" -ScriptBlock {
        Remove-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix $route.DestinationPrefix -NextHop $route.NextHop -Confirm:$false -ErrorAction Stop
    } -Quiet

    if ($success) {
        Update-Status "Static route removed: $($route.DestinationPrefix) via $($route.NextHop)" -Type Success
        Write-OperationLog -Action "Remove static route" -Result "Succeeded" -Detail "Adapter=$($adapter.Name); Prefix=$($route.DestinationPrefix); NextHop=$($route.NextHop)"
        Refresh-StaticRouteList
    }
}

function Update-HostsGroupList {
    if (-not $script:HostsGroups) { $script:HostsGroups = @() }
    if ($script:lstHostsGroups) { $script:lstHostsGroups.Items.Clear() }

    foreach ($group in @($script:HostsGroups)) {
        $entries = @($group.Entries)
        $state = if ([bool]$group.Enabled) { "enabled" } else { "disabled" }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = "[$state] $($group.Name) - $($entries.Count) entr$(if ($entries.Count -eq 1) { 'y' } else { 'ies' })"
        $item.Tag = $group
        [void]$script:lstHostsGroups.Items.Add($item)
    }

    if ($script:txtHostsStatus) {
        $script:txtHostsStatus.Text = "NetForge-managed hosts groups loaded: $(@($script:HostsGroups).Count). Apply Hosts writes the marked section only."
    }
    if ($script:txtDiagOutput) {
        $script:txtDiagOutput.Text = Format-HostsGroupRows -Groups @($script:HostsGroups)
    }
}

function Refresh-HostsGroups {
    try {
        $path = Get-HostsFilePath
        $text = ""
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $text = Get-Content -Raw -LiteralPath $path
        }
        $script:HostsGroups = @(ConvertFrom-HostsManagedSection -Text $text)
        Update-HostsGroupList
        Update-Status "Hosts groups refreshed" -Type Success
        Write-OperationLog -Action "Refresh hosts groups" -Result "Succeeded" -Detail "Groups=$(@($script:HostsGroups).Count)"
    } catch {
        Update-Status "Hosts refresh failed: $($_.Exception.Message)" -Type Error
        if ($script:txtHostsStatus) { $script:txtHostsStatus.Text = "Hosts refresh failed: $($_.Exception.Message)" }
        Write-OperationLog -Action "Refresh hosts groups" -Result "Failed" -Detail $_.Exception.Message
    }
}

function Add-HostsEntry {
    if (-not $script:HostsGroups) { $script:HostsGroups = @() }

    $target = Get-HostsEntryTarget -GroupName $script:txtHostsGroupName.Text -Address $script:txtHostsAddress.Text -HostNames $script:txtHostsNames.Text
    if (-not $target.IsValid) {
        Show-MessageBox -Message $target.Message -Title "Hosts Entry" -Icon Warning
        Update-Status $target.Message -Type Error
        return
    }

    $group = @($script:HostsGroups | Where-Object { ([string]$_.Name).Equals($target.GroupName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if ($group.Count -eq 0) {
        $newGroup = [pscustomobject]@{
            Name = $target.GroupName
            Enabled = $true
            Entries = @()
        }
        $script:HostsGroups = @($script:HostsGroups) + $newGroup
        $groupObject = $newGroup
    } else {
        $groupObject = $group[0]
    }

    $groupObject.Entries = @($groupObject.Entries) + [pscustomobject]@{
        Address = $target.Address
        HostNames = @($target.HostNames)
    }
    Update-HostsGroupList
    Update-Status "Hosts entry staged for group $($target.GroupName)" -Type Success
}

function Toggle-SelectedHostsGroup {
    if ($null -eq $script:lstHostsGroups.SelectedItem) {
        Show-MessageBox -Message "Select a hosts group to toggle." -Title "Hosts Group" -Icon Warning
        return
    }

    $group = $script:lstHostsGroups.SelectedItem.Tag
    $group.Enabled = -not [bool]$group.Enabled
    Update-HostsGroupList
    Update-Status "Hosts group '$($group.Name)' toggled" -Type Success
}

function Remove-SelectedHostsGroup {
    if ($null -eq $script:lstHostsGroups.SelectedItem) {
        Show-MessageBox -Message "Select a hosts group to remove." -Title "Hosts Group" -Icon Warning
        return
    }

    $group = $script:lstHostsGroups.SelectedItem.Tag
    $script:HostsGroups = @($script:HostsGroups | Where-Object { -not ([string]$_.Name).Equals([string]$group.Name, [System.StringComparison]::OrdinalIgnoreCase) })
    Update-HostsGroupList
    Update-Status "Hosts group '$($group.Name)' removed from staged changes" -Type Success
}

function Save-HostsGroups {
    try {
        $path = Get-HostsFilePath
        $currentText = ""
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $currentText = Get-Content -Raw -LiteralPath $path
        }

        $backupDir = Join-Path $script:ConfigPath "HostsBackups"
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $backupPath = Join-Path $backupDir ("hosts-{0}.bak" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
            Copy-Item -LiteralPath $path -Destination $backupPath -Force
        }

        $newText = Update-HostsManagedSection -CurrentText $currentText -Groups @($script:HostsGroups)
        Set-Content -LiteralPath $path -Value $newText -Encoding ASCII
        ipconfig /flushdns | Out-Null
        Refresh-HostsGroups
        Update-Status "Hosts groups applied" -Type Success
        Write-OperationLog -Action "Apply hosts groups" -Result "Succeeded" -Detail "Groups=$(@($script:HostsGroups).Count); Path=$path"
    } catch {
        Update-Status "Hosts apply failed: $($_.Exception.Message)" -Type Error
        if ($script:txtHostsStatus) { $script:txtHostsStatus.Text = "Hosts apply failed: $($_.Exception.Message)" }
        Write-OperationLog -Action "Apply hosts groups" -Result "Failed" -Detail $_.Exception.Message
    }
}

function Get-PacketCaptureDirectory {
    return (Join-Path $script:ConfigPath "Captures")
}

function Get-PacketCaptureFileSet {
    param(
        [string]$Directory,
        [datetime]$Timestamp = (Get-Date)
    )

    $stamp = $Timestamp.ToString("yyyyMMdd-HHmmss")
    return [pscustomobject]@{
        Directory = $Directory
        EtlPath = Join-Path $Directory "netforge-capture-$stamp.etl"
        PcapPath = Join-Path $Directory "netforge-capture-$stamp.pcapng"
    }
}

function Get-PacketCaptureToolStatus {
    $pktmon = Get-Command pktmon.exe -ErrorAction SilentlyContinue
    $wireshark = Get-Command wireshark.exe -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        PktmonPath = if ($pktmon) { $pktmon.Source } else { "" }
        WiresharkPath = if ($wireshark) { $wireshark.Source } else { "" }
        HasPktmon = ($null -ne $pktmon)
        HasWireshark = ($null -ne $wireshark)
    }
}

function Format-PacketCaptureSummary {
    param(
        [string]$EtlPath,
        [string]$PcapPath,
        [bool]$OpenedWireshark,
        [string[]]$StopOutput = @(),
        [string[]]$ConvertOutput = @()
    )

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Packet capture complete") | Out-Null
    $sb.AppendLine("ETL: $EtlPath") | Out-Null
    $sb.AppendLine("PCAPNG: $PcapPath") | Out-Null
    $sb.AppendLine("Wireshark: $(if ($OpenedWireshark) { 'launched' } else { 'not available or not launched' })") | Out-Null
    if ($StopOutput.Count -gt 0) {
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine("pktmon stop:") | Out-Null
        foreach ($line in $StopOutput) { $sb.AppendLine([string]$line) | Out-Null }
    }
    if ($ConvertOutput.Count -gt 0) {
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine("pktmon etl2pcap:") | Out-Null
        foreach ($line in $ConvertOutput) { $sb.AppendLine([string]$line) | Out-Null }
    }

    return $sb.ToString()
}

function Start-PacketCapture {
    if ($script:PacketCaptureRunning) { return }

    $tools = Get-PacketCaptureToolStatus
    if (-not $tools.HasPktmon) {
        Update-Status "Packet capture requires pktmon.exe" -Type Error
        Show-MessageBox -Message "pktmon.exe was not found on this Windows installation." -Title "Packet Capture" -Icon Error
        return
    }

    $captureDir = Get-PacketCaptureDirectory
    if (-not (Test-Path -LiteralPath $captureDir)) {
        New-Item -Path $captureDir -ItemType Directory -Force | Out-Null
    }

    $files = Get-PacketCaptureFileSet -Directory $captureDir
    $args = @("start", "--capture", "--comp", "nics", "--pkt-size", "0", "--file-name", $files.EtlPath, "--file-size", "128")
    $output = & $tools.PktmonPath @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "Packet capture failed to start" -Type Error
        Write-OperationLog -Action "Packet capture" -Result "StartFailed" -Detail (($output | Out-String).Trim())
        return
    }

    $script:PacketCaptureRunning = $true
    $script:PacketCaptureEtlPath = $files.EtlPath
    $script:PacketCapturePcapPath = $files.PcapPath
    $script:btnPacketCapture.Content = Get-UiString -Key "button.packetCapture.stop" -DefaultValue "Stop Capture"
    $script:txtDiagOutput.Text = "Packet capture running on NIC components.`nETL: $($files.EtlPath)`nClick Stop Capture to convert to PCAPNG."
    Update-Status "Packet capture running"
    Write-OperationLog -Action "Packet capture" -Result "Started" -Detail "ETL=$($files.EtlPath)"
}

function Stop-PacketCapture {
    param([switch]$OpenWireshark)

    if (-not $script:PacketCaptureRunning) { return }

    $tools = Get-PacketCaptureToolStatus
    $script:PacketCaptureRunning = $false
    $script:btnPacketCapture.Content = Get-UiString -Key "button.packetCapture.start" -DefaultValue "Start Capture"

    $stopOutput = @()
    $convertOutput = @()
    $openedWireshark = $false
    try {
        $stopOutput = @(& $tools.PktmonPath stop 2>&1)
        $convertOutput = @(& $tools.PktmonPath etl2pcap $script:PacketCaptureEtlPath --out $script:PacketCapturePcapPath 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $script:PacketCapturePcapPath -PathType Leaf)) {
            throw "pktmon conversion did not produce $($script:PacketCapturePcapPath)."
        }

        if ($OpenWireshark -and $tools.HasWireshark) {
            Start-Process -FilePath $tools.WiresharkPath -ArgumentList $script:PacketCapturePcapPath
            $openedWireshark = $true
        }

        $script:txtDiagOutput.Text = Format-PacketCaptureSummary -EtlPath $script:PacketCaptureEtlPath -PcapPath $script:PacketCapturePcapPath -OpenedWireshark:$openedWireshark -StopOutput $stopOutput -ConvertOutput $convertOutput
        Update-Status "Packet capture saved to $($script:PacketCapturePcapPath)" -Type Success
        Write-OperationLog -Action "Packet capture" -Result "Succeeded" -Detail "PCAPNG=$($script:PacketCapturePcapPath); Wireshark=$openedWireshark"
    } catch {
        $script:txtDiagOutput.Text = "Packet capture stop/convert failed: $($_.Exception.Message)`n`n$($stopOutput | Out-String)`n$($convertOutput | Out-String)"
        Update-Status "Packet capture conversion failed" -Type Error
        Write-OperationLog -Action "Packet capture" -Result "Failed" -Detail $_.Exception.Message
    }
}

function Toggle-PacketCapture {
    if ($script:PacketCaptureRunning) {
        Stop-PacketCapture -OpenWireshark
    } else {
        Start-PacketCapture
    }
}

function Test-CableDiagnosticPropertyName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return ($Name -match '(?i)(cable|sfp|ddm|dom|optic|optical|transceiver|module|temperature|laser|rx\s*power|tx\s*power|fec|duplex|media\s*type|link\s*speed)')
}

function Get-CableDiagnosticData {
    param($Adapter)

    if ($null -eq $Adapter) {
        throw "Select an adapter before running cable diagnostics."
    }

    $driverProperties = @()
    try {
        $driverProperties = @(Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction Stop | Where-Object {
            (Test-CableDiagnosticPropertyName -Name $_.DisplayName) -or (Test-CableDiagnosticPropertyName -Name $_.RegistryKeyword)
        } | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.DisplayName
                Value = [string]$_.DisplayValue
                Keyword = [string]$_.RegistryKeyword
            }
        })
    } catch {
        $driverProperties = @([pscustomobject]@{ Name = "Advanced properties"; Value = "Unavailable: $($_.Exception.Message)"; Keyword = "" })
    }

    $hardwareInfo = $null
    try {
        $hardwareInfo = Get-NetAdapterHardwareInfo -Name $Adapter.Name -ErrorAction Stop
    } catch {
        $hardwareInfo = $null
    }

    $statistics = $null
    try {
        $statistics = Get-NetAdapterStatistics -Name $Adapter.Name -ErrorAction Stop
    } catch {
        $statistics = $null
    }

    return [pscustomobject]@{
        AdapterName = [string]$Adapter.Name
        InterfaceDescription = [string]$Adapter.InterfaceDescription
        Status = [string]$Adapter.Status
        LinkSpeed = [string]$Adapter.LinkSpeed
        MacAddress = [string]$Adapter.MacAddress
        DriverProperties = @($driverProperties)
        HardwareInfo = $hardwareInfo
        Statistics = $statistics
    }
}

function Format-CableDiagnosticReport {
    param([pscustomobject]$Data)

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Cable / transceiver diagnostics") | Out-Null
    $sb.AppendLine("=" * 32) | Out-Null
    $sb.AppendLine("Adapter: $($Data.AdapterName)") | Out-Null
    $sb.AppendLine("Description: $($Data.InterfaceDescription)") | Out-Null
    $sb.AppendLine("Status: $($Data.Status)") | Out-Null
    $sb.AppendLine("Link Speed: $($Data.LinkSpeed)") | Out-Null
    $sb.AppendLine("MAC: $($Data.MacAddress)") | Out-Null
    $sb.AppendLine("") | Out-Null

    if ($Data.HardwareInfo) {
        $sb.AppendLine("Hardware") | Out-Null
        $sb.AppendLine("--------") | Out-Null
        foreach ($propertyName in @("InterfaceDescription", "BusType", "DeviceType", "NumaNode", "PcieLinkSpeed", "PcieLinkWidth", "Version")) {
            $property = $Data.HardwareInfo.PSObject.Properties[$propertyName]
            if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $sb.AppendLine(("{0}: {1}" -f $propertyName, $property.Value)) | Out-Null
            }
        }
        $sb.AppendLine("") | Out-Null
    }

    if ($Data.Statistics) {
        $sb.AppendLine("Counters") | Out-Null
        $sb.AppendLine("--------") | Out-Null
        foreach ($propertyName in @("ReceivedBytes", "SentBytes", "ReceivedUnicastPackets", "SentUnicastPackets", "ReceivedDiscardedPackets", "OutboundDiscardedPackets", "ReceivedPacketErrors", "OutboundPacketErrors")) {
            $property = $Data.Statistics.PSObject.Properties[$propertyName]
            if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $sb.AppendLine(("{0}: {1}" -f $propertyName, $property.Value)) | Out-Null
            }
        }
        $sb.AppendLine("") | Out-Null
    }

    $visibleProperties = @($Data.DriverProperties | Where-Object { -not ([string]$_.Name).StartsWith("Advanced properties") })
    $sb.AppendLine("Cable / SFP / DDM driver properties") | Out-Null
    $sb.AppendLine("-----------------------------------") | Out-Null
    if ($visibleProperties.Count -eq 0) {
        $sb.AppendLine("No cable, SFP, DDM, DOM, or optical telemetry properties are exposed by this adapter driver.") | Out-Null
    } else {
        foreach ($property in $visibleProperties) {
            $name = if ([string]::IsNullOrWhiteSpace($property.Name)) { $property.Keyword } else { $property.Name }
            $sb.AppendLine(("{0}: {1}" -f $name, $property.Value)) | Out-Null
        }
    }

    $unavailable = @($Data.DriverProperties | Where-Object { ([string]$_.Name).StartsWith("Advanced properties") })
    if ($unavailable.Count -gt 0) {
        $sb.AppendLine("") | Out-Null
        foreach ($item in $unavailable) { $sb.AppendLine($item.Value) | Out-Null }
    }

    return $sb.ToString()
}

function Invoke-CableDiagnostics {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    try {
        $data = Get-CableDiagnosticData -Adapter $adapter
        $script:txtDiagOutput.Text = Format-CableDiagnosticReport -Data $data
        Update-Status "Cable diagnostics complete"
        Write-OperationLog -Action "Cable diagnostics" -Result "Succeeded" -Detail "Adapter=$($adapter.Name); Properties=$(@($data.DriverProperties).Count)"
    } catch {
        $script:txtDiagOutput.Text = "Cable diagnostics failed: $($_.Exception.Message)"
        Update-Status "Cable diagnostics failed" -Type Error
        Write-OperationLog -Action "Cable diagnostics" -Result "Failed" -Detail $_.Exception.Message
    }
}

function Invoke-Nslookup {
    $target = $script:txtPingTarget.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-MessageBox -Message "Please enter a target address." -Title "No Target" -Icon Warning
        return
    }

    Update-Status "Running NSLookup for $target..."
    try {
        $output = nslookup $target 2>&1
        $script:txtDiagOutput.Text = $output | Out-String
        Update-Status "NSLookup complete"
    } catch {
        Update-Status "Error: $($_.Exception.Message)" -Type Error
    }
}

# ============================================================================
# ADAPTER ENABLE/DISABLE
# ============================================================================
function Enable-SelectedAdapter {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    Update-Status "Enabling $($adapter.Name)..."
    try {
        Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
        Update-Status "$($adapter.Name) enabled successfully" -Type Success
        Start-Sleep -Milliseconds 1000
        Refresh-AdapterList
    } catch {
        Update-Status "Error enabling adapter: $($_.Exception.Message)" -Type Error
    }
}

function Disable-SelectedAdapter {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }

    $result = Show-MessageBox -Message "Disable network adapter '$($adapter.Name)'?`n`nThis will disconnect the network connection." -Title "Confirm" -Buttons YesNo -Icon Warning
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Update-Status "Disabling $($adapter.Name)..."
    try {
        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
        Update-Status "$($adapter.Name) disabled" -Type Success
        Start-Sleep -Milliseconds 500
        Refresh-AdapterList
    } catch {
        Update-Status "Error disabling adapter: $($_.Exception.Message)" -Type Error
    }
}

# ============================================================================
# EXPORT/IMPORT FUNCTIONS
# ============================================================================
function New-DiagnosticsRedactionReport {
    param([bool]$PrivacyMode = $true)

    return [ordered]@{
        PrivacyMode = [bool]$PrivacyMode
        Categories = [ordered]@{
            WebhookUrls = 0
            ProxyServers = 0
            MappedDrivePaths = 0
            SSIDs = 0
            GatewayMacs = 0
            LocalPaths = 0
            AdapterNames = 0
        }
        Files = @()
    }
}

function Add-DiagnosticsRedactionCount {
    param(
        [System.Collections.IDictionary]$Report,
        [string]$Category,
        [int]$Count
    )

    if ($null -eq $Report -or [string]::IsNullOrWhiteSpace($Category) -or $Count -le 0) { return }
    if (-not $Report.Categories.Contains($Category)) {
        $Report.Categories[$Category] = 0
    }
    $Report.Categories[$Category] = [int]$Report.Categories[$Category] + $Count
}

function Add-DiagnosticsRedactionFile {
    param(
        [System.Collections.IDictionary]$Report,
        [string]$Path,
        [string]$Kind,
        [bool]$Redacted
    )

    if ($null -eq $Report) { return }
    $Report.Files = @($Report.Files) + [pscustomobject]@{
        Path = [string]$Path
        Kind = [string]$Kind
        Redacted = [bool]$Redacted
    }
}

function Add-DiagnosticsValue {
    param(
        [System.Collections.Generic.List[string]]$List,
        [AllowEmptyString()][string]$Value
    )

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if (-not $List.Contains($text)) {
        [void]$List.Add($text)
    }
}

function Get-DiagnosticsProxyTokens {
    param([string]$ProxyServer)

    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($part in (([string]$ProxyServer) -split '[;,]')) {
        $text = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        Add-DiagnosticsValue -List $tokens -Value $text

        $withoutScheme = $text -replace '^[A-Za-z][A-Za-z0-9+\-.]*://', ''
        $proxyHost = ($withoutScheme -split '/')[0]
        if ($proxyHost -match '^\[(.+?)\](?::\d+)?$') {
            Add-DiagnosticsValue -List $tokens -Value $Matches[1]
        } elseif ($proxyHost -match '^([^:]+)(?::\d+)?$') {
            Add-DiagnosticsValue -List $tokens -Value $Matches[1]
        }
    }

    return @($tokens)
}

function Get-DiagnosticsRedactionValues {
    param(
        [object[]]$Profiles = @(),
        $Adapter = $null,
        [string]$ConfigPath = "",
        [string]$ProfilesPath = "",
        [string]$LogsPath = ""
    )

    $proxyServers = New-Object System.Collections.Generic.List[string]
    $ssids = New-Object System.Collections.Generic.List[string]
    $gatewayMacs = New-Object System.Collections.Generic.List[string]
    $localPaths = New-Object System.Collections.Generic.List[string]
    $adapterNames = New-Object System.Collections.Generic.List[string]

    foreach ($profile in @($Profiles | Where-Object { $_ })) {
        if ($profile.PSObject.Properties["ProxyServer"]) {
            foreach ($token in @(Get-DiagnosticsProxyTokens -ProxyServer ([string]$profile.ProxyServer))) {
                Add-DiagnosticsValue -List $proxyServers -Value $token
            }
        }
        if ($profile.PSObject.Properties["MatchSSID"]) {
            Add-DiagnosticsValue -List $ssids -Value ([string]$profile.MatchSSID)
        }
        if ($profile.PSObject.Properties["MatchGatewayMac"]) {
            Add-DiagnosticsValue -List $gatewayMacs -Value ([string]$profile.MatchGatewayMac)
        }
    }

    if ($Adapter) {
        foreach ($propertyName in @("Name", "InterfaceAlias", "InterfaceDescription", "MacAddress")) {
            $property = $Adapter.PSObject.Properties[$propertyName]
            if ($property) {
                if ($propertyName -eq "MacAddress") {
                    Add-DiagnosticsValue -List $gatewayMacs -Value ([string]$property.Value)
                } else {
                    Add-DiagnosticsValue -List $adapterNames -Value ([string]$property.Value)
                }
            }
        }
    }

    foreach ($path in @($ConfigPath, $ProfilesPath, $LogsPath)) {
        Add-DiagnosticsValue -List $localPaths -Value $path
    }

    return [pscustomobject]@{
        ProxyServers = @($proxyServers)
        SSIDs = @($ssids)
        GatewayMacs = @($gatewayMacs)
        LocalPaths = @($localPaths | Sort-Object Length -Descending)
        AdapterNames = @($adapterNames | Sort-Object Length -Descending)
    }
}

function ConvertTo-DiagnosticsRedactedText {
    param(
        [AllowEmptyString()][string]$Text,
        $Values,
        [System.Collections.IDictionary]$Report,
        [bool]$PrivacyMode = $true
    )

    $result = [string]$Text
    if (-not $PrivacyMode) { return $result }

    $webhookPattern = 'https://(?:discord(?:app)?\.com)/api/webhooks/\d+/[A-Za-z0-9._-]+'
    $webhookMatches = [regex]::Matches($result, $webhookPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($webhookMatches.Count -gt 0) {
        Add-DiagnosticsRedactionCount -Report $Report -Category "WebhookUrls" -Count $webhookMatches.Count
        $result = [regex]::Replace($result, $webhookPattern, 'https://discord.com/api/webhooks/[redacted]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    foreach ($value in @($Values.ProxyServers)) {
        $pattern = [regex]::Escape([string]$value)
        $matches = [regex]::Matches($result, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($matches.Count -gt 0) {
            Add-DiagnosticsRedactionCount -Report $Report -Category "ProxyServers" -Count $matches.Count
            $result = [regex]::Replace($result, $pattern, '[redacted-proxy]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }

    $uncPattern = '\\\\[^\\\s"'']+\\[^\s"'']+'
    $uncMatches = [regex]::Matches($result, $uncPattern)
    if ($uncMatches.Count -gt 0) {
        Add-DiagnosticsRedactionCount -Report $Report -Category "MappedDrivePaths" -Count $uncMatches.Count
        $result = [regex]::Replace($result, $uncPattern, '\\[redacted-host]\[redacted-share]')
    }

    foreach ($value in @($Values.SSIDs)) {
        $pattern = [regex]::Escape([string]$value)
        $matches = [regex]::Matches($result, $pattern)
        if ($matches.Count -gt 0) {
            Add-DiagnosticsRedactionCount -Report $Report -Category "SSIDs" -Count $matches.Count
            $result = [regex]::Replace($result, $pattern, '[redacted-ssid]')
        }
    }

    foreach ($value in @($Values.GatewayMacs)) {
        $pattern = [regex]::Escape([string]$value)
        $matches = [regex]::Matches($result, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($matches.Count -gt 0) {
            Add-DiagnosticsRedactionCount -Report $Report -Category "GatewayMacs" -Count $matches.Count
            $result = [regex]::Replace($result, $pattern, '[redacted-mac]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }

    $macPattern = '\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b|\b[0-9a-f]{12}\b'
    $macMatches = [regex]::Matches($result, $macPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($macMatches.Count -gt 0) {
        Add-DiagnosticsRedactionCount -Report $Report -Category "GatewayMacs" -Count $macMatches.Count
        $result = [regex]::Replace($result, $macPattern, '[redacted-mac]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    foreach ($value in @($Values.LocalPaths)) {
        $pattern = [regex]::Escape([string]$value)
        $matches = [regex]::Matches($result, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($matches.Count -gt 0) {
            Add-DiagnosticsRedactionCount -Report $Report -Category "LocalPaths" -Count $matches.Count
            $result = [regex]::Replace($result, $pattern, '[redacted-path]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }

    foreach ($value in @($Values.AdapterNames)) {
        $pattern = [regex]::Escape([string]$value)
        $matches = [regex]::Matches($result, $pattern)
        if ($matches.Count -gt 0) {
            Add-DiagnosticsRedactionCount -Report $Report -Category "AdapterNames" -Count $matches.Count
            $result = [regex]::Replace($result, $pattern, '[redacted-adapter]')
        }
    }

    return $result
}

function Write-DiagnosticsRedactedTextFile {
    param(
        [string]$Path,
        [AllowEmptyString()][string]$Text,
        $Values,
        [System.Collections.IDictionary]$Report,
        [string]$Kind,
        [string]$ReportPath = "",
        [bool]$PrivacyMode = $true
    )

    $redacted = ConvertTo-DiagnosticsRedactedText -Text $Text -Values $Values -Report $Report -PrivacyMode:$PrivacyMode
    Set-Content -LiteralPath $Path -Value $redacted -Encoding UTF8
    $reportedPath = if ([string]::IsNullOrWhiteSpace($ReportPath)) { [System.IO.Path]::GetFileName($Path) } else { $ReportPath }
    Add-DiagnosticsRedactionFile -Report $Report -Path $reportedPath -Kind $Kind -Redacted:$PrivacyMode
}

function New-DiagnosticsExportManifest {
    param(
        [string]$DestinationPath,
        [bool]$PrivacyMode,
        [object[]]$LogFiles = @(),
        [object[]]$ProfileFiles = @()
    )

    return [ordered]@{
        Version = $script:AppVersion
        GeneratedAt = (Get-Date).ToString("o")
        Destination = [System.IO.Path]::GetFileName($DestinationPath)
        PrivacyMode = [bool]$PrivacyMode
        Includes = @(
            [pscustomobject]@{ Name = "adapter-state.json"; Count = 1; Redacted = [bool]$PrivacyMode },
            [pscustomobject]@{ Name = "Logs"; Count = @($LogFiles).Count; Redacted = [bool]$PrivacyMode },
            [pscustomobject]@{ Name = "Profiles"; Count = @($ProfileFiles).Count; Redacted = [bool]$PrivacyMode },
            [pscustomobject]@{ Name = "redaction-report.json"; Count = 1; Redacted = $false }
        )
        RedactionCategories = @("WebhookUrls", "ProxyServers", "MappedDrivePaths", "SSIDs", "GatewayMacs", "LocalPaths", "AdapterNames")
    }
}

function Format-DiagnosticsExportPreview {
    param($Manifest)

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Diagnostics export preview") | Out-Null
    $sb.AppendLine("==========================") | Out-Null
    $sb.AppendLine("Destination: $($Manifest.Destination)") | Out-Null
    $sb.AppendLine("Privacy mode: $($Manifest.PrivacyMode)") | Out-Null
    foreach ($item in @($Manifest.Includes)) {
        $sb.AppendLine(("{0}: {1} item(s), redacted={2}" -f $item.Name, $item.Count, $item.Redacted)) | Out-Null
    }
    return $sb.ToString()
}

function Export-DiagnosticsBundle {
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "Zip Files (*.zip)|*.zip"
    $saveDialog.FileName = "NetForge_Diagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    $saveDialog.Title = "Export Diagnostics"

    if ($saveDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $tempRoot = Join-Path $env:TEMP "NetForgeDiag-$([guid]::NewGuid().ToString('N'))"
    try {
        Write-OperationLog -Action "Export diagnostics" -Result "Started" -Detail $saveDialog.FileName
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

        $logsTarget = Join-Path $tempRoot "Logs"
        $profilesTarget = Join-Path $tempRoot "Profiles"
        New-Item -Path $logsTarget -ItemType Directory -Force | Out-Null
        New-Item -Path $profilesTarget -ItemType Directory -Force | Out-Null

        $privacyMode = $true
        if ($script:chkDiagnosticsPrivacyMode) {
            $privacyMode = [bool]$script:chkDiagnosticsPrivacyMode.IsChecked
        }

        $adapter = Get-SelectedAdapter
        $profiles = @(Get-Profiles)
        $logFiles = @()
        $profileFiles = @()
        if (Test-Path -LiteralPath $script:LogsPath) {
            $logFiles = @(Get-ChildItem -LiteralPath $script:LogsPath -File -ErrorAction SilentlyContinue)
        }
        if (Test-Path -LiteralPath $script:ProfilesPath) {
            $profileFiles = @(Get-ChildItem -LiteralPath $script:ProfilesPath -Filter "*.json" -File -ErrorAction SilentlyContinue)
        }

        $redactionValues = Get-DiagnosticsRedactionValues -Profiles $profiles -Adapter $adapter -ConfigPath $script:ConfigPath -ProfilesPath $script:ProfilesPath -LogsPath $script:LogsPath
        $redactionReport = New-DiagnosticsRedactionReport -PrivacyMode:$privacyMode
        $manifest = New-DiagnosticsExportManifest -DestinationPath $saveDialog.FileName -PrivacyMode:$privacyMode -LogFiles $logFiles -ProfileFiles $profileFiles
        $previewText = Format-DiagnosticsExportPreview -Manifest $manifest
        if ($script:txtDiagOutput) {
            $script:txtDiagOutput.Text = $previewText
        }
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempRoot "preview-manifest.json") -Encoding UTF8

        foreach ($logFile in $logFiles) {
            $targetPath = Join-Path $logsTarget $logFile.Name
            $text = Get-Content -Raw -LiteralPath $logFile.FullName -ErrorAction SilentlyContinue
            Write-DiagnosticsRedactedTextFile -Path $targetPath -Text $text -Values $redactionValues -Report $redactionReport -Kind "Log" -ReportPath ("Logs/{0}" -f $logFile.Name) -PrivacyMode:$privacyMode
        }
        foreach ($profileFile in $profileFiles) {
            $targetPath = Join-Path $profilesTarget $profileFile.Name
            $text = Get-Content -Raw -LiteralPath $profileFile.FullName -ErrorAction SilentlyContinue
            Write-DiagnosticsRedactedTextFile -Path $targetPath -Text $text -Values $redactionValues -Report $redactionReport -Kind "Profile" -ReportPath ("Profiles/{0}" -f $profileFile.Name) -PrivacyMode:$privacyMode
        }

        $adapterSnapshot = $null
        if ($adapter) {
            try {
                $adapterSnapshot = Get-AdapterNetworkSnapshot -Adapter $adapter -Reason "Diagnostics export"
            } catch {
                $adapterSnapshot = [pscustomobject]@{ Error = $_.Exception.Message }
            }
        }

        $state = [ordered]@{
            ExportedAt = (Get-Date).ToString("o")
            Version = $script:AppVersion
            ConfigPath = $script:ConfigPath
            ProfilesPath = $script:ProfilesPath
            LogsPath = $script:LogsPath
            SelectedAdapter = if ($adapter) { $adapter | Select-Object Name, InterfaceDescription, ifIndex, Status, MacAddress, LinkSpeed } else { $null }
            AdapterSnapshot = $adapterSnapshot
            Profiles = $profiles
            RecentProfileLoadWarnings = $script:LastProfileLoadWarnings
        }

        $stateJson = $state | ConvertTo-Json -Depth 10
        Write-DiagnosticsRedactedTextFile -Path (Join-Path $tempRoot "adapter-state.json") -Text $stateJson -Values $redactionValues -Report $redactionReport -Kind "State" -ReportPath "adapter-state.json" -PrivacyMode:$privacyMode
        $redactionReport["GeneratedAt"] = (Get-Date).ToString("o")
        $redactionReport["Version"] = $script:AppVersion
        $redactionReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempRoot "redaction-report.json") -Encoding UTF8

        if (Test-Path -LiteralPath $saveDialog.FileName) {
            Remove-Item -LiteralPath $saveDialog.FileName -Force
        }
        Compress-Archive -Path (Join-Path $tempRoot "*") -DestinationPath $saveDialog.FileName -Force

        Write-OperationLog -Action "Export diagnostics" -Result "Succeeded" -Detail "Path=$($saveDialog.FileName); PrivacyMode=$privacyMode; Logs=$($logFiles.Count); Profiles=$($profileFiles.Count)"
        Update-Status "Diagnostics exported to $($saveDialog.FileName)" -Type Success
    } catch {
        Write-OperationLog -Action "Export diagnostics" -Result "Failed" -Detail $_.Exception.Message
        Update-Status "Diagnostics export failed: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Diagnostics export failed:`n$($_.Exception.Message)" -Title "Export Failed" -Icon Error
    } finally {
        if ((Test-Path -LiteralPath $tempRoot) -and $tempRoot.StartsWith($env:TEMP, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Export-AllConfiguration {
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "JSON Files (*.json)|*.json"
    $saveDialog.FileName = "NetForge_Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $saveDialog.Title = "Export Configuration"

    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $export = @{
                ExportDate = (Get-Date).ToString("o")
                Version = $script:AppVersion
                Profiles = Get-Profiles
                DnsPresets = $script:DnsPresets
            }

            $export | ConvertTo-Json -Depth 10 | Set-Content -Path $saveDialog.FileName -Encoding UTF8
            Update-Status "Configuration exported to $($saveDialog.FileName)" -Type Success
        } catch {
            Update-Status "Export failed: $($_.Exception.Message)" -Type Error
        }
    }
}

function Import-Configuration {
    $openDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openDialog.Filter = "Supported Imports (*.json;*.xml)|*.json;*.xml|JSON Files (*.json)|*.json|WLAN Profile XML (*.xml)|*.xml"
    $openDialog.Title = "Import Configuration"

    if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $importRecords = Get-ProfileImportRecords -Path $openDialog.FileName
            $incomingProfiles = @($importRecords.Profiles)

            $existingNames = @{}
            if (Test-Path -LiteralPath $script:ProfilesPath) {
                Get-ChildItem -Path $script:ProfilesPath -Filter "*.json" | ForEach-Object {
                    $existingNames[$_.Name.ToLowerInvariant()] = $true
                }
            }

            $seenNames = @{}
            $accepted = @()
            $rejected = @()
            $index = 0

            foreach ($incomingProfile in $incomingProfiles) {
                $index++
                $validation = Get-ProfileValidationResult -ProfileData $incomingProfile
                if (-not $validation.IsValid) {
                    $rejected += "Row $index rejected: $($validation.Message)"
                    continue
                }

                $safeKey = $validation.SafeFileName.ToLowerInvariant()
                if ($seenNames.ContainsKey($safeKey)) {
                    $rejected += "Row $index '$($validation.Profile.Name)' rejected: duplicate name inside import."
                    continue
                }
                if ($existingNames.ContainsKey($safeKey)) {
                    $rejected += "Row $index '$($validation.Profile.Name)' rejected: profile already exists."
                    continue
                }

                $seenNames[$safeKey] = $true
                $accepted += $validation
            }

            $logLines = @(
                "Import dry-run: $($accepted.Count) accepted, $($rejected.Count) rejected from $($importRecords.SourcePath) ($($importRecords.SourceKind))."
            )
            foreach ($item in $accepted) {
                $logLines += "Accepted: $($item.Profile.Name) -> $($item.SafeFileName)"
            }
            if ($rejected.Count -gt 0) {
                $logLines += "Rejected:"
                $logLines += $rejected
            }

            if ($accepted.Count -eq 0) {
                Write-ProfileImportLog -Lines $logLines
                Update-Status "Import dry-run rejected all profiles; see diagnostics output" -Type Warning
                return
            }

            foreach ($item in $accepted) {
                $filePath = Join-Path $script:ProfilesPath $item.SafeFileName
                Write-ProfileFileAtomic -ProfileData $item.Profile -FilePath $filePath
            }

            $logLines += "Imported $($accepted.Count) profile(s)."
            Write-ProfileImportLog -Lines $logLines
            Refresh-ProfileList
            if ($rejected.Count -gt 0) {
                Update-Status "Imported $($accepted.Count) profile(s), rejected $($rejected.Count); see diagnostics output" -Type Warning
            } else {
                Update-Status "Imported $($accepted.Count) profile(s) successfully" -Type Success
            }
        } catch {
            Update-Status "Import failed: $($_.Exception.Message)" -Type Error
            Write-ProfileImportLog -Lines @("Import failed:", $_.Exception.Message)
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($ApplyProfile)) {
    Invoke-CliApplyProfile -ProfileName $ApplyProfile -AdapterSelector $AdapterName -Quiet:$Silent
}

# ============================================================================
# EVENT HANDLERS
# ============================================================================
$cmbUiTheme.Add_SelectionChanged({
    Save-UiThemeSelection
})

$chkCompactMode.Add_Checked({
    Save-CompactModeSelection
})

$chkCompactMode.Add_Unchecked({
    Save-CompactModeSelection
})

$lstAdapters.Add_SelectionChanged({
    Update-AdapterDisplay
    Refresh-StaticRouteList
    Refresh-AppRoutingInterfaceList
})

$chkAdvancedAdapters.Add_Checked({
    $script:ShowAdvancedAdapters = $true
    Refresh-AdapterList
})

$chkAdvancedAdapters.Add_Unchecked({
    $script:ShowAdvancedAdapters = $false
    Refresh-AdapterList
})

$rbDHCP.Add_Checked({
    $script:pnlStaticIP.IsEnabled = $false
    $script:pnlStaticIP.Opacity = 0.6
})

$rbStatic.Add_Checked({
    $script:pnlStaticIP.IsEnabled = $true
    $script:pnlStaticIP.Opacity = 1.0
})

$chkConfigureIPv6Address.Add_Checked({ Set-IPv6ConfigurationControlState })
$chkConfigureIPv6Address.Add_Unchecked({ Set-IPv6ConfigurationControlState })

$rbDnsDHCP.Add_Checked({
    $script:pnlCustomDns.IsEnabled = $false
    $script:pnlCustomDns.Opacity = 0.6
    Show-DohConfiguration
    Show-DotConfiguration
})

$rbDnsPreset.Add_Checked({
    $script:pnlCustomDns.IsEnabled = $false
    $script:pnlCustomDns.Opacity = 0.6
    Show-DohConfiguration
    Show-DotConfiguration
})

$rbDnsCustom.Add_Checked({
    $script:pnlCustomDns.IsEnabled = $true
    $script:pnlCustomDns.Opacity = 1.0
    Show-DohConfiguration
    Show-DotConfiguration
})

$lstDnsPresets.Add_SelectionChanged({
    Update-SelectedDnsDisplay
})

$lstWifiNetworks.Add_SelectionChanged({
    Show-WifiSelection
})

$lstProfiles.Add_SelectionChanged({
    Load-ProfileToEditor
})

$txtDnsSearch.Add_TextChanged({
    $category = if ($script:cmbDnsCategory.SelectedItem) { $script:cmbDnsCategory.SelectedItem.Content } else { "All Categories" }
    Refresh-DnsPresets -Filter $script:txtDnsSearch.Text -Category $category
})

$cmbDnsCategory.Add_SelectionChanged({
    $category = if ($script:cmbDnsCategory.SelectedItem) { $script:cmbDnsCategory.SelectedItem.Content } else { "All Categories" }
    Refresh-DnsPresets -Filter $script:txtDnsSearch.Text -Category $category
})

$txtDnsPrimary.Add_TextChanged({ Show-DohConfiguration; Show-DotConfiguration })
$txtDnsSecondary.Add_TextChanged({ Show-DohConfiguration; Show-DotConfiguration })
$chkIPv6Dns.Add_Checked({ Show-DohConfiguration; Show-DotConfiguration })
$chkIPv6Dns.Add_Unchecked({ Show-DohConfiguration; Show-DotConfiguration })

# Button event handlers
$btnRefresh.Add_Click({ Refresh-AdapterList })
$btnExport.Add_Click({ Export-AllConfiguration })
$btnImport.Add_Click({ Import-Configuration })
$btnEnableAdapter.Add_Click({ Enable-SelectedAdapter })
$btnDisableAdapter.Add_Click({ Disable-SelectedAdapter })
$btnGenerateMac.Add_Click({ Invoke-GenerateMacAddress })
$btnApplyMac.Add_Click({ Invoke-MacOverride })
$btnRevertMac.Add_Click({ Invoke-MacRevert })
$btnApplyMetric.Add_Click({ Invoke-ApplyInterfaceMetric })
$btnAutoMetric.Add_Click({ Invoke-AutomaticInterfaceMetric })
$btnIPv4FirstMetric.Add_Click({ Invoke-AdapterBindingPriority -Mode "IPv4First" })
$btnIPv6FirstMetric.Add_Click({ Invoke-AdapterBindingPriority -Mode "IPv6First" })
$btnApplyIP.Add_Click({ Apply-IPConfiguration })
$btnApplyDns.Add_Click({ Apply-DNSConfiguration })
$btnRegisterDoh.Add_Click({ Register-DohEncryption })
$btnRegisterDot.Add_Click({ Register-DotEncryption })
$btnTestEncryptedDns.Add_Click({ Invoke-EncryptedDnsHealthTest })
$btnValidateDoqProxy.Add_Click({ Invoke-ValidateDoqProxy })
$btnStartDoqProxy.Add_Click({ Invoke-StartDoqProxy })
$btnStopDoqProxy.Add_Click({ Invoke-StopDoqProxy })
$btnApplyDoqLocalDns.Add_Click({ Invoke-ApplyDoqLocalResolver })
$btnApplyNextDnsEndpoints.Add_Click({ Invoke-ApplyNextDnsEndpoint })
$btnWifiRefresh.Add_Click({ Invoke-WifiNetworkScan })
$btnWifiConnect.Add_Click({ Invoke-WifiConnect })
$btnWifiDisconnect.Add_Click({ Invoke-WifiDisconnect })
$btnNewProfile.Add_Click({
    $script:txtProfileName.Text = "New Profile"
    $script:txtProfileDesc.Text = ""
    $script:chkProfileAutoApply.IsChecked = $false
    $script:txtProfileMatchSsid.Text = ""
    $script:txtProfileGatewayMac.Text = ""
    $script:chkProfileSchedule.IsChecked = $false
    $script:txtProfileScheduleTime.Text = "08:00"
    $script:txtProfileScheduleDays.Text = "Every day"
    $script:chkProfileDHCP.IsChecked = $true
    $script:txtProfileIP.Text = ""
    $script:txtProfileSubnet.Text = "255.255.255.0"
    $script:txtProfileGateway.Text = ""
    $script:txtProfilePrefix.Text = "24"
    $script:chkProfileDnsDHCP.IsChecked = $true
    $script:txtProfileDns1.Text = ""
    $script:txtProfileDns2.Text = ""
    $script:chkProfileNetworkCategory.IsChecked = $false
    if ($script:cmbProfileNetworkCategory.Items.Count -gt 0) { $script:cmbProfileNetworkCategory.SelectedIndex = 0 }
    $script:chkProfileProxy.IsChecked = $false
    $script:chkProfileProxyEnabled.IsChecked = $false
    $script:txtProfileProxyServer.Text = ""
    $script:txtProfileProxyBypass.Text = ""
    $script:chkProfilePrinter.IsChecked = $false
    $script:txtProfilePrinterName.Text = ""
    $script:chkProfileMappedDrives.IsChecked = $false
    $script:txtProfileMappedDrives.Text = ""
})
$btnDeleteProfile.Add_Click({ Delete-Profile })
$btnExportProfileQr.Add_Click({ Export-SelectedProfileQrCode })
$btnImportProfileQr.Add_Click({ Import-ProfileQrCode })
$btnChooseProfileStore.Add_Click({ Invoke-ChooseProfileStore })
$btnUseOneDriveProfileStore.Add_Click({ Invoke-OneDriveProfileStore })
$btnRevertProfileStore.Add_Click({ Invoke-RevertProfileStore })
$btnProfileStoreHealth.Add_Click({
    Update-ProfileStoreDisplay
    Update-Status "Profile storage health refreshed"
})
$btnSaveProfile.Add_Click({ Save-Profile })
$btnProfileDiff.Add_Click({ Show-ProfileDiff })
$btnApplyProfile.Add_Click({ Apply-Profile })
$btnCaptureProfileMatch.Add_Click({ Invoke-CaptureProfileMatch })
$btnRefreshAutoApply.Add_Click({ Invoke-RefreshAutoApplyInspector })
$btnFlushDns.Add_Click({ Invoke-FlushDns })
$btnReleaseIP.Add_Click({ Invoke-ReleaseIP })
$btnRenewIP.Add_Click({ Invoke-RenewIP })
$btnRestoreNetworkState.Add_Click({ Invoke-RestoreLastNetworkState })
$btnExportDiagnostics.Add_Click({ Export-DiagnosticsBundle })
$btnLaunchRdpProfile.Add_Click({ Invoke-RdpProfileLaunch })
$btnRevertRdpProfile.Add_Click({ [void](Invoke-RdpProfileRevert -Reason "manual") })
$btnBrowseAppRoutingProgram.Add_Click({ Browse-AppRoutingProgram })
$btnApplyAppRouting.Add_Click({ Apply-AppRoutingPolicy })
$btnRemoveAppRouting.Add_Click({ Remove-SelectedAppRoutingPolicy })
$btnRefreshAppRouting.Add_Click({
    Refresh-AppRoutingInterfaceList
    [void](Invoke-AppRoutingPolicyRepair -Trigger "ManualRefresh")
    Refresh-AppRoutingRuleList
})
$btnResetWinsock.Add_Click({ Invoke-ResetWinsock })
$btnResetTCP.Add_Click({ Invoke-ResetTCP })
$btnNetworkReset.Add_Click({ Invoke-NetworkReset })
$btnPing.Add_Click({ Invoke-Ping })
$btnTraceroute.Add_Click({ Invoke-Traceroute })
$btnMtrTrace.Add_Click({ Toggle-MtrTrace })
$btnPortScan.Add_Click({ Invoke-PortScan })
$btnReachabilityWizard.Add_Click({ Invoke-ReachabilityWizard })
$btnPacketCapture.Add_Click({ Toggle-PacketCapture })
$btnCableDiagnostics.Add_Click({ Invoke-CableDiagnostics })
$btnNslookup.Add_Click({ Invoke-Nslookup })
$btnAddStaticRoute.Add_Click({ Add-StaticRoute })
$btnRemoveStaticRoute.Add_Click({ Remove-SelectedStaticRoute })
$btnRefreshStaticRoutes.Add_Click({ Refresh-StaticRouteList })
$btnHostsAddEntry.Add_Click({ Add-HostsEntry })
$btnHostsToggleGroup.Add_Click({ Toggle-SelectedHostsGroup })
$btnHostsRemoveGroup.Add_Click({ Remove-SelectedHostsGroup })
$btnHostsRefresh.Add_Click({ Refresh-HostsGroups })
$btnHostsApply.Add_Click({ Save-HostsGroups })

# Diagnostics button handlers
$btnDiagPing.Add_Click({ Invoke-DiagPingTest })
$btnContinuousPing.Add_Click({ Toggle-ContinuousPing })
$btnLatencyHistogram.Add_Click({ Invoke-LatencyHistogram })
$btnSpeedTest.Add_Click({ Invoke-SpeedTest })
$btnDnsLookup.Add_Click({ Invoke-DnsLookup })
$btnSaveEndpointPolicy.Add_Click({ Save-EndpointPolicySettings })
$btnSaveDiscordWebhook.Add_Click({ Save-DiscordWebhookSettings })
$btnCheckRelease.Add_Click({ Invoke-CheckRelease })
$btnSaveLocale.Add_Click({ Save-LocaleSelection })
$btnRefreshCapabilities.Add_Click({
    $script:txtCapabilityMatrix.Text = "Scanning capabilities..."
    $checks = Get-CapabilityMatrix
    $report = Format-CapabilityMatrixReport -Checks $checks
    $script:txtCapabilityMatrix.Text = $report
    Write-OperationLog -Action "CapabilityMatrix" -Result "Info" -Detail "$($checks.Count) checks, $(@($checks | Where-Object { -not $_.Available }).Count) unavailable"
    Update-Status "Capability matrix scanned" -Type Success
})
$script:txtReleaseCheckVersion.Text = "Current version: $script:AppVersion"

# ============================================================================
# CONNECTION STATUS TIMER (auto-refresh every 30 seconds)
# ============================================================================
$script:ConnStatusTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ConnStatusTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:ConnStatusTimer.Add_Tick({
    Update-ConnectionStatus
})
$script:ConnStatusTimer.Start()

$script:AutoProfileTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:AutoProfileTimer.Interval = [TimeSpan]::FromMinutes(5)
$script:AutoProfileTimer.Add_Tick({
    Invoke-AutoApplyProfile -Trigger "FallbackTimer"
})
$script:AutoProfileTimer.Start()
Register-NetworkChangeAutoApply

$script:ScheduleProfileTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ScheduleProfileTimer.Interval = [TimeSpan]::FromMinutes(1)
$script:ScheduleProfileTimer.Add_Tick({
    Invoke-ScheduledProfileSwitch -Trigger "ScheduleTimer"
})
$script:ScheduleProfileTimer.Start()

# ============================================================================
# CLEANUP ON WINDOW CLOSE
# ============================================================================
$window.Add_Closing({
    $script:ContinuousPingRunning = $false
    if ($script:ContinuousPingTimer) {
        $script:ContinuousPingTimer.Stop()
    }
    if ($script:MtrRunning) {
        Stop-MtrTrace
    }
    if ($script:PortScanPowerShell) {
        try {
            $script:PortScanPowerShell.Stop()
        } catch {
            Write-OperationLog -Action "Port scan stop" -Result "Warning" -Detail $_.Exception.Message
        }
    }
    if ($script:ReachabilityWizardPowerShell) {
        try {
            $script:ReachabilityWizardPowerShell.Stop()
        } catch {
            Write-OperationLog -Action "Reachability wizard stop" -Result "Warning" -Detail $_.Exception.Message
        }
    }
    if ($script:PacketCaptureRunning) {
        Stop-PacketCapture
    }
    if ($script:EncryptedDnsHealthTimer) {
        $script:EncryptedDnsHealthTimer.Stop()
    }
    if ($script:EncryptedDnsHealthJob) {
        Stop-Job $script:EncryptedDnsHealthJob -ErrorAction SilentlyContinue
        Remove-Job $script:EncryptedDnsHealthJob -Force -ErrorAction SilentlyContinue
    }
    if ($script:DoqProxyProcess -and -not $script:DoqProxyProcess.HasExited) {
        Stop-Process -Id $script:DoqProxyProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($script:AutoProfileTimer) {
        $script:AutoProfileTimer.Stop()
    }
    if ($script:ScheduleProfileTimer) {
        $script:ScheduleProfileTimer.Stop()
    }
    if ($script:RdpRestoreSnapshot) {
        [void](Invoke-RdpProfileRevert -Reason "app close")
    }
    Stop-RdpMonitor
    Unregister-NetworkChangeAutoApply
    Remove-SystemTray
    $script:ConnStatusTimer.Stop()
})

# ============================================================================
# INITIALIZATION
# ============================================================================
Refresh-AdapterList
Initialize-DnsPresetCatalog
Refresh-DnsPresets
Show-DohConfiguration
Show-DotConfiguration
Refresh-ProfileList
Update-ProfileStoreDisplay
Initialize-AccessibilityMetadata
Apply-Localization
Initialize-ThemeSelector
Initialize-CompactModeControl
Initialize-SystemTray
Initialize-EndpointPolicyControls
Initialize-LocaleSelector
Initialize-DiscordWebhookControls
Initialize-AppRoutingControls
Show-RestoreSnapshotButtonState
Update-ConnectionStatus
Update-PublicIP
Show-WifiActionState
Update-RdpProfileControls
Invoke-WifiNetworkScan
Invoke-AutoApplyProfile -Trigger "Startup"
Invoke-ScheduledProfileSwitch -Trigger "Startup"

# Select first adapter if available
if ($lstAdapters.Items.Count -gt 0) {
    $lstAdapters.SelectedIndex = 0
}

# ============================================================================
# SHOW WINDOW
# ============================================================================
$window.ShowDialog() | Out-Null
