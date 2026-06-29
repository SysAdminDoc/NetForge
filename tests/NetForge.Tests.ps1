BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:NetForgePath = Join-Path $script:RepoRoot 'NetForge.ps1'

    function Import-NetForgeFunction {
        param([string[]]$Name)

        $source = Get-Content -Raw $script:NetForgePath
        $ast = [scriptblock]::Create($source).Ast

        foreach ($functionName in $Name) {
            $functionAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
            }, $true)

            if ($null -eq $functionAst) {
                throw "Function '$functionName' was not found."
            }

            Invoke-Expression "function global:$functionName $($functionAst.Body.Extent.Text)"
        }
    }
}

Describe 'NetForge script' {
    It 'parses without syntax errors' {
        $parseErrors = $null
        [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $script:NetForgePath), [ref]$parseErrors) | Out-Null
        $parseErrors.Count | Should -Be 0
    }
}

Describe 'Profile validation' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-ValidIPv4Address',
            'Test-ValidIPv4PrefixLength',
            'ConvertTo-CleanMacAddress',
            'Test-ValidMacAddress',
            'Get-ProfileProperty',
            'ConvertTo-ProfileBoolean',
            'Get-WlanXmlElementText',
            'ConvertFrom-WlanSsidHex',
            'ConvertFrom-WlanProfileXmlDocument',
            'Get-ProfileImportRecords',
            'Get-ProfileScheduleDayAliases',
            'Normalize-ProfileScheduleDays',
            'Normalize-ProfileScheduleTime',
            'ConvertTo-ProfileScheduleDaysText',
            'Get-ProfileScheduleDescription',
            'Test-ProfileScheduleDue',
            'Get-SafeProfileFileName',
            'ConvertFrom-MappedDriveText',
            'ConvertTo-MappedDriveText',
            'Normalize-MappedDriveList',
            'Get-ProfileValidationResult',
            'Write-ProfileFileAtomic'
        )
        $script:ProfileSchemaVersion = 3
    }

    It 'normalizes a legacy static profile to the current schema version' {
        $profile = [pscustomobject]@{
            Name = 'Clinic LAN'
            Description = 'Static clinic profile'
            AutoApply = 'true'
            MatchSSID = 'Clinic'
            MatchGatewayMac = '00-11-22-33-44-55'
            UseDHCP = 'false'
            IPAddress = '192.168.50.20'
            SubnetMask = '255.255.255.0'
            Gateway = '192.168.50.1'
            PrefixLength = '24'
            UseDHCPForDNS = 'false'
            PrimaryDNS = '1.1.1.1'
            SecondaryDNS = '1.0.0.1'
        }

        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeTrue
        $result.Profile.SchemaVersion | Should -Be 3
        $result.Profile.AutoApply | Should -BeTrue
        $result.Profile.MatchGatewayMac | Should -Be '001122334455'
        $result.Profile.ConfigureProxy | Should -BeFalse
        $result.Profile.MappedDrives.Count | Should -Be 0
        $result.SafeFileName | Should -Be 'Clinic_LAN.json'
    }

    It 'normalizes optional profile environment actions' {
        $profile = [pscustomobject]@{
            Name = 'Clinic Environment'
            UseDHCP = $true
            UseDHCPForDNS = $true
            ConfigureNetworkCategory = $true
            NetworkCategory = 'Private'
            ConfigureProxy = $true
            ProxyEnabled = $true
            ProxyServer = 'proxy.clinic.local:8080'
            ProxyBypass = '<local>'
            ConfigureDefaultPrinter = $true
            DefaultPrinterName = 'Front Desk'
            ConfigureMappedDrives = $true
            MappedDrives = "Z: \\fileserver\share"
        }

        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeTrue
        $result.Profile.ConfigureNetworkCategory | Should -BeTrue
        $result.Profile.NetworkCategory | Should -Be 'Private'
        $result.Profile.ProxyServer | Should -Be 'proxy.clinic.local:8080'
        $result.Profile.DefaultPrinterName | Should -Be 'Front Desk'
        $result.Profile.MappedDrives.Count | Should -Be 1
        $result.Profile.MappedDrives[0].DriveLetter | Should -Be 'Z'
        $result.Profile.MappedDrives[0].RemotePath | Should -Be '\\fileserver\share'
    }

    It 'normalizes scheduled profile switches' {
        $profile = [pscustomobject]@{
            Name = 'Morning Work'
            UseDHCP = $true
            UseDHCPForDNS = $true
            ScheduleEnabled = $true
            ScheduleTime = '8:05'
            ScheduleDays = 'weekdays'
        }

        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeTrue
        $result.Profile.SchemaVersion | Should -Be 3
        $result.Profile.ScheduleEnabled | Should -BeTrue
        $result.Profile.ScheduleTime | Should -Be '08:05'
        $result.Profile.ScheduleDays | Should -Contain 'Monday'
        $result.Profile.ScheduleDays | Should -Contain 'Friday'
        $result.Profile.ScheduleDays | Should -Not -Contain 'Saturday'
        (Normalize-ProfileScheduleDays -Days 'Every day').Days.Count | Should -Be 7
        Get-ProfileScheduleDescription -ProfileData $result.Profile | Should -Be '08:05 Weekdays'
        Test-ProfileScheduleDue -ProfileData $result.Profile -Now ([datetime]'2026-06-29T08:05:00') | Should -BeTrue
        Test-ProfileScheduleDue -ProfileData $result.Profile -Now ([datetime]'2026-06-29T08:06:00') | Should -BeFalse
        Test-ProfileScheduleDue -ProfileData $result.Profile -Now ([datetime]'2026-06-28T08:05:00') | Should -BeFalse
    }

    It 'rejects invalid profile data before writing' {
        $profile = [pscustomobject]@{
            Name = 'Bad'
            UseDHCP = $false
            IPAddress = 'not-an-ip'
            PrefixLength = '99'
            UseDHCPForDNS = $false
            PrimaryDNS = 'also-bad'
        }

        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'valid IPv4 address'
        $result.Message | Should -Match 'primary DNS'
    }

    It 'rejects invalid environment profile actions before writing' {
        $profile = [pscustomobject]@{
            Name = 'Bad Environment'
            UseDHCP = $true
            UseDHCPForDNS = $true
            ConfigureNetworkCategory = $true
            NetworkCategory = 'Domain'
            ConfigureProxy = $true
            ProxyEnabled = $true
            ProxyServer = ''
            ConfigureDefaultPrinter = $true
            DefaultPrinterName = ''
            ConfigureMappedDrives = $true
            MappedDrives = 'Z: not-a-unc-path'
        }

        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'Network category'
        $result.Message | Should -Match 'proxy server'
        $result.Message | Should -Match 'printer name'
        $result.Message | Should -Match 'Mapped drive'
    }

    It 'rejects invalid scheduled profile switches before writing' {
        $profile = [pscustomobject]@{
            Name = 'Bad Schedule'
            UseDHCP = $true
            UseDHCPForDNS = $true
            ScheduleEnabled = $true
            ScheduleTime = '25:61'
            ScheduleDays = 'Funday'
        }

        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'valid 24-hour'
        $result.Message | Should -Match 'Unknown schedule day'
    }

    It 'round-trips mapped drive text' {
        $drives = ConvertFrom-MappedDriveText -Text "Y: \\server\apps`r`nZ:=\\server\data"
        $text = ConvertTo-MappedDriveText -MappedDrives $drives

        $drives.Count | Should -Be 2
        $drives[0].DriveLetter | Should -Be 'Y'
        $text | Should -Match 'Y: \\\\server\\apps'
        $text | Should -Match 'Z: \\\\server\\data'
    }

    It 'converts WLAN XML exports into auto-apply profiles without storing secrets' {
        [xml]$wlanXml = @'
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>ClinicSecure</name>
  <SSIDConfig>
    <SSID>
      <hex>436C696E69632057694669</hex>
      <name>Clinic WiFi</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <protected>false</protected>
        <keyMaterial>not-imported</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
'@

        $profile = ConvertFrom-WlanProfileXmlDocument -Document $wlanXml -SourcePath 'Wi-Fi-ClinicSecure.xml'
        $result = Get-ProfileValidationResult -ProfileData $profile

        $result.IsValid | Should -BeTrue
        $result.Profile.Name | Should -Be 'Wi-Fi - ClinicSecure'
        $result.Profile.AutoApply | Should -BeTrue
        $result.Profile.MatchSSID | Should -Be 'Clinic WiFi'
        $result.Profile.UseDHCP | Should -BeTrue
        $result.Profile.UseDHCPForDNS | Should -BeTrue
        $result.Profile.Description | Should -Match 'Authentication: WPA2PSK'
        $result.Profile.Description | Should -Match 'Wireless key material is not stored'
        $result.Profile.Description | Should -Not -Match 'not-imported'
    }

    It 'reads WLAN XML import files and falls back to SSID hex names' {
        $xmlPath = Join-Path $TestDrive 'Wi-Fi-Guest.xml'
        @'
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>GuestNetwork</name>
  <SSIDConfig>
    <SSID>
      <hex>4775657374</hex>
    </SSID>
  </SSIDConfig>
</WLANProfile>
'@ | Set-Content -LiteralPath $xmlPath -Encoding UTF8

        $records = Get-ProfileImportRecords -Path $xmlPath
        $result = Get-ProfileValidationResult -ProfileData $records.Profiles[0]

        $records.SourceKind | Should -Be 'WLAN XML'
        $records.Profiles.Count | Should -Be 1
        $result.IsValid | Should -BeTrue
        $result.Profile.MatchSSID | Should -Be 'Guest'
    }

    It 'rejects XML files that are not WLAN profile exports' {
        [xml]$badXml = '<notAProfile />'

        { ConvertFrom-WlanProfileXmlDocument -Document $badXml } | Should -Throw '*WLAN profile XML*'
    }

    It 'writes profile JSON atomically' {
        $profile = [pscustomobject]@{
            Name = 'Atomic'
            UseDHCP = $true
            UseDHCPForDNS = $true
        }
        $result = Get-ProfileValidationResult -ProfileData $profile
        $filePath = Join-Path $TestDrive $result.SafeFileName

        Write-ProfileFileAtomic -ProfileData $result.Profile -FilePath $filePath
        $roundTrip = Get-Content -Raw $filePath | ConvertFrom-Json

        $roundTrip.Name | Should -Be 'Atomic'
        $roundTrip.SchemaVersion | Should -Be 3
    }
}

