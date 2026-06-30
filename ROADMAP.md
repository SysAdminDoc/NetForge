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

## Research-Driven Additions

### P1

- [ ] P1 — Add DoQ proxy binary trust and session observability
  Why: NetForge launches an operator-selected `dnsproxy.exe` but does not record binary hash/publisher, capture stdout/stderr, or explain proxy crash/hang states.
  Evidence: `NetForge.ps1:7768-7833`; AdGuard `dnsproxy` issues; Control D `ctrld` issue 308; RESEARCH.md Competitive Landscape.
  Touches: `NetForge.ps1` DoQ proxy helpers, operation logs, diagnostics export, `tests/NetForge.Tests.ps1`.
  Acceptance: Validate Proxy reports version, full path, SHA256, Authenticode status when available, and file modified time; Start Proxy captures stdout/stderr to `%APPDATA%\NetForge\Logs`; health output shows running/exited/stale state and last error; tests cover command-plan/log-path formatting without starting a real proxy.
  Complexity: M

- [ ] P1 — Add current release screenshot and visual/package smoke
  Why: committed `screenshot.png` still shows v1.13.0 and README has a "Screenshots Coming soon" section while the project ships v1.48.0 releases.
  Evidence: `screenshot.png`; `README.md:162`; GitHub release `v1.48.0`; RESEARCH.md Security.
  Touches: `screenshot.png`, `README.md`, `tools\Test-NetForge.ps1`, optional screenshot capture helper.
  Acceptance: screenshot shows current version and current tabs, README screenshot section no longer contradicts the asset, local checks fail if the screenshot-visible version lags `version.json`, and release packaging includes the refreshed image.
  Complexity: M

- [ ] P1 — Add in-app release and checksum verification
  Why: GitHub releases already publish zip and `.sha256` assets, but users must manually compare checksums from README instructions.
  Evidence: GitHub release `v1.48.0` assets; `README.md` installation section; NetSetMan update/licensing docs; RESEARCH.md Architecture.
  Touches: `NetForge.ps1` Diagnostics tab, release metadata helpers, endpoint policy controls, `tests/NetForge.Tests.ps1`.
  Acceptance: Diagnostics offers "Check Release" that fetches latest GitHub release metadata over HTTPS, compares `version.json`/`$script:AppVersion`, displays zip and checksum asset names plus digest, never auto-installs, respects offline/privacy failure states, and tests cover version comparison and asset selection.
  Complexity: M

### P2

