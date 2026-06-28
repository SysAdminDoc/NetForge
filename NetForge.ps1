<#
.SYNOPSIS
    NetForge - Professional Network Adapter Management Utility
.DESCRIPTION
    Comprehensive network adapter configuration tool with static IP management,
    DNS control, profile saving, ping/latency monitoring, connection status,
    WiFi info, speed testing, DNS lookup, and extensive customization options.
.NOTES
    Author: NetForge
    Version: 1.18.0
    Requires: Windows PowerShell 5.1+ with Administrator privileges
#>

#Requires -Version 5.1

param(
    [switch]$Debug
)

# ============================================================================
# ELEVATION CHECK
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
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

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:AppName = "NetForge"
$script:AppVersion = "1.18.0"
$script:ConfigPath = Join-Path $env:APPDATA "NetForge"
$script:ProfilesPath = Join-Path $script:ConfigPath "Profiles"
$script:LogsPath = Join-Path $script:ConfigPath "Logs"
$script:SettingsFile = Join-Path $script:ConfigPath "settings.json"
$script:ProfileSchemaVersion = 1
$script:ContinuousPingRunning = $false
$script:ContinuousPingPS = $null
$script:CachedPublicIP = $null
$script:SpeedTestRunning = $false
$script:WifiScanRunning = $false
$script:WifiNetworks = @()
$script:WifiInterfaceName = $null
$script:ShowAdvancedAdapters = $false
$script:EncryptedDnsHealthRunning = $false
$script:EncryptedDnsHealthJob = $null
$script:EncryptedDnsHealthTimer = $null
$script:DoqProxyProcess = $null
$script:LastAutoAppliedProfile = ""
$script:LastAutoApplySignature = ""
$script:LastAutoApplyAttemptKey = ""
$script:LastNetworkSnapshot = $null
$script:LastProfileLoadWarnings = @()
$script:AutoProfileTimer = $null
$script:NetworkChangeHandlers = @{}
$script:NetworkChangeSubscribed = $false