Describe 'Encrypted DNS endpoint helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-DohTemplate',
            'ConvertTo-DotHostValue',
            'Test-DotHost',
            'New-DnsQueryMessage',
            'Invoke-DnsUdpProbe',
            'Get-DnsConfigLeakResult',
            'Format-DnsLatencyRows',
            'Format-DnsHealthResultLines',
            'Test-NextDnsConfigId'
        )
    }

    It 'validates DoH templates' {
        Test-DohTemplate -Template 'https://dns.google/dns-query' | Should -BeTrue
        Test-DohTemplate -Template 'http://dns.google/dns-query' | Should -BeFalse
    }

    It 'normalizes DoT hosts' {
        ConvertTo-DotHostValue -HostName 'dns.google' | Should -Be 'dns.google:853'
        ConvertTo-DotHostValue -HostName 'dns.google:8853' | Should -Be 'dns.google:8853'
        ConvertTo-DotHostValue -HostName 'bad host name' | Should -Be ''
    }

    It 'validates NextDNS configuration IDs' {
        Test-NextDnsConfigId -ConfigId 'abc123' | Should -BeTrue
        Test-NextDnsConfigId -ConfigId '-abc123' | Should -BeFalse
        Test-NextDnsConfigId -ConfigId 'abc' | Should -BeFalse
    }

    It 'builds a DNS wire query for health probes' {
        $query = New-DnsQueryMessage -QueryName 'example.com'

        $query.Length | Should -BeGreaterThan 20
        $query[2] | Should -Be 1
        $query[3] | Should -Be 0
    }

    It 'rejects invalid UDP probe targets without network access' {
        $probe = Invoke-DnsUdpProbe -Server 'bad host' -Port 53

        $probe.Success | Should -BeFalse
        $probe.Message | Should -Match 'Not an IP address'
    }

    It 'detects adapter DNS outside the selected resolver target' {
        $result = Get-DnsConfigLeakResult -AdapterServers @('8.8.8.8', '1.1.1.1') -TargetServers @('1.1.1.1')

        $result.Success | Should -BeFalse
        $result.Message | Should -Match '8.8.8.8'
    }

    It 'formats health sections with latency state' {
        $lines = Format-DnsHealthResultLines -Results @(
            [pscustomobject]@{ Sort = 1; Section = 'Resolver latency'; Name = '1.1.1.1 UDP/53'; Success = $true; Message = 'UDP response 64 bytes'; LatencyMs = 12 },
            [pscustomobject]@{ Sort = 2; Section = 'Local proxy listener'; Name = '127.0.0.1:53'; Success = $false; Message = 'timed out'; LatencyMs = $null }
        )

        ($lines -join "`n") | Should -Match 'Resolver latency'
        ($lines -join "`n") | Should -Match 'OK 1.1.1.1 UDP/53'
        ($lines -join "`n") | Should -Match 'FAIL 127.0.0.1:53'
    }

    It 'formats resolver latency rows for apply previews' {
        $lines = Format-DnsLatencyRows -Rows @(
            [pscustomobject]@{ Resolver = '1.1.1.1'; Protocol = 'UDP/53'; Success = $true; LatencyMs = 10; Message = 'UDP response 64 bytes' }
        )

        ($lines -join "`n") | Should -Match '1.1.1.1'
        ($lines -join "`n") | Should -Match '10 ms'
    }
}

