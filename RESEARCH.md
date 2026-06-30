# Research - NetForge

## Executive Summary
NetForge is a Windows PowerShell 5.1/WPF network operations console for adapter profile switching, DNS configuration, encrypted-DNS diagnostics, profile automation, app routing guards, and local troubleshooting. Its strongest current shape is the portable single-script release: v1.51.0 now includes rollback-aware network changes, DPAPI-protected webhook storage, app guard reconciliation, redacted diagnostics exports, DNS-over-HTTPS/TLS/QUIC health checks, optional local DoQ proxy launch, scheduled/event/tray/CLI/RDP profile workflows, localization, themes, compact mode, and a release zip with checksum assets. The highest-value direction is to keep hardening trust, upgrade safety, degraded-state observability, and rendered release evidence before adding larger diagnostic domains.

Top opportunities:
- P1: Add DoQ proxy binary trust evidence, stdout/stderr capture, session health, and recovery guidance for operator-provided `dnsproxy.exe`.
- P1: Refresh release evidence by replacing the stale screenshot, fixing the README screenshot section, and adding local visual/package smoke tied to `version.json`.
- P1: Add an in-app GitHub release/checksum verifier that never auto-installs and respects endpoint-policy/offline states.
- P2: Add settings schema validation, migration backups, and corrupt-settings quarantine as the settings surface grows.
- P2: Add local DNS provider catalog freshness checks plus vendored DLL version/license/advisory gates.
- P2: Add capability preflight so unavailable cmdlets/modules/tools become explicit degraded states, not late feature failures.
- P2: Add safe configuration export/import preview and privacy modes separate from diagnostics redaction.
- P2: Add rendered UI/theme/compact/accessibility smoke tests, GUI locale selection, analyzer-baseline ratcheting, and source-module boundaries while preserving the single-file release.
- P2/P3: Improve network intelligence with DHCP lease/server identity, Network List Manager-backed auto-apply matching, manual DNS benchmark history, and manual endpoint-policy-gated RDAP/ASN lookup.

## Product Map
- Core workflows: select adapter; apply DHCP/static IPv4/IPv6 and DNS; configure DNS presets/custom resolvers; test DoH/DoT/DoQ health; optionally launch a local DoQ proxy.
- Core workflows: save/apply/import/export profiles; trigger profiles by SSID/gateway MAC/schedule/tray/CLI/RDP; rollback IP/DNS/profile changes.
- Core workflows: run local repair and diagnostics: flush/release/renew/reset, DNS lookup, ping/traceroute/MTR, latency histogram, reachability wizard, port scan, static routes, hosts groups, packet capture, WiFi spectrum, cable diagnostics, diagnostics export, and app interface guards.
- User personas: Windows laptop roamers, field/helpdesk technicians, privacy-DNS users, small-fleet admins, and power users managing multiple NIC/VPN/WiFi contexts on Windows 10/11 LTSC-friendly systems.
- Platforms and distribution: Windows 10/11, Windows PowerShell 5.1, WPF/.NET Framework, admin-elevated script, GitHub release zip plus `.sha256`; local signing support exists but no local code-signing certificate is available.
- Key integrations and data flows: NetTCPIP/DnsClient/NetSecurity cmdlets, WMI/CIM, `netsh`, `ipconfig`, `pktmon`, Windows Firewall/WFP interface filters, NetworkChange events, `%APPDATA%\NetForge` settings/profiles/logs/captures, bundled QRCoder/ZXing.Net DLLs, optional external `dnsproxy.exe`, optional Discord webhook POSTs, and optional endpoint-policy-gated internet lookups.

## Competitive Landscape
- NetSetMan: Strong commercial reference for profile breadth, AutoSwitch conditions/status, admin-service elevation, and deployable settings. Learn from explicit profile priority/status, update evidence, and settings portability; avoid licensing/domain-management complexity and keyboard-shortcut workflows.
- NETworkManager: Active OSS reference for a broad Windows network toolbox, encrypted profile files, package distribution, DHCP-server lookup demand, RDAP/WHOIS demand, and backup/restore requests. Learn from diagnostics breadth and release discipline; avoid a rewrite away from NetForge's portable PowerShell/LTSC advantage.
- Simple IP Config, DNS Changer, and the PowerToys network preset request: Lightweight switchers confirm continued demand for fast adapter/IP/DNS presets. Learn from focused switching flows and visible preset state; avoid stale adapter lists, release-trust ambiguity, and hiding degraded states.
- DNSCrypt Proxy, AdGuard `dnsproxy`, Control D `ctrld`, NextDNS CLI, YogaDNS, and DNS Jumper: Strong references for encrypted DNS, provider catalogs, resolver status, proxy lifecycle, and resolver benchmarking. Learn from delegating protocol churn to maintained resolvers and showing latency/freshness; avoid bundling unsigned proxy binaries or hiding stderr/service failures.
- Portmaster and GlassWire: Adjacent app-policy tools show the value of app path visibility, persistent rules, status history, and unobtrusive alerts. Learn from policy drift visibility and support redaction; avoid becoming a full always-on firewall/traffic engine.
- ManageEngine OpUtils: Commercial reference that treats DHCP, DNS, IPAM, rogue detection, and exports as paid operational visibility. Learn that DHCP lease/server identity is valuable even when NetForge should stay local and lightweight; avoid building centralized IPAM, credentials, or polling services.
- Microsoft Windows APIs: NetSecurity interface filters, WFP, NetworkChange, DPAPI, Win32 network adapter configuration, optional DhcpServer cmdlets, and Network List Manager are the maintainable boundary. Prefer documented APIs over registry scraping, custom packet protocols, or unsupported network stack manipulation.
- RDAP standards and IANA bootstrap data: RDAP provides JSON registration data for IP networks and autonomous systems. Learn from standardized, manual lookup flows; avoid automatic external enrichment during local diagnostics because target lookups can reveal user activity.

