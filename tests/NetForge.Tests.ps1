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
            'Test-ValidIPv6Address',
            'Test-ValidIPv6PrefixLength',
            'Get-ApplyValidationResult',
            'Get-IPv6ApplyTarget',
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
            'Test-ValidProxyServer',
            'Test-ValidProxyBypass',
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

    It 'validates optional static IPv6 apply targets' {
        Test-ValidIPv6Address -IP '2001:db8::100' | Should -BeTrue
        Test-ValidIPv6Address -IP '192.168.1.20' | Should -BeFalse
        Test-ValidIPv6PrefixLength -PrefixLength 64 | Should -BeTrue
        Test-ValidIPv6PrefixLength -PrefixLength 129 | Should -BeFalse

        $target = Get-IPv6ApplyTarget -ConfigureIPv6 $true -IPv6Address '2001:db8::100' -IPv6PrefixText '64' -IPv6Gateway 'fe80::1'
        $target.IsValid | Should -BeTrue
        $target.ConfigureIPv6 | Should -BeTrue
        $target.IPv6Address | Should -Be '2001:db8::100'
        $target.IPv6PrefixLength | Should -Be 64
        $target.IPv6Gateway | Should -Be 'fe80::1'

        $disabled = Get-IPv6ApplyTarget -ConfigureIPv6 $false -IPv6Address '' -IPv6PrefixText '' -IPv6Gateway ''
        $disabled.IsValid | Should -BeTrue
        $disabled.ConfigureIPv6 | Should -BeFalse

        $badGateway = Get-IPv6ApplyTarget -ConfigureIPv6 $true -IPv6Address '2001:db8::100' -IPv6PrefixText '64' -IPv6Gateway '192.168.1.1'
        $badGateway.IsValid | Should -BeFalse
        $badGateway.Message | Should -Match 'IPv6 default gateway'
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

    It 'normalizes weekend schedule and boundary times' {
        $weekend = Normalize-ProfileScheduleDays -Days 'Weekends'
        $weekend.IsValid | Should -BeTrue
        $weekend.Days | Should -Contain 'Saturday'
        $weekend.Days | Should -Contain 'Sunday'
        $weekend.Days.Count | Should -Be 2

        $midnight = Normalize-ProfileScheduleTime -Time '00:00'
        $midnight.IsValid | Should -BeTrue
        $midnight.Time | Should -Be '00:00'

        $endOfDay = Normalize-ProfileScheduleTime -Time '23:59'
        $endOfDay.IsValid | Should -BeTrue
        $endOfDay.Time | Should -Be '23:59'

        $caseDays = Normalize-ProfileScheduleDays -Days 'MONDAY,friday'
        $caseDays.IsValid | Should -BeTrue
        $caseDays.Days | Should -Contain 'Monday'
        $caseDays.Days | Should -Contain 'Friday'
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

Describe 'Profile QR payload helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-ValidIPv4Address',
            'Test-ValidIPv4PrefixLength',
            'Test-ValidIPv6Address',
            'Test-ValidIPv6PrefixLength',
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
            'ConvertTo-Base64Url',
            'ConvertFrom-Base64Url',
            'ConvertTo-GzipBase64Url',
            'ConvertFrom-GzipBase64Url',
            'ConvertTo-ProfileQrPayload',
            'ConvertFrom-ProfileQrPayload'
        )
        $script:ProfileSchemaVersion = 3
        $script:AppVersion = '9.9.9'
        $script:ProfileQrPayloadPrefix = 'NETFORGE-PROFILE-V1:'
        $script:ProfileQrMaxPayloadLength = 2950
    }

    It 'round-trips a profile through a compact QR payload' {
        $profile = [pscustomobject]@{
            Name = 'QR Clinic'
            Description = 'QR profile'
            UseDHCP = $true
            UseDHCPForDNS = $false
            PrimaryDNS = '1.1.1.1'
            SecondaryDNS = '1.0.0.1'
        }

        $payload = ConvertTo-ProfileQrPayload -ProfileData $profile
        $record = ConvertFrom-ProfileQrPayload -Payload $payload

        $payload | Should -Match '^NETFORGE-PROFILE-V1:'
        $payload.Length | Should -BeLessOrEqual 2950
        $record.Profile.Name | Should -Be 'QR Clinic'
        $record.Profile.PrimaryDNS | Should -Be '1.1.1.1'
        $record.SafeFileName | Should -Be 'QR_Clinic.json'
        $record.AppVersion | Should -Be '9.9.9'
    }

    It 'rejects non-NetForge QR payloads' {
        { ConvertFrom-ProfileQrPayload -Payload 'https://example.com' } | Should -Throw '*not a NetForge profile*'
    }
}

Describe 'CLI profile apply helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Resolve-CliProfile',
            'Resolve-CliAdapter'
        )
        $script:ProfilesPath = 'C:\Profiles'
    }

    It 'resolves a saved profile name case-insensitively' {
        $profiles = @(
            [pscustomobject]@{ Name = 'Home' },
            [pscustomobject]@{ Name = 'Work' }
        )

        $profile = Resolve-CliProfile -ProfileName 'home' -Profiles $profiles

        $profile.Name | Should -Be 'Home'
    }

    It 'reports available profiles when a CLI profile is missing' {
        $profiles = @(
            [pscustomobject]@{ Name = 'Home' },
            [pscustomobject]@{ Name = 'Work' }
        )

        { Resolve-CliProfile -ProfileName 'Travel' -Profiles $profiles } | Should -Throw "*Available profiles: Home, Work*"
    }

    It 'defaults to the first active adapter' {
        $adapters = @(
            [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 4; InterfaceDescription = 'Intel Ethernet'; Status = 'Disconnected' },
            [pscustomobject]@{ Name = 'Wi-Fi'; ifIndex = 9; InterfaceDescription = 'Intel Wi-Fi'; Status = 'Up' }
        )

        $adapter = Resolve-CliAdapter -Adapters $adapters

        $adapter.Name | Should -Be 'Wi-Fi'
    }

    It 'resolves adapters by interface index' {
        $adapters = @(
            [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 4; InterfaceDescription = 'Intel Ethernet'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Wi-Fi'; ifIndex = 9; InterfaceDescription = 'Intel Wi-Fi'; Status = 'Up' }
        )

        $adapter = Resolve-CliAdapter -AdapterName '4' -Adapters $adapters

        $adapter.Name | Should -Be 'Ethernet'
    }
}

Describe 'RDP profile launch helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-RdpLaunchPlan'
        )
    }

    It 'builds a mstsc host launch argument' {
        $plan = Get-RdpLaunchPlan -Target 'rdp.example.com:3390'

        $plan.IsValid | Should -BeTrue
        $plan.FilePath | Should -Be 'mstsc.exe'
        $plan.ArgumentList | Should -Be '/v:rdp.example.com:3390'
        $plan.DisplayTarget | Should -Be 'rdp.example.com:3390'
    }

    It 'rejects raw mstsc option text in host mode' {
        $plan = Get-RdpLaunchPlan -Target '/admin rdp.example.com'

        $plan.IsValid | Should -BeFalse
        $plan.Message | Should -Match 'Use a saved .rdp file'
    }

    It 'quotes an existing RDP file path' {
        $rdpPath = Join-Path $TestDrive 'Work Profile.rdp'
        Set-Content -LiteralPath $rdpPath -Value 'full address:s:rdp.example.com' -Encoding ASCII

        $plan = Get-RdpLaunchPlan -Target $rdpPath

        $plan.IsValid | Should -BeTrue
        $plan.ArgumentList | Should -Be ('"' + $rdpPath + '"')
        $plan.DisplayTarget | Should -Be $rdpPath
    }

    It 'rejects a non-existent RDP file' {
        $plan = Get-RdpLaunchPlan -Target 'C:\nonexistent\missing.rdp'

        $plan.IsValid | Should -BeFalse
        $plan.Message | Should -Match 'not found'
    }

    It 'rejects empty target' {
        $plan = Get-RdpLaunchPlan -Target ''

        $plan.IsValid | Should -BeFalse
        $plan.Message | Should -Match 'host or .rdp file'
    }

    It 'accepts a simple hostname' {
        $plan = Get-RdpLaunchPlan -Target 'server01'

        $plan.IsValid | Should -BeTrue
        $plan.ArgumentList | Should -Be '/v:server01'
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

    It 'rejects catalogs with missing required provider fields' {
        $catalog = [pscustomobject]@{
            SchemaVersion = 1
            Providers = @(
                [pscustomobject]@{
                    Name = ''
                    Category = ''
                    Description = ''
                    IPv4Primary = '8.8.8.8'
                    IPv4Secondary = '8.8.4.4'
                    Capabilities = @('ipv4')
                }
            )
        }

        $result = ConvertFrom-DnsProviderCatalog -Catalog $catalog
        $result.IsValid | Should -BeFalse
    }

    It 'rejects null catalog' {
        $result = ConvertFrom-DnsProviderCatalog -Catalog $null
        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'empty'
    }

    It 'rejects wrong schema version' {
        $catalog = [pscustomobject]@{ SchemaVersion = 99; Providers = @() }
        $result = ConvertFrom-DnsProviderCatalog -Catalog $catalog
        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'schema'
    }
}

Describe 'DNS preset apply target helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Get-ApplyValidationResult',
            'Get-DnsPresetApplyTarget'
        )
    }

    It 'builds an automatic DNS target for DHCP presets' {
        $target = Get-DnsPresetApplyTarget -PresetName 'DHCP (Automatic)' -PresetData ([pscustomobject]@{
            Primary = 'DHCP'
            Secondary = 'DHCP'
        })

        $target.IsValid | Should -BeTrue
        $target.UseAutomatic | Should -BeTrue
        $target.Servers.Count | Should -Be 0
        $target.StatusMessage | Should -Match 'automatic'
    }

    It 'includes unique IPv4 and IPv6 servers when requested' {
        $target = Get-DnsPresetApplyTarget -PresetName 'Example DNS' -PresetData ([pscustomobject]@{
            Primary = '1.1.1.1'
            Secondary = '1.0.0.1'
            PrimaryV6 = '2606:4700:4700::1111'
            SecondaryV6 = '2606:4700:4700::1111'
        }) -IncludeIPv6 $true

        $target.IsValid | Should -BeTrue
        $target.UseAutomatic | Should -BeFalse
        $target.Servers | Should -Contain '1.1.1.1'
        $target.Servers | Should -Contain '1.0.0.1'
        $target.Servers | Should -Contain '2606:4700:4700::1111'
        @($target.Servers | Where-Object { $_ -eq '2606:4700:4700::1111' }).Count | Should -Be 1
    }

    It 'rejects invalid preset server addresses' {
        $target = Get-DnsPresetApplyTarget -PresetName 'Broken DNS' -PresetData ([pscustomobject]@{
            Primary = '999.999.999.999'
            Secondary = ''
        })

        $target.IsValid | Should -BeFalse
        $target.Message | Should -Match 'invalid server'
    }
}

Describe 'Theme catalog helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-UiThemeCatalog',
            'Get-UiThemeNames',
            'Resolve-UiThemeName'
        )
    }

    It 'ships the expected dark theme alternatives' {
        $themes = Get-UiThemeCatalog
        $names = Get-UiThemeNames

        $names | Should -Contain 'GitHub Dark'
        $names | Should -Contain 'Catppuccin Mocha'
        $names | Should -Contain 'Nord'

        foreach ($themeName in $names) {
            foreach ($requiredKey in @('BgPrimary', 'BgSecondary', 'BgTertiary', 'BgStatus', 'BorderColor', 'AccentBlue', 'AccentGreen', 'AccentOrange', 'AccentRed', 'AccentPurple', 'TextPrimary', 'TextSecondary', 'TextMuted', 'ButtonHover', 'ButtonPressed', 'SuccessButton', 'SuccessButtonHover', 'DangerButtonBg', 'DangerButtonHover', 'DangerButtonPressed', 'ListItemHover', 'ListItemSelected')) {
                $themes[$themeName].Contains($requiredKey) | Should -BeTrue
                $themes[$themeName][$requiredKey] | Should -Match '^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$'
            }
        }
    }

    It 'resolves theme names case-insensitively and falls back to GitHub Dark' {
        Resolve-UiThemeName -Name 'nord' | Should -Be 'Nord'
        Resolve-UiThemeName -Name 'catppuccin mocha' | Should -Be 'Catppuccin Mocha'
        Resolve-UiThemeName -Name 'unknown' | Should -Be 'GitHub Dark'
    }
}