Describe 'Network signature keys' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Get-NetworkSignatureKey')
    }

    It 'builds a stable key from adapter, SSID, gateway, and gateway MAC' {
        $signature = [pscustomobject]@{
            Adapter = [pscustomobject]@{ ifIndex = 12 }
            SSID = 'Clinic'
            Gateway = '192.168.50.1'
            GatewayMac = '001122334455'
        }

        Get-NetworkSignatureKey -Signature $signature | Should -Be '12|Clinic|192.168.50.1|001122334455'
    }
}

Describe 'DNS provider catalog' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-ValidIPv4Address',
            'Test-DohTemplate',
            'ConvertTo-DotHostValue',
            'Test-DotHost',
            'Get-FileSha256',
            'Test-DnsCatalogIntegrity',
            'ConvertFrom-DnsProviderCatalog'
        )
    }

    It 'verifies the shipped catalog sidecar hash' {
        $catalogPath = Join-Path $script:RepoRoot 'dns-providers.json'
        $hashPath = "$catalogPath.sha256"

        $result = Test-DnsCatalogIntegrity -CatalogPath $catalogPath -HashPath $hashPath

        $result.IsValid | Should -BeTrue
        $result.Hash | Should -Match '^[a-f0-9]{64}$'
    }

    It 'loads providers with encrypted DNS capabilities' {
        $catalog = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'dns-providers.json') | ConvertFrom-Json

        $result = ConvertFrom-DnsProviderCatalog -Catalog $catalog

        $result.IsValid | Should -BeTrue
        $result.Presets.Count | Should -BeGreaterThan 30
        $result.Presets['Cloudflare DNS'].DoHTemplate | Should -Be 'https://cloudflare-dns.com/dns-query'
        $result.Presets['Cloudflare DNS'].DoTHost | Should -Be 'one.one.one.one:853'
        $result.Presets['Cloudflare DNS'].Capabilities | Should -Contain 'doh'
        $result.Presets['AdGuard DNS'].Capabilities | Should -Contain 'ad-blocking'
    }

    It 'rejects invalid catalog providers before replacing defaults' {
        $catalog = [pscustomobject]@{
            SchemaVersion = 1
            Providers = @(
                [pscustomobject]@{
                    Name = 'Broken DNS'
                    Category = 'Public'
                    Description = 'Invalid provider'
                    IPv4 = @('999.999.999.999')
                    IPv6 = @('not-ipv6')
                    DoH = 'http://example.test/dns-query'
                    DoT = 'bad host'
                    DoQ = 'udp://example.test'
                    Capabilities = @('ipv4', 'unknown')
                }
            )
        }

        $result = ConvertFrom-DnsProviderCatalog -Catalog $catalog

        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'invalid IPv4'
        $result.Message | Should -Match 'unknown capability'
    }
}

