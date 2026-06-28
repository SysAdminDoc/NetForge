# Research - NetForge

## Executive Summary
NetForge is a Windows PowerShell 5.1/WPF network adapter manager with a strong single-screen operations shape: adapter status, IPv4/DNS switching, encrypted DNS registration, WiFi controls, profiles, and diagnostics are already in one portable script. The highest-value direction is to harden state-changing network operations before adding more surface area: preflight validation and rollback, schema-safe profile import/storage, persistent diagnostics, event-driven profile matching, test coverage, accessibility, DNS leak/latency checks, packaging, and provider catalog maintenance.

Top opportunities:
- P0: Add preflight validation, snapshots, and rollback for profile/IP/DNS changes.
- P0: Version and validate profile/import JSON, then write atomically.
- P0: Add persistent operation logs, crash logs, and a diagnostic export.
- P1: Replace 60-second profile polling with Windows network-change events.
- P1: Add a Pester/PSScriptAnalyzer harness for the single script.
- P1: Add WPF accessibility names, focus order, and high-contrast checks.
- P1: Add encrypted DNS leak/fallback and resolver latency validation.
- P2: Ship signed/checksummed release artifacts and align version docs.
- P2: Move DNS/provider metadata into a validated catalog update path.

## Product Map
- Core workflows: choose an adapter, apply DHCP/static IPv4, apply preset/custom DNS, register DoH/DoT/DoQ metadata, save/apply profiles, run diagnostics.
- User personas: Windows laptop roamers, field techs, helpdesk/admin users, privacy/security DNS users, power users managing multiple adapters.
- Platforms and distribution: Windows 10/11, Windows PowerShell 5.1, WPF/.NET Framework, administrator launch, current distribution as `NetForge.ps1` plus `dist/NetForge-v1.13.0.zip`.
- Key integrations and data flows: Windows NetTCPIP/DnsClient cmdlets, `netsh wlan`, `netsh dns`, `ipconfig`, external `dnsproxy.exe`, JSON profiles under `%APPDATA%\NetForge\Profiles`, optional local dirty-tree profile sync path, public-IP and speed-test HTTP endpoints.

## Competitive Landscape
- NetSetMan: Mature network profile switching, automatic location detection, and broad profile actions. Learn from its profile breadth and event-like switching; avoid burying core actions behind dense configuration dialogs.
- Simple IP Config: Small open-source static IP/DNS profile switcher. Learn from its focused profile model; avoid staying limited to IPv4-only profile fields.
- Simple DNSCrypt: Clear encrypted-DNS status and resolver selection. Learn from explicit resolver health/trust signals; avoid implying encryption is active when only metadata was registered.
- YogaDNS: Rule-based encrypted DNS client for Windows. Learn from per-network/per-process DNS routing concepts; avoid building a full resolver stack into the PowerShell GUI.
- DNS Jumper: DNS benchmark and fast resolver selection. Learn from one-click latency comparison; avoid opaque "fastest" choices without showing measurements.
- NetAdapter Repair All In One: Repair-oriented reset workflow. Learn from grouped repair actions and clear restart expectations; avoid destructive repair actions without rollback/export first.
- AdGuard `dnsproxy` and DNSCrypt Proxy: Proven local encrypted DNS proxies with DoH/DoT/DoQ/DNSCrypt support. Learn from delegating transport complexity to maintained proxies; avoid bundling unsigned binaries.
- Microsoft networking APIs: Network List Manager and Windows.Networking.Connectivity expose change events. Learn from event-driven detection; avoid indefinite polling as profile complexity grows.

## Security, Privacy, and Reliability
- Verified: `NetForge.ps1:4570-4608` applies profiles by removing existing IPv4 addresses/routes before the full target profile is validated and without a captured rollback bundle.
- Verified: `NetForge.ps1:4701-4818` applies adapter IP/DNS changes with user confirmation, but no reusable snapshot/restore path if a later command fails.
- Verified: `NetForge.ps1:4386-4477` loads and saves profiles without schema versioning, uniqueness checks, or atomic temp-file replacement; corrupt profiles are swallowed by an empty catch.
- Verified: `NetForge.ps1:5087-5107` imports every incoming profile object and writes profile JSON without validating required fields, duplicate names, or target path collisions.
- Verified: `NetForge.ps1:3037-3068` and `NetForge.ps1:3293-3394` call external public-IP and speed-test endpoints with no offline/privacy mode or configurable endpoint list.
- Verified: PSScriptAnalyzer flags empty catch blocks, `$profile` assignments that shadow PowerShell's `$PROFILE`, and runspace variable-scope warnings around ping/traceroute jobs.
- Verified: local working tree `NetForge.ps1` is `1.14.0` while tracked docs still describe `1.13.0`; release metadata can drift unless versioning is centralized.
- Missing guardrails: rollback snapshots, profile schema migrations, import dry-run, DNS leak check, signed proxy/download verification, persistent log file, crash log file, diagnostic export, and repeatable analyzer/test gates.
- Recovery needs: "restore previous network state" from last snapshot, "open log folder", "export diagnostic bundle", and "revert profile storage path and migrate files back".