Describe 'Compact mode helpers' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName WindowsBase
        Import-NetForgeFunction -Name @(
            'ConvertTo-SettingsBoolean',
            'Resolve-CompactModeSetting',
            'ConvertTo-ScaledThickness',
            'ConvertTo-CompactFontSize'
        )
    }

    It 'normalizes persisted compact mode settings' {
        Resolve-CompactModeSetting -Value 'enabled' | Should -BeTrue
        Resolve-CompactModeSetting -Value 'false' | Should -BeFalse
        Resolve-CompactModeSetting -Value $null | Should -BeFalse
    }

    It 'scales spacing and font sizes with lower bounds' {
        $thickness = New-Object System.Windows.Thickness -ArgumentList 10, 20, 0, 5
        $scaled = ConvertTo-ScaledThickness -Thickness $thickness -Scale 0.82

        $scaled.Left | Should -Be 8.2
        $scaled.Top | Should -Be 16.4
        $scaled.Right | Should -Be 0
        $scaled.Bottom | Should -Be 4.1
        ConvertTo-CompactFontSize -FontSize 28 -Scale 0.82 | Should -Be 23
        ConvertTo-CompactFontSize -FontSize 10 -Scale 0.5 | Should -Be 9
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
        Get-UiString -Key 'app.title' -DefaultValue 'fallback' | Should -Be "NetForge - Administraci$([char]0xf3)n de red"
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
            'Resolve-SpeedTestEndpoint',
            'Test-ProtectedAppSettingName',
            'Get-ProtectedAppSettingName',
            'Initialize-ProtectedDataApi',
            'Protect-AppSettingSecret',
            'Unprotect-AppSettingSecret',
            'Get-AppSettingSecretValue',
            'Get-KnownSettingNames',
            'Test-SettingsSchema',
            'Backup-SettingsFile',
            'Get-AppSettings',
            'Save-AppSetting',
            'Complete-PendingProtectedSettingMigrations',
            'ConvertTo-DiscordWebhookSafeText',
            'Test-DiscordWebhookUrl',
            'Get-DiscordWebhookRedactedUrl',
            'New-DiscordProfileWebhookPayload'
        )
        $versionMetadata = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'version.json') | ConvertFrom-Json
        $script:AppVersion = [string]$versionMetadata.Version
        $script:ProtectedSettingNames = @('DiscordWebhookUrl')
        $script:SettingsSchemaVersion = 1
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
        $source | Should -Match 'DiscordWebhookEnabled'
        $source | Should -Match 'ProtectedSettingNames'
    }

    It 'protects Discord webhook settings with current-user DPAPI' {
        $url = 'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl'

        Test-ProtectedAppSettingName -Name 'DiscordWebhookUrl' | Should -BeTrue
        Get-ProtectedAppSettingName -Name 'DiscordWebhookUrl' | Should -Be 'DiscordWebhookUrlProtected'

        $protected = Protect-AppSettingSecret -Value $url
        $protected | Should -Not -BeNullOrEmpty
        $protected | Should -Not -Be $url
        Unprotect-AppSettingSecret -ProtectedValue $protected | Should -Be $url
    }

    It 'reads legacy plaintext webhook settings as migration candidates' {
        $url = 'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl'
        $settings = [pscustomobject]@{
            DiscordWebhookEnabled = $true
            DiscordWebhookUrl = $url
        }

        $secret = Get-AppSettingSecretValue -Settings $settings -Name 'DiscordWebhookUrl'

        $secret.HasValue | Should -BeTrue
        $secret.Value | Should -Be $url
        $secret.IsProtected | Should -BeFalse
        $secret.NeedsMigration | Should -BeTrue
        $secret.Error | Should -Be ''
    }

    It 'handles missing and invalid protected webhook settings without exposing secrets' {
        $missing = Get-AppSettingSecretValue -Settings ([pscustomobject]@{}) -Name 'DiscordWebhookUrl'
        $missing.HasValue | Should -BeFalse
        $missing.Value | Should -Be ''

        $invalid = Get-AppSettingSecretValue -Settings ([pscustomobject]@{
            DiscordWebhookUrlProtected = 'not-base64'
        }) -Name 'DiscordWebhookUrl'

        $invalid.HasValue | Should -BeFalse
        $invalid.Value | Should -Be ''
        $invalid.IsProtected | Should -BeTrue
        $invalid.NeedsMigration | Should -BeFalse
        $invalid.Error | Should -Match 'Could not decrypt protected setting secret'
    }

    It 'stores Discord webhook URLs only as protected settings' {
        $script:ConfigPath = Join-Path $TestDrive 'secret-settings'
        $script:SettingsFile = Join-Path $script:ConfigPath 'settings.json'
        $url = 'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl'

        Save-AppSetting -Name 'DiscordWebhookUrl' -Value $url
        $settingsText = Get-Content -Raw -LiteralPath $script:SettingsFile
        $settings = $settingsText | ConvertFrom-Json
        $secret = Get-AppSettingSecretValue -Settings $settings -Name 'DiscordWebhookUrl'

        $settingsText | Should -Not -Match ([regex]::Escape($url))
        $settings.PSObject.Properties['DiscordWebhookUrl'] | Should -BeNullOrEmpty
        $settings.DiscordWebhookUrlProtected | Should -Not -BeNullOrEmpty
        $secret.HasValue | Should -BeTrue
        $secret.Value | Should -Be $url
        $secret.IsProtected | Should -BeTrue
        $secret.NeedsMigration | Should -BeFalse
    }

    It 'migrates pending legacy webhook settings to protected storage' {
        $script:ConfigPath = Join-Path $TestDrive 'migration-settings'
        $script:SettingsFile = Join-Path $script:ConfigPath 'settings.json'
        New-Item -Path $script:ConfigPath -ItemType Directory -Force | Out-Null
        $url = 'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl'
        [pscustomobject]@{
            DiscordWebhookEnabled = $true
            DiscordWebhookUrl = $url
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8

        $script:PendingProtectedSettingMigrations = [ordered]@{
            DiscordWebhookUrl = $url
        }
        Complete-PendingProtectedSettingMigrations

        $settingsText = Get-Content -Raw -LiteralPath $script:SettingsFile
        $settings = $settingsText | ConvertFrom-Json
        $secret = Get-AppSettingSecretValue -Settings $settings -Name 'DiscordWebhookUrl'

        $settingsText | Should -Not -Match ([regex]::Escape($url))
        $settings.PSObject.Properties['DiscordWebhookUrl'] | Should -BeNullOrEmpty
        $settings.DiscordWebhookUrlProtected | Should -Not -BeNullOrEmpty
        $settings.DiscordWebhookEnabled | Should -BeTrue
        $secret.Value | Should -Be $url
        $script:PendingProtectedSettingMigrations.Count | Should -Be 0
    }

    It 'accepts only Discord HTTPS webhook URLs and redacts tokens' {
        Test-DiscordWebhookUrl -Url 'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl' | Should -BeTrue
        Test-DiscordWebhookUrl -Url 'https://discordapp.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl' | Should -BeTrue
        Test-DiscordWebhookUrl -Url 'http://discord.com/api/webhooks/123456789012345678/abc' | Should -BeFalse
        Test-DiscordWebhookUrl -Url 'https://discord.com.evil.example/api/webhooks/123456789012345678/abc' | Should -BeFalse
        Test-DiscordWebhookUrl -Url 'https://discord.com/api/webhooks/123456789012345678/abc?wait=true' | Should -BeFalse
        Test-DiscordWebhookUrl -Url 'https://discord.com/channels/123' | Should -BeFalse

        Get-DiscordWebhookRedactedUrl -Url 'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl' | Should -Be 'https://discord.com/api/webhooks/123456789012345678/[redacted]'
    }

    It 'builds a Discord profile payload without webhook secrets or mentions' {
        $profile = [pscustomobject]@{ Name = 'Clinic @everyone' }
        $adapter = [pscustomobject]@{ Name = 'Wi-Fi'; ifIndex = 12 }

        $payloadJson = New-DiscordProfileWebhookPayload -ProfileData $profile -Adapter $adapter -Source 'Manual'
        $payload = $payloadJson | ConvertFrom-Json

        $payload.username | Should -Be 'NetForge'
        $payload.content | Should -Match 'Clinic @everyone'
        $payload.allowed_mentions.parse.Count | Should -Be 0
        $payload.embeds[0].title | Should -Be 'Profile applied'
        ($payload.embeds[0].fields | Where-Object { $_.name -eq 'Profile' }).value | Should -Be 'Clinic @everyone'
        ($payload.embeds[0].fields | Where-Object { $_.name -eq 'Adapter' }).value | Should -Be 'Wi-Fi [12]'
        ($payload.embeds[0].fields | Where-Object { $_.name -eq 'Source' }).value | Should -Be 'Manual'
        $payloadJson | Should -Not -Match 'api/webhooks'
    }
}

Describe 'Interface metric priority helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-AdapterBindingPriorityPlan'
        )
    }

    It 'builds IPv4-first and IPv6-first metric plans' {
        $ipv4First = Get-AdapterBindingPriorityPlan -Mode 'IPv4First'
        $ipv6First = Get-AdapterBindingPriorityPlan -Mode 'IPv6First'

        $ipv4First.IPv4Metric | Should -BeLessThan $ipv4First.IPv6Metric
        $ipv6First.IPv6Metric | Should -BeLessThan $ipv6First.IPv4Metric
        $ipv4First.Description | Should -Be 'IPv4 first'
        $ipv6First.Description | Should -Be 'IPv6 first'
        { Get-AdapterBindingPriorityPlan -Mode 'BadMode' } | Should -Throw
    }
}

Describe 'Latency histogram helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Resolve-LatencyHistogramDuration',
            'Get-LatencyPercentile',
            'Get-LatencyHistogramBucketDefinitions',
            'New-LatencyHistogramBucket',
            'Get-LatencyHistogramSummary',
            'Format-LatencyHistogramValue',
            'Format-LatencyHistogramReport'
        )
    }

    It 'validates bounded histogram durations' {
        $valid = Resolve-LatencyHistogramDuration -Value '45'
        $tooShort = Resolve-LatencyHistogramDuration -Value '4'
        $invalid = Resolve-LatencyHistogramDuration -Value 'abc'

        $valid.IsValid | Should -BeTrue
        $valid.Seconds | Should -Be 45
        $tooShort.IsValid | Should -BeFalse
        $tooShort.Message | Should -Match 'between 5 and 300'
        $invalid.IsValid | Should -BeFalse
        $invalid.Seconds | Should -Be 30
    }

    It 'summarizes latency buckets, percentiles, and loss' {
        $samples = @(
            [pscustomobject]@{ Success = $true; LatencyMs = 10 },
            [pscustomobject]@{ Success = $true; LatencyMs = 25 },
            [pscustomobject]@{ Success = $true; LatencyMs = 75 },
            [pscustomobject]@{ Success = $true; LatencyMs = 250 },
            [pscustomobject]@{ Success = $true; LatencyMs = 700 },
            [pscustomobject]@{ Success = $false; LatencyMs = -1 },
            [pscustomobject]@{ Success = $false; LatencyMs = $null }
        )

        $summary = Get-LatencyHistogramSummary -Samples $samples -Target 'example.com' -DurationSeconds 7
        $timeoutBucket = $summary.Buckets | Where-Object { $_.Label -eq 'Timeout/loss' }
        $fastBucket = $summary.Buckets | Where-Object { $_.Label -eq '0-19 ms' }

        $summary.SampleCount | Should -Be 7
        $summary.SuccessCount | Should -Be 5
        $summary.LossCount | Should -Be 2
        $summary.LossPercent | Should -Be 28.6
        $summary.MinMs | Should -Be 10
        $summary.AvgMs | Should -Be 212
        $summary.MaxMs | Should -Be 700
        $summary.P50Ms | Should -Be 75
        $summary.P95Ms | Should -Be 700
        $fastBucket.Count | Should -Be 1
        $timeoutBucket.Count | Should -Be 2
        $timeoutBucket.Bar.Length | Should -BeGreaterThan 0

        $report = Format-LatencyHistogramReport -Summary $summary
        $report | Should -Match 'Latency histogram for example.com over 7s'
        $report | Should -Match 'P50/P95: 75 ms / 700 ms'
        $report | Should -Match 'Timeout/loss'
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

Describe 'Static route helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIPv4Address',
            'Test-ValidIPv6Address',
            'Get-ApplyValidationResult',
            'Test-ManualRouteRow',
            'Get-RoutePrefixInfo',
            'Get-StaticRouteTarget',
            'Format-StaticRouteRows'
        )
    }

    It 'validates IPv4 and IPv6 route targets' {
        $ipv4 = Get-StaticRouteTarget -DestinationPrefix '10.20.0.0/16' -NextHop '192.168.1.1' -MetricText '25'
        $ipv6 = Get-StaticRouteTarget -DestinationPrefix '2001:db8:10::/64' -NextHop 'fe80::1' -MetricText ''
        $mismatch = Get-StaticRouteTarget -DestinationPrefix '10.20.0.0/16' -NextHop 'fe80::1' -MetricText '25'
        $badPrefix = Get-StaticRouteTarget -DestinationPrefix '10.20.0.0' -NextHop '192.168.1.1' -MetricText '25'
        $badMetric = Get-StaticRouteTarget -DestinationPrefix '10.20.0.0/16' -NextHop '192.168.1.1' -MetricText '10000'

        $ipv4.IsValid | Should -BeTrue
        $ipv4.AddressFamily | Should -Be 'IPv4'
        $ipv4.RouteMetric | Should -Be 25
        $ipv6.IsValid | Should -BeTrue
        $ipv6.AddressFamily | Should -Be 'IPv6'
        $ipv6.RouteMetric | Should -BeNullOrEmpty
        $mismatch.IsValid | Should -BeFalse
        $mismatch.Message | Should -Match 'valid IPv4'
        $badPrefix.IsValid | Should -BeFalse
        $badPrefix.Message | Should -Match 'CIDR format'
        $badMetric.IsValid | Should -BeFalse
        $badMetric.Message | Should -Match '0 to 9999'
    }

    It 'formats manual static route rows' {
        Test-ManualRouteRow -Route ([pscustomobject]@{ RouteProtocol = 'NetMgmt' }) | Should -BeTrue
        Test-ManualRouteRow -Route ([pscustomobject]@{ RouteProtocol = 'Local' }) | Should -BeFalse

        $report = Format-StaticRouteRows -Routes @(
            [pscustomobject]@{ DestinationPrefix = '10.20.0.0/16'; NextHop = '192.168.1.1'; RouteMetric = 25 },
            [pscustomobject]@{ DestinationPrefix = '2001:db8:10::/64'; NextHop = 'fe80::1'; RouteMetric = $null }
        )

        $report | Should -Match 'Destination prefix'
        $report | Should -Match '10.20.0.0/16'
        $report | Should -Match '2001:db8:10::/64'
        (Format-StaticRouteRows -Routes @()) | Should -Match 'No manual static routes'
    }
}

