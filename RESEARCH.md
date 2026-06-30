# Research - NetForge

## Executive Summary
NetForge is a Windows PowerShell 5.1/WPF network operations console for adapter profile switching, DNS configuration, encrypted DNS diagnostics, profile automation, and local troubleshooting. Its strongest current shape is the portable single-script release that now covers rollback-aware IP/DNS/profile changes, schema-v3 profiles, QR/WLAN import, scheduled and event-driven profile switching, tray/CLI/RDP workflows, Discord profile webhooks, packet capture, MTR, reachability, port scanning, cable diagnostics, localization, themes, compact mode, and app interface guards. The highest-value direction remains trust and recovery hardening around this expanded surface before adding large new domains.

Top opportunities:
- P0: Protect Discord webhook and future bearer-secret settings with Windows DPAPI or Credential Manager.
- P0: Persist app interface guard intent and reconcile Windows Firewall interface rules after adapter topology changes.
- P1: Add diagnostics-export redaction, preview, and redaction-report output before copying profiles/logs into a zip.
- P1: Add DoQ proxy binary trust evidence, stdout/stderr capture, health state, and recovery messages around operator-provided `dnsproxy.exe`.
- P1: Refresh release evidence by replacing the stale screenshot, fixing the README screenshot section, and adding a local visual/package smoke tied to `version.json`.
- P1: Add an in-app GitHub release/checksum verifier that never auto-installs and respects endpoint-policy/offline states.
- P2: Add local DNS provider catalog freshness checks plus vendored DLL advisory/version gates.
- P2: Split pure helpers into source modules while preserving the generated single-file `NetForge.ps1` release artifact.
- P2: Add rendered UI/theme/compact/accessibility smoke tests, a GUI locale selector, and analyzer-baseline ratcheting.
- P2/P3: Expand diagnostics with DHCP lease/server identity checks and manual RDAP/ASN ownership lookup, both privacy-gated.

## Product Map
- Core workflows: select adapter; apply DHCP/static IPv4/IPv6 and DNS; configure DNS presets/custom resolvers; test DoH/DoT/DoQ health; optionally launch a local DoQ proxy.
- Core workflows: save/apply/import/export profiles; trigger profiles by SSID/gateway MAC/schedule/tray/CLI/RDP; rollback IP/DNS/profile changes.
- Core workflows: run local repair and diagnostics: flush/release/renew/reset, DNS lookup, ping/traceroute/MTR, latency histogram, reachability wizard, port scan, static routes, hosts groups, packet capture, WiFi spectrum, cable diagnostics, diagnostics export, and app interface guards.
- User personas: Windows laptop roamers, field/helpdesk technicians, privacy-DNS users, small-fleet admins, and power users managing multiple NIC/VPN/WiFi contexts on Windows 10/11 LTSC-friendly systems.
- Platforms and distribution: Windows 10/11, Windows PowerShell 5.1, WPF/.NET Framework, admin-elevated script, GitHub release zip plus `.sha256`; local signing support exists but no local code-signing certificate is available.
- Key integrations and data flows: NetTCPIP/DnsClient/NetSecurity cmdlets, WMI/CIM, `netsh`, `ipconfig`, `pktmon`, Windows Firewall/WFP interface filters, NetworkChange events, `%APPDATA%\NetForge` settings/profiles/logs/captures, bundled QRCoder/ZXing.Net DLLs, optional external `dnsproxy.exe`, optional Discord webhook POSTs, and optional endpoint-policy-gated internet lookups.

