# Roadmap

PowerShell/WPF network adapter manager: IP/DHCP switching, 40+ DNS presets, profile system, diagnostics. Roadmap targets laptop roaming, advanced diagnostics, and deeper DNS-over-* support.

## Planned Features

### Adapter Control

### DNS Over HTTPS/TLS/QUIC

### Profiles

### Diagnostics

### IPv6 & Advanced

### UX

## Competitive Research
- **NetSetMan** — the reference for profile switching; borrow its per-SSID auto-apply pattern.
- **NetAdapter Repair All-in-One** — leader on repair actions; mirror its reset depth.
- **Simple DNSCrypt** — UX reference for encrypted DNS configuration.
- **YogaDNS** — DoH/DoT proxy layer on Windows; study integration approach.

## Nice-to-Haves

## Open-Source Research (Round 2)

### Related OSS Projects
- https://github.com/allisonsteranko/IP-Config-GUI — classic Win7/8 IP config GUI, reference for adapter enumeration patterns
- https://github.com/microsoft/windows-networking-tools — official Microsoft samples, INetworkListManager COM + Windows.Networking.NetworkInformation WinRT APIs
- https://github.com/katlogic/bindip — app-to-adapter binding (poor-man's NETNS) via registry mapping
- https://github.com/xcesco/argon-network-switcher — Java network/proxy/printer/mapped-drive profile switcher, Apache 2.0
- https://github.com/Zaczero/DNSChanger — .NET DNS changer with DoH/DNSCrypt, bundled profiles for Cloudflare/Google/AdGuard/NextDNS/Quad9
- https://github.com/AdguardTeam/dnsproxy — DoH/DoT/DoQ/DNSCrypt proxy for local resolver
- https://github.com/gpailler/DnsProxy — .NET 8 DNS forwarder with interface-change monitoring, runs as Windows service
- https://github.com/HirbodBehnam/Proxy-Switcher — system proxy toggling with tray minimize
- https://github.com/lion06/autoproxyswitcher — auto-proxy based on network change detection, documented Windows APIs
- https://github.com/DnsChanger/dnsChanger-desktop — cross-platform Electron DNS changer

### Features to Borrow
- Per-application adapter binding (bindip) — pin Zoom to Wi-Fi, pin backup to Ethernet, without VPN split tunneling
- System-service mode that watches for interface changes and re-applies policy (gpailler/DnsProxy)

### Patterns & Architectures Worth Studying
- INetworkListManager COM events vs WMI adapter-change polling — Microsoft's own sample uses INetworkListManager; more efficient than our WMI polling
- Profile schema: (SSID/network-name match rules) → (IP config, DNS, proxy, firewall category, printers) — argon-network-switcher's XML schema is a clean reference
- Documented Windows API proxy switching vs registry-poke (lion06/autoproxyswitcher) — survives Windows updates better
- Modern Windows.Networking.NetworkInformation WinRT vs legacy netsh/WMI — NetForge is PowerShell WPF, consider WinRT cmdlets for faster enumeration
- PS5.1 compatibility shim — none of these projects target PS5.1; NetForge's edge is working on LTSC without .NET updates

## Audit Findings (2026-07-01)

### P1

- [ ] P1 -- Move Update-ConnectionStatus networking calls to background runspace
  Why: ConnStatusTimer fires every 30s and runs Get-NetIPAddress, Get-NetRoute, netsh wlan show interfaces synchronously on the UI thread.
  Where: `NetForge.ps1` Update-ConnectionStatus, Update-WifiInfo

- [ ] P1 -- Consolidate duplicate networking cmdlet calls in Update-AdapterDisplay / Update-AdapterDetails
  Why: 10+ networking cmdlet calls with 3 duplicates (Get-NetIPInterface, Get-NetRoute, Get-NetIPAddress) every time adapter selection changes.
  Where: `NetForge.ps1` Update-AdapterDisplay, Update-AdapterDetails

### P2

- [ ] P2 -- Add test coverage for Restore-NetworkSnapshot / Invoke-NetworkMutation control flow
  Why: Safety-critical rollback code has zero test coverage. Extract a testable planning step.
  Where: `tests/NetForge.Tests.ps1`

- [ ] P2 -- Add mapped drive UNC path external-server warning
  Why: Profile QR code imports can map drives to attacker-controlled SMB servers, leaking NTLM hashes from the elevated process.
  Where: `NetForge.ps1` Set-MappedDriveState

- [ ] P2 -- Move Invoke-AdapterRestartForMac to background runspace
  Why: 2.4 seconds of Start-Sleep blocking the UI thread during MAC override/revert.
  Where: `NetForge.ps1` Invoke-AdapterRestartForMac

- [ ] P2 -- Cache netsh wlan show interfaces output with TTL
  Why: Called independently by Update-WifiInfo (every 30s) and Get-CurrentNetworkSignature (every 5m).
  Where: `NetForge.ps1` Update-WifiInfo, Get-CurrentNetworkSignature

### P3

- [ ] P3 -- Add maximum entry count per hosts group
  Why: No limit on entries per group or total groups allows unbounded hosts file growth via crafted import.
  Where: `NetForge.ps1` ConvertTo-HostsManagedSection

