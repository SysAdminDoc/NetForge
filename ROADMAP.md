# Roadmap

PowerShell/WPF network adapter manager: IP/DHCP switching, 40+ DNS presets, profile system, diagnostics. Roadmap targets laptop roaming, advanced diagnostics, and deeper DNS-over-* support.

## Planned Features

### Adapter Control

### DNS Over HTTPS/TLS/QUIC

### Profiles
- Cloud-sync profiles via OneDrive folder path
- Import from `netsh wlan export profile` XML
- Schedule profile switches (home at 6pm, work at 8am)

### Diagnostics
- MTR-style continuous traceroute with per-hop latency history
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
- Location-aware profile switching with auto-detect on network change events (argon-network-switcher, autoproxyswitcher) — "I plugged into clinic network, apply Clinic profile"
- Bundled DNS preset list (Cloudflare 1.1.1.1, Quad9, NextDNS, AdGuard, Google) with one-click apply (DNSChanger)
- DoQ encrypted DNS support via local proxy (AdGuard dnsproxy) - NetForge now has external dnsproxy controls plus native Windows DoH/DoT metadata
- Per-application adapter binding (bindip) — pin Zoom to Wi-Fi, pin backup to Ethernet, without VPN split tunneling
- Profile includes: IP+DNS+Proxy+printers+mapped-drives (argon-network-switcher)
- Network Category (Public/Private) toggle via INetworkListManager (microsoft/windows-networking-tools) — common clinic workflow, awkward in Settings UI
- DNS round-trip latency test per-profile to pick fastest resolver (DNSChanger feature)
- System-service mode that watches for interface changes and re-applies policy (gpailler/DnsProxy)

### Patterns & Architectures Worth Studying
- INetworkListManager COM events vs WMI adapter-change polling — Microsoft's own sample uses INetworkListManager; more efficient than our WMI polling
- Profile schema: (SSID/network-name match rules) → (IP config, DNS, proxy, firewall category, printers) — argon-network-switcher's XML schema is a clean reference
- Documented Windows API proxy switching vs registry-poke (lion06/autoproxyswitcher) — survives Windows updates better
- Modern Windows.Networking.NetworkInformation WinRT vs legacy netsh/WMI — NetForge is PowerShell WPF, consider WinRT cmdlets for faster enumeration
- PS5.1 compatibility shim — none of these projects target PS5.1; NetForge's edge is working on LTSC without .NET updates

## Research-Driven Additions

### P1
- [ ] P1 - Add Pester and PSScriptAnalyzer quality gates
  Why: The app is a single high-privilege script and currently has no tracked tests; parser check passed but analyzer found maintainability and reliability warnings.
  Evidence: `NetForge.ps1` parse OK, PSScriptAnalyzer warnings for empty catches, `$profile` automatic-variable shadowing, and runspace variable scope.
  Touches: `tests/`, `NetForge.ps1`, local build/test scripts, README test instructions.
  Acceptance: Local test command runs parser validation, PSScriptAnalyzer with a committed baseline/allowlist, and Pester tests for validation, profile migration, endpoint parsing, and command-plan generation.
  Complexity: M

- [ ] P1 - Add accessibility names, focus order, and high-contrast checks
  Why: The WPF UI has many custom controls but no `AutomationProperties.Name`, making Narrator/UI Automation coverage weak.
  Evidence: `NetForge.ps1:407-1780`, Microsoft WPF accessibility guidance.
  Touches: XAML styles, adapter/DNS/profile/diagnostics controls, screenshot capture process.
  Acceptance: Primary controls have automation names, tab order follows visual workflow, high-contrast mode preserves readable labels/status, and an accessibility smoke script verifies key controls by automation ID/name.
  Complexity: M

- [ ] P1 - Add encrypted DNS leak, fallback, and resolver latency checks
  Why: DoH/DoT registration and DoQ proxy start are not enough to prove queries are encrypted, non-leaking, or performant.
  Evidence: `NetForge.ps1:3748-4304`, YogaDNS, Simple DNSCrypt, DNS Jumper, RFC 8484/RFC 7858/RFC 9250.
  Touches: DNS tab, `Invoke-EncryptedDnsHealthTest`, `Invoke-StartDoqProxy`, diagnostics output.
  Acceptance: DNS health shows configured adapter DNS, encrypted endpoint probe, UDP fallback state, local-proxy listener state, and per-resolver latency table before applying a preset.
  Complexity: L