Describe 'Localization resources' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'ConvertFrom-StringResourceDocument',
            'Read-StringResourceFile',
            'Get-DynamicLocalizationKeyList',
            'Initialize-StringResources',
            'Get-UiString'
        )

        $script:StringsPath = Join-Path $script:RepoRoot 'strings'
        $script:DefaultLocale = 'en-US'
        $script:UiLocale = 'en-US'
        $script:StringResources = @{}
        $script:DefaultStringResources = @{}
        $script:LocalizationMissingKeys = @()
    }

    It 'keeps shipped locale files in key parity' {
        $english = Get-Content -Raw -LiteralPath (Join-Path $script:StringsPath 'en-US.json') | ConvertFrom-Json
        $spanish = Get-Content -Raw -LiteralPath (Join-Path $script:StringsPath 'es-ES.json') | ConvertFrom-Json
        $englishKeys = @($english.strings.PSObject.Properties.Name | Sort-Object)
        $spanishKeys = @($spanish.strings.PSObject.Properties.Name | Sort-Object)
        $diff = @(Compare-Object -ReferenceObject $englishKeys -DifferenceObject $spanishKeys)

        $diff.Count | Should -Be 0
        foreach ($key in Get-DynamicLocalizationKeyList) {
            $englishKeys | Should -Contain $key
            $spanishKeys | Should -Contain $key
        }

        $translatedCount = @($englishKeys | Where-Object { [string]$english.strings.$_ -ne [string]$spanish.strings.$_ }).Count
        $translatedCount | Should -BeGreaterThan 20
    }

    It 'covers static XAML text with English resource values' {
        $source = Get-Content -Raw -LiteralPath $script:NetForgePath
        $english = Get-Content -Raw -LiteralPath (Join-Path $script:StringsPath 'en-US.json') | ConvertFrom-Json
        $resourceValues = @($english.strings.PSObject.Properties | ForEach-Object { [string]$_.Value })
        $ignoredPatterns = @(
            '^\{',
            '^--$',
            '^\d',
            '^v\d',
            '^NetForge v\d',
            '^N$',
            '^etForge$',
            '^\*$',
            '^ / $',
            '^%$',
            '^MB$',
            '^Mbps$',
            '^ms$',
            '^sec$',
            '^ERR$',
            '^\.\.\.$',
            '^dnsproxy\.exe$',
            '^example\.com$',
            '^quic://',
            '^127\.0\.0\.1$',
            '^1\.1\.1\.1:53$',
            '^255\.255\.255\.0$'
        )

        $matches = [regex]::Matches($source, '\b(?:Text|Content|Header|Title)="([^"]+)"')
        $staticValues = @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        foreach ($value in $staticValues) {
            $ignored = $false
            foreach ($pattern in $ignoredPatterns) {
                if ($value -match $pattern) {
                    $ignored = $true
                    break
                }
            }

            if (-not $ignored) {
                $resourceValues | Should -Contain $value
            }
        }
    }

    It 'loads locale overlays and falls back to caller defaults' {
        $result = Initialize-StringResources -Locale 'es-ES'

        $result.IsValid | Should -BeTrue
        Get-UiString -Key 'app.title' -DefaultValue 'fallback' | Should -Be 'NetForge - Administracion de red'
        Get-UiString -Key 'missing.key' -DefaultValue 'fallback' | Should -Be 'fallback'
        $script:LocalizationMissingKeys.Count | Should -Be 0
    }
}