Describe 'App interface guard helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'ConvertTo-AppRoutingSafeRuleText',
            'Get-AppSettings',
            'Get-AppRoutingFirewallRuleName',
            'Get-AppRoutingPolicies',
            'Get-AppRoutingPolicyPlan',
            'Get-AppRoutingPolicyRepairPlan',
            'Get-AppRoutingRuleSpec',
            'Get-ProtectedAppSettingName',
            'Initialize-ProtectedDataApi',
            'New-AppRoutingPolicyRecord',
            'Protect-AppSettingSecret',
            'Remove-AppRoutingStoredPolicy',
            'Save-AppRoutingPolicies',
            'Save-AppRoutingPolicyRecord',
            'Save-AppSetting',
            'Get-KnownSettingNames',
            'Test-SettingsSchema',
            'Backup-SettingsFile',
            'Test-AppRoutingFirewallRuleMatchesSpec',
            'Test-ProtectedAppSettingName',
            'Unprotect-AppSettingSecret',
            'Format-AppRoutingRuleRows'
        )
        $script:AppRoutingRuleGroup = 'NetForge App Routing'
        $script:AppRoutingPolicySettingName = 'AppRoutingPolicies'
        $script:ProtectedSettingNames = @('DiscordWebhookUrl')
        $script:SettingsSchemaVersion = 1
    }

    It 'plans outbound app blocks for every adapter except the allowed interface' {
        $program = Join-Path $TestDrive 'browser.exe'
        Set-Content -LiteralPath $program -Value 'stub' -Encoding ASCII
        $adapters = @(
            [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Clinic VPN'; Status = 'Up' }
        )

        $plan = Get-AppRoutingPolicyPlan -ProgramPath $program -InterfaceAlias 'Clinic VPN' -Adapters $adapters

        $plan.IsValid | Should -BeTrue
        $plan.ProgramPath | Should -Be ([System.IO.Path]::GetFullPath($program))
        $plan.InterfaceAlias | Should -Be 'Clinic VPN'
        $plan.BlockedAliases | Should -Contain 'Wi-Fi'
        $plan.BlockedAliases | Should -Contain 'Ethernet'
        $plan.BlockedAliases | Should -Not -Contain 'Clinic VPN'
        $plan.RuleGroup | Should -Be 'NetForge App Routing'
        Get-AppRoutingFirewallRuleName -ProgramPath $plan.ProgramPath -InterfaceAlias 'Wi-Fi' | Should -Match '^NetForge-AppRoute-[a-f0-9]{16}-Wi-Fi$'
    }

    It 'rejects missing executables and unknown allowed interfaces' {
        $program = Join-Path $TestDrive 'notepad.txt'
        Set-Content -LiteralPath $program -Value 'stub' -Encoding ASCII
        $adapters = @([pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' })

        $badProgram = Get-AppRoutingPolicyPlan -ProgramPath $program -InterfaceAlias 'Wi-Fi' -Adapters $adapters
        $badInterface = Get-AppRoutingPolicyPlan -ProgramPath (Join-Path $TestDrive 'missing.exe') -InterfaceAlias 'VPN' -Adapters $adapters

        $badProgram.IsValid | Should -BeFalse
        $badProgram.Message | Should -Match '\.exe'
        $badInterface.IsValid | Should -BeFalse
        $badInterface.Message | Should -Match 'was not found'
    }

    It 'formats app interface guard rule rows' {
        $rows = Format-AppRoutingRuleRows -Rules @(
            [pscustomobject]@{ DisplayName = 'browser via VPN - block Wi-Fi'; Program = 'C:\Apps\browser.exe'; InterfaceAlias = 'Wi-Fi'; Enabled = 'True' }
        )

        $rows | Should -Match 'browser via VPN'
        $rows | Should -Match 'C:\\Apps\\browser\.exe'
        $rows | Should -Match 'Blocked interface: Wi-Fi'
        (Format-AppRoutingRuleRows -Rules @()) | Should -Match 'No NetForge app interface guards'
    }

    It 'persists app guard policy records by program path and allowed interface' {
        $script:ConfigPath = Join-Path $TestDrive 'NetForge'
        $script:SettingsFile = Join-Path $script:ConfigPath 'settings.json'
        $program = Join-Path $TestDrive 'browser.exe'
        Set-Content -LiteralPath $program -Value 'stub' -Encoding ASCII
        $adapters = @(
            [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Clinic VPN'; Status = 'Up' }
        )
        $plan = Get-AppRoutingPolicyPlan -ProgramPath $program -InterfaceAlias 'Clinic VPN' -Adapters $adapters

        Save-AppRoutingPolicyRecord -Plan $plan

        $settings = Get-Content -Raw -LiteralPath $script:SettingsFile | ConvertFrom-Json
        $storedPolicies = @($settings.AppRoutingPolicies)
        $loadedPolicies = @(Get-AppRoutingPolicies)
        $storedPolicies.Count | Should -Be 1
        $storedPolicies[0].ProgramPath | Should -Be ([System.IO.Path]::GetFullPath($program))
        $storedPolicies[0].InterfaceAlias | Should -Be 'Clinic VPN'
        $loadedPolicies.Count | Should -Be 1
        $loadedPolicies[0].ProgramPath | Should -Be ([System.IO.Path]::GetFullPath($program))

        Remove-AppRoutingStoredPolicy -ProgramPath $program | Should -Be 1
        @(Get-AppRoutingPolicies).Count | Should -Be 0
    }

    It 'plans a missing firewall rule when a new adapter appears' {
        $program = Join-Path $TestDrive 'backup.exe'
        Set-Content -LiteralPath $program -Value 'stub' -Encoding ASCII
        $resolvedProgram = [System.IO.Path]::GetFullPath($program)
        $adapters = @(
            [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Clinic VPN'; Status = 'Up' }
        )
        $existingRules = @(
            [pscustomobject]@{
                RuleName = Get-AppRoutingFirewallRuleName -ProgramPath $resolvedProgram -InterfaceAlias 'Wi-Fi'
                Program = $resolvedProgram
                InterfaceAlias = 'Wi-Fi'
                Enabled = 'True'
                Action = 'Block'
                Direction = 'Outbound'
            }
        )

        $repair = Get-AppRoutingPolicyRepairPlan -Policies @(
            [pscustomobject]@{ ProgramPath = $resolvedProgram; InterfaceAlias = 'Clinic VPN' }
        ) -ExistingRules $existingRules -Adapters $adapters

        $repair.RulesToCreate.Count | Should -Be 1
        $repair.RulesToCreate[0].InterfaceAlias | Should -Be 'Ethernet'
        $repair.RulesToRemove.Count | Should -Be 0
        $repair.HasChanges | Should -BeTrue
    }

    It 'plans stale firewall rule removal when an adapter disappears' {
        $program = Join-Path $TestDrive 'backup.exe'
        Set-Content -LiteralPath $program -Value 'stub' -Encoding ASCII
        $resolvedProgram = [System.IO.Path]::GetFullPath($program)
        $adapters = @(
            [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Clinic VPN'; Status = 'Up' }
        )
        $existingRules = @(
            [pscustomobject]@{
                RuleName = Get-AppRoutingFirewallRuleName -ProgramPath $resolvedProgram -InterfaceAlias 'Wi-Fi'
                Program = $resolvedProgram
                InterfaceAlias = 'Wi-Fi'
                Enabled = 'True'
                Action = 'Block'
                Direction = 'Outbound'
            },
            [pscustomobject]@{
                RuleName = Get-AppRoutingFirewallRuleName -ProgramPath $resolvedProgram -InterfaceAlias 'Ethernet'
                Program = $resolvedProgram
                InterfaceAlias = 'Ethernet'
                Enabled = 'True'
                Action = 'Block'
                Direction = 'Outbound'
            }
        )

        $repair = Get-AppRoutingPolicyRepairPlan -Policies @(
            [pscustomobject]@{ ProgramPath = $resolvedProgram; InterfaceAlias = 'Clinic VPN' }
        ) -ExistingRules $existingRules -Adapters $adapters

        $repair.RulesToCreate.Count | Should -Be 0
        $repair.RulesToRemove.Count | Should -Be 1
        $repair.RulesToRemove[0].InterfaceAlias | Should -Be 'Ethernet'
        $repair.HasChanges | Should -BeTrue
    }

    It 'leaves unchanged app interface guard topology untouched' {
        $program = Join-Path $TestDrive 'backup.exe'
        Set-Content -LiteralPath $program -Value 'stub' -Encoding ASCII
        $resolvedProgram = [System.IO.Path]::GetFullPath($program)
        $adapters = @(
            [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up' },
            [pscustomobject]@{ Name = 'Clinic VPN'; Status = 'Up' }
        )
        $existingRules = foreach ($alias in @('Wi-Fi', 'Ethernet')) {
            [pscustomobject]@{
                RuleName = Get-AppRoutingFirewallRuleName -ProgramPath $resolvedProgram -InterfaceAlias $alias
                Program = $resolvedProgram
                InterfaceAlias = $alias
                Enabled = 'True'
                Action = 'Block'
                Direction = 'Outbound'
            }
        }

        $repair = Get-AppRoutingPolicyRepairPlan -Policies @(
            [pscustomobject]@{ ProgramPath = $resolvedProgram; InterfaceAlias = 'Clinic VPN' }
        ) -ExistingRules $existingRules -Adapters $adapters

        $repair.RulesToCreate.Count | Should -Be 0
        $repair.RulesToRemove.Count | Should -Be 0
        $repair.HasChanges | Should -BeFalse
    }
}

Describe 'Hosts file group helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Get-ApplyValidationResult',
            'Get-HostsSectionBeginMarker',
            'Get-HostsSectionEndMarker',
            'Get-HostsManagedSectionLimits',
            'Test-HostsManagedSectionLimits',
            'Test-HostsGroupName',
            'Test-HostsEntryHostName',
            'ConvertTo-HostsEntryHostNames',
            'Get-HostsEntryTarget',
            'ConvertFrom-HostsManagedSection',
            'ConvertTo-HostsManagedSection',
            'Update-HostsManagedSection',
            'Format-HostsGroupRows'
        )
    }

    It 'validates hosts group entries' {
        $target = Get-HostsEntryTarget -GroupName 'Work' -Address '10.10.0.10' -HostNames 'intranet.local files.local'
        $badGroup = Get-HostsEntryTarget -GroupName 'Bad#Group' -Address '10.10.0.10' -HostNames 'intranet.local'
        $badHost = Get-HostsEntryTarget -GroupName 'Work' -Address '10.10.0.10' -HostNames 'bad_host'

        $target.IsValid | Should -BeTrue
        $target.GroupName | Should -Be 'Work'
        $target.HostNames | Should -Contain 'intranet.local'
        $target.HostNames | Should -Contain 'files.local'
        $badGroup.IsValid | Should -BeFalse
        $badGroup.Message | Should -Match 'group name'
        $badHost.IsValid | Should -BeFalse
        $badHost.Message | Should -Match 'Invalid hostname'
    }

    It 'renders, parses, and replaces the managed hosts section only' {
        $groups = @(
            [pscustomobject]@{
                Name = 'Work'
                Enabled = $true
                Entries = @([pscustomobject]@{ Address = '10.10.0.10'; HostNames = @('intranet.local', 'files.local') })
            },
            [pscustomobject]@{
                Name = 'Lab'
                Enabled = $false
                Entries = @([pscustomobject]@{ Address = '192.168.50.5'; HostNames = @('lab.local') })
            }
        )

        $section = ConvertTo-HostsManagedSection -Groups $groups
        $section | Should -Match ([regex]::Escape((Get-HostsSectionBeginMarker)))
        $section | Should -Match 'NetForge group: Lab \| disabled'
        $section | Should -Match '# 192.168.50.5 lab.local'

        $parsed = ConvertFrom-HostsManagedSection -Text "127.0.0.1 localhost`r`n$section`r`n# unmanaged"
        $parsed.Count | Should -Be 2
        $parsed[0].Name | Should -Be 'Work'
        $parsed[0].Entries[0].HostNames | Should -Contain 'files.local'
        $parsed[1].Enabled | Should -BeFalse

        $updated = Update-HostsManagedSection -CurrentText "127.0.0.1 localhost`r`n# unmanaged" -Groups $groups
        $updated | Should -Match '127.0.0.1 localhost'
        $updated | Should -Match '# unmanaged'
        $updated | Should -Match 'NetForge group: Work'

        $replacement = Update-HostsManagedSection -CurrentText $updated -Groups @()
        $replacement | Should -Match '127.0.0.1 localhost'
        $replacement | Should -Not -Match 'NetForge group: Work'
        (Format-HostsGroupRows -Groups $groups) | Should -Match 'Work \(1 entry\)'
        (Format-HostsGroupRows -Groups @()) | Should -Match 'No NetForge-managed hosts groups'
    }

    It 'replaces an existing managed section without duplicating' {
        $groups = @(
            [pscustomobject]@{
                Name = 'Initial'
                Enabled = $true
                Entries = @([pscustomobject]@{ Address = '10.0.0.1'; HostNames = @('server.local') })
            }
        )

        $initial = Update-HostsManagedSection -CurrentText "127.0.0.1 localhost" -Groups $groups
        $initial | Should -Match 'NetForge group: Initial'

        $updated = @(
            [pscustomobject]@{
                Name = 'Replaced'
                Enabled = $true
                Entries = @([pscustomobject]@{ Address = '10.0.0.2'; HostNames = @('new.local') })
            }
        )

        $result = Update-HostsManagedSection -CurrentText $initial -Groups $updated
        $result | Should -Match '127.0.0.1 localhost'
        $result | Should -Match 'NetForge group: Replaced'
        $result | Should -Not -Match 'NetForge group: Initial'

        $beginCount = ([regex]::Matches($result, [regex]::Escape((Get-HostsSectionBeginMarker)))).Count
        $endCount = ([regex]::Matches($result, [regex]::Escape((Get-HostsSectionEndMarker)))).Count
        $beginCount | Should -Be 1
        $endCount | Should -Be 1
    }

    It 'handles empty hosts file gracefully' {
        $groups = @(
            [pscustomobject]@{
                Name = 'Test'
                Enabled = $true
                Entries = @([pscustomobject]@{ Address = '10.0.0.1'; HostNames = @('test.local') })
            }
        )

        $result = Update-HostsManagedSection -CurrentText "" -Groups $groups
        $result | Should -Match 'NetForge group: Test'
        $result | Should -Match '10.0.0.1 test.local'
    }

    It 'rejects groups that exceed the per-group entry limit' {
        $limits = Get-HostsManagedSectionLimits
        $entries = @(1..($limits.MaxEntriesPerGroup + 1) | ForEach-Object {
            [pscustomobject]@{ Address = '127.0.0.1'; HostNames = @("host$_.example") }
        })
        $groups = @([pscustomobject]@{ Name = 'Oversized'; Enabled = $true; Entries = $entries })

        { ConvertTo-HostsManagedSection -Groups $groups } | Should -Throw "*maximum of $($limits.MaxEntriesPerGroup) entries*"
    }

    It 'rejects excessive group and total entry counts' {
        $limits = Get-HostsManagedSectionLimits
        $tooManyGroups = @(1..($limits.MaxGroups + 1) | ForEach-Object {
            [pscustomobject]@{ Name = "Group$_"; Enabled = $true; Entries = @() }
        })
        $groupResult = Test-HostsManagedSectionLimits -Groups $tooManyGroups

        $fullEntries = @(1..$limits.MaxEntriesPerGroup | ForEach-Object {
            [pscustomobject]@{ Address = '127.0.0.1'; HostNames = @("host$_.example") }
        })
        $tooManyEntries = @(1..9 | ForEach-Object {
            [pscustomobject]@{ Name = "Group$_"; Enabled = $true; Entries = $fullEntries }
        })
        $entryResult = Test-HostsManagedSectionLimits -Groups $tooManyEntries

        $groupResult.IsValid | Should -BeFalse
        $groupResult.Message | Should -Match 'maximum of 64 groups'
        $entryResult.IsValid | Should -BeFalse
        $entryResult.Message | Should -Match 'maximum of 2048 total entries'
    }

    It 'limits the number of hostnames on a single entry' {
        $limits = Get-HostsManagedSectionLimits
        $hostNames = (1..($limits.MaxHostNamesPerEntry + 1) | ForEach-Object { "host$_.example" }) -join ' '

        $result = Get-HostsEntryTarget -GroupName 'Work' -Address '127.0.0.1' -HostNames $hostNames

        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match "at most $($limits.MaxHostNamesPerEntry) hostnames"
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

Describe 'Reachability wizard helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Resolve-ReachabilityTarget',
            'Format-ReachabilityProbeReport'
        )
    }

    It 'parses URLs and derives default HTTPS ports' {
        $target = Resolve-ReachabilityTarget -Target 'https://example.com/path'

        $target.IsValid | Should -BeTrue
        $target.Host | Should -Be 'example.com'
        $target.Port | Should -Be 443
        $target.Scheme | Should -Be 'https'
    }

    It 'parses host port targets and rejects path-like hosts' {
        $target = Resolve-ReachabilityTarget -Target 'server.local:3389'
        $target.IsValid | Should -BeTrue
        $target.Host | Should -Be 'server.local'
        $target.Port | Should -Be 3389

        $invalid = Resolve-ReachabilityTarget -Target 'server.local/share'
        $invalid.IsValid | Should -BeFalse
        $invalid.Message | Should -Match 'host cannot contain'
    }

    It 'formats DNS gateway route firewall and MTU sections' {
        $report = Format-ReachabilityProbeReport -Result ([pscustomobject]@{
            DisplayTarget = 'server.local:3389'
            CheckedAt = '2026-06-29T12:00:00.0000000-04:00'
            DnsStatus = 'OK'
            DnsMessage = 'server.local resolved to 1 address.'
            Addresses = @('10.10.10.20')
            GatewayStatus = 'OK'
            GatewayMessage = 'Default gateway 10.10.10.1 answered.'
            RouteStatus = 'WARN'
            RouteMessage = 'Target did not answer ICMP.'
            PortStatus = 'OK'
            PortMessage = 'TCP 3389 connected in 15 ms.'
            MtuStatus = 'WARN'
            MtuMessage = '1472-byte DF probe failed.'
            Summary = @('MTU result is inconclusive.')
        })

        $report | Should -Match '1\. DNS'
        $report | Should -Match '2\. Gateway'
        $report | Should -Match '3\. Route'
        $report | Should -Match '4\. Firewall / Port'
        $report | Should -Match '5\. MTU'
        $report | Should -Match 'TCP 3389 connected'
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

Describe 'Diagnostics export redaction helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Add-DiagnosticsRedactionCount',
            'Add-DiagnosticsRedactionFile',
            'Add-DiagnosticsValue',
            'Get-DiagnosticsProxyTokens',
            'Get-DiagnosticsRedactionValues',
            'New-DiagnosticsRedactionReport',
            'ConvertTo-DiagnosticsRedactedText',
            'New-DiagnosticsExportManifest',
            'Format-DiagnosticsExportPreview'
        )
        $script:AppVersion = '1.50.0'
    }

    It 'redacts webhook proxy mapped-drive SSID gateway MAC adapter and local path values' {
        $profile = [pscustomobject]@{
            MatchSSID = 'ClinicPrivate'
            MatchGatewayMac = '00-11-22-33-44-55'
            ProxyServer = 'proxy.clinic.local:8080'
        }
        $adapter = [pscustomobject]@{
            Name = 'Clinic Ethernet'
            InterfaceDescription = 'Intel Sensitive NIC'
            MacAddress = 'AA-BB-CC-DD-EE-FF'
        }
        $values = Get-DiagnosticsRedactionValues -Profiles @($profile) -Adapter $adapter -ConfigPath 'C:\Users\matt\AppData\Roaming\NetForge' -ProfilesPath 'D:\NetForgeProfiles' -LogsPath 'C:\Users\matt\AppData\Roaming\NetForge\Logs'
        $report = New-DiagnosticsRedactionReport -PrivacyMode:$true
        $raw = @(
            'https://discord.com/api/webhooks/123456789012345678/abc.DEF_ghi-jkl',
            'proxy.clinic.local:8080',
            '\\fileserver\share',
            'ClinicPrivate',
            '00-11-22-33-44-55',
            'AA-BB-CC-DD-EE-FF',
            'Clinic Ethernet',
            'C:\Users\matt\AppData\Roaming\NetForge'
        ) -join "`n"

        $redacted = ConvertTo-DiagnosticsRedactedText -Text $raw -Values $values -Report $report -PrivacyMode:$true

        $redacted | Should -Not -Match 'api/webhooks/123456789012345678/abc'
        $redacted | Should -Not -Match 'proxy\.clinic\.local'
        $redacted | Should -Not -Match 'fileserver'
        $redacted | Should -Not -Match 'ClinicPrivate'
        $redacted | Should -Not -Match '00-11-22-33-44-55'
        $redacted | Should -Not -Match 'AA-BB-CC-DD-EE-FF'
        $redacted | Should -Not -Match 'Clinic Ethernet'
        $redacted | Should -Not -Match 'C:\\Users\\matt'
        $redacted | Should -Match '\[redacted-proxy\]'
        $redacted | Should -Match '\[redacted-ssid\]'
        $redacted | Should -Match '\[redacted-mac\]'
        $report.Categories.WebhookUrls | Should -BeGreaterThan 0
        $report.Categories.ProxyServers | Should -BeGreaterThan 0
        $report.Categories.MappedDrivePaths | Should -BeGreaterThan 0
        $report.Categories.SSIDs | Should -BeGreaterThan 0
        $report.Categories.GatewayMacs | Should -BeGreaterThan 0
        $report.Categories.LocalPaths | Should -BeGreaterThan 0
        $report.Categories.AdapterNames | Should -BeGreaterThan 0
    }

    It 'leaves diagnostics text unchanged when privacy mode is off' {
        $values = Get-DiagnosticsRedactionValues -Profiles @([pscustomobject]@{ MatchSSID = 'ClinicPrivate'; ProxyServer = 'proxy.clinic.local:8080' })
        $report = New-DiagnosticsRedactionReport -PrivacyMode:$false
        $raw = 'ClinicPrivate uses proxy.clinic.local:8080'

        ConvertTo-DiagnosticsRedactedText -Text $raw -Values $values -Report $report -PrivacyMode:$false | Should -Be $raw
        $report.Categories.SSIDs | Should -Be 0
        $report.Categories.ProxyServers | Should -Be 0
    }

    It 'builds a diagnostics export preview manifest' {
        $manifest = New-DiagnosticsExportManifest -DestinationPath 'C:\Temp\diag.zip' -PrivacyMode:$true -LogFiles @('a.log', 'b.log') -ProfileFiles @('clinic.json')
        $preview = Format-DiagnosticsExportPreview -Manifest $manifest

        $manifest.Destination | Should -Be 'diag.zip'
        $manifest.PrivacyMode | Should -BeTrue
        ($manifest.Includes | Where-Object { $_.Name -eq 'Logs' }).Count | Should -Be 2
        ($manifest.Includes | Where-Object { $_.Name -eq 'Profiles' }).Count | Should -Be 1
        $preview | Should -Match 'Diagnostics export preview'
        $preview | Should -Match 'redaction-report\.json'
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

Describe 'WLAN interface status parsing' {
    BeforeAll {
        Import-NetForgeFunction -Name @('ConvertFrom-WlanInterfaceOutput')
    }

    It 'parses connected interface details and infers a missing band' {
        $output = @'
    Name                   : Wi-Fi
    State                  : connected
    SSID                   : Clinic Wireless
    BSSID                  : 00:11:22:33:44:55
    Authentication         : WPA2-Personal
    Radio type             : 802.11ac
    Channel                : 149
    Receive rate (Mbps)    : 866.7
    Signal                 : 82%
'@

        $result = ConvertFrom-WlanInterfaceOutput -Output $output

        $result.SSID | Should -Be 'Clinic Wireless'
        $result.Signal | Should -Be '82%'
        $result.Channel | Should -Be '149'
        $result.Band | Should -Be '5 GHz'
        $result.Authentication | Should -Be 'WPA2-Personal'
        $result.Speed | Should -Be '866.7 Mbps'
    }

    It 'returns display fallbacks for empty output' {
        $result = ConvertFrom-WlanInterfaceOutput -Output ''

        $result.SSID | Should -Be '--'
        $result.Signal | Should -Be '--'
        $result.Speed | Should -Be '--'
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
            'Get-KnownSettingNames',
            'Test-SettingsSchema',
            'Backup-SettingsFile',
            'Get-AppSettings',
            'Save-AppSetting',
            'Test-ProfileStorePath',
            'Get-ProfileStoreMigrationPlan',
            'Write-ProfileStoreBackupManifest'
        )
        $script:ProfileSchemaVersion = 3
        $versionMetadata = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'version.json') | ConvertFrom-Json
        $script:AppVersion = [string]$versionMetadata.Version
        $script:ProtectedSettingNames = @('DiscordWebhookUrl')
        $script:SettingsSchemaVersion = 1
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

Describe 'RDAP lookup helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Select-RdapBootstrapEndpoint',
            'Format-RdapLookupReport'
        )
    }

    It 'selects the correct RDAP endpoint from bootstrap data' {
        $bootstrap = [pscustomobject]@{
            services = @(
                @(
                    @("1.0.0.0/8"),
                    @("https://rdap.arin.net/registry/")
                ),
                @(
                    @("8.0.0.0/8"),
                    @("https://rdap.arin.net/registry/")
                )
            )
        }

        $endpoint = Select-RdapBootstrapEndpoint -IpAddress '8.8.8.8' -BootstrapData $bootstrap

        $endpoint | Should -Be 'https://rdap.arin.net/registry/'
    }

    It 'returns null for unmatched IP addresses' {
        $bootstrap = [pscustomobject]@{
            services = @(
                @(
                    @("10.0.0.0/8"),
                    @("https://rdap.example.com/")
                )
            )
        }

        $endpoint = Select-RdapBootstrapEndpoint -IpAddress '192.168.1.1' -BootstrapData $bootstrap

        $endpoint | Should -BeNullOrEmpty
    }

    It 'formats an RDAP response with entity and CIDR data' {
        $rdapResponse = [pscustomobject]@{
            name = 'GOOGLE'
            handle = 'NET-8-8-8-0-1'
            type = 'DIRECT ALLOCATION'
            country = 'US'
            cidr0_cidrs = @([pscustomobject]@{ v4prefix = '8.8.8.0'; length = 24 })
            entities = @(
                [pscustomobject]@{
                    roles = @('registrant')
                    vcardArray = @('vcard', @(
                        @('fn', @{}, 'text', 'Google LLC')
                    ))
                }
            )
        }

        $report = Format-RdapLookupReport -QueryAddress '8.8.8.8' -RdapResponse $rdapResponse

        $report | Should -Match 'RDAP lookup: 8.8.8.8'
        $report | Should -Match 'Network: GOOGLE'
        $report | Should -Match 'Country: US'
        $report | Should -Match '8.8.8.0/24'
    }

    It 'handles null RDAP response gracefully' {
        $report = Format-RdapLookupReport -QueryAddress '10.0.0.1' -RdapResponse $null

        $report | Should -Match 'No RDAP data'
    }
}