# Create directories
if (-not (Test-Path $script:ConfigPath)) { New-Item -Path $script:ConfigPath -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $script:ProfilesPath)) { New-Item -Path $script:ProfilesPath -ItemType Directory -Force | Out-Null }
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
        <Color x:Key="BorderColor">#30363d</Color>
        <Color x:Key="AccentBlue">#58a6ff</Color>
        <Color x:Key="AccentGreen">#3fb950</Color>
        <Color x:Key="AccentOrange">#d29922</Color>
        <Color x:Key="AccentRed">#f85149</Color>
        <Color x:Key="AccentPurple">#a371f7</Color>
        <Color x:Key="TextPrimary">#f0f6fc</Color>
        <Color x:Key="TextSecondary">#8b949e</Color>
        <Color x:Key="TextMuted">#6e7681</Color>

        <SolidColorBrush x:Key="BgPrimaryBrush" Color="{StaticResource BgPrimary}"/>
        <SolidColorBrush x:Key="BgSecondaryBrush" Color="{StaticResource BgSecondary}"/>
        <SolidColorBrush x:Key="BgTertiaryBrush" Color="{StaticResource BgTertiary}"/>
        <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}"/>
        <SolidColorBrush x:Key="AccentBlueBrush" Color="{StaticResource AccentBlue}"/>
        <SolidColorBrush x:Key="AccentGreenBrush" Color="{StaticResource AccentGreen}"/>
        <SolidColorBrush x:Key="AccentOrangeBrush" Color="{StaticResource AccentOrange}"/>
        <SolidColorBrush x:Key="AccentRedBrush" Color="{StaticResource AccentRed}"/>
        <SolidColorBrush x:Key="AccentPurpleBrush" Color="{StaticResource AccentPurple}"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimary}"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondary}"/>
        <SolidColorBrush x:Key="TextMutedBrush" Color="{StaticResource TextMuted}"/>

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
                                <Setter TargetName="border" Property="Background" Value="#30363d"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBlueBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#282e36"/>
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
            <Setter Property="Background" Value="#238636"/>
            <Setter Property="BorderBrush" Value="#2ea043"/>
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
                                <Setter TargetName="border" Property="Background" Value="#2ea043"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#238636"/>
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
            <Setter Property="Background" Value="#21262d"/>
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
                                <Setter TargetName="border" Property="Background" Value="#f8514926"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#f8514940"/>
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
                                <Setter TargetName="border" Property="Background" Value="#1f2428"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1f6feb26"/>
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
                        <TextBlock Text="v1.18.0" FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                    </Border>
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="btnRefresh" Content="Refresh Adapters" Style="{StaticResource ModernButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnExport" Content="Export All" Style="{StaticResource ModernButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnImport" Content="Import" Style="{StaticResource ModernButton}"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Connection Status Bar -->
        <Border Grid.Row="1" Background="#0f1318" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1" Padding="24,10">
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
                                            <Button x:Name="btnAutoMetric" Content="Auto Metric" Style="{StaticResource ModernButton}" Padding="14,8"/>
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
                                            <TextBlock x:Name="txtEncryptedDnsHealthStatus" Text="Validates DoH/DoT handshake." FontSize="11" Foreground="{StaticResource TextMutedBrush}" TextWrapping="Wrap"/>
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
                                        <Button x:Name="btnExportDiagnostics" Content="Export Diagnostics" Style="{StaticResource ModernButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnResetWinsock" Content="Reset Winsock" Style="{StaticResource DangerButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnResetTCP" Content="Reset TCP/IP Stack" Style="{StaticResource DangerButton}" Margin="0,0,12,12"/>
                                        <Button x:Name="btnNetworkReset" Content="Full Network Reset" Style="{StaticResource DangerButton}" Margin="0,0,0,12"/>
                                    </WrapPanel>
                                </Border>

                                <!-- Network Diagnostics -->
                                <TextBlock Text="NETWORK DIAGNOSTICS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,12"/>

                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" Padding="20" Margin="0,0,0,20">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,16">
                                            <TextBox x:Name="txtPingTarget" Style="{StaticResource ModernTextBox}" Width="300" Text="8.8.8.8" Margin="0,0,12,0"/>
                                            <Button x:Name="btnPing" Content="Ping" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnTraceroute" Content="Traceroute" Style="{StaticResource ModernButton}" Margin="0,0,12,0"/>
                                            <Button x:Name="btnNslookup" Content="NSLookup" Style="{StaticResource ModernButton}"/>
                                        </StackPanel>

                                        <Border Grid.Row="1" Background="{StaticResource BgPrimaryBrush}" CornerRadius="6" Padding="16" MaxHeight="250">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <TextBlock x:Name="txtDiagOutput" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap" Text="Diagnostic output will appear here..."/>
                                            </ScrollViewer>
                                        </Border>
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
                                            <TextBlock Text="DHCP Server" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,0,0,4"/>
                                            <TextBlock x:Name="txtInfoDHCPServer" Text="--" FontSize="13" Foreground="{StaticResource TextPrimaryBrush}"/>
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
                <TextBlock Grid.Column="1" Text="NetForge v1.18.0 | Running as Administrator" FontSize="11" Foreground="{StaticResource TextMutedBrush}" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ============================================================================
