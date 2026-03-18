<#
.SYNOPSIS
    NetForge - Professional Network Adapter Management Utility
.DESCRIPTION
    Comprehensive network adapter configuration tool with static IP management,
    DNS control, profile saving, and extensive customization options.
.NOTES
    Author: NetForge
    Version: 1.0.0
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
$script:AppVersion = "1.0.0"
$script:ConfigPath = Join-Path $env:APPDATA "NetForge"
$script:ProfilesPath = Join-Path $script:ConfigPath "Profiles"
$script:SettingsFile = Join-Path $script:ConfigPath "settings.json"

# Create directories
if (-not (Test-Path $script:ConfigPath)) { New-Item -Path $script:ConfigPath -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $script:ProfilesPath)) { New-Item -Path $script:ProfilesPath -ItemType Directory -Force | Out-Null }

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
        Description = "Fast, reliable DNS by Google"
        Category = "Public"
    }
    "Cloudflare DNS" = @{
        Primary = "1.1.1.1"
        Secondary = "1.0.0.1"
        PrimaryV6 = "2606:4700:4700::1111"
        SecondaryV6 = "2606:4700:4700::1001"
        Description = "Privacy-focused, fastest DNS resolver"
        Category = "Public"
    }
    "Cloudflare Malware Blocking" = @{
        Primary = "1.1.1.2"
        Secondary = "1.0.0.2"
        PrimaryV6 = "2606:4700:4700::1112"
        SecondaryV6 = "2606:4700:4700::1002"
        Description = "Cloudflare with malware protection"
        Category = "Security"
    }
    "Cloudflare Family" = @{
        Primary = "1.1.1.3"
        Secondary = "1.0.0.3"
        PrimaryV6 = "2606:4700:4700::1113"
        SecondaryV6 = "2606:4700:4700::1003"
        Description = "Cloudflare with malware + adult content blocking"
        Category = "Family"
    }
    "Quad9 DNS" = @{
        Primary = "9.9.9.9"
        Secondary = "149.112.112.112"
        PrimaryV6 = "2620:fe::fe"
        SecondaryV6 = "2620:fe::9"
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
    Height="850"
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
                        <TextBlock Text="v1.0.0" FontSize="11" Foreground="{StaticResource TextMutedBrush}"/>
                    </Border>
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="btnRefresh" Content="Refresh Adapters" Style="{StaticResource ModernButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnExport" Content="Export All" Style="{StaticResource ModernButton}" Margin="0,0,8,0"/>
                    <Button x:Name="btnImport" Content="Import" Style="{StaticResource ModernButton}"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Row="1">
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
                        <TextBlock Text="NETWORK ADAPTERS" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMutedBrush}"/>
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

                                <!-- Apply Button -->
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button x:Name="btnApplyDns" Content="Apply DNS Configuration" Style="{StaticResource PrimaryButton}" Padding="24,12"/>
                                </StackPanel>
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
                                            <Button x:Name="btnApplyProfile" Content="Apply to Adapter" Style="{StaticResource ModernButton}" Padding="20,10"/>
                                        </StackPanel>
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
                </TabControl>
            </Grid>
        </Grid>

        <!-- Status Bar -->
        <Border Grid.Row="2" Background="{StaticResource BgSecondaryBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Padding="16,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <TextBlock x:Name="txtStatusBar" Grid.Column="0" Text="Ready" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"/>
                <TextBlock Grid.Column="1" Text="NetForge v1.0.0 | Running as Administrator" FontSize="11" Foreground="{StaticResource TextMutedBrush}" VerticalAlignment="Center"/>
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

# Get all named controls
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    $name = $_.Name
    Set-Variable -Name $name -Value $window.FindName($name) -Scope Script
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
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
function Get-NetworkAdapters {
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Virtual -eq $false -or $_.Name -like "*Ethernet*" -or $_.Name -like "*Wi-Fi*" } | Sort-Object Name
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
        $descText.Text = $adapter.InterfaceDescription
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
}

function Update-AdapterDetails {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) { return }
    
    try {
        $script:txtInfoIndex.Text = $adapter.ifIndex.ToString()
        $script:txtInfoType.Text = $adapter.InterfaceType
        
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
        # Ignore errors
    }
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
}