Describe 'DNS resolver benchmark' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Format-DnsBenchmarkResult',
            'Format-DnsBenchmarkReport'
        )
    }

    It 'formats a benchmark result with latency stats' {
        $result = Format-DnsBenchmarkResult -Server 'Cloudflare' -Queries 5 -Successes 5 -Failures 0 -MinMs 12.3 -AvgMs 18.7 -MaxMs 25.1

        $result.Server | Should -Be 'Cloudflare'
        $result.FailRate | Should -Be 0
        $result.MinMs | Should -Be 12.3
        $result.AvgMs | Should -Be 18.7
    }

    It 'formats a benchmark report sorted by avg latency' {
        $results = @(
            (Format-DnsBenchmarkResult -Server 'SlowDNS' -Queries 5 -Successes 5 -Failures 0 -MinMs 50 -AvgMs 80 -MaxMs 120),
            (Format-DnsBenchmarkResult -Server 'FastDNS' -Queries 5 -Successes 5 -Failures 0 -MinMs 5 -AvgMs 10 -MaxMs 15)
        )

        $report = Format-DnsBenchmarkReport -Results $results

        $report | Should -Match 'Fastest: FastDNS'
        $report | Should -Match 'SlowDNS'
    }

    It 'handles empty benchmark results' {
        $report = Format-DnsBenchmarkReport -Results @()

        $report | Should -Be 'No benchmark results.'
    }
}