# WINDOW INITIALIZATION
# ============================================================================
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

    $routes = @(Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
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

    return [pscustomobject]@{
        CapturedAt = (Get-Date).ToString("o")
        Reason = $Reason
        InterfaceIndex = $Adapter.ifIndex
        InterfaceAlias = $Adapter.Name
        Dhcp = [string]$ipInterface.Dhcp
        IPv4Addresses = $addresses
        DefaultRoutes = $routes
        DnsAutomatic = ($staticDnsServers.Count -eq 0)
        StaticDnsServers = $staticDnsServers
        EffectiveDnsServers = $effectiveDnsServers
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
    if ($script:rbDHCP.IsChecked) {
        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            UseDHCP = $true
            StatusMessage = "DHCP enabled"
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

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        UseDHCP = $false
        IPAddress = $ip
        Gateway = $gateway
        PrefixLength = $prefix
        StatusMessage = "Static IP $ip configured"
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

        $preset = $selected.Tag.Data
        if ($preset.Primary -eq "DHCP") {
            return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
                UseAutomatic = $true
                Servers = @()
                StatusMessage = "DNS preset '$($selected.Tag.Name)' set to automatic"
            }
        }

        $servers = @()
        foreach ($server in @($preset.Primary, $preset.Secondary)) {
            if ([string]::IsNullOrWhiteSpace($server)) { continue }
            if (-not (Test-ValidIP -IP $server)) {
                return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$($selected.Tag.Name)' contains invalid server '$server'."
            }
            $servers += $server
        }

        if ($script:chkIPv6Dns.IsChecked) {
            foreach ($server in @($preset.PrimaryV6, $preset.SecondaryV6)) {
                if ([string]::IsNullOrWhiteSpace($server)) { continue }
                if (-not (Test-ValidIP -IP $server)) {
                    return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$($selected.Tag.Name)' contains invalid IPv6 server '$server'."
                }
                $servers += $server
            }
        }

        $servers = @($servers | Select-Object -Unique)
        if ($servers.Count -eq 0) {
            return Get-ApplyValidationResult -IsValid $false -Message "DNS preset '$($selected.Tag.Name)' has no usable DNS servers."
        }

        return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
            UseAutomatic = $false
            Servers = $servers
            StatusMessage = "DNS preset '$($selected.Tag.Name)' applied"
        }
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

    return Get-ApplyValidationResult -IsValid $true -Message "" -Data @{
        UseDHCP = $useDhcp
        IPAddress = $ipAddress
        Gateway = $gateway
        PrefixLength = if ($useDhcp) { 0 } else { $prefix }
        UseAutomatic = $useDnsAutomatic
        Servers = @($dnsServers | Select-Object -Unique)
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
        return
    }

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
}

function Get-SelectedAdapter {
    $selected = $script:lstAdapters.SelectedItem
    if ($null -eq $selected) { return $null }
    return $selected.Tag
}

