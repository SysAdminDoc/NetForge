# CLAUDE.md - NetForge

## Overview
WPF GUI for managing Windows network adapters. Static/DHCP configuration, DNS preset library, profile save/load, IPv6 support. v1.0.0.

## Tech Stack
- PowerShell 5.1, WPF GUI
- Settings/profiles stored in `%APPDATA%\NetForge\Profiles`

## Key Details
- ~2,165 lines, single-file
- DNS presets: Google, Cloudflare, Quad9, NextDNS, OpenDNS, and more
- Actions: flush DNS, release/renew, reset adapter, toggle adapter state
- Full ComboBox ControlTemplates for dark mode dropdowns
- Named network profile persistence

## Build/Run
```powershell
.\NetForge.ps1
```

## Version
1.0.0

## File Paths
- Settings: `%APPDATA%\NetForge\`
- Profiles: `%APPDATA%\NetForge\Profiles\`
