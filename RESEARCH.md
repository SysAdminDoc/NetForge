# Research - NetForge

## Executive Summary
NetForge is now a broad Windows PowerShell 5.1/WPF network operations console rather than the small IP/DNS switcher described by older research: v1.48.0 already covers rollback-protected IP/DNS/profile changes, schema-v3 profiles, encrypted DNS health checks, DoQ proxy launch, QR/WLAN import, scheduled and event-driven profile switching, RDP apply/revert, Discord webhooks, tray switching, diagnostics export, packet capture, reachability, port scanning, static routes, hosts groups, localization, themes, and app interface guards. The highest-value direction is trust hardening around this larger surface: protect persisted secrets, make firewall app guards survive adapter changes, redact support exports, supervise external DNS proxy sessions, and make release evidence/current screenshots prove the shipped artifact.

Top opportunities:
- P0: Move Discord webhook and future bearer secrets out of plaintext `settings.json` into Windows DPAPI/Credential Manager storage.
- P0: Persist app interface guard policies and reconcile firewall interface rules when adapters change.
- P1: Add redaction and preview controls to diagnostics export before copying profiles/logs into a zip.
- P1: Add DoQ proxy binary trust, stdout/stderr logging, and failure-state supervision around external `dnsproxy.exe`.
- P1: Refresh release evidence: screenshot, README screenshot section, and a local visual/package smoke tied to `version.json`.
- P1: Add an in-app release/checksum verifier against GitHub release assets.
- P2: Add local DNS provider catalog freshness tooling and advisory/dependency version checks for vendored DLLs.
- P2: Split pure logic into source modules with a build step that still emits the portable single-file release script.
- P2: Add rendered UI/accessibility/theme smoke tests and a GUI locale selector.

## Product Map
- Core workflows: select adapter; apply DHCP/static IPv4/IPv6 and DNS; register/test encrypted DNS and optional DoQ local proxy; save/apply/import profiles; run diagnostics and recovery tools.
- Core workflows: manage profile automation through SSID/gateway-MAC rules, schedules, tray actions, CLI `-ApplyProfile`, and RDP launch/revert.
- Core workflows: inspect and repair Windows networking with static routes, hosts groups, packet capture, reachability wizard, MTR, port scan, WiFi spectrum, cable diagnostics, and app interface guards.
- User personas: Windows laptop roamers, field/helpdesk technicians, privacy-DNS users, small-fleet admins, and power users managing multiple NIC/VPN/WiFi contexts on Windows 10/11 LTSC-friendly systems.
- Platforms and distribution: Windows 10/11, Windows PowerShell 5.1, WPF/.NET Framework, admin-elevated script, GitHub releases with `NetForge-v1.48.0.zip` and `.sha256`; signing is attempted but no code-signing certificate is present locally.
- Key integrations and data flows: NetTCPIP/DnsClient/NetSecurity cmdlets, `netsh`, `pktmon`, Windows Firewall/WFP interface filters, NetworkChange events, `%APPDATA%\NetForge` settings/profiles/logs/captures, bundled QRCoder/ZXing.Net DLLs, optional external `dnsproxy.exe`, and optional Discord webhook POSTs.