Describe 'Configuration export and import preview' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-ConfigExportManifest',
            'Get-ProfileImportPreview',
            'Format-ImportPreviewReport'
        )
    }

    It 'builds a full export manifest with no suppressed fields' {
        $profiles = @(
            [pscustomobject]@{ Name = 'Work'; AutoApply = $true },
            [pscustomobject]@{ Name = 'Home'; AutoApply = $false }
        )

        $manifest = Get-ConfigExportManifest -Profiles $profiles -Mode 'full'

        $manifest.Mode | Should -Be 'full'
        $manifest.ProfileCount | Should -Be 2
        $manifest.SuppressedFields.Count | Should -Be 0
    }

    It 'builds a shareable export manifest with suppressed privacy fields' {
        $profiles = @([pscustomobject]@{ Name = 'Work'; AutoApply = $true })

        $manifest = Get-ConfigExportManifest -Profiles $profiles -Mode 'shareable'

        $manifest.Mode | Should -Be 'shareable'
        $manifest.SuppressedFields | Should -Contain 'MatchGatewayMac'
        $manifest.SuppressedFields | Should -Contain 'ProxyServer'
    }

    It 'previews import with accepted, conflicting, and rejected profiles' {
        $incoming = @(
            [pscustomobject]@{ Name = 'NewProfile' },
            [pscustomobject]@{ Name = 'Work' },
            [pscustomobject]@{ Name = '' }
        )

        $preview = Get-ProfileImportPreview -IncomingProfiles $incoming -ExistingProfileNames @('Work', 'Home')

        $preview.AcceptedCount | Should -Be 1
        $preview.ConflictingCount | Should -Be 1
        $preview.RejectedCount | Should -Be 1
        $preview.Conflicting[0].Name | Should -Be 'Work'
    }

    It 'formats an import preview report' {
        $preview = [pscustomobject]@{
            AcceptedCount = 2
            ConflictingCount = 1
            RejectedCount = 0
            Accepted = @([pscustomobject]@{ Name = 'A' }, [pscustomobject]@{ Name = 'B' })
            Conflicting = @([pscustomobject]@{ Name = 'C'; Reason = 'Profile already exists.' })
            Rejected = @()
        }

        $report = Format-ImportPreviewReport -Preview $preview

        $report | Should -Match 'Accept: 2'
        $report | Should -Match 'Conflict: 1'
        $report | Should -Match 'already exist'
    }
}

Describe 'Capability matrix' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-CapabilityAvailable',
            'Format-CapabilityMatrixReport'
        )
    }

    It 'detects available and missing cmdlets' {
        $available = Test-CapabilityAvailable -Name 'Get-Date' -Type 'Cmdlet'
        $missing = Test-CapabilityAvailable -Name 'NoSuchCmdlet-12345' -Type 'Cmdlet'

        $available.Available | Should -BeTrue
        $missing.Available | Should -BeFalse
        $missing.Detail | Should -Be 'Not found'
    }

    It 'formats a capability matrix report' {
        $checks = @(
            [pscustomobject]@{ Name = 'Admin'; Type = 'Admin'; Available = $true; Detail = 'Elevated' },
            [pscustomobject]@{ Name = 'pktmon'; Type = 'Executable'; Available = $false; Detail = 'Not found' }
        )

        $report = Format-CapabilityMatrixReport -Checks $checks

        $report | Should -Match '\[OK\] Admin'
        $report | Should -Match '\[UNAVAILABLE\] pktmon'
        $report | Should -Match '1 capability'
    }
}

Describe 'Network List Manager match' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Test-NetworkListManagerMatch')
    }

    It 'matches a profile by network name' {
        $profile = [pscustomobject]@{ MatchNetworkName = 'Corporate LAN'; MatchNetworkId = '' }
        $networks = @([pscustomobject]@{ Name = 'Corporate LAN'; NetworkId = 'abc-123'; Category = 'DomainAuthenticated' })

        $result = Test-NetworkListManagerMatch -ProfileData $profile -NlmNetworks $networks

        $result.Matched | Should -BeTrue
        $result.MatchedBy | Should -Match 'NetworkName'
    }

    It 'does not match when no NLM rules are set' {
        $profile = [pscustomobject]@{ Name = 'Basic' }
        $networks = @([pscustomobject]@{ Name = 'Office'; NetworkId = 'abc'; Category = 'Private' })

        $result = Test-NetworkListManagerMatch -ProfileData $profile -NlmNetworks $networks

        $result.Matched | Should -BeFalse
    }

    It 'reports no match when networks do not align' {
        $profile = [pscustomobject]@{ MatchNetworkName = 'Home WiFi'; MatchNetworkId = '' }
        $networks = @([pscustomobject]@{ Name = 'Office LAN'; NetworkId = 'xyz'; Category = 'Private' })

        $result = Test-NetworkListManagerMatch -ProfileData $profile -NlmNetworks $networks

        $result.Matched | Should -BeFalse
    }
}

Describe 'Auto-apply inspector' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'ConvertTo-CleanMacAddress',
            'Format-AutoApplyInspectorLine',
            'Format-AutoApplyInspectorReport'
        )
    }

    It 'reports matched status when SSID matches' {
        $profile = [pscustomobject]@{ Name = 'Work'; AutoApply = $true; MatchSSID = 'CorpWiFi'; MatchGatewayMac = '' }
        $signature = [pscustomobject]@{ SSID = 'CorpWiFi'; Gateway = '10.0.0.1'; GatewayMac = '00-11-22-33-44-55' }

        $line = Format-AutoApplyInspectorLine -ProfileData $profile -Signature $signature

        $line.Status | Should -Be 'Matched'
        $line.Reason | Should -Match 'SSID'
    }

    It 'reports no-match when rules do not match current network' {
        $profile = [pscustomobject]@{ Name = 'Home'; AutoApply = $true; MatchSSID = 'HomeNet'; MatchGatewayMac = '' }
        $signature = [pscustomobject]@{ SSID = 'CoffeeShop'; Gateway = '192.168.1.1'; GatewayMac = 'AA-BB-CC-DD-EE-FF' }

        $line = Format-AutoApplyInspectorLine -ProfileData $profile -Signature $signature

        $line.Status | Should -Be 'NoMatch'
        $line.Reason | Should -Match 'SSID=HomeNet'
    }

    It 'reports disabled for profiles with auto-apply off' {
        $profile = [pscustomobject]@{ Name = 'Manual'; AutoApply = $false; MatchSSID = ''; MatchGatewayMac = '' }
        $signature = [pscustomobject]@{ SSID = 'Any'; Gateway = '10.0.0.1'; GatewayMac = '' }

        $line = Format-AutoApplyInspectorLine -ProfileData $profile -Signature $signature

        $line.Status | Should -Be 'Disabled'
    }

    It 'formats a complete inspector report with network signature' {
        $lines = @(
            [pscustomobject]@{ Name = 'Work'; Status = 'Active'; Reason = 'Matched by SSID.' },
            [pscustomobject]@{ Name = 'Home'; Status = 'NoMatch'; Reason = 'Rules: SSID=HomeNet' }
        )
        $signature = [pscustomobject]@{ SSID = 'CorpWiFi'; Gateway = '10.0.0.1'; GatewayMac = '00-11-22-33-44-55' }

        $report = Format-AutoApplyInspectorReport -Lines $lines -Signature $signature -LastAppliedName 'Work'

        $report | Should -Match 'SSID: CorpWiFi'
        $report | Should -Match 'Last applied: Work'
        $report | Should -Match '\[ACTIVE\] Work'
        $report | Should -Match '\[--\] Home'
    }
}

Describe 'DHCP lease diagnostics' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Format-DhcpLeaseInfo')
    }

    It 'formats DHCP server with lease timing' {
        $now = Get-Date
        $cim = [pscustomobject]@{
            DHCPServer = '192.168.1.1'
            DHCPLeaseObtained = $now.AddHours(-12)
            DHCPLeaseExpires = $now.AddHours(12)
        }

        $result = Format-DhcpLeaseInfo -CimConfig $cim

        $result.ServerText | Should -Match '192\.168\.1\.1'
        $result.ServerText | Should -Match 'Lease:'
        $result.LeaseText | Should -Not -BeNullOrEmpty
    }

    It 'reports expired lease' {
        $now = Get-Date
        $cim = [pscustomobject]@{
            DHCPServer = '10.0.0.1'
            DHCPLeaseObtained = $now.AddHours(-48)
            DHCPLeaseExpires = $now.AddHours(-1)
        }

        $result = Format-DhcpLeaseInfo -CimConfig $cim

        $result.ServerText | Should -Match 'EXPIRED'
    }

    It 'handles missing CIM config gracefully' {
        $result = Format-DhcpLeaseInfo -CimConfig $null

        $result.ServerText | Should -Be '--'
        $result.LeaseText | Should -BeNullOrEmpty
    }

    It 'handles DHCP server with no lease fields' {
        $cim = [pscustomobject]@{
            DHCPServer = '192.168.1.1'
        }

        $result = Format-DhcpLeaseInfo -CimConfig $cim

        $result.ServerText | Should -Be '192.168.1.1'
        $result.LeaseText | Should -BeNullOrEmpty
    }
}

