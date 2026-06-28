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
            'Get-SafeProfileFileName',
            'Get-ProfileValidationResult',
            'Write-ProfileFileAtomic'
        )
        $script:ProfileSchemaVersion = 1
    }

    It 'normalizes a legacy static profile to schema version 1' {
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
        $result.Profile.SchemaVersion | Should -Be 1
        $result.Profile.AutoApply | Should -BeTrue
        $result.Profile.MatchGatewayMac | Should -Be '001122334455'
        $result.SafeFileName | Should -Be 'Clinic_LAN.json'
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
        $roundTrip.SchemaVersion | Should -Be 1
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
            'Get-SafeProfileFileName',
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
        $script:ProfileSchemaVersion = 1
        $script:AppVersion = '1.21.0'
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