- [ ] P1 - Harden profile storage sync and migration
  Why: Folder-based sync is useful, but changing the storage path without migration/conflict handling risks missing or overwritten profiles.
  Evidence: local dirty-tree `Save-AppSetting`, `Invoke-ProfileStoreChange`, `Get-OneDriveProfileStore`; NetSetMan/argon-network-switcher profile portability.
  Touches: profile storage controls, `Save-AppSetting`, `Invoke-ProfileStoreChange`, profile import/export.
  Acceptance: Changing storage can copy existing profiles, detect same-name conflicts, keep a backup manifest, report sync path health, and revert to local storage without data loss.
  Complexity: M

### P2
- [ ] P2 - Centralize version and release metadata
  Why: Script, README badge, changelog, working notes, and dist zip are still updated manually and can drift across releases.
  Evidence: `NetForge.ps1:7`, `NetForge.ps1:47`, `README.md`, `CHANGELOG.md`, working notes, release zip naming.
  Touches: `NetForge.ps1`, README, changelog, working notes, release packaging script.
  Acceptance: One version source updates script header/UI, README badge, changelog heading, release zip name, and working notes; local verification fails on mismatch.
  Complexity: S

- [ ] P2 - Ship signed/checksummed release artifacts
  Why: A high-privilege PowerShell network tool should make authenticity and install path clear.
  Evidence: PowerShell signing docs, execution policy docs, current release zip artifact.
  Touches: release script, dist artifact, README install section, GitHub release asset process.
  Acceptance: Release build produces a clean zip, SHA256 file, optional Authenticode signature when a certificate exists, and README instructions for verifying the artifact.
  Complexity: M

- [ ] P2 - Move DNS providers into a validated catalog
  Why: DNS providers change endpoints and features; editing a 5,313-line script for preset maintenance increases risk.
  Evidence: `NetForge.ps1:82-719`, AdGuard dnsproxy, NextDNS Windows docs, Control D `ctrld`, DNSCrypt Proxy.
  Touches: DNS preset loading, provider schema, catalog validation, DNS tab filtering.
  Acceptance: Built-in catalog loads from signed/hashed JSON with schema validation, supports provider capabilities (IPv4, IPv6, DoH, DoT, DoQ, family/security/ad-blocking), and falls back to embedded defaults offline.
  Complexity: L

- [ ] P2 - Externalize UI strings for localization
  Why: All UI text is embedded in XAML/functions, blocking translation and increasing copy drift.
  Evidence: `NetForge.ps1:700-1780`, Microsoft WPF globalization/localization guidance, DNS Jumper multi-language distribution.
  Touches: XAML text, status/message strings, profile import/export labels, README locale notes.
  Acceptance: User-visible strings resolve through a resource table, English remains default, missing keys fail tests, and at least one second locale file proves the path.
  Complexity: L

- [ ] P2 - Add configurable offline/privacy endpoints
  Why: Public-IP and speed-test features contact third-party endpoints automatically or on demand without user-visible endpoint policy.
  Evidence: `NetForge.ps1:3037-3068`, `NetForge.ps1:3293-3394`.
  Touches: settings file, status bar public IP, speed test, diagnostics settings UI.
  Acceptance: Users can disable public-IP lookup, select HTTPS-only speed-test endpoints, see last-contacted endpoint in logs, and run diagnostics without external calls.
  Complexity: M

### P3
- [ ] P3 - Add optional standard-user helper service
  Why: Running the entire GUI elevated increases blast radius; a small broker can constrain privileged network mutations.
  Evidence: Windows service pattern in `gpailler/DnsProxy`, current `#Requires`/auto-elevation flow in `NetForge.ps1:19-31`.
  Touches: helper service project or script, IPC contract, command authorization, installer/release package.
  Acceptance: GUI can run unelevated, privileged actions are sent to a signed local helper with an allowlisted command contract, and logs show caller/action/result.
  Complexity: XL

- [ ] P3 - Expand profiles to Windows network category, proxy, printers, and mapped drives
  Why: Mature switchers treat a network profile as an environment, not just IP/DNS.
  Evidence: NetSetMan, argon-network-switcher, Microsoft Network List Manager docs, existing roadmap profile research.
  Touches: profile schema migration, profile editor, apply/rollback planner, import/export.
  Acceptance: Profiles can optionally set Public/Private category, system proxy, default printer, and mapped drives, with preview diff and rollback coverage for each action.
  Complexity: XL