Describe 'Endpoint privacy policy' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'ConvertTo-SettingsBoolean',
            'Test-HttpsEndpointUri',
            'Get-PublicIpEndpointList',
            'Get-SpeedTestEndpointCatalog',
            'Resolve-SpeedTestEndpoint'
        )
    }

    It 'normalizes persisted endpoint policy booleans' {
        ConvertTo-SettingsBoolean -Value $true -DefaultValue $false | Should -BeTrue
        ConvertTo-SettingsBoolean -Value 'disabled' -DefaultValue $true | Should -BeFalse
        ConvertTo-SettingsBoolean -Value 'yes' -DefaultValue $false | Should -BeTrue
        ConvertTo-SettingsBoolean -Value '' -DefaultValue $true | Should -BeTrue
    }

    It 'keeps public IP and speed-test endpoint catalogs HTTPS-only' {
        foreach ($endpoint in Get-PublicIpEndpointList) {
            Test-HttpsEndpointUri -Uri $endpoint | Should -BeTrue
        }

        foreach ($endpoint in Get-SpeedTestEndpointCatalog) {
            Test-HttpsEndpointUri -Uri $endpoint.Url | Should -BeTrue
        }
    }

    It 'falls back when a speed-test endpoint is blank, unknown, or non-HTTPS' {
        $fallback = Resolve-SpeedTestEndpoint -Endpoint ''
        $fallback.Url | Should -Be 'https://speed.cloudflare.com/__down?bytes=1048576'

        (Resolve-SpeedTestEndpoint -Endpoint 'http://speedtest.example/1MB.bin').Url | Should -Be $fallback.Url
        (Resolve-SpeedTestEndpoint -Endpoint 'unknown').Url | Should -Be $fallback.Url
        (Resolve-SpeedTestEndpoint -Endpoint 'OVH 1 MB (HTTPS)').Url | Should -Be 'https://proof.ovh.net/files/1Mb.dat'
    }

    It 'removes legacy HTTP speed-test fallbacks and gates external calls' {
        $source = Get-Content -Raw $script:NetForgePath

        $source | Should -Not -Match 'http://speedtest\.tele2\.net'
        $source | Should -Not -Match 'http://proof\.ovh\.net'
        $source | Should -Match 'PublicIpLookupEnabled'
        $source | Should -Match 'ExternalSpeedTestEnabled'
        $source | Should -Match 'SpeedTestEndpoint'
    }
}