Describe 'Settings schema validation' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-KnownSettingNames',
            'Test-SettingsSchema'
        )
        $script:SettingsSchemaVersion = 1
    }

    It 'validates a well-formed settings hash' {
        $settings = [ordered]@{
            SettingsSchemaVersion = 1
            UiTheme = 'GitHub Dark'
            CompactMode = 'false'
            PublicIpLookupEnabled = 'true'
            UpdatedAt = '2026-06-30T12:00:00Z'
        }

        $result = Test-SettingsSchema -Settings $settings

        $result.IsValid | Should -BeTrue
        $result.SchemaVersion | Should -Be 1
        $result.Issues.Count | Should -Be 0
    }

    It 'detects unknown setting keys' {
        $settings = [ordered]@{
            SettingsSchemaVersion = 1
            UiTheme = 'GitHub Dark'
            SomeUnknownKey = 'value'
        }

        $result = Test-SettingsSchema -Settings $settings

        $result.IsValid | Should -BeFalse
        ($result.Issues -join ' ') | Should -Match 'Unknown setting key'
    }

    It 'warns when schema version exceeds supported' {
        $settings = [ordered]@{
            SettingsSchemaVersion = 99
        }

        $result = Test-SettingsSchema -Settings $settings

        $result.IsValid | Should -BeFalse
        ($result.Issues -join ' ') | Should -Match 'newer than supported'
    }

    It 'handles legacy settings without schema version' {
        $settings = [ordered]@{
            UiTheme = 'Catppuccin Mocha'
            CompactMode = 'true'
        }

        $result = Test-SettingsSchema -Settings $settings

        $result.SchemaVersion | Should -Be 0
        $result.IsValid | Should -BeTrue
    }

    It 'accepts empty settings hash' {
        $settings = [ordered]@{}
        $result = Test-SettingsSchema -Settings $settings
        $result.IsValid | Should -BeTrue
        $result.SchemaVersion | Should -Be 0
    }

    It 'accepts all known setting keys' {
        $known = Get-KnownSettingNames
        $settings = [ordered]@{}
        foreach ($k in $known) { $settings[$k] = 'test' }
        $result = Test-SettingsSchema -Settings $settings
        $result.IsValid | Should -BeTrue
    }

    It 'ignores SettingsReadWarning key' {
        $settings = [ordered]@{
            SettingsReadWarning = 'test warning'
            UiTheme = 'Nord'
        }
        $result = Test-SettingsSchema -Settings $settings
        $result.IsValid | Should -BeTrue
    }
}

Describe 'Vendored dependency manifest' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Test-VendoredDependencyManifest')
    }

    It 'validates real vendored DLLs and license files' {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $manifestPath = Join-Path $repoRoot 'lib\dependencies.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            Set-ItResult -Skipped -Because 'dependencies.json not found'
            return
        }

        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $result = Test-VendoredDependencyManifest -Manifest $manifest -LibDirectory (Join-Path $repoRoot 'lib') -LicenseDirectory (Join-Path $repoRoot 'licenses')

        $result.Issues.Count | Should -Be 0
        $result.Entries.Count | Should -BeGreaterThan 0
        foreach ($entry in $result.Entries) {
            $entry.VersionMatch | Should -BeTrue -Because "$($entry.Name) DLL version should match manifest"
        }
    }

    It 'detects version drift and missing files' {
        $manifest = [pscustomobject]@{
            SchemaVersion = 1
            Dependencies = @(
                [pscustomobject]@{
                    Name = 'FakeLib'
                    FileName = 'FakeLib.dll'
                    Version = '9.9.9.9'
                    License = 'MIT'
                    LicenseFile = 'FakeLib-LICENSE.txt'
                    SourceUrl = 'https://example.com'
                    NuGetId = 'FakeLib'
                }
            )
        }

        $result = Test-VendoredDependencyManifest -Manifest $manifest -LibDirectory $TestDrive -LicenseDirectory $TestDrive

        $result.Issues.Count | Should -BeGreaterThan 0
        ($result.Issues -join ' ') | Should -Match 'not found'
    }
}

Describe 'DNS catalog freshness helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-DnsProviderEntry',
            'Format-DnsCatalogFreshnessReport'
        )
    }

    It 'detects capability-endpoint mismatches in a provider entry' {
        $provider = [pscustomobject]@{
            Name = 'Test Provider'
            Category = 'Public'
            Description = 'Test'
            IPv4 = @('1.2.3.4')
            IPv6 = @()
            DoH = 'https://dns.test/dns-query'
            DoT = ''
            DoQ = ''
            Capabilities = @('ipv4', 'ipv6')
        }

        $issues = @(Test-DnsProviderEntry -Provider $provider)

        $issues.Count | Should -BeGreaterThan 0
        ($issues -join ' ') | Should -Match 'ipv6 capability but has no IPv6'
        ($issues -join ' ') | Should -Match 'DoH template but missing doh capability'
    }

    It 'reports no issues for a well-formed provider entry' {
        $provider = [pscustomobject]@{
            Name = 'Good Provider'
            Category = 'Public'
            Description = 'Test'
            IPv4 = @('1.1.1.1')
            IPv6 = @('2606:4700::1111')
            DoH = 'https://dns.test/dns-query'
            DoT = 'dns.test:853'
            DoQ = ''
            Capabilities = @('ipv4', 'ipv6', 'doh', 'dot', 'public')
        }

        $issues = @(Test-DnsProviderEntry -Provider $provider)

        $issues.Count | Should -Be 0
    }

    It 'formats a freshness report with issues' {
        $report = Format-DnsCatalogFreshnessReport -TotalProviders 42 -Issues @('Test issue one', 'Test issue two') -CatalogHash 'abc123'

        $report | Should -Match 'Providers: 42'
        $report | Should -Match 'Hash: abc123'
        $report | Should -Match 'Issues \(2\)'
        $report | Should -Match 'Test issue one'
    }

    It 'formats a clean freshness report' {
        $report = Format-DnsCatalogFreshnessReport -TotalProviders 42 -Issues @() -CatalogHash 'abc123'

        $report | Should -Match 'No capability/endpoint mismatches'
    }
}

Describe 'Release check helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Compare-VersionStrings',
            'Select-ReleaseAssets',
            'Format-ReleaseCheckReport'
        )
    }

    It 'detects update available when latest is newer' {
        $result = Compare-VersionStrings -Current '1.50.0' -Latest 'v1.51.0'

        $result.Result | Should -Be 'UpdateAvailable'
        $result.Message | Should -Match '1\.50\.0 -> 1\.51\.0'
    }

    It 'reports current when versions match' {
        $result = Compare-VersionStrings -Current '1.51.0' -Latest 'v1.51.0'

        $result.Result | Should -Be 'Current'
        $result.Message | Should -Match 'latest version'
    }

    It 'reports ahead when current exceeds latest' {
        $result = Compare-VersionStrings -Current '1.52.0' -Latest 'v1.51.0'

        $result.Result | Should -Be 'Ahead'
        $result.Message | Should -Match 'ahead'
    }

    It 'handles missing version strings gracefully' {
        $result = Compare-VersionStrings -Current '' -Latest 'v1.51.0'

        $result.Result | Should -Be 'Unknown'
    }

    It 'selects zip and sha256 assets from a release' {
        $assets = @(
            [pscustomobject]@{ name = 'NetForge-v1.51.0.zip'; size = 2000000; browser_download_url = 'https://example.com/zip' },
            [pscustomobject]@{ name = 'NetForge-v1.51.0.zip.sha256'; size = 128; browser_download_url = 'https://example.com/sha' }
        )

        $selected = Select-ReleaseAssets -Assets $assets

        $selected.ZipAsset | Should -Not -BeNullOrEmpty
        $selected.ZipAsset.Name | Should -Be 'NetForge-v1.51.0.zip'
        $selected.ChecksumAsset | Should -Not -BeNullOrEmpty
        $selected.ChecksumAsset.Name | Should -Be 'NetForge-v1.51.0.zip.sha256'
    }

    It 'returns null assets when release has no zip or checksum' {
        $selected = Select-ReleaseAssets -Assets @()

        $selected.ZipAsset | Should -BeNullOrEmpty
        $selected.ChecksumAsset | Should -BeNullOrEmpty
    }

    It 'formats a complete release check report' {
        $releaseData = [pscustomobject]@{ TagName = 'v1.51.0'; PublishedAt = '2026-06-29'; HtmlUrl = 'https://example.com' }
        $comparison = [pscustomobject]@{ Result = 'Current'; Message = 'Running latest version (1.51.0).' }
        $assets = [pscustomobject]@{
            ZipAsset = [pscustomobject]@{ Name = 'NetForge-v1.51.0.zip'; Size = 2097152; DownloadUrl = 'https://example.com/zip' }
            ChecksumAsset = [pscustomobject]@{ Name = 'NetForge-v1.51.0.zip.sha256'; Size = 128; DownloadUrl = 'https://example.com/sha' }
        }

        $report = Format-ReleaseCheckReport -CurrentVersion '1.51.0' -ReleaseData $releaseData -VersionComparison $comparison -Assets $assets

        $report | Should -Match 'Current version: 1.51.0'
        $report | Should -Match 'Latest release: v1.51.0'
        $report | Should -Match 'Running latest version'
        $report | Should -Match 'NetForge-v1.51.0.zip'
        $report | Should -Match 'NetForge-v1.51.0.zip.sha256'
    }
}

Describe 'DoQ proxy trust and session helpers' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Format-DoqProxyTrustLines',
            'Get-DoqProxyLogPaths',
            'Format-DoqProxyHealthState'
        )
    }

    It 'formats trust lines with all fields populated' {
        $report = [pscustomobject]@{
            FullPath = 'C:\tools\dnsproxy.exe'
            Version = 'dnsproxy version 0.73.5'
            SHA256 = 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2'
            Authenticode = 'Valid'
            ModifiedTime = '2026-06-15T10:00:00.0000000-04:00'
        }

        $lines = Format-DoqProxyTrustLines -Report $report

        $lines.Count | Should -Be 5
        ($lines -join "`n") | Should -Match 'Path: C:\\tools\\dnsproxy.exe'
        ($lines -join "`n") | Should -Match 'Version: dnsproxy version 0.73.5'
        ($lines -join "`n") | Should -Match 'SHA256: A1B2C3D4'
        ($lines -join "`n") | Should -Match 'Authenticode: Valid'
        ($lines -join "`n") | Should -Match 'Modified:'
    }

    It 'formats trust lines with no fields populated' {
        $report = [pscustomobject]@{
            FullPath = $null
            Version = $null
            SHA256 = $null
            Authenticode = $null
            ModifiedTime = $null
        }

        $lines = @(Format-DoqProxyTrustLines -Report $report)

        $lines.Count | Should -Be 1
        $lines[0] | Should -Be 'No binary trust information available.'
    }

    It 'builds timestamped stdout and stderr log paths' {
        $logPaths = Get-DoqProxyLogPaths -LogsDirectory 'C:\AppData\NetForge\Logs' -Timestamp ([datetime]'2026-06-29T09:30:45')

        $logPaths.StdoutPath | Should -Be 'C:\AppData\NetForge\Logs\doqproxy-stdout-20260629-093045.log'
        $logPaths.StderrPath | Should -Be 'C:\AppData\NetForge\Logs\doqproxy-stderr-20260629-093045.log'
    }

    It 'reports stopped state when no process exists' {
        $state = Format-DoqProxyHealthState -Process $null

        $state.State | Should -Be 'Stopped'
        $state.Message | Should -Match 'No NetForge-managed DoQ proxy session'
        $state.LastError | Should -BeNullOrEmpty
    }

    It 'reports running state for a live process' {
        $mockProcess = [pscustomobject]@{
            Id = 12345
            HasExited = $false
        }

        $state = Format-DoqProxyHealthState -Process $mockProcess

        $state.State | Should -Be 'Running'
        $state.Message | Should -Match 'PID 12345'
    }

    It 'reports exited state with exit code for a terminated process' {
        $mockProcess = [pscustomobject]@{
            Id = 54321
            HasExited = $true
            ExitCode = 1
        }

        $state = Format-DoqProxyHealthState -Process $mockProcess

        $state.State | Should -Be 'Exited'
        $state.Message | Should -Match 'exit code 1'
        $state.Message | Should -Match 'PID was 54321'
    }
}