## Architecture Assessment
- Verified: the app is a 5,313-line single script. Split implementation behind stable functions/modules for NetState, ProfileStore, DnsEncryption, Wifi, Diagnostics, and UI wiring before larger feature work.
- Verified: destructive network actions are interleaved with WPF event handlers and status text. Extract pure validation/planning functions so tests can exercise them without admin/network mutation.
- Verified: no tracked test suite exists. Add Pester tests for IP/profile/DNS validation, profile migration, DNS endpoint parsing, NextDNS ID parsing, and command-plan generation.
- Verified: WPF controls do not define `AutomationProperties.Name`; add accessible names, tab order checks, and high-contrast verification for adapter/profile/DNS workflows.
- Likely: profile sync via arbitrary folders needs migration/conflict handling before it is safe as a OneDrive workflow; the current dirty-tree implementation changes paths but does not copy, merge, lock, or resolve conflicts.
- Likely: profile auto-apply should move from timer polling (`NetForge.ps1:5260-5265`) to Network List Manager or Windows.Networking.Connectivity events to reduce delay and avoid repeated background network probes.
- Documentation gaps: README still says screenshots are "Coming soon" despite `screenshot.png`, and version/release/docs can drift across README, CHANGELOG, working notes, script header, and dist zip.

## Rejected Ideas
- Keyboard shortcuts: current product rules reject shortcut-driven workflows; keep quick actions in visible UI/tray controls instead.
- Mobile companion app: weak fit for a Windows admin utility; QR/profile sharing can be handled by export/import if later needed.
- Bundled packet-capture driver by default: Npcap/Wireshark integration adds driver install and trust burden; keep capture optional and gated after rollback/logging exists.
- Full per-app WFP routing now: useful but high-risk and kernel-adjacent; prefer profile reliability, DNS leak checks, and adapter binding research first.
- Replacing `dnsproxy.exe` with an in-script DoQ resolver: maintained proxy projects already solve protocol churn better than a PowerShell implementation.
- Cloud account sync service: folder-based sync is enough if schema, migration, and conflict handling are hardened.

## Sources
Competitors and adjacent tools:
- https://www.netsetman.com/
- https://github.com/KurtisLiggett/Simple-IP-Config
- https://github.com/bitbeans/SimpleDnsCrypt
- https://www.yogadns.com/
- https://www.sordum.org/7952/dns-jumper-v2-3/
- https://www.netadapterrepair.com/
- https://github.com/AdguardTeam/dnsproxy
- https://github.com/DNSCrypt/dnscrypt-proxy
- https://github.com/Zaczero/DNSChanger
- https://github.com/DnsChanger/dnsChanger-desktop
- https://github.com/xcesco/argon-network-switcher
- https://github.com/microsoft/windows-networking-tools
- https://github.com/Control-D-Inc/ctrld
- https://github.com/nextdns/nextdns/wiki/Windows

Standards and platform APIs:
- https://www.rfc-editor.org/rfc/rfc8484
- https://www.rfc-editor.org/rfc/rfc7858
- https://www.rfc-editor.org/rfc/rfc9250
- https://learn.microsoft.com/en-us/powershell/module/dnsclient/set-dnsclientserveraddress
- https://learn.microsoft.com/en-us/powershell/module/dnsclient/set-dnsclientdohserveraddress
- https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface
- https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netipaddress
- https://learn.microsoft.com/en-us/windows/win32/nla/network-list-manager-portal
- https://learn.microsoft.com/en-us/windows/win32/api/netlistmgr/nn-netlistmgr-inetworklistmanagerevents
- https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.networkstatuschanged
- https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/accessibility
- https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/wpf-globalization-and-localization-overview

Tooling and distribution:
- https://github.com/PowerShell/PSScriptAnalyzer
- https://pester.dev/
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies

## Open Questions
None.