- [ ] P2 — Add local DNS provider catalog freshness tooling
  Why: `dns-providers.json` is validated by hash, but there is no local tool to compare provider endpoints/capabilities against official provider docs or regenerate the sidecar safely.
  Evidence: `dns-providers.json`, `dns-providers.json.sha256`, `tools\Test-NetForge.ps1`; DNS Jumper provider/benchmark flow; Cloudflare DNS docs; RESEARCH.md Architecture.
  Touches: `dns-providers.json`, `dns-providers.json.sha256`, `tools\Test-NetForge.ps1`, new non-markdown tool under `tools\`, `tests/NetForge.Tests.ps1`.
  Acceptance: a local tool validates provider URL/DoH/DoT/DoQ fields, flags stale or unreachable documented endpoints without mutating by default, can regenerate the hash after intentional edits, and Pester covers malformed provider entries plus hash drift.
  Complexity: M

- [ ] P2 — Add local dependency and advisory gate for vendored DLLs
  Why: QRCoder and ZXing.Net are vendored binaries, so normal package-manager update visibility does not exist.
  Evidence: `lib/QRCoder.dll` version 1.8.0.0, `lib/zxing.dll` version 0.16.11.0, GitHub Advisory API queries, QRCoder/ZXing release pages; RESEARCH.md Sources.
  Touches: `tools\Test-NetForge.ps1`, new dependency manifest data file if needed, `tests/NetForge.Tests.ps1`, `lib\`, `licenses\`.
  Acceptance: local checks report vendored DLL name/version/license/source URL, query or document current GitHub Advisory/NuGet advisory status, fail on unknown DLL drift or missing license notice, and require intentional manifest updates for library replacement.
  Complexity: M

- [ ] P2 — Build source-module boundaries while preserving single-file release output
  Why: `NetForge.ps1` is 13,307 lines and 355 functions, which raises change risk as feature work continues.
  Evidence: `NetForge.ps1`, `tests/NetForge.Tests.ps1`, `tools\New-NetForgeReleasePackage.ps1`; RESEARCH.md Architecture.
  Touches: new non-markdown source files under `src\`, `NetForge.ps1`, `tools\New-NetForgeReleasePackage.ps1`, `tools\Test-NetForge.ps1`, `tests\NetForge.Tests.ps1`.
  Acceptance: pure helpers for settings/secrets, DNS catalog, app guard policy, DoQ proxy, diagnostics export, and release metadata live in source modules; a local build step composes the portable `NetForge.ps1`; package output remains a single runnable script; existing 79 tests plus new module/build tests pass.
  Complexity: XL

- [ ] P2 — Add rendered UI, theme, compact-mode, and accessibility smoke tests
  Why: current tests validate static strings/accessibility metadata but do not prove every tab renders across themes or compact mode after rapid UI growth.
  Evidence: `NetForge.ps1:1556`, `NetForge.ps1:1765`, `NetForge.ps1:2004`, `NetForge.ps1:2101`, `NetForge.ps1:2334`, `NetForge.ps1:2621`; `tests/NetForge.Tests.ps1:1561`; RESEARCH.md Architecture.
  Touches: `tools\Test-NetForge.ps1`, `tests\`, optional non-markdown UI smoke helper, theme/compact/accessibility helpers in `NetForge.ps1`.
  Acceptance: local checks can run a non-mutating WPF load smoke that verifies all major tabs, supported themes, compact mode, automation names, and minimum window constraints without changing network settings; failures include the missing control name/tab/theme.
  Complexity: L


- [ ] P2 — Add auto-apply priority and match-status inspector
  Why: NetSetMan exposes AutoSwitch priority/status, while NetForge mostly records auto-apply match/skip reasoning in logs.
  Evidence: NetSetMan AutoSwitch docs; `NetForge.ps1:10035-10070`; operation log auto-apply entries; RESEARCH.md Competitive Landscape.
  Touches: `NetForge.ps1` Profiles tab, auto-apply matcher, operation log formatter, `tests/NetForge.Tests.ps1`.
  Acceptance: Profiles tab shows current network signature, ordered candidate profiles, first-match priority, skip reason, last applied profile, and next scheduled profile; tests cover formatter output for match/no-match/duplicate-due scenarios.
  Complexity: M

- [ ] P2 — Add GUI locale selector and locale coverage report
  Why: English and Spanish resource files have parity, but users must edit `settings.json` manually to switch locales.
  Evidence: `strings/en-US.json`, `strings/es-ES.json`, `NetForge.ps1:440-446`, `README.md` configuration section; NETworkManager multilingual surface; RESEARCH.md Architecture.
  Touches: `NetForge.ps1` settings/header UI, localization helpers, `README.md`, `tools\Test-NetForge.ps1`, `tests/NetForge.Tests.ps1`.
  Acceptance: UI exposes a locale selector backed by shipped resource files, changing it persists safely and applies on restart with a clear status message, local checks emit a locale coverage summary, and tests cover fallback plus key parity.
  Complexity: M

- [ ] P2 — Ratchet PSScriptAnalyzer exclusions into targeted baselines
  Why: broad analyzer exclusions hide future regressions in state-changing functions, runspace captures, unused code, and naming drift.
  Evidence: `PSScriptAnalyzerSettings.psd1`; `tools\Test-NetForge.ps1`; RESEARCH.md Architecture.
  Touches: `PSScriptAnalyzerSettings.psd1`, `tools\Test-NetForge.ps1`, `NetForge.ps1`, `tests\`.
  Acceptance: local checks document or baseline each intentional analyzer suppression by rule and function/line pattern, newly introduced violations fail the gate, and at least `PSUseShouldProcessForStateChangingFunctions` and `PSUseUsingScopeModifierInNewRunspaces` are narrowed to justified exceptions.
  Complexity: M

- [ ] P2 — Add DHCP lease and server identity diagnostics
  Why: adapter details show DHCP enabled/server state, but field troubleshooting needs lease timing and server identity evidence to spot expired leases or rogue DHCP before resetting adapters.
  Evidence: `NetForge.ps1:2588-2589`, `NetForge.ps1:4843-4844`; Microsoft `Win32_NetworkAdapterConfiguration`; NETworkManager issue #3305; ManageEngine OpUtils DHCP monitoring.
  Touches: `NetForge.ps1` Adapter Info and Network Tools diagnostics, operation logs, `tests\NetForge.Tests.ps1`.
  Acceptance: selecting an adapter can show DHCP enabled state, server IP, lease obtained/expires/remaining time, DHCP server MAC from neighbor cache when available, optional domain-authorized server comparison via `Get-DhcpServerInDC` only when the cmdlet/domain context is available, clear unavailable/offline states, and Pester tests with mocked CIM, neighbor, missing-cmdlet, and authorized-server data.
  Complexity: M

### P3

- [ ] P3 — Add manual RDAP and ASN ownership lookup for diagnostic targets
  Why: reachability and port-scan output can prove connectivity but not who owns a public IP/netblock, and RDAP is the current JSON standard for IP network and ASN registration data.
  Evidence: `NetForge.ps1:11870-12097`; NETworkManager issue #3348; RFC 9083; IANA RDAP bootstrap data.
  Touches: `NetForge.ps1` Network Tools/Diagnostics target parser, endpoint-policy controls, operation log redaction, `tests\NetForge.Tests.ps1`.
  Acceptance: a manual lookup accepts IPv4/IPv6 or hostname, resolves hostnames only after explicit action, uses IANA RDAP bootstrap JSON over HTTPS to choose the IP/ASN RDAP endpoint, displays netblock/name/country/abuse-contact fields when present, respects disabled/offline endpoint-policy states, never runs automatically during reachability or port scans, and tests cover bootstrap selection plus canned RDAP JSON formatting/redaction.
  Complexity: L

## Research-Driven Additions

### P2

- [ ] P2 — Add settings schema validation and migration backups
  Why: settings now hold endpoint policy, protected secrets, app routing policies, theme, compact mode, and locale state, but there is no explicit schema version or corrupt-settings quarantine.
  Evidence: `NetForge.ps1:8991-9048`; NETworkManager issue #2700; RESEARCH.md Security, Privacy, and Reliability.
  Touches: `NetForge.ps1` settings helpers, `%APPDATA%\NetForge\settings.json` migration path, `tests\NetForge.Tests.ps1`.
  Acceptance: settings include a `SettingsSchemaVersion`, load validates known keys/types, migrations create a timestamped backup before rewrite, corrupt settings are quarantined with a clear in-app warning, protected setting migration still succeeds, and tests cover valid, legacy, unknown-key, and corrupt JSON cases.
  Complexity: M

- [ ] P2 — Add configuration export privacy modes and import preview
  Why: diagnostics export is redacted, but full configuration export still writes raw profiles and DNS presets without a clear shareable-vs-restorable choice or import preview.
  Evidence: `NetForge.ps1:13603-13623`; NETworkManager issue #2700; RESEARCH.md Security, Privacy, and Reliability.
  Touches: `NetForge.ps1` export/import helpers and dialogs, profile validation, operation log, `tests\NetForge.Tests.ps1`.
  Acceptance: export offers full backup and redacted shareable modes with a manifest of included/suppressed fields, import shows accepted/rejected/conflicting profile counts before writing, failed imports leave existing profiles unchanged, and tests cover raw export, redacted export, conflict preview, and rollback-on-error behavior.
  Complexity: M

- [ ] P2 — Add capability preflight and degraded-feature matrix
  Why: NetForge depends on Windows cmdlets, modules, optional tools, admin state, and endpoint policy that vary by host; failures should be visible before a user clicks a feature.
  Evidence: live PowerShell 5.1 environment lacked `Get-FileHash`; `tools\Test-NetForge.ps1`; RESEARCH.md Security, Privacy, and Reliability.
  Touches: `NetForge.ps1` Diagnostics tab/status helpers, startup initialization, hashing fallback helper, `tests\NetForge.Tests.ps1`.
  Acceptance: Diagnostics shows a non-mutating capability matrix for admin state, NetTCPIP, DnsClient, NetSecurity, DhcpServer, pktmon, netsh, Get-AuthenticodeSignature, hashing support, endpoint policy, and optional proxy paths; unavailable capabilities disable or label dependent controls; tests cover available, missing-cmdlet, missing-module, and endpoint-disabled cases.
  Complexity: M

- [ ] P2 — Add Network List Manager identity as an auto-apply match source
  Why: SSID and gateway matching are useful, but Windows exposes network identity/category through documented APIs that can make wired, VPN, and domain networks less brittle.
  Evidence: `NetForge.ps1:10137-10323`; Microsoft NetworkChange API; Microsoft windows-networking-tools; RESEARCH.md Architecture Assessment.
  Touches: `NetForge.ps1` profile schema/matcher/UI, auto-apply inspector item, operation logs, `tests\NetForge.Tests.ps1`.
  Acceptance: profiles can capture and match Network List Manager network name/GUID/category when available, fall back cleanly when COM/API access fails, show this signal in the auto-apply inspector, preserve existing SSID/gateway behavior, and tests mock match, no-match, unavailable, and migrated-profile cases.
  Complexity: M

### P3

- [ ] P3 — Add manual DNS resolver benchmark and comparison history
  Why: NetForge can test resolver health, but resolver selection still lacks a bounded manual benchmark/history view like DNS Jumper-style workflows.
  Evidence: DNS Jumper; DNS Changer Desktop; `dns-providers.json`; RESEARCH.md Competitive Landscape.
  Touches: `NetForge.ps1` DNS tab/health helpers, DNS provider catalog display, endpoint-policy controls, `tests\NetForge.Tests.ps1`.
  Acceptance: a manual benchmark runs selected current/custom/catalog resolvers with bounded query count/timeouts, records latency and failure rate without auto-applying changes, keeps local recent-history rows with clear endpoint-policy/offline states, and tests cover result formatting, timeout handling, disabled endpoint policy, and no-history state.
  Complexity: M