function Update-AdapterDisplay {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        $script:txtAdapterName.Text = "Select an adapter"
        $script:txtCurrentIP.Text = "--"
        $script:txtMAC.Text = "--"
        $script:txtStatus.Text = "--"
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
    } catch {
        $script:txtCurrentIP.Text = "Error"
    }

    Update-AdapterDetails
    Show-MacOverrideDisplay
    Show-InterfaceMetricDisplay
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

        $dhcpServer = (Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }).DHCPServer
        $script:txtInfoDHCPServer.Text = if ($dhcpServer) { $dhcpServer } else { "--" }

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
                    }
                    continue
                }

                if ($null -eq $current) { continue }

                if ($line -match '^Authentication\s*:\s*(.+)$') {
                    $current.Authentication = $Matches[1].Trim()
                } elseif ($line -match '^Encryption\s*:\s*(.+)$') {
                    $current.Encryption = $Matches[1].Trim()
                } elseif ($line -match '^BSSID\s+\d+\s*:\s*(.+)$') {
                    $current.Bssids += $Matches[1].Trim()
                } elseif ($line -match '^Signal\s*:\s*(.+)$') {
                    $current.Signals += $Matches[1].Trim()
                } elseif ($line -match '^Channel\s*:\s*(.+)$') {
                    $current.Channels += $Matches[1].Trim()
                } elseif ($line -match '^Band\s*:\s*(.+)$') {
                    $current.Bands += $Matches[1].Trim()
                } elseif ($line -match '^Radio type\s*:\s*(.+)$') {
                    $current.RadioTypes += $Matches[1].Trim()
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
    $ps = [PowerShell]::Create()
    $ps.AddScript({
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "NetForge/$script:AppVersion")
            $ip = $wc.DownloadString("https://api.ipify.org").Trim()
            $wc.Dispose()
            return $ip
        } catch {
            try {
                $wc2 = New-Object System.Net.WebClient
                $wc2.Headers.Add("User-Agent", "NetForge/$script:AppVersion")
                $ip = $wc2.DownloadString("https://icanhazip.com").Trim()
                $wc2.Dispose()
                return $ip
            } catch {
                return "Error"
            }
        }
    })

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            try {
                $result = $ps.EndInvoke($handle)
                if ($result -and $result.Count -gt 0) {
                    $script:CachedPublicIP = $result[0]
                    $script:txtConnPublicIP.Text = $result[0]
                }
            } catch {
                $script:txtConnPublicIP.Text = "Error"
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

function Toggle-ContinuousPing {
    if ($script:ContinuousPingRunning) {
        # Stop continuous ping
        $script:ContinuousPingRunning = $false
        $script:btnContinuousPing.Content = "Start Continuous Ping"
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
    $script:btnContinuousPing.Content = "Stop Continuous Ping"
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
    $script:SpeedTestRunning = $true
    $script:btnSpeedTest.IsEnabled = $false
    $script:btnSpeedTest.Content = "Testing..."
    Update-Status "Running speed test..."

    $script:txtSpeedDown.Text = "..."
    $script:txtSpeedSize.Text = "..."
    $script:txtSpeedTime.Text = "..."

    $ps = [PowerShell]::Create()
    $ps.AddScript({
        try {
            # Use a ~10MB test file from a reliable CDN
            $url = "http://speedtest.tele2.net/10MB.zip"
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "NetForge/$script:AppVersion")

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $data = $wc.DownloadData($url)
            $sw.Stop()
            $wc.Dispose()

            $sizeBytes = $data.Length
            $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
            $elapsed = $sw.Elapsed.TotalSeconds
            $speedMbps = [math]::Round(($sizeBytes * 8) / ($elapsed * 1000000), 2)

            return @{
                SpeedMbps = $speedMbps
                SizeMB = $sizeMB
                Seconds = [math]::Round($elapsed, 2)
                Success = $true
            }
        } catch {
            # Fallback URL
            try {
                $url2 = "http://proof.ovh.net/files/1Mb.dat"
                $wc2 = New-Object System.Net.WebClient
                $wc2.Headers.Add("User-Agent", "NetForge/$script:AppVersion")

                $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
                $data2 = $wc2.DownloadData($url2)
                $sw2.Stop()
                $wc2.Dispose()

                $sizeBytes2 = $data2.Length
                $sizeMB2 = [math]::Round($sizeBytes2 / 1MB, 2)
                $elapsed2 = $sw2.Elapsed.TotalSeconds
                $speedMbps2 = [math]::Round(($sizeBytes2 * 8) / ($elapsed2 * 1000000), 2)

                return @{
                    SpeedMbps = $speedMbps2
                    SizeMB = $sizeMB2
                    Seconds = [math]::Round($elapsed2, 2)
                    Success = $true
                }
            } catch {
                return @{ Success = $false; Error = $_.Exception.Message }
            }
        }
    })

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
                        Update-Status ("Speed test complete: " + $info.SpeedMbps.ToString() + " Mbps") -Type Success
                    } else {
                        $script:txtSpeedDown.Text = "ERR"
                        $script:txtSpeedSize.Text = "--"
                        $script:txtSpeedTime.Text = "--"
                        Update-Status "Speed test failed" -Type Error
                    }
                }
            } catch {
                $script:txtSpeedDown.Text = "ERR"
                Update-Status "Speed test error" -Type Error
            }
            $ps.Dispose()
            $script:SpeedTestRunning = $false
            $script:btnSpeedTest.IsEnabled = $true
            $script:btnSpeedTest.Content = "Speed Test"
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
# DNS PRESET FUNCTIONS
# ============================================================================
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
        $descText.Text = $data.Description
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

    $dohTarget = Get-DohConfigurationTarget
    $dotTarget = Get-DotConfigurationTarget
    $dohTemplate = if (Test-DohTemplate -Template $dohTarget.Template) { $dohTarget.Template } else { "" }
    $dotHost = if (Test-DotHost -HostName $dotTarget.RawDoTHost) { $dotTarget.DoTHost } else { "" }

    if ([string]::IsNullOrWhiteSpace($dohTemplate) -and [string]::IsNullOrWhiteSpace($dotHost)) {
        Show-MessageBox -Message "Select a preset with DoH/DoT metadata or enter a valid custom DoH template or DoT host before testing encrypted DNS health." -Title "No Encrypted DNS Target" -Icon Warning
        return
    }

    $script:EncryptedDnsHealthRunning = $true
    $script:btnTestEncryptedDns.IsEnabled = $false
    $script:txtEncryptedDnsHealthStatus.Text = "Testing encrypted DNS..."
    Update-Status "Testing encrypted DNS health..."

    $healthScript = {
        param($DohTemplate, $DotHost)

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

                $response = $request.GetResponse()
                try {
                    $stream = $response.GetResponseStream()
                    $memory = New-Object System.IO.MemoryStream
                    $stream.CopyTo($memory)
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
                    }
                } finally {
                    if ($response) { $response.Close() }
                }
            } catch {
                return [pscustomobject]@{
                    Protocol = "DoH"
                    Success = $false
                    Message = $_.Exception.Message
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

                return [pscustomobject]@{
                    Protocol = "DoT"
                    Success = $true
                    Message = "TLS handshake and DNS response $responseLength bytes"
                }
            } catch {
                return [pscustomobject]@{
                    Protocol = "DoT"
                    Success = $false
                    Message = $_.Exception.Message
                }
            } finally {
                if ($sslStream) { $sslStream.Dispose() }
                if ($client) { $client.Close() }
            }
        }

        $results = @()
        if (-not [string]::IsNullOrWhiteSpace($DohTemplate)) {
            $results += Invoke-DohHealthProbe -Template $DohTemplate
        }
        if (-not [string]::IsNullOrWhiteSpace($DotHost)) {
            $results += Invoke-DotHealthProbe -HostValue $DotHost
        }
        return $results
    }

    $script:EncryptedDnsHealthJob = Start-Job -ScriptBlock $healthScript -ArgumentList $dohTemplate, $dotHost

    $script:EncryptedDnsHealthTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:EncryptedDnsHealthTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:EncryptedDnsHealthTimer.Add_Tick({
        if ($script:EncryptedDnsHealthJob.State -notin @("Completed", "Failed", "Stopped")) { return }

        $script:EncryptedDnsHealthTimer.Stop()

        try {
            $results = @(Receive-Job $script:EncryptedDnsHealthJob -ErrorAction Stop)
            $lines = @()
            foreach ($result in $results) {
                $prefix = if ($result.Success) { "OK" } else { "FAIL" }
                $lines += "$($result.Protocol) $prefix`: $($result.Message)"
            }

            if ($lines.Count -eq 0) {
                $script:txtEncryptedDnsHealthStatus.Text = "No health results returned."
                Update-Status "Encrypted DNS health test returned no results" -Type Warning
            } else {
                $script:txtEncryptedDnsHealthStatus.Text = $lines -join "`n"
                $failed = @($results | Where-Object { -not $_.Success })
                if ($failed.Count -eq 0) {
                    Update-Status "Encrypted DNS health test passed" -Type Success
                } else {
                    Update-Status "Encrypted DNS health test found $($failed.Count) failure(s)" -Type Warning
                }
            }
        } catch {
            $script:txtEncryptedDnsHealthStatus.Text = "Health test failed: $($_.Exception.Message)"
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

function Invoke-ValidateDoqProxy {
    $config = Get-DoqProxyConfiguration
    $errors = Test-DoqProxyConfiguration -Config $config

    if ($errors.Count -gt 0) {
        $script:txtDoqProxyStatus.Text = $errors -join "`n"
        Update-Status "DoQ proxy configuration needs attention" -Type Warning
        return $false
    }

    try {
        $versionOutput = & $config.ProxyPath --version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw $versionOutput.Trim()
        }

        $summary = if ([string]::IsNullOrWhiteSpace($versionOutput.Trim())) { "dnsproxy found." } else { $versionOutput.Trim() }
        $script:txtDoqProxyStatus.Text = "Ready: $summary"
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
        $script:DoqProxyProcess = Start-Process -FilePath $config.ProxyPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 600

        if ($script:DoqProxyProcess.HasExited) {
            $exitCode = $script:DoqProxyProcess.ExitCode
            $script:DoqProxyProcess = $null
            throw "dnsproxy exited immediately with code $exitCode."
        }

        $script:txtDoqProxyStatus.Text = "DoQ proxy running on $($config.ListenAddress):$($config.ListenPort). PID $($script:DoqProxyProcess.Id)."
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
        UseDHCP = $useDhcp
        IPAddress = $ipAddress
        SubnetMask = $subnetMask
        Gateway = $gateway
        PrefixLength = if ($useDhcp) { "" } else { [string]$prefix }
        UseDHCPForDNS = $useDnsAutomatic
        PrimaryDNS = $primaryDns
        SecondaryDNS = $secondaryDns
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

function Write-ProfileImportLog {
    param([string[]]$Lines)

    if ($script:txtDiagOutput) {
        $script:txtDiagOutput.Text = ($Lines -join "`n")
    }
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
    $script:chkProfileDHCP.IsChecked = $profile.UseDHCP
    $script:txtProfileIP.Text = $profile.IPAddress
    $script:txtProfileSubnet.Text = $profile.SubnetMask
    $script:txtProfileGateway.Text = $profile.Gateway
    $script:txtProfilePrefix.Text = $profile.PrefixLength
    $script:chkProfileDnsDHCP.IsChecked = $profile.UseDHCPForDNS
    $script:txtProfileDns1.Text = $profile.PrimaryDNS
    $script:txtProfileDns2.Text = $profile.SecondaryDNS
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
        UseDHCP = $script:chkProfileDHCP.IsChecked
        IPAddress = $script:txtProfileIP.Text
        SubnetMask = $script:txtProfileSubnet.Text
        Gateway = $script:txtProfileGateway.Text
        PrefixLength = $script:txtProfilePrefix.Text
        UseDHCPForDNS = $script:chkProfileDnsDHCP.IsChecked
        PrimaryDNS = $script:txtProfileDns1.Text
        SecondaryDNS = $script:txtProfileDns2.Text
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
        if ($Source -ne "Auto") {
            Show-MessageBox -Message $target.Message -Title "Profile Validation Failed" -Icon Error
        }
        return $false
    }

    Update-Status "Applying profile '$($ProfileData.Name)'..."

    $quietApply = ($Source -eq "Auto")
    $success = Invoke-NetworkMutation -Adapter $Adapter -ActionName "Apply profile '$($ProfileData.Name)'" -Quiet:$quietApply -ScriptBlock {
        Invoke-AdapterIPTarget -Adapter $Adapter -Target $target
        Invoke-AdapterDNSTarget -Adapter $Adapter -Target $target
    }

    if ($success) {
        $script:LastAutoAppliedProfile = if ($Source -eq "Auto") { $ProfileData.Name } else { $script:LastAutoAppliedProfile }
        Update-Status "Profile '$($ProfileData.Name)' applied successfully" -Type Success
        Start-Sleep -Milliseconds 500
        Update-AdapterDisplay
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

function Register-NetworkChangeAutoApply {
    if ($script:NetworkChangeSubscribed) { return }

    try {
        $addressHandler = [System.Net.NetworkInformation.NetworkAddressChangedEventHandler]{
            $window.Dispatcher.BeginInvoke([action]{
                Invoke-AutoApplyProfile -Trigger "NetworkAddressChanged"
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
    Add-DiffLine -Label "Match SSID" -CurrentValue "--" -TargetValue $script:txtProfileMatchSsid.Text.Trim()
    Add-DiffLine -Label "Gateway MAC" -CurrentValue "--" -TargetValue (ConvertTo-CleanMacAddress -MacAddress $script:txtProfileGatewayMac.Text)

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

    $result = Show-MessageBox -Message "Apply DNS configuration to '$($adapter.Name)'?" -Title "Confirm" -Buttons YesNo -Icon Question
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

        if (Test-Path -LiteralPath $script:LogsPath) {
            Copy-Item -Path (Join-Path $script:LogsPath "*") -Destination $logsTarget -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $script:ProfilesPath) {
            Copy-Item -Path (Join-Path $script:ProfilesPath "*.json") -Destination $profilesTarget -Force -ErrorAction SilentlyContinue
        }

        $adapter = Get-SelectedAdapter
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
            Profiles = Get-Profiles
            RecentProfileLoadWarnings = $script:LastProfileLoadWarnings
        }

        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempRoot "adapter-state.json") -Encoding UTF8

        if (Test-Path -LiteralPath $saveDialog.FileName) {
            Remove-Item -LiteralPath $saveDialog.FileName -Force
        }
        Compress-Archive -Path (Join-Path $tempRoot "*") -DestinationPath $saveDialog.FileName -Force

        Write-OperationLog -Action "Export diagnostics" -Result "Succeeded" -Detail $saveDialog.FileName
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
    $openDialog.Filter = "JSON Files (*.json)|*.json"
    $openDialog.Title = "Import Configuration"

    if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $import = Get-Content $openDialog.FileName -Raw | ConvertFrom-Json
            $incomingProfiles = @()

            if ($import.Profiles) {
                $incomingProfiles = @($import.Profiles)
            } elseif ($import.Name) {
                $incomingProfiles = @($import)
            } else {
                Write-ProfileImportLog -Lines @("Import rejected:", "No profile records were found in $($openDialog.FileName).")
                Update-Status "Import rejected: no profiles found" -Type Error
                return
            }

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
                "Import dry-run: $($accepted.Count) accepted, $($rejected.Count) rejected from $($openDialog.FileName)."
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

# ============================================================================
# EVENT HANDLERS
# ============================================================================
$lstAdapters.Add_SelectionChanged({
    Update-AdapterDisplay
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
    $script:chkProfileDHCP.IsChecked = $true
    $script:txtProfileIP.Text = ""
    $script:txtProfileSubnet.Text = "255.255.255.0"
    $script:txtProfileGateway.Text = ""
    $script:txtProfilePrefix.Text = "24"
    $script:chkProfileDnsDHCP.IsChecked = $true
    $script:txtProfileDns1.Text = ""
    $script:txtProfileDns2.Text = ""
})
$btnDeleteProfile.Add_Click({ Delete-Profile })
$btnSaveProfile.Add_Click({ Save-Profile })
$btnProfileDiff.Add_Click({ Show-ProfileDiff })
$btnApplyProfile.Add_Click({ Apply-Profile })
$btnCaptureProfileMatch.Add_Click({ Invoke-CaptureProfileMatch })
$btnFlushDns.Add_Click({ Invoke-FlushDns })
$btnReleaseIP.Add_Click({ Invoke-ReleaseIP })
$btnRenewIP.Add_Click({ Invoke-RenewIP })
$btnRestoreNetworkState.Add_Click({ Invoke-RestoreLastNetworkState })
$btnExportDiagnostics.Add_Click({ Export-DiagnosticsBundle })
$btnResetWinsock.Add_Click({ Invoke-ResetWinsock })
$btnResetTCP.Add_Click({ Invoke-ResetTCP })
$btnNetworkReset.Add_Click({ Invoke-NetworkReset })
$btnPing.Add_Click({ Invoke-Ping })
$btnTraceroute.Add_Click({ Invoke-Traceroute })
$btnNslookup.Add_Click({ Invoke-Nslookup })

# Diagnostics button handlers
$btnDiagPing.Add_Click({ Invoke-DiagPingTest })
$btnContinuousPing.Add_Click({ Toggle-ContinuousPing })
$btnSpeedTest.Add_Click({ Invoke-SpeedTest })
$btnDnsLookup.Add_Click({ Invoke-DnsLookup })

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

# ============================================================================
# CLEANUP ON WINDOW CLOSE
# ============================================================================
$window.Add_Closing({
    $script:ContinuousPingRunning = $false
    if ($script:ContinuousPingTimer) {
        $script:ContinuousPingTimer.Stop()
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
    Unregister-NetworkChangeAutoApply
    $script:ConnStatusTimer.Stop()
})

# ============================================================================
# INITIALIZATION
# ============================================================================
Refresh-AdapterList
Refresh-DnsPresets
Show-DohConfiguration
Show-DotConfiguration
Refresh-ProfileList
Show-RestoreSnapshotButtonState
Update-ConnectionStatus
Update-PublicIP
Show-WifiActionState
Invoke-WifiNetworkScan
Invoke-AutoApplyProfile -Trigger "Startup"

# Select first adapter if available
if ($lstAdapters.Items.Count -gt 0) {
    $lstAdapters.SelectedIndex = 0
}

# ============================================================================
# SHOW WINDOW
# ============================================================================
$window.ShowDialog() | Out-Null