## Competitive Landscape
- NetSetMan: Strongest commercial reference for profile breadth, AutoSwitch conditions/status, admin service elevation, and deployable settings files. Learn from its explicit AutoSwitch priority/status and service-backed privilege model; avoid duplicating licensing/domain-management complexity or adding shortcuts.
- NETworkManager: Active OSS reference for a broad Windows network toolbox, package distribution, encrypted profile files, and multilingual UI. Learn from its maintained release discipline and diagnostics breadth; avoid a rewrite away from the current portable PowerShell/LTSC advantage.
- Simple IP Config and DNS Changer: Lightweight OSS profile/DNS switchers keep the core workflow simple, but their open issues show recurring trust and reliability pain around unsigned/flagged binaries, adapter refresh, profile restore, language files, and packaging paths. Learn from their focused flows; avoid inheriting stale adapter lists or release-trust ambiguity.
- YogaDNS and DNSCrypt Proxy: Good references for honest DNS encryption state, system-level request logs, resolver rules, and encrypted-proxy management. Learn from explicit resolver/rule status; avoid building a full resolver stack inside NetForge.
- AdGuard `dnsproxy`, Control D `ctrld`, DNSCrypt Proxy, and NextDNS CLI: Maintained encrypted DNS engines with recent releases and real-world service/proxy failure issues. Learn from delegating protocol churn to maintained proxies; avoid bundling unsigned DNS proxy binaries or hiding proxy stderr/restart failures.
- DNS Jumper: Strong free reference for fast DNS switching, DNS backup/restore, and benchmarking. Learn from provider freshness and latency visibility; avoid opaque "fastest DNS" choices without showing measurements.
- Proxifier, GlassWire, and Portmaster: Adjacent per-app network policy tools show that users value app-path visibility, profile/rule persistence, traffic history, and unobtrusive alerts. Learn from rule maintenance and path visibility; avoid an always-on intrusive firewall/traffic engine.
- Microsoft networking APIs and DNS privacy RFCs: NetSecurity interface filters, WFP, NetworkChange events, DPAPI, DoH, DoT, DoQ, and ODoH are the stable boundary. Prefer documented Windows APIs and maintained external proxies over registry tricks or custom protocol implementations.

## Security, Privacy, and Reliability
- Verified: `NetForge.ps1:466-467` loads `DiscordWebhookUrl` from plaintext settings and `NetForge.ps1:9218-9219` writes the full webhook URL back to `settings.json`; logs redact it, but local storage remains a bearer-secret exposure.
- Verified: `Export-DiagnosticsBundle` copies logs and profile JSON (`NetForge.ps1:12834-12839`) and writes `Profiles = Get-Profiles` into `adapter-state.json` (`NetForge.ps1:12851-12860`), so proxy servers, mapped-drive paths, SSIDs, gateways, adapter names, and local paths can leave the machine without a redaction preview.
- Verified: app interface guards are generated from the adapters present at apply time (`NetForge.ps1:10775-10800`, `NetForge.ps1:10972-10980`); NetworkChange handlers run profile auto-apply only (`NetForge.ps1:10124-10159`), so later adapter additions/removals can leave guard policy drift.
- Verified: DoQ proxy startup validates `--version` and starts an arbitrary `dnsproxy.exe` path (`NetForge.ps1:7768-7833`), but it does not record binary hash/publisher, capture stdout/stderr, watch process health, or expose a recovery path beyond stop/start.
- Verified: local release packaging supports Authenticode signing when a cert exists, but `CodeSigningCertCount=0` in the local certificate stores and `Roadmap_Blocked.md` already parks the standard-user helper service behind signing availability.
- Verified: the current `screenshot.png` shows v1.13.0 while `version.json`, README badges, and GitHub releases are v1.48.0; README also still contains a `## Screenshots` "Coming soon" section.
- Verified: local checks passed during this pass: `tools\Test-NetForge.ps1` found and ran 79 tests with zero failures.
- Missing guardrails: DPAPI/Credential Manager migration for secrets, support-export redaction manifest, app-guard policy reconciliation, external proxy session logs, release visual smoke, local dependency/advisory checks, and a path to ratchet broad PSScriptAnalyzer exclusions.
- Recovery and rollback needs: IP/DNS/profile rollback exists; remaining recovery gaps are app-guard rule drift repair, DoQ proxy failure diagnosis, safe support-bundle sharing, and package/update verification before users run downloaded zips.