## Competitive Landscape
- NetSetMan: Strong commercial reference for profile breadth, AutoSwitch conditions/status, admin-service elevation, and deployable settings. Learn from explicit profile priority/status and update evidence; avoid licensing/domain-management complexity and keyboard-shortcut workflows.
- NETworkManager: Active OSS reference for a broad Windows network toolbox, encrypted profile files, package distribution, DHCP-server lookup demand, and WHOIS/RDAP demand. Learn from diagnostics breadth and release discipline; avoid a rewrite away from NetForge's portable PowerShell/LTSC advantage.
- Simple IP Config and DNS Changer: Lightweight OSS switchers keep IP/DNS flows simple, but their issue histories show adapter refresh, restore, trust, language, and packaging pain. Learn from focused switching flows; avoid stale adapter lists and release-trust ambiguity.
- DNSCrypt Proxy, AdGuard `dnsproxy`, Control D `ctrld`, NextDNS CLI, YogaDNS, and DNS Jumper: Strong references for encrypted DNS, provider catalogs, resolver status, and proxy lifecycle. Learn from delegating protocol churn to maintained resolvers and from showing latency/freshness; avoid bundling unsigned proxy binaries or hiding stderr/service failures.
- Portmaster and GlassWire: Adjacent app-policy tools show the value of app path visibility, persistent rules, traffic/status history, and unobtrusive alerts. Learn from policy drift visibility and support redaction; avoid becoming a full always-on firewall/traffic engine.
- ManageEngine OpUtils: Commercial reference that treats DHCP, DNS, IPAM, rogue detection, and exports as paid operational visibility. Learn that DHCP lease/server identity is valuable even when NetForge should stay local and lightweight; avoid building centralized IPAM, credentials, or polling services.
- Microsoft Windows APIs: NetSecurity interface filters, WFP, NetworkChange, DPAPI, Win32 network adapter configuration, and optional DhcpServer cmdlets are the maintainable boundary. Prefer documented APIs over registry scraping, custom packet protocols, or unsupported network stack manipulation.
- RDAP standards and IANA bootstrap data: RDAP provides JSON registration data for IP networks and autonomous systems. Learn from standardized, manual lookup flows; avoid automatic external enrichment during local diagnostics because target lookups can reveal user activity.

## Security, Privacy, and Reliability
- Verified: `NetForge.ps1:466-467` loads `DiscordWebhookUrl` from plaintext settings and `NetForge.ps1:9218-9219` writes the full webhook URL back to `settings.json`; logs redact it, but local storage remains a bearer-secret exposure.
- Verified: `Export-DiagnosticsBundle` copies logs/profile JSON (`NetForge.ps1:12834-12839`) and writes `Profiles = Get-Profiles` into `adapter-state.json` (`NetForge.ps1:12851-12860`), so proxy servers, mapped-drive paths, SSIDs, gateways, adapter names, and local paths can leave the machine without a redaction preview.
- Verified: app interface guards are generated from adapters present at apply time (`NetForge.ps1:10775-10800`, `NetForge.ps1:10972-10980`); NetworkChange handlers run profile auto-apply only (`NetForge.ps1:10124-10159`), so later adapter additions/removals can leave guard policy drift.
- Verified: DoQ proxy startup validates `--version` and starts an arbitrary `dnsproxy.exe` path (`NetForge.ps1:7768-7833`), but it does not record binary hash/publisher, capture stdout/stderr, watch process health, or expose a recovery path beyond stop/start.
- Verified: adapter details show DHCP enabled/server state (`NetForge.ps1:2588-2589`, `NetForge.ps1:4843-4844`) but discard DHCP lease obtained/expires fields, server MAC/neighbor identity, and optional domain-authorized DHCP comparison available through documented Windows APIs.
- Verified: reachability and port-scan diagnostics resolve DNS/gateway/route/port/MTU (`NetForge.ps1:11870-12097`) but have no manual RDAP/ASN ownership view for public targets; any such lookup must be explicit and endpoint-policy gated.
- Verified: local release packaging supports Authenticode signing when a cert exists, but local certificate stores report no code-signing certificate and `Roadmap_Blocked.md` already separates the standard-user helper service behind that blocker.
- Verified: the committed `screenshot.png` shows v1.13.0 while `version.json`, README badges, and GitHub releases are v1.48.0; README also still contains a `## Screenshots` "Coming soon" section.
- Verified: `tools\Test-NetForge.ps1` ran 79 Pester tests with zero failures during this pass.
- Missing guardrails: DPAPI/Credential Manager migration for secrets, support-export redaction manifest, app-guard policy reconciliation, external proxy session logs, release visual smoke, dependency/advisory gates, DHCP lease/server identity reporting, manual RDAP/ASN privacy gating, and targeted PSScriptAnalyzer baselines.
- Recovery and rollback needs: IP/DNS/profile rollback exists; remaining recovery gaps are app-guard rule drift repair, DoQ proxy failure diagnosis, safe support-bundle sharing, package/update verification, and clearer DHCP lease/server mismatch evidence before users reset adapters.

