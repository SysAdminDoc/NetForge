# CLAUDE.md - NetForge

## Overview
WPF GUI for managing Windows network adapters. Static/DHCP configuration, DNS preset library, profile save/load, IPv6 support, diagnostics tab with ping/speed test/DNS lookup, live connection status bar with WiFi info. v1.1.0.

## Tech Stack
- PowerShell 5.1, WPF GUI
- Settings/profiles stored in `%APPDATA%\NetForge\Profiles`
- Async via `[PowerShell]::Create()` + `BeginInvoke()` + `DispatcherTimer`

## Key Details
- ~2,960 lines, single-file
- DNS presets: Google, Cloudflare, Quad9, NextDNS, OpenDNS, and more
- Actions: flush DNS, release/renew, reset adapter, toggle adapter state
- Full ComboBox ControlTemplates for dark mode dropdowns
- Named network profile persistence
- Connection status bar: connected/disconnected dot, local/public IP, gateway, connection type
- WiFi info panel: SSID, signal strength, channel, band, auth, link speed (via netsh)
- Diagnostics tab: ping test (10 pings, min/avg/max stats), continuous ping (color-coded), speed test (~10MB download), DNS lookup
- No emoji/unicode anywhere (encoding safety)

## Build/Run
```powershell
.\NetForge.ps1
```

## Version
1.1.0

## File Paths
- Settings: `%APPDATA%\NetForge\`
- Profiles: `%APPDATA%\NetForge\Profiles\`