## Architecture Assessment
- Verified: `NetForge.ps1` is 13,307 lines with 355 functions; tests are 1,583 lines in one Pester file. This is workable for a portable release, but risky for continued feature growth without a source-module build that emits the same single-file artifact.
- Verified: `PSScriptAnalyzerSettings.psd1` excludes state-changing, unused, approved-verb, and runspace-scope rules. The current pass is green, but the exclusions should become a ratcheted baseline instead of permanent blind spots.
- Verified: major tabs are embedded in one XAML here-string: IP Configuration, DNS Configuration, WiFi, Profiles, Network Tools, Diagnostics (`NetForge.ps1:1556`, `1765`, `2004`, `2101`, `2334`, `2621`). Static accessibility metadata exists, but there is no rendered UIA/theme smoke that proves every tab still loads and remains usable after rapid feature additions.
- Verified: i18n has `strings/en-US.json` and `strings/es-ES.json` with key parity, but locale selection is manual through `settings.json`; no user-facing selector or locale coverage report exists.
- Verified: GitHub releases and zip/checksum assets exist through v1.48.0, but the app does not expose a "check release/checksum" flow and the README installation path still makes users perform manual checksum comparison.
- Refactor candidates: extract pure helpers for settings/secret storage, profile store, DNS catalog, DoQ proxy, app guard policy, diagnostics export, and release metadata into source modules while preserving `NetForge.ps1` as generated release output.
- Test gaps: no DPAPI migration tests, no redaction tests for support bundles, no app-guard topology-change tests, no DoQ proxy process-log tests, no rendered screenshot/UIA smoke, no DNS catalog freshness/advisory gate.
- Documentation gaps: README screenshot section is stale, screenshot asset is stale, and release docs do not distinguish unsigned local packages from signed packages when a certificate is available.

## Rejected Ideas
- Full standard-user helper service now: blocked by the local absence of a code-signing certificate and already tracked in `Roadmap_Blocked.md`; do not duplicate it in active `ROADMAP.md`.
- Keyboard shortcuts for profile apply: rejected by global project rules; keep visible tray/CLI/profile controls instead.
- Bundling `dnsproxy.exe`: rejected because protocol proxy binaries need their own update/security lifecycle; NetForge should validate and supervise an operator-provided binary.
- Direct in-script DoQ/ODoH/DNSCrypt resolver implementation: rejected because RFC churn and proxy edge cases are already handled better by dnsproxy/ctrld/dnscrypt-proxy.
- Full always-on traffic firewall/IDS: GlassWire and Portmaster are purpose-built for that; NetForge should stay an operator network configuration and diagnostics utility.
- Cloud multi-user/fleet management: weak fit for a local admin tool and would create credential, tenancy, and privacy obligations that the current product does not need.
- Mobile companion app: weak fit; QR/profile import-export already covers the useful transfer workflow.
- Plugin ecosystem: premature for a single-file elevated PowerShell tool; stabilize module boundaries and release build generation first.
- Rewrite in C#/.NET: not recommended because NetForge's differentiator is a portable PowerShell 5.1 tool that works on LTSC without a new runtime install.
- Dependabot/Renovate or GitHub Actions: rejected by repository policy; dependency, advisory, build, and release checks must stay local.

## Sources
Competitors and adjacent tools:
- https://www.netsetman.com/en/help
- https://www.netsetman.com/en/pro
- https://github.com/BornToBeRoot/NETworkManager
- https://github.com/KurtisLiggett/Simple-IP-Config
- https://github.com/DNSCrypt/dnscrypt-proxy
- https://github.com/AdguardTeam/dnsproxy
- https://github.com/Control-D-Inc/ctrld
- https://github.com/nextdns/nextdns
- https://github.com/DnsChanger/dnsChanger-desktop
- https://github.com/microsoft/windows-networking-tools
- https://github.com/katlogic/bindip
- https://www.yogadns.com/docs/
- https://www.sordum.org/7952/dns-jumper-v2-3/
- https://www.proxifier.com/
- https://www.glasswire.com/features/
- https://github.com/safing/portmaster

Standards and platform APIs:
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
- https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallinterfacefilter
- https://learn.microsoft.com/en-us/windows/win32/fwp/windows-filtering-platform-start-page
- https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkchange.networkaddresschanged
- https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata
- https://www.rfc-editor.org/rfc/rfc8484
- https://www.rfc-editor.org/rfc/rfc7858
- https://www.rfc-editor.org/rfc/rfc9250
- https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/

Dependency, tooling, and advisories:
- https://github.com/Shane32/QRCoder/releases/tag/v1.8.0
- https://github.com/micjahn/ZXing.Net/releases/tag/v0.16.11.0
- https://github.com/PowerShell/PSScriptAnalyzer
- https://pester.dev/
- https://github.com/advisories?query=ecosystem%3Anuget

## Open Questions
None for active roadmap prioritization. Code-signing certificate availability remains the blocker for the already-separated standard-user helper service.