## Architecture Assessment
- Verified: `NetForge.ps1` is 13,307 lines with 355 functions; tests are 1,583 lines in one Pester file. This is workable for a portable release, but risky for continued feature growth without a source-module build that emits the same single-file artifact.
- Verified: `PSScriptAnalyzerSettings.psd1` excludes state-changing, unused, approved-verb, and runspace-scope rules. The current test pass is green, but exclusions should become a ratcheted baseline rather than permanent blind spots.
- Verified: major tabs are embedded in one XAML here-string: IP Configuration, DNS Configuration, WiFi, Profiles, Network Tools, Diagnostics (`NetForge.ps1:1556`, `1765`, `2004`, `2101`, `2334`, `2621`). Static accessibility metadata exists, but there is no rendered UIA/theme smoke that proves every tab still loads and remains usable after rapid feature additions.
- Verified: i18n has `strings/en-US.json` and `strings/es-ES.json` with key parity, but locale selection is manual through `settings.json`; no user-facing selector or locale coverage report exists.
- Verified: GitHub releases and zip/checksum assets exist through v1.48.0, but the app does not expose a "check release/checksum" flow and README still makes users compare checksums manually.
- Verified: DHCP display currently lives in `Update-AdapterDetails`; a focused helper can extract CIM/neighbor/authorized-server data for both UI and tests without changing profile apply behavior.
- Verified: RDAP/ASN lookup can reuse existing target parsing, endpoint-policy controls, operation-log redaction, and canned JSON tests; it should not run as part of automatic reachability or scan flows.
- Refactor candidates: extract pure helpers for settings/secret storage, profile store, DNS catalog, DoQ proxy, app guard policy, diagnostics export, DHCP inspection, RDAP parsing, and release metadata into source modules while preserving `NetForge.ps1` as generated release output.
- Test gaps: no DPAPI migration tests, no support-bundle redaction tests, no app-guard topology-change tests, no DoQ proxy process-log tests, no rendered screenshot/UIA smoke, no DNS catalog freshness/advisory gate, no DHCP lease/authorized-server tests, and no RDAP bootstrap/formatting tests.
- Documentation gaps: README screenshot section is stale, screenshot asset is stale, and release docs do not distinguish unsigned local packages from signed packages when a certificate is available.

## Rejected Ideas
- Full standard-user helper service now: blocked by the local absence of a code-signing certificate and already tracked in `Roadmap_Blocked.md`; do not duplicate it in active `ROADMAP.md`.
- Keyboard shortcuts for profile apply: rejected by global project rules; keep visible tray, CLI, and profile controls instead.
- Bundling `dnsproxy.exe`: rejected because protocol proxy binaries need their own update/security lifecycle; NetForge should validate and supervise an operator-provided binary.
- Direct in-script DoQ/ODoH/DNSCrypt resolver implementation: rejected because proxy edge cases are already handled better by dnsproxy, ctrld, dnscrypt-proxy, and NextDNS.
- Central DHCP/IPAM monitoring: rejected because commercial scope polling, credentials, AD integration, alerts, and exports are a different product; NetForge should expose local lease/server identity and optional authorized-server comparison only.
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
- https://oneuptime.com/blog/post/2026-03-20-detect-rogue-dhcp-servers-network/view

Standards and platform APIs:
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallinterfacefilter
- https://learn.microsoft.com/en-us/windows/win32/fwp/windows-filtering-platform-start-page
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