Describe 'MTR history helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'New-MtrHopRecord',
            'Update-MtrHopHistory',
            'Format-MtrLatency',
            'Format-MtrHistoryRows'
        )
    }

    It 'aggregates per-hop latency, loss, and destination state' {
        $history = @{}
        $history = Update-MtrHopHistory -History $history -ProbeResults @(
            [pscustomobject]@{ Hop = 1; Address = '192.168.1.1'; LatencyMs = 3; Status = 'TtlExpired'; IsDestination = $false },
            [pscustomobject]@{ Hop = 2; Address = '8.8.8.8'; LatencyMs = 20; Status = 'Success'; IsDestination = $true }
        )
        $history = Update-MtrHopHistory -History $history -ProbeResults @(
            [pscustomobject]@{ Hop = 1; Address = '192.168.1.1'; LatencyMs = -1; Status = 'TimedOut'; IsDestination = $false },
            [pscustomobject]@{ Hop = 2; Address = '8.8.8.8'; LatencyMs = 30; Status = 'Success'; IsDestination = $true }
        )

        $history[1].Sent | Should -Be 2
        $history[1].Received | Should -Be 1
        $history[1].LossPercent | Should -Be 50
        $history[2].BestMs | Should -Be 20
        $history[2].AvgMs | Should -Be 25
        $history[2].WorstMs | Should -Be 30
        $history[2].IsDestination | Should -BeTrue

        $rows = Format-MtrHistoryRows -History $history -Target '8.8.8.8' -Cycle 2
        $rows | Should -Match 'MTR-style trace to 8.8.8.8'
        $rows | Should -Match '50%'
        $rows | Should -Match '8.8.8.8'
        $rows | Should -Match 'dest'
    }
}

Describe 'Port scan helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'ConvertTo-UInt32IPv4',
            'ConvertFrom-UInt32IPv4',
            'Get-PortScanTargetList',
            'Get-DefaultPortScanPorts',
            'Get-PortServiceName',
            'Format-PortScanRows'
        )
    }

    It 'expands bounded IPv4 CIDR targets for LAN discovery' {
        $targets = Get-PortScanTargetList -Target '192.168.50.0/30'

        $targets.Count | Should -Be 2
        $targets[0] | Should -Be '192.168.50.1'
        $targets[1] | Should -Be '192.168.50.2'
        { Get-PortScanTargetList -Target '192.168.0.0/16' } | Should -Throw '*limited to /24 through /32*'
    }

    It 'uses a broader host port set and compact CIDR discovery set' {
        (Get-DefaultPortScanPorts -TargetCount 1) | Should -Contain 5985
        ((Get-DefaultPortScanPorts -TargetCount 12) -join ',') | Should -Be '80,443,445,3389'
    }

    It 'formats open TCP services and empty scan results' {
        $rows = Format-PortScanRows -Target 'server.local' -TargetCount 1 -Ports @(80, 443) -ElapsedMs 42 -Results @(
            [pscustomobject]@{ Target = 'server.local'; Port = 443; Status = 'Open'; LatencyMs = 12 },
            [pscustomobject]@{ Target = 'server.local'; Port = 80; Status = 'Closed'; LatencyMs = -1 }
        )

        $rows | Should -Match 'Port scan for server.local'
        $rows | Should -Match 'HTTPS'
        $rows | Should -Match '443'
        $rows | Should -Not -Match 'Closed'

        $empty = Format-PortScanRows -Target 'server.local' -TargetCount 1 -Ports @(80) -ElapsedMs 10 -Results @()
        $empty | Should -Match 'No open ports'
    }
}

Describe 'Packet capture helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-PacketCaptureFileSet',
            'Format-PacketCaptureSummary'
        )
    }

    It 'builds timestamped ETL and PCAPNG capture paths' {
        $files = Get-PacketCaptureFileSet -Directory 'C:\Temp\NetForge' -Timestamp ([datetime]'2026-06-29T14:15:30')

        $files.EtlPath | Should -Be 'C:\Temp\NetForge\netforge-capture-20260629-141530.etl'
        $files.PcapPath | Should -Be 'C:\Temp\NetForge\netforge-capture-20260629-141530.pcapng'
    }

    It 'formats packet capture conversion summaries' {
        $summary = Format-PacketCaptureSummary -EtlPath 'capture.etl' -PcapPath 'capture.pcapng' -OpenedWireshark:$true -StopOutput @('Stopped') -ConvertOutput @('Converted')

        $summary | Should -Match 'Packet capture complete'
        $summary | Should -Match 'capture.pcapng'
        $summary | Should -Match 'Wireshark: launched'
        $summary | Should -Match 'pktmon etl2pcap'
    }
}