Describe 'Profile apply target validation' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-ValidIPv4Address',
            'Test-ValidIPv4PrefixLength',
            'Test-ValidIPv6Address',
            'Test-ValidIPv6PrefixLength',
            'Get-ApplyValidationResult',
            'Get-IPv6ApplyTarget',
            'Test-ValidProxyServer',
            'Test-ValidProxyBypass',
            'ConvertFrom-MappedDriveText',
            'ConvertTo-MappedDriveText',
            'Normalize-MappedDriveList',
            'Get-ProfileApplyTarget'
        )
    }

    It 'builds a valid DHCP apply target from a DHCP profile' {
        $profile = [pscustomobject]@{
            Name = 'Test DHCP'
            UseDHCP = $true
            UseDHCPForDNS = $true
            ConfigureNetworkCategory = $false
            ConfigureProxy = $false
            ConfigureDefaultPrinter = $false
            ConfigureMappedDrives = $false
        }

        $target = Get-ProfileApplyTarget -ProfileData $profile

        $target.IsValid | Should -BeTrue
        $target.UseDHCP | Should -BeTrue
        $target.UseAutomatic | Should -BeTrue
    }

    It 'builds a valid static IP and DNS apply target' {
        $profile = [pscustomobject]@{
            Name = 'Test Static'
            UseDHCP = $false
            IPAddress = '192.168.1.50'
            Gateway = '192.168.1.1'
            PrefixLength = '24'
            UseDHCPForDNS = $false
            PrimaryDNS = '8.8.8.8'
            SecondaryDNS = '8.8.4.4'
            ConfigureNetworkCategory = $false
            ConfigureProxy = $false
            ConfigureDefaultPrinter = $false
            ConfigureMappedDrives = $false
        }

        $target = Get-ProfileApplyTarget -ProfileData $profile

        $target.IsValid | Should -BeTrue
        $target.UseDHCP | Should -BeFalse
        $target.IPAddress | Should -Be '192.168.1.50'
        $target.PrefixLength | Should -Be 24
        $target.Servers.Count | Should -Be 2
    }

    It 'rejects static profile with invalid IP address' {
        $profile = [pscustomobject]@{
            Name = 'Bad IP'
            UseDHCP = $false
            IPAddress = 'not-an-ip'
            PrefixLength = '24'
            UseDHCPForDNS = $true
            ConfigureNetworkCategory = $false
            ConfigureProxy = $false
            ConfigureDefaultPrinter = $false
            ConfigureMappedDrives = $false
        }

        $target = Get-ProfileApplyTarget -ProfileData $profile

        $target.IsValid | Should -BeFalse
        $target.Message | Should -Match 'invalid IPv4'
    }

    It 'rejects static DNS profile with invalid primary DNS' {
        $profile = [pscustomobject]@{
            Name = 'Bad DNS'
            UseDHCP = $true
            UseDHCPForDNS = $false
            PrimaryDNS = 'not-valid'
            ConfigureNetworkCategory = $false
            ConfigureProxy = $false
            ConfigureDefaultPrinter = $false
            ConfigureMappedDrives = $false
        }

        $target = Get-ProfileApplyTarget -ProfileData $profile

        $target.IsValid | Should -BeFalse
        $target.Message | Should -Match 'invalid primary DNS'
    }

    It 'rejects proxy profile with empty proxy server' {
        $profile = [pscustomobject]@{
            Name = 'Bad Proxy'
            UseDHCP = $true
            UseDHCPForDNS = $true
            ConfigureNetworkCategory = $false
            ConfigureProxy = $true
            ProxyEnabled = $true
            ProxyServer = ''
            ConfigureDefaultPrinter = $false
            ConfigureMappedDrives = $false
        }

        $target = Get-ProfileApplyTarget -ProfileData $profile

        $target.IsValid | Should -BeFalse
        $target.Message | Should -Match 'no proxy server'
    }
}

Describe 'Proxy format validation' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Test-ValidProxyServer', 'Test-ValidProxyBypass')
    }

    It 'accepts valid proxy server values' {
        Test-ValidProxyServer -Server 'proxy.corp.local:8080' | Should -BeTrue
        Test-ValidProxyServer -Server '10.0.0.1:3128' | Should -BeTrue
        Test-ValidProxyServer -Server 'http=proxy:80' | Should -BeTrue
    }

    It 'rejects proxy server with dangerous characters' {
        Test-ValidProxyServer -Server 'proxy.local; whoami' | Should -BeFalse
        Test-ValidProxyServer -Server 'proxy&calc' | Should -BeFalse
        Test-ValidProxyServer -Server '' | Should -BeFalse
    }

    It 'accepts valid proxy bypass patterns' {
        Test-ValidProxyBypass -Bypass '*.local;10.*;192.168.*;<local>' | Should -BeTrue
        Test-ValidProxyBypass -Bypass '' | Should -BeTrue
    }

    It 'rejects proxy bypass with dangerous characters' {
        Test-ValidProxyBypass -Bypass 'local;$(calc)' | Should -BeFalse
        Test-ValidProxyBypass -Bypass ('a' * 2001) | Should -BeFalse
    }
}

Describe 'Diagnostic target validation' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Test-ValidDiagnosticTarget')
    }

    It 'accepts valid IPv4 addresses' {
        Test-ValidDiagnosticTarget -Target '8.8.8.8' | Should -BeTrue
        Test-ValidDiagnosticTarget -Target '192.168.1.0/24' | Should -BeTrue
    }

    It 'accepts valid IPv6 addresses' {
        Test-ValidDiagnosticTarget -Target '2001:4860:4860::8888' | Should -BeTrue
        Test-ValidDiagnosticTarget -Target '[::1]' | Should -BeTrue
    }

    It 'accepts valid hostnames' {
        Test-ValidDiagnosticTarget -Target 'example.com' | Should -BeTrue
        Test-ValidDiagnosticTarget -Target 'server-01.local' | Should -BeTrue
    }

    It 'rejects empty and whitespace targets' {
        Test-ValidDiagnosticTarget -Target '' | Should -BeFalse
        Test-ValidDiagnosticTarget -Target '   ' | Should -BeFalse
    }

    It 'rejects targets with shell-dangerous characters' {
        Test-ValidDiagnosticTarget -Target '8.8.8.8 & calc' | Should -BeFalse
        Test-ValidDiagnosticTarget -Target '8.8.8.8; whoami' | Should -BeFalse
        Test-ValidDiagnosticTarget -Target '$(calc)' | Should -BeFalse
        Test-ValidDiagnosticTarget -Target 'host|pipe' | Should -BeFalse
        Test-ValidDiagnosticTarget -Target 'host`cmd' | Should -BeFalse
    }

    It 'rejects excessively long targets' {
        Test-ValidDiagnosticTarget -Target ('a' * 254) | Should -BeFalse
    }
}

Describe 'Hosts group name security' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Test-HostsGroupName')
    }

    It 'rejects group names with newlines' {
        Test-HostsGroupName -Name "Legit`nEvil" | Should -BeFalse
        Test-HostsGroupName -Name "Legit`r`nEvil" | Should -BeFalse
    }

    It 'rejects group names with hash or pipe' {
        Test-HostsGroupName -Name "group#test" | Should -BeFalse
        Test-HostsGroupName -Name "group|test" | Should -BeFalse
    }

    It 'accepts valid group names' {
        Test-HostsGroupName -Name "Work servers" | Should -BeTrue
        Test-HostsGroupName -Name "home-lab" | Should -BeTrue
    }
}

Describe 'QR decompression limit' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'ConvertTo-Base64Url',
            'ConvertFrom-Base64Url',
            'ConvertTo-GzipBase64Url',
            'ConvertFrom-GzipBase64Url'
        )
    }

    It 'round-trips a normal payload' {
        $input = '{"Name":"Test","SchemaVersion":3}'
        $compressed = ConvertTo-GzipBase64Url -Text $input
        $result = ConvertFrom-GzipBase64Url -Text $compressed
        $result | Should -Be $input
    }
}

Describe 'MAC address validation' {
    BeforeAll {
        Import-NetForgeFunction -Name @('ConvertTo-CleanMacAddress', 'Test-ValidMacAddress')
    }

    It 'accepts valid colon-separated unicast MAC' {
        Test-ValidMacAddress -MacAddress '00:1A:2B:3C:4D:5E' | Should -BeTrue
    }

    It 'accepts valid dash-separated unicast MAC' {
        Test-ValidMacAddress -MacAddress '00-1A-2B-3C-4D-5E' | Should -BeTrue
    }

    It 'accepts valid raw hex MAC' {
        Test-ValidMacAddress -MacAddress '001A2B3C4D5E' | Should -BeTrue
    }

    It 'rejects all-zeros MAC' {
        Test-ValidMacAddress -MacAddress '00:00:00:00:00:00' | Should -BeFalse
    }

    It 'rejects all-FFs broadcast MAC' {
        Test-ValidMacAddress -MacAddress 'FF:FF:FF:FF:FF:FF' | Should -BeFalse
    }

    It 'rejects multicast MACs (odd first octet)' {
        Test-ValidMacAddress -MacAddress '01:00:00:00:00:00' | Should -BeFalse
    }

    It 'rejects short MAC' {
        Test-ValidMacAddress -MacAddress '001A2B3C4D' | Should -BeFalse
    }

    It 'rejects empty and null MAC' {
        Test-ValidMacAddress -MacAddress '' | Should -BeFalse
        Test-ValidMacAddress -MacAddress $null | Should -BeFalse
    }

    It 'normalizes lowercase to uppercase' {
        ConvertTo-CleanMacAddress -MacAddress 'aa:bb:cc:dd:ee:ff' | Should -Be 'AABBCCDDEEFF'
    }
}

Describe 'MAC adapter restart planning' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Get-AdapterRestartPlan')
    }

    It 'rejects a missing adapter' {
        $plan = Get-AdapterRestartPlan -Adapter $null

        $plan.IsValid | Should -BeFalse
        $plan.ShouldRestart | Should -BeFalse
        $plan.Message | Should -Match 'No adapter'
    }

    It 'defers restart for an inactive adapter' {
        $plan = Get-AdapterRestartPlan -Adapter ([pscustomobject]@{ Name = 'Ethernet'; Status = 'Disabled' })

        $plan.IsValid | Should -BeTrue
        $plan.ShouldRestart | Should -BeFalse
        $plan.Message | Should -Match 'next time it is enabled'
    }

    It 'plans a background restart for an active adapter' {
        $plan = Get-AdapterRestartPlan -Adapter ([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up' })

        $plan.IsValid | Should -BeTrue
        $plan.ShouldRestart | Should -BeTrue
        $plan.AdapterName | Should -Be 'Ethernet'
    }

    It 'keeps the restart sleeps inside a background PowerShell worker' {
        $source = Get-Content -Raw $script:NetForgePath
        $ast = [scriptblock]::Create($source).Ast
        $functionAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-AdapterRestartForMac'
        }, $true)
        $functionText = $functionAst.Extent.Text

        $functionText | Should -Match '\[PowerShell\]::Create\(\)'
        $functionText | Should -Match '\.BeginInvoke\(\)'
        $functionText | Should -Match 'DispatcherTimer'
        $functionText | Should -Match 'Start-Sleep -Milliseconds 1200'
        $functionText | Should -Match 'MacRestartRunning'
    }
}

Describe 'Adapter connection kind classification' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Get-AdapterSearchText', 'Get-AdapterConnectionKind')
    }

    It 'classifies WiFi adapters' {
        $adapter = [pscustomobject]@{ Name = "Wi-Fi"; InterfaceDescription = "Intel(R) Wi-Fi 6 AX201"; InterfaceAlias = "Wi-Fi"; MediaType = ""; InterfaceType = 71 }
        Get-AdapterConnectionKind -Adapter $adapter | Should -Be 'WiFi'
    }

    It 'classifies Ethernet adapters' {
        $adapter = [pscustomobject]@{ Name = "Ethernet"; InterfaceDescription = "Realtek PCIe GbE Controller"; InterfaceAlias = "Ethernet"; MediaType = "802.3"; InterfaceType = 6 }
        Get-AdapterConnectionKind -Adapter $adapter | Should -Be 'Ethernet'
    }

    It 'classifies VPN adapters' {
        $adapter = [pscustomobject]@{ Name = "WireGuard Tunnel"; InterfaceDescription = "WireGuard Tunnel"; InterfaceAlias = "wg0"; MediaType = ""; InterfaceType = 0 }
        Get-AdapterConnectionKind -Adapter $adapter | Should -Be 'VPN'
    }

    It 'classifies Hyper-V adapters' {
        $adapter = [pscustomobject]@{ Name = "vEthernet (Default Switch)"; InterfaceDescription = "Hyper-V Virtual Ethernet Adapter"; InterfaceAlias = "vEthernet"; MediaType = ""; InterfaceType = 6 }
        Get-AdapterConnectionKind -Adapter $adapter | Should -Be 'Hyper-V'
    }

    It 'classifies Bluetooth PAN adapters' {
        $adapter = [pscustomobject]@{ Name = "Bluetooth Network Connection"; InterfaceDescription = "Bluetooth PAN"; InterfaceAlias = ""; MediaType = ""; InterfaceType = 0 }
        Get-AdapterConnectionKind -Adapter $adapter | Should -Be 'Bluetooth PAN'
    }

    It 'returns Unknown for null adapter' {
        Get-AdapterConnectionKind -Adapter $null | Should -Be 'Unknown'
    }
}