# ============================================================================
# PROFILE FUNCTIONS
# ============================================================================
function Get-Profiles {
    $profiles = @()
    if (Test-Path $script:ProfilesPath) {
        Get-ChildItem -Path $script:ProfilesPath -Filter "*.json" | ForEach-Object {
            try {
                $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $profiles += $content
            } catch { }
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
}

function Load-ProfileToEditor {
    $selected = $script:lstProfiles.SelectedItem
    if ($null -eq $selected) { return }
    
    $profile = $selected.Tag
    $script:txtProfileName.Text = $profile.Name
    $script:txtProfileDesc.Text = $profile.Description
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
        Name = $name
        Description = $script:txtProfileDesc.Text
        UseDHCP = $script:chkProfileDHCP.IsChecked
        IPAddress = $script:txtProfileIP.Text
        SubnetMask = $script:txtProfileSubnet.Text
        Gateway = $script:txtProfileGateway.Text
        PrefixLength = $script:txtProfilePrefix.Text
        UseDHCPForDNS = $script:chkProfileDnsDHCP.IsChecked
        PrimaryDNS = $script:txtProfileDns1.Text
        SecondaryDNS = $script:txtProfileDns2.Text
        CreatedAt = (Get-Date).ToString("o")
    }
    
    $safeName = $name -replace '[^\w\-]', '_'
    $filePath = Join-Path $script:ProfilesPath "$safeName.json"
    $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
    
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
        $safeName = $profile.Name -replace '[^\w\-]', '_'
        $filePath = Join-Path $script:ProfilesPath "$safeName.json"
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force
        }
        Update-Status "Profile '$($profile.Name)' deleted" -Type Success
        Refresh-ProfileList
    }
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
    
    $result = Show-MessageBox -Message "Apply IP configuration to '$($adapter.Name)'?" -Title "Confirm" -Buttons YesNo -Icon Question
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    
    Update-Status "Applying IP configuration..."
    
    try {
        if ($script:rbDHCP.IsChecked) {
            # Enable DHCP
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled -ErrorAction Stop
            
            # Remove static IP addresses
            Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                Where-Object { $_.PrefixOrigin -eq "Manual" } | 
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            
            # Remove static gateway
            Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            
            Update-Status "DHCP enabled on $($adapter.Name)" -Type Success
        } else {
            # Static IP configuration
            $ip = $script:txtIPAddress.Text.Trim()
            $gateway = $script:txtGateway.Text.Trim()
            $prefix = [int]$script:txtPrefix.Text.Trim()
            
            if (-not (Test-ValidIP $ip)) {
                Show-MessageBox -Message "Invalid IP address format." -Title "Validation Error" -Icon Error
                return
            }
            
            # Remove existing configuration
            Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            
            # Apply new configuration
            New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
            
            if (Test-ValidIP $gateway) {
                New-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop $gateway -ErrorAction Stop | Out-Null
            }
            
            Update-Status "Static IP $ip configured on $($adapter.Name)" -Type Success
        }
        
        Start-Sleep -Milliseconds 500
        Update-AdapterDisplay
    } catch {
        Update-Status "Error: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to apply IP configuration:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
}

