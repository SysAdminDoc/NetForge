# Roadmap

PowerShell/WPF network adapter manager: IP/DHCP switching, 40+ DNS presets, profile system, diagnostics. Roadmap targets laptop roaming, advanced diagnostics, and deeper DNS-over-* support.

## Planned Features

### Adapter Control

### DNS Over HTTPS/TLS/QUIC

### Profiles

### Diagnostics
- Port scanner (nmap-lite via raw sockets) for LAN device discovery
- Packet capture to `.pcap` via Npcap wrapper + optional Wireshark launch
- Cable diagnostics (DDM/DOM SFP reads on server NICs that support it)
- Wi-Fi spectrum view (channel utilization) with BSSID list
- Latency histogram to any endpoint over N seconds

### IPv6 & Advanced
- IPv6 address/prefix configuration UI (currently IPv4-centric)
- Static route editor
- Hosts file editor with entry-group toggles
- Adapter binding priority (IPv4-first vs IPv6-first)

### UX
- System tray mode with quick DNS / profile switcher
- Dark theme alternatives (Catppuccin, Nord)
- Hotkey to apply "Home" or "Work" profile
- Compact mode for laptops

## Competitive Research
- **NetSetMan** — the reference for profile switching; borrow its per-SSID auto-apply pattern.
- **NetAdapter Repair All-in-One** — leader on repair actions; mirror its reset depth.
- **Simple DNSCrypt** — UX reference for encrypted DNS configuration.
- **YogaDNS** — DoH/DoT proxy layer on Windows; study integration approach.

## Nice-to-Haves
- QR-code import/export of profiles (scan from phone app)
- CLI companion (`netforge.ps1 -ApplyProfile Home -Silent`) for scripting
- RDP launch with auto-profile switch + revert on disconnect
- Integrated "why can't I reach X" wizard (DNS → gateway → route → firewall → MTU)
- Discord webhook on profile apply for fleet tracking
- Per-app routing rules via WFP (force browser through VPN, leave others direct)

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