Describe 'Adapter display snapshot' {
    BeforeAll {
        Import-NetForgeFunction -Name @('Get-AdapterDisplaySnapshot')
    }

    BeforeEach {
        Mock Get-NetIPInterface {
            @(
                [pscustomobject]@{ AddressFamily = 'IPv4'; Dhcp = 'Enabled' },
                [pscustomobject]@{ AddressFamily = 'IPv6'; Dhcp = 'Enabled' }
            )
        }
        Mock Get-NetIPAddress {
            @(
                [pscustomobject]@{ AddressFamily = 'IPv4'; IPAddress = '192.168.1.20'; PrefixLength = 24; PrefixOrigin = 'Dhcp' },
                [pscustomobject]@{ AddressFamily = 'IPv6'; IPAddress = '2001:db8::20'; PrefixLength = 64; PrefixOrigin = 'Manual' }
            )
        }
        Mock Get-NetRoute {
            @(
                [pscustomobject]@{ DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; RouteProtocol = 'Dhcp' },
                [pscustomobject]@{ DestinationPrefix = '::/0'; NextHop = 'fe80::1'; RouteProtocol = 'NetMgmt' }
            )
        }
        Mock Get-DnsClientServerAddress {
            [pscustomobject]@{ ServerAddresses = @('1.1.1.1', '1.0.0.1') }
        }
        Mock Get-CimInstance {
            [pscustomobject]@{ DHCPServer = '192.168.1.1' }
        }
    }

    It 'queries each networking source once and projects both display views' {
        $adapter = [pscustomobject]@{ ifIndex = 7; Name = 'Ethernet' }

        $snapshot = Get-AdapterDisplaySnapshot -Adapter $adapter

        $snapshot.IPv4Address.IPAddress | Should -Be '192.168.1.20'
        $snapshot.IPv4DefaultRoute.NextHop | Should -Be '192.168.1.1'
        $snapshot.IPv6ManualAddress.IPAddress | Should -Be '2001:db8::20'
        $snapshot.IPv6DisplayAddress.IPAddress | Should -Be '2001:db8::20'
        $snapshot.IPv6DefaultRoute.NextHop | Should -Be 'fe80::1'
        $snapshot.DnsServers | Should -Be @('1.1.1.1', '1.0.0.1')
        $snapshot.CimConfig.DHCPServer | Should -Be '192.168.1.1'

        Should -Invoke Get-NetIPInterface -Times 1 -Exactly
        Should -Invoke Get-NetIPAddress -Times 1 -Exactly
        Should -Invoke Get-NetRoute -Times 1 -Exactly
        Should -Invoke Get-DnsClientServerAddress -Times 1 -Exactly
        Should -Invoke Get-CimInstance -Times 1 -Exactly
    }
}

Describe 'Network snapshot restore planning' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Test-ValidIP',
            'Test-ValidIPv4Address',
            'Test-ValidIPv4PrefixLength',
            'Test-ValidIPv6Address',
            'Test-ValidIPv6PrefixLength',
            'Get-NetworkSnapshotRestorePlan',
            'Restore-NetworkSnapshot'
        )
    }

    It 'rejects missing and invalid snapshot targets before mutation' {
        (Get-NetworkSnapshotRestorePlan -Snapshot $null).IsValid | Should -BeFalse
        $invalid = Get-NetworkSnapshotRestorePlan -Snapshot ([pscustomobject]@{ InterfaceIndex = 0 })
        $invalid.IsValid | Should -BeFalse
        $invalid.Message | Should -Match 'interface index'
    }

    It 'filters invalid restore values into a safe deterministic plan' {
        $snapshot = [pscustomobject]@{
            InterfaceIndex = 7
            Dhcp = 'Disabled'
            IPv4Addresses = @(
                [pscustomobject]@{ IPAddress = '192.168.10.20'; PrefixLength = 24 },
                [pscustomobject]@{ IPAddress = 'bad'; PrefixLength = 99 }
            )
            DefaultRoutes = @(
                [pscustomobject]@{ NextHop = '192.168.10.1'; RouteMetric = 15 },
                [pscustomobject]@{ NextHop = 'bad'; RouteMetric = 20 }
            )
            IPv6Addresses = @([pscustomobject]@{ IPAddress = '2001:db8::20'; PrefixLength = 64 })
            IPv6DefaultRoutes = @([pscustomobject]@{ NextHop = 'fe80::1'; RouteMetric = 25 })
            DnsAutomatic = $false
            StaticDnsServers = @('1.1.1.1', 'not-an-ip', '1.1.1.1')
            Environment = [pscustomobject]@{ NetworkCategory = 'Private' }
        }

        $plan = Get-NetworkSnapshotRestorePlan -Snapshot $snapshot

        $plan.IsValid | Should -BeTrue
        $plan.DhcpEnabled | Should -BeFalse
        $plan.IPv4Addresses.Count | Should -Be 1
        $plan.IPv4DefaultRoutes.Count | Should -Be 1
        $plan.IPv6Addresses.Count | Should -Be 1
        $plan.IPv6DefaultRoutes.Count | Should -Be 1
        $plan.DnsServers | Should -Be @('1.1.1.1')
        $plan.ResetDns | Should -BeFalse
    }

    It 'executes the DHCP restore plan and reports adapter success' {
        Mock Get-NetAdapter { [pscustomobject]@{ Name = 'Ethernet' } }
        Mock Get-NetIPAddress { @() }
        Mock Remove-NetIPAddress {}
        Mock Get-NetRoute { @() }
        Mock Remove-NetRoute {}
        Mock Set-NetIPInterface {}
        Mock New-NetIPAddress {}
        Mock New-NetRoute {}
        Mock Set-DnsClientServerAddress {}

        $snapshot = [pscustomobject]@{
            InterfaceIndex = 7
            Dhcp = 'Enabled'
            IPv4Addresses = @()
            DefaultRoutes = @()
            IPv6Addresses = @()
            IPv6DefaultRoutes = @()
            DnsAutomatic = $true
            StaticDnsServers = @()
            Environment = $null
        }

        $result = Restore-NetworkSnapshot -Snapshot $snapshot

        $result.Restored | Should -BeTrue
        $result.Message | Should -Match 'Ethernet'
        Should -Invoke Set-NetIPInterface -Times 1 -Exactly -ParameterFilter { $Dhcp -eq 'Enabled' }
        Should -Invoke Set-DnsClientServerAddress -Times 1 -Exactly -ParameterFilter { $ResetServerAddresses }
    }

    It 'returns the mutation error when the restore target cannot be opened' {
        Mock Get-NetAdapter { throw 'adapter missing' }

        $snapshot = [pscustomobject]@{
            InterfaceIndex = 7
            Dhcp = 'Enabled'
            IPv4Addresses = @()
            DefaultRoutes = @()
            IPv6Addresses = @()
            IPv6DefaultRoutes = @()
            DnsAutomatic = $true
            StaticDnsServers = @()
            Environment = $null
        }

        $result = Restore-NetworkSnapshot -Snapshot $snapshot

        $result.Restored | Should -BeFalse
        $result.Message | Should -Match 'adapter missing'
    }
}

Describe 'Network mutation control flow' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-AdapterNetworkSnapshot',
            'Register-LastNetworkSnapshot',
            'Write-OperationLog',
            'Update-Status',
            'Restore-NetworkSnapshot',
            'Invoke-NetworkMutation'
        )

        function global:Show-MessageBox {
            param($Message, $Title, $Icon)
        }
    }

    BeforeEach {
        $script:MutationExecuted = $false
        Mock Get-AdapterNetworkSnapshot {
            [pscustomobject]@{ CapturedAt = '2026-08-12T12:00:00Z'; InterfaceIndex = 7 }
        }
        Mock Register-LastNetworkSnapshot {}
        Mock Write-OperationLog {}
        Mock Update-Status {}
        Mock Show-MessageBox {}
        Mock Restore-NetworkSnapshot {
            [pscustomobject]@{ Restored = $true; Message = 'restored' }
        }
    }

    It 'runs a mutation after capturing and registering a snapshot' {
        $adapter = [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7 }

        $result = Invoke-NetworkMutation -Adapter $adapter -ActionName 'Test change' -ScriptBlock { $script:MutationExecuted = $true } -Quiet

        $result | Should -BeTrue
        $script:MutationExecuted | Should -BeTrue
        Should -Invoke Register-LastNetworkSnapshot -Times 1 -Exactly
        Should -Invoke Restore-NetworkSnapshot -Times 0 -Exactly
    }

    It 'does not attempt rollback when snapshot capture fails' {
        Mock Get-AdapterNetworkSnapshot { throw 'capture failed' }
        $adapter = [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7 }

        $result = Invoke-NetworkMutation -Adapter $adapter -ActionName 'Test change' -ScriptBlock { throw 'must not run' } -Quiet

        $result | Should -BeFalse
        Should -Invoke Restore-NetworkSnapshot -Times 0 -Exactly
        Should -Invoke Update-Status -Times 1 -ParameterFilter { $Message -match 'before a rollback snapshot' }
    }

    It 'rolls back a failed mutation and reports restored state' {
        $adapter = [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7 }

        $result = Invoke-NetworkMutation -Adapter $adapter -ActionName 'Test change' -ScriptBlock { throw 'mutation failed' } -Quiet

        $result | Should -BeFalse
        Should -Invoke Restore-NetworkSnapshot -Times 1 -Exactly
        Should -Invoke Update-Status -Times 1 -ParameterFilter { $Message -match 'previous network state restored' }
    }

    It 'reports a rollback failure without hiding the original mutation failure' {
        Mock Restore-NetworkSnapshot {
            [pscustomobject]@{ Restored = $false; Message = 'restore failed' }
        }
        $adapter = [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7 }

        $result = Invoke-NetworkMutation -Adapter $adapter -ActionName 'Test change' -ScriptBlock { throw 'mutation failed' } -Quiet

        $result | Should -BeFalse
        Should -Invoke Update-Status -Times 1 -ParameterFilter { $Message -match 'restore failed' }
        Should -Invoke Write-OperationLog -Times 1 -ParameterFilter { $Result -eq 'RollbackFailed' -and $Detail -match 'mutation failed' }
    }
}

Describe 'Mapped drive external server guard' {
    BeforeAll {
        Import-NetForgeFunction -Name @(
            'Get-ProfileProperty',
            'ConvertTo-ProfileBoolean',
            'ConvertFrom-MappedDriveText',
            'Normalize-MappedDriveList',
            'Get-MappedDriveState',
            'Get-ExternalMappedDriveServerList',
            'Write-OperationLog',
            'Set-MappedDriveState'
        )

        function global:Show-MessageBox {
            param($Message, $Title, $Buttons, $Icon)
            return 'No'
        }
    }

    BeforeEach {
        Mock Get-MappedDriveState { @() }
        Mock Write-OperationLog {}
        Mock Show-MessageBox { 'No' }
    }

    It 'lists unique remote servers while excluding local aliases' {
        $drives = @(
            [pscustomobject]@{ RemotePath = '\\fileserver\share' },
            [pscustomobject]@{ RemotePath = '\\FILESERVER\other' },
            [pscustomobject]@{ RemotePath = '\\WORKSTATION\local' },
            [pscustomobject]@{ RemotePath = '\\localhost\local' },
            [pscustomobject]@{ RemotePath = '\\203.0.113.10\drop' }
        )

        $servers = @(Get-ExternalMappedDriveServerList -MappedDrives $drives -ComputerName 'WORKSTATION' -DnsDomain 'example.test')

        $servers.Count | Should -Be 2
        $servers | Should -Contain 'fileserver'
        $servers | Should -Contain '203.0.113.10'
    }

    It 'cancels before mapping when the user does not trust a remote server' {
        $drives = @([pscustomobject]@{ DriveLetter = 'Z'; RemotePath = '\\untrusted.example\share'; Persistent = $true })

        { Set-MappedDriveState -MappedDrives $drives } | Should -Throw '*cancelled before contacting*'

        Should -Invoke Show-MessageBox -Times 1 -Exactly -ParameterFilter { $Message -match 'NTLM' -and $Message -match 'untrusted\.example' }
    }

    It 'fails closed without prompting during silent profile apply' {
        $drives = @([pscustomobject]@{ DriveLetter = 'Z'; RemotePath = '\\untrusted.example\share'; Persistent = $true })

        { Set-MappedDriveState -MappedDrives $drives -NonInteractive } | Should -Throw '*require interactive confirmation*'

        Should -Invoke Show-MessageBox -Times 0 -Exactly
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