function Apply-DNSConfiguration {
    $adapter = Get-SelectedAdapter
    if ($null -eq $adapter) {
        Show-MessageBox -Message "Please select a network adapter first." -Title "No Adapter Selected" -Icon Warning
        return
    }
    
    $result = Show-MessageBox -Message "Apply DNS configuration to '$($adapter.Name)'?" -Title "Confirm" -Buttons YesNo -Icon Question
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    
    Update-Status "Applying DNS configuration..."
    
    try {
        if ($script:rbDnsDHCP.IsChecked) {
            # Use DHCP for DNS
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            Update-Status "DNS set to automatic on $($adapter.Name)" -Type Success
        }
        elseif ($script:rbDnsPreset.IsChecked) {
            $selected = $script:lstDnsPresets.SelectedItem
            if ($null -eq $selected) {
                Show-MessageBox -Message "Please select a DNS preset." -Title "No Selection" -Icon Warning
                return
            }
            
            $preset = $selected.Tag.Data
            if ($preset.Primary -eq "DHCP") {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            } else {
                $dnsServers = @($preset.Primary)
                if ($preset.Secondary) { $dnsServers += $preset.Secondary }
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsServers -ErrorAction Stop
            }
            Update-Status "DNS preset '$($selected.Tag.Name)' applied to $($adapter.Name)" -Type Success
        }
        else {
            # Custom DNS
            $primary = $script:txtDnsPrimary.Text.Trim()
            $secondary = $script:txtDnsSecondary.Text.Trim()
            
            if (-not (Test-ValidIP $primary)) {
                Show-MessageBox -Message "Invalid primary DNS address." -Title "Validation Error" -Icon Error
                return
            }
            
            $dnsServers = @($primary)
            if (Test-ValidIP $secondary) { $dnsServers += $secondary }
            
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsServers -ErrorAction Stop
            Update-Status "Custom DNS applied to $($adapter.Name)" -Type Success
        }
        
        Update-AdapterDetails
    } catch {
        Update-Status "Error: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to apply DNS configuration:`n$($_.Exception.Message)" -Title "Error" -Icon Error
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
    
    Update-Status "Applying profile '$($profile.Name)'..."
    
    try {
        # Apply IP configuration
        if ($profile.UseDHCP) {
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled -ErrorAction Stop
            Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                Where-Object { $_.PrefixOrigin -eq "Manual" } | 
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        } else {
            Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            
            $prefix = if ($profile.PrefixLength) { [int]$profile.PrefixLength } else { 24 }
            New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $profile.IPAddress -PrefixLength $prefix -ErrorAction Stop | Out-Null
            
            if (Test-ValidIP $profile.Gateway) {
                New-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop $profile.Gateway -ErrorAction Stop | Out-Null
            }
        }
        
        # Apply DNS configuration
        if ($profile.UseDHCPForDNS) {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
        } else {
            $dnsServers = @()
            if (Test-ValidIP $profile.PrimaryDNS) { $dnsServers += $profile.PrimaryDNS }
            if (Test-ValidIP $profile.SecondaryDNS) { $dnsServers += $profile.SecondaryDNS }
            if ($dnsServers.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsServers -ErrorAction Stop
            }
        }
        
        Update-Status "Profile '$($profile.Name)' applied successfully" -Type Success
        Start-Sleep -Milliseconds 500
        Update-AdapterDisplay
    } catch {
        Update-Status "Error: $($_.Exception.Message)" -Type Error
        Show-MessageBox -Message "Failed to apply profile:`n$($_.Exception.Message)" -Title "Error" -Icon Error
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
            
            if ($import.Profiles) {
                foreach ($profile in $import.Profiles) {
                    $safeName = $profile.Name -replace '[^\w\-]', '_'
                    $filePath = Join-Path $script:ProfilesPath "$safeName.json"
                    $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
                }
            }
            
            Refresh-ProfileList
            Update-Status "Configuration imported successfully" -Type Success
        } catch {
            Update-Status "Import failed: $($_.Exception.Message)" -Type Error
        }
    }
}

# ============================================================================
# EVENT HANDLERS
# ============================================================================
$lstAdapters.Add_SelectionChanged({
    Update-AdapterDisplay
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
})

$rbDnsPreset.Add_Checked({
    $script:pnlCustomDns.IsEnabled = $false
    $script:pnlCustomDns.Opacity = 0.6
})

$rbDnsCustom.Add_Checked({
    $script:pnlCustomDns.IsEnabled = $true
    $script:pnlCustomDns.Opacity = 1.0
})

$lstDnsPresets.Add_SelectionChanged({
    Update-SelectedDnsDisplay
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

# Button event handlers
$btnRefresh.Add_Click({ Refresh-AdapterList })
$btnExport.Add_Click({ Export-AllConfiguration })
$btnImport.Add_Click({ Import-Configuration })
$btnEnableAdapter.Add_Click({ Enable-SelectedAdapter })
$btnDisableAdapter.Add_Click({ Disable-SelectedAdapter })
$btnApplyIP.Add_Click({ Apply-IPConfiguration })
$btnApplyDns.Add_Click({ Apply-DNSConfiguration })
$btnNewProfile.Add_Click({
    $script:txtProfileName.Text = "New Profile"
    $script:txtProfileDesc.Text = ""
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
$btnApplyProfile.Add_Click({ Apply-Profile })
$btnFlushDns.Add_Click({ Invoke-FlushDns })
$btnReleaseIP.Add_Click({ Invoke-ReleaseIP })
$btnRenewIP.Add_Click({ Invoke-RenewIP })
$btnResetWinsock.Add_Click({ Invoke-ResetWinsock })
$btnResetTCP.Add_Click({ Invoke-ResetTCP })
$btnNetworkReset.Add_Click({ Invoke-NetworkReset })
$btnPing.Add_Click({ Invoke-Ping })
$btnTraceroute.Add_Click({ Invoke-Traceroute })
$btnNslookup.Add_Click({ Invoke-Nslookup })

# ============================================================================
# INITIALIZATION
# ============================================================================
Refresh-AdapterList
Refresh-DnsPresets
Refresh-ProfileList

# Select first adapter if available
if ($lstAdapters.Items.Count -gt 0) {
    $lstAdapters.SelectedIndex = 0
}

# ============================================================================
# SHOW WINDOW
# ============================================================================
$window.ShowDialog() | Out-Null
