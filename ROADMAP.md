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

### P0

- [ ] P0 — Protect persisted webhook and future secret settings with DPAPI
  Why: Discord webhook URLs are bearer secrets and are currently saved in plaintext `settings.json`.
  Evidence: `NetForge.ps1:466-467`, `NetForge.ps1:9218-9219`; Microsoft `ProtectedData`; RESEARCH.md Security.
  Touches: `NetForge.ps1` settings load/save helpers, Discord webhook helpers, `tests/NetForge.Tests.ps1`.
  Acceptance: existing plaintext `DiscordWebhookUrl` migrates to current-user protected storage, `settings.json` retains only non-secret flags or a secret reference, UI still shows redacted status, webhook send still works, and Pester covers migration, missing secret, and invalid secret cases.
  Complexity: M

- [ ] P0 — Reconcile app interface guards after adapter topology changes
  Why: current guards block only adapters present at apply time, so newly added adapters can bypass an intended app restriction.
  Evidence: `NetForge.ps1:10775-10800`, `NetForge.ps1:10972-10980`, `NetForge.ps1:10124-10159`; Microsoft NetSecurity interface filter docs; RESEARCH.md Security.
  Touches: `NetForge.ps1` app routing helpers, network-change handler, app routing UI status, `tests/NetForge.Tests.ps1`.
  Acceptance: NetForge persists each app guard policy as program path plus allowed interface, detects missing/stale firewall rules on startup and NetworkChange events, repairs drift idempotently, logs created/removed rules, and tests cover added adapter, removed adapter, and unchanged topology.
  Complexity: L

### P1

- [ ] P1 — Add redacted diagnostics export with preview manifest
  Why: diagnostics export currently copies profiles/logs and embeds all loaded profiles, which can expose SSIDs, proxy servers, mapped-drive paths, adapter names, and local paths.
  Evidence: `NetForge.ps1:12834-12863`; RESEARCH.md Security; GlassWire/Portmaster trust patterns.
  Touches: `NetForge.ps1` diagnostics export, profile serialization helpers, operation log redaction helpers, `tests/NetForge.Tests.ps1`.
  Acceptance: export shows a preview manifest before writing, redacts webhook-like URLs, proxy hosts, mapped-drive UNC hosts, SSIDs/gateway MACs when privacy mode is selected, includes a `redaction-report.json`, and Pester proves raw sensitive test values do not appear in exported JSON/log text.
  Complexity: M

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