Describe 'Cable diagnostic helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-CableDiagnosticPropertyName',
            'Format-CableDiagnosticReport'
        )
    }

    It 'recognizes cable and transceiver driver telemetry names' {
        Test-CableDiagnosticPropertyName -Name 'SFP Module Temperature' | Should -BeTrue
        Test-CableDiagnosticPropertyName -Name 'Cable Length' | Should -BeTrue
        Test-CableDiagnosticPropertyName -Name 'Rx Power' | Should -BeTrue
        Test-CableDiagnosticPropertyName -Name 'Interrupt Moderation' | Should -BeFalse
    }

    It 'formats driver-exposed cable telemetry and no-telemetry fallbacks' {
        $data = [pscustomobject]@{
            AdapterName = 'Ethernet 1'
            InterfaceDescription = 'Server NIC'
            Status = 'Up'
            LinkSpeed = '10 Gbps'
            MacAddress = '00-11-22-33-44-55'
            HardwareInfo = $null
            Statistics = [pscustomobject]@{
                ReceivedBytes = 1000
                SentBytes = 500
                ReceivedPacketErrors = 0
                OutboundPacketErrors = 1
            }
            DriverProperties = @(
                [pscustomobject]@{ Name = 'SFP Module Temperature'; Value = '42 C'; Keyword = '*SfpTemperature' }
            )
        }

        $report = Format-CableDiagnosticReport -Data $data

        $report | Should -Match 'Cable / transceiver diagnostics'
        $report | Should -Match 'SFP Module Temperature: 42 C'
        $report | Should -Match 'OutboundPacketErrors: 1'

        $empty = [pscustomobject]@{
            AdapterName = 'Ethernet 1'
            InterfaceDescription = 'Server NIC'
            Status = 'Up'
            LinkSpeed = '10 Gbps'
            MacAddress = '00-11-22-33-44-55'
            HardwareInfo = $null
            Statistics = $null
            DriverProperties = @()
        }
        (Format-CableDiagnosticReport -Data $empty) | Should -Match 'No cable, SFP, DDM, DOM, or optical telemetry'
    }
}

Describe 'WiFi spectrum helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-WifiChannelBand',
            'Get-WifiChannelUtilization',
            'Format-WifiSpectrumReport'
        )
    }

    It 'aggregates BSSID counts and strongest signal per channel' {
        $networks = @(
            [pscustomobject]@{
                SSID = 'Clinic'
                Signal = '80%'
                Channels = @('6')
                BssidDetails = @(
                    [pscustomobject]@{ SSID = 'Clinic'; BSSID = '00:11:22:33:44:55'; Channel = '6'; Signal = '80%'; Band = '2.4 GHz' },
                    [pscustomobject]@{ SSID = 'Clinic'; BSSID = '00:11:22:33:44:66'; Channel = '6'; Signal = '62%'; Band = '2.4 GHz' }
                )
            },
            [pscustomobject]@{
                SSID = 'Lab'
                Signal = '55%'
                Channels = @('149')
                BssidDetails = @(
                    [pscustomobject]@{ SSID = 'Lab'; BSSID = 'AA:BB:CC:DD:EE:FF'; Channel = '149'; Signal = '55%'; Band = '5 GHz' }
                )
            }
        )

        $rows = Get-WifiChannelUtilization -Networks $networks

        $rows.Count | Should -Be 2
        $rows[0].Channel | Should -Be '6'
        $rows[0].BssidCount | Should -Be 2
        $rows[0].StrongestSignal | Should -Be 80
        $rows[0].SSIDs | Should -Contain 'Clinic'
        $rows[1].Band | Should -Be '5 GHz'

        $report = Format-WifiSpectrumReport -ChannelRows $rows
        $report | Should -Match 'Channel utilization'
        $report | Should -Match '00:11:22:33:44:55'
        $report | Should -Match 'Clinic'
    }

    It 'falls back to channel lists when per-BSSID details are unavailable' {
        $rows = Get-WifiChannelUtilization -Networks @(
            [pscustomobject]@{ SSID = 'Fallback'; Signal = '44%'; Channels = @('11'); BssidDetails = @() }
        )

        $rows.Count | Should -Be 1
        $rows[0].Band | Should -Be '2.4 GHz'
        $rows[0].StrongestSignal | Should -Be 44
        (Format-WifiSpectrumReport -ChannelRows @()) | Should -Match 'No WiFi channel data'
    }
}