## Security, Privacy, and Reliability
- Verified: `Invoke-ValidateDoqProxy` and `Invoke-StartDoqProxy` validate `--version` and start an operator-selected `dnsproxy.exe` path (`NetForge.ps1:7896-7962`), but do not record file hash/publisher/modified time, capture stdout/stderr, watch health after launch, or export proxy session evidence.
- Verified: `Save-AppSetting` writes atomically and keeps a transient backup (`NetForge.ps1:8991-9037`), but settings have no explicit schema version, validator, migration ledger, or quarantine path for corrupt/unknown settings as endpoint policy, protected secrets, routing policies, UI theme, compact mode, and locale state accumulate.
- Verified: `Export-AllConfiguration` writes raw `Profiles = Get-Profiles` and `DnsPresets = $script:DnsPresets` to JSON (`NetForge.ps1:13603-13623`); diagnostics export has redaction, but configuration export/import still need explicit full-backup vs shareable-redacted modes and import preview/rollback confidence.
- Verified: `README.md:161-163` still has a `## Screenshots` "Coming soon" section while `README.md:23` references `screenshot.png`; the screenshot is stale relative to v1.51.0 and `tools\New-NetForgeReleasePackage.ps1:111` packages it.
- Verified: GitHub release v1.51.0 was published on 2026-06-30 with `NetForge-v1.51.0.zip` and `.sha256` assets, but the app has no release/checksum verification flow and README still requires manual checksum comparison.
- Verified: adapter details show DHCP enabled/server state only (`NetForge.ps1:4969-4972`) and omit lease obtained/expires/remaining time, server MAC from neighbor cache, and optional domain-authorized DHCP comparison.
- Verified: auto-apply currently matches profile metadata through SSID/gateway-style signatures (`NetForge.ps1:10137-10235`) and subscribes to `NetworkChange` events (`NetForge.ps1:10291-10323`), but it does not expose Network List Manager network identity/category as a match source.
- Verified: local feature paths depend on cmdlets/modules/tools that can vary by Windows edition and session, yet there is no up-front capability matrix; a live PowerShell 5.1 check in this environment could not resolve `Get-FileHash`, reinforcing the need for preflight plus fallback hashing.
- Verified: QRCoder.dll is version 1.8.0.0 and zxing.dll is version 0.16.11.0; GitHub Advisory API queries for `QRCoder` and `ZXing.Net` returned no NuGet advisories, but there is no local manifest gate to detect binary/license/source drift.
- Missing guardrails: external proxy trust/session logs, settings schema migrations, configuration export privacy/preview, capability preflight, release visual smoke, in-app release verification, dependency/advisory gates, DHCP lease/server identity reporting, Network List Manager match evidence, manual DNS benchmark history, manual RDAP/ASN privacy gating, and targeted PSScriptAnalyzer baselines.
- Recovery and rollback needs: IP/DNS/profile rollback exists; remaining recovery gaps are settings migration/quarantine, configuration import preview/undo confidence, DoQ proxy failure diagnosis, package/update verification, and clearer DHCP/server mismatch evidence before users reset adapters.