Describe 'Profile storage migration' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-ValidIPv4Address',
            'Test-ValidIPv4PrefixLength',
            'ConvertTo-CleanMacAddress',
            'Test-ValidMacAddress',
            'Get-ProfileProperty',
            'ConvertTo-ProfileBoolean',
            'Get-ProfileScheduleDayAliases',
            'Normalize-ProfileScheduleDays',
            'Normalize-ProfileScheduleTime',
            'ConvertTo-ProfileScheduleDaysText',
            'Get-SafeProfileFileName',
            'ConvertFrom-MappedDriveText',
            'ConvertTo-MappedDriveText',
            'Normalize-MappedDriveList',
            'Get-ProfileValidationResult',
            'Resolve-ProfileStorePath',
            'Test-SamePath',
            'Get-FileSha256',
            'Get-AppSettings',
            'Save-AppSetting',
            'Test-ProfileStorePath',
            'Get-ProfileStoreMigrationPlan',
            'Write-ProfileStoreBackupManifest'
        )
        $script:ProfileSchemaVersion = 3
        $versionMetadata = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'version.json') | ConvertFrom-Json
        $script:AppVersion = [string]$versionMetadata.Version
    }

    It 'normalizes equivalent profile store paths' {
        $path = Join-Path $TestDrive 'Profiles'
        New-Item -Path $path -ItemType Directory -Force | Out-Null

        Test-SamePath -PathA $path -PathB "$path\" | Should -BeTrue
    }

    It 'plans profile copies without overwriting the target store' {
        $source = Join-Path $TestDrive 'source'
        $target = Join-Path $TestDrive 'target'
        New-Item -Path $source, $target -ItemType Directory -Force | Out-Null

        $profile = [pscustomobject]@{
            Name = 'Clinic LAN'
            UseDHCP = $true
            UseDHCPForDNS = $true
        }
        $validation = Get-ProfileValidationResult -ProfileData $profile
        $validation.Profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $source $validation.SafeFileName) -Encoding UTF8

        $plan = Get-ProfileStoreMigrationPlan -SourcePath $source -TargetPath $target

        $plan.CanMigrate | Should -BeTrue
        $plan.CopyFiles.Count | Should -Be 1
        $plan.Conflicts.Count | Should -Be 0
    }

    It 'blocks same-name profile conflicts' {
        $source = Join-Path $TestDrive 'conflict-source'
        $target = Join-Path $TestDrive 'conflict-target'
        New-Item -Path $source, $target -ItemType Directory -Force | Out-Null

        $sourceProfile = [pscustomobject]@{ Name = 'Clinic LAN'; Description = 'source'; UseDHCP = $true; UseDHCPForDNS = $true }
        $targetProfile = [pscustomobject]@{ Name = 'Clinic LAN'; Description = 'target'; UseDHCP = $true; UseDHCPForDNS = $true }
        $sourceValidation = Get-ProfileValidationResult -ProfileData $sourceProfile
        $targetValidation = Get-ProfileValidationResult -ProfileData $targetProfile
        $sourceValidation.Profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $source $sourceValidation.SafeFileName) -Encoding UTF8
        $targetValidation.Profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target $targetValidation.SafeFileName) -Encoding UTF8

        $plan = Get-ProfileStoreMigrationPlan -SourcePath $source -TargetPath $target

        $plan.CanMigrate | Should -BeFalse
        $plan.Conflicts.Count | Should -Be 1
        $plan.Conflicts[0] | Should -Match 'Clinic LAN'
    }

    It 'writes a backup manifest for profile store changes' {
        $script:ConfigPath = Join-Path $TestDrive 'config'
        New-Item -Path $script:ConfigPath -ItemType Directory -Force | Out-Null
        $plan = [pscustomobject]@{
            SourcePath = Join-Path $TestDrive 'source'
            TargetPath = Join-Path $TestDrive 'target'
            CanMigrate = $true
            CopyFiles = @([pscustomobject]@{ Name = 'Clinic LAN'; SafeFileName = 'Clinic_LAN.json'; Sha256 = 'abc123' })
            Skipped = @()
            Conflicts = @()
            InvalidProfiles = @()
        }

        $manifestPath = Write-ProfileStoreBackupManifest -Plan $plan -ActionName 'Test'
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

        Test-Path -LiteralPath $manifestPath | Should -BeTrue
        $manifest.Action | Should -Be 'Test'
        $manifest.Copied[0].SafeFileName | Should -Be 'Clinic_LAN.json'
    }

    It 'persists profile store settings atomically' {
        $script:ConfigPath = Join-Path $TestDrive 'settings'
        $script:SettingsFile = Join-Path $script:ConfigPath 'settings.json'
        $profileStore = Join-Path $TestDrive 'synced-profiles'

        Save-AppSetting -Name 'ProfileStorePath' -Value $profileStore
        $settings = Get-Content -Raw -LiteralPath $script:SettingsFile | ConvertFrom-Json

        $settings.ProfileStorePath | Should -Be $profileStore
        $settings.UpdatedAt | Should -Not -BeNullOrEmpty
    }
}

Describe 'Accessibility metadata' {
    It 'lists automation names for primary workflows' {
        $source = Get-Content -Raw $script:NetForgePath
        $requiredControls = @(
            'lstAdapters',
            'btnApplyIP',
            'lstDnsPresets',
            'btnApplyDns',
            'lstProfiles',
            'btnApplyProfile',
            'btnRestoreNetworkState',
            'btnExportDiagnostics'
        )

        foreach ($controlName in $requiredControls) {
            $source | Should -Match "$controlName\s*="
        }

        $source | Should -Match 'Initialize-AccessibilityMetadata'
        $source | Should -Match 'AutomationProperties'
        $source | Should -Match 'AccessibilityTabOrder'
    }
}