## Architecture Assessment
- Verified: `NetForge.ps1` is 14,028 lines with 363 top-level functions; `tests\NetForge.Tests.ps1` is 1,908 lines with 91 Pester `It` blocks. This is still workable for a portable release, but feature risk is now dominated by single-file coupling unless pure helpers move behind source-module boundaries that still emit one release script.
- Verified: `PSScriptAnalyzerSettings.psd1:2-10` excludes state-changing, unused, approved-verb, singular-noun, and runspace-scope rules. Current local checks can stay green while new regressions are hidden unless suppressions become a ratcheted baseline by rule/function/pattern.
- Verified: theme and compact controls are live (`NetForge.ps1:1540-1542`, `NetForge.ps1:3077-3302`) and static accessibility metadata is tested, but there is no rendered UIA/theme/compact smoke proving each major tab still loads after rapid UI growth.
- Verified: i18n has `strings/en-US.json` and `strings/es-ES.json` with parity tests, and settings can load `UiLocale` (`NetForge.ps1:560-568`), but there is no GUI locale selector or operator-readable locale coverage report.
- Verified: DNS catalog hash validation exists in `tools\Test-NetForge.ps1:12-67`, but there is no freshness tool comparing provider endpoints/capabilities to provider docs or regenerating the sidecar safely after intentional edits.
- Verified: release packaging validates current zip/sha naming when `dist` exists (`tools\Test-NetForge.ps1:110-122`), but does not fail on stale screenshot-visible version or prove the packaged UI launches.
- Refactor candidates: extract pure helpers for settings schema/migration, protected settings, profile store, DNS catalog, DoQ proxy command/session planning, app guard policy, diagnostics/config export, capability preflight, DHCP inspection, Network List Manager identity, RDAP parsing, DNS benchmarking, and release metadata into source modules while preserving `NetForge.ps1` as generated output.
- Test gaps: no DoQ process-log tests, no settings migration/corruption tests, no config export privacy/import-preview tests, no capability preflight matrix tests, no rendered screenshot/UIA smoke, no DNS catalog freshness/advisory gate, no DHCP lease/authorized-server tests, no Network List Manager match tests, and no RDAP/bootstrap or DNS benchmark formatting tests.
- Documentation gaps: README screenshot section is stale, screenshot asset is stale, release docs do not distinguish unsigned local packages from signed packages when a certificate is available, and manual checksum verification is not mirrored in-app.

## Rejected Ideas
- Full standard-user helper service now: blocked by the local absence of a code-signing certificate and already separated in `Roadmap_Blocked.md`; do not duplicate it in active `ROADMAP.md`.
- Keyboard shortcuts for profile apply: rejected by global project rules; keep visible tray, CLI, and profile controls instead.
- Bundling `dnsproxy.exe`: rejected because protocol proxy binaries need their own update/security lifecycle; NetForge should validate and supervise an operator-provided binary.
- Direct in-script DoQ/ODoH/DNSCrypt resolver implementation: rejected because proxy edge cases are already handled better by dnsproxy, ctrld, dnscrypt-proxy, and NextDNS.
- Central DHCP/IPAM monitoring: rejected because commercial-scope polling, credentials, AD integration, alerts, and exports are a different product; NetForge should expose local lease/server identity and optional authorized-server comparison only.
- Automatic RDAP enrichment during reachability, port scan, or DNS lookup: rejected because it would leak diagnostic targets to external services; keep RDAP/ASN lookup manual and endpoint-policy gated.
- Full always-on traffic firewall/IDS: rejected because Portmaster and GlassWire are purpose-built for that; NetForge should remain an operator network configuration and diagnostics utility.
- Cloud multi-user/fleet management: weak fit for a local admin tool and would create credential, tenancy, and privacy obligations that the current product does not need.
- Mobile companion app: weak fit; QR/profile import-export already covers the useful transfer workflow.
- Plugin ecosystem: premature for a single-file elevated PowerShell tool; stabilize module boundaries and release build generation first.
- Rewrite in C#/.NET: not recommended because NetForge's differentiator is a portable PowerShell 5.1 tool that works on LTSC without a new runtime install.
- Dependabot/Renovate or GitHub Actions: rejected by repository policy; dependency, advisory, build, and release checks must stay local.

## Sources
Competitors, community, and adjacent tools:
- https://www.netsetman.com/en/help
- https://github.com/BornToBeRoot/NETworkManager
- https://github.com/BornToBeRoot/NETworkManager/issues/3305
- https://github.com/BornToBeRoot/NETworkManager/issues/3348
- https://github.com/BornToBeRoot/NETworkManager/issues/2700
- https://github.com/microsoft/PowerToys/issues/42029
- https://github.com/KurtisLiggett/Simple-IP-Config
- https://github.com/DnsChanger/dnsChanger-desktop
- https://github.com/DNSCrypt/dnscrypt-proxy
- https://github.com/AdguardTeam/dnsproxy
- https://github.com/Control-D-Inc/ctrld
- https://github.com/nextdns/nextdns
- https://www.yogadns.com/docs/
- https://www.sordum.org/7952/dns-jumper-v2-3/
- https://www.glasswire.com/features/
- https://github.com/safing/portmaster
- https://www.manageengine.com/products/oputils/dhcp-monitoring.html
- https://github.com/cslev/awesome-network-analysis

Standards and platform APIs:
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallinterfacefilter
- https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkchange.networkaddresschanged
- https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata
- https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapterconfiguration
- https://learn.microsoft.com/en-us/powershell/module/dhcpserver/get-dhcpserverindc?view=windowsserver2025-ps
- https://www.rfc-editor.org/rfc/rfc9250
- https://www.rfc-editor.org/rfc/rfc9083
- https://data.iana.org/rdap/

Dependency, tooling, and advisories:
- https://github.com/Shane32/QRCoder/releases/tag/v1.8.0
- https://github.com/micjahn/ZXing.Net/releases/tag/v0.16.11.0
- https://github.com/advisories?query=ecosystem%3Anuget

## Open Questions
None for active roadmap prioritization. Code-signing certificate availability remains the blocker for the already-separated standard-user helper service.
