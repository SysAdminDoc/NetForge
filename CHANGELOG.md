# Changelog

All notable changes to NetForge will be documented in this file.

## [v1.53.0] - 2026-07-01

- Added: PSScriptAnalyzer exclusions now documented with per-rule justification.
- Added: Configuration export privacy modes (full backup vs shareable/redacted) with import preview showing accepted/conflicting/rejected counts.
- Added: Network List Manager identity as an auto-apply match source (network name/GUID/category via COM).
- Added: DNS resolver benchmark in DNS tab (5-query latency test, sorted results, fastest resolver identification).
- Added: RDAP IP ownership lookup in Network Tools (IANA bootstrap endpoint selection, netblock/name/country/entity display).

## [v1.52.0] - 2026-07-01

- Added: DoQ proxy binary trust report (SHA256, Authenticode, version, modified time) and stdout/stderr session logging.
- Added: In-app release and checksum verification in Diagnostics tab (GitHub API, version comparison, asset display).
- Added: DNS provider catalog freshness tool (`tools\Test-DnsCatalogFreshness.ps1`) with capability/endpoint mismatch detection.
- Added: Vendored DLL dependency manifest (`lib\dependencies.json`) with version drift and license file validation.
- Added: Settings schema validation (SettingsSchemaVersion, known-key check, corrupt-file quarantine, migration backups).
- Added: DHCP lease timing and server identity in adapter info panel (lease obtained/expires/remaining, expired flag).
- Added: Auto-apply priority and match-status inspector in Profiles tab.
- Added: GUI locale selector in Diagnostics tab (backed by shipped resource files, persists via settings, restart to apply).
- Added: Capability preflight matrix in Diagnostics tab (admin, modules, cmdlets, executables).

## [v1.51.0] - 2026-06-29

- Added: Diagnostics export privacy mode with a preview manifest and bundled `redaction-report.json`.
- Changed: Diagnostics exports now redact webhook URLs, proxy hosts, mapped-drive UNC paths, SSIDs, MACs, adapter names, and local paths when privacy mode is enabled.
- Added: Pester coverage for diagnostics export redaction, privacy-off behavior, and preview manifest formatting.

## [v1.50.0] - 2026-06-29

- Changed: App interface guards now persist the program path and allowed adapter so they can be reconciled after adapter changes.
- Added: Startup, NetworkChange, and manual Refresh Guards repair for missing or stale NetForge-owned firewall interface rules.
- Added: Pester coverage for persisted app guard policies, added adapters, removed adapters, and unchanged topology.

## [v1.49.0] - 2026-06-29

- Changed: Discord webhook URLs now migrate from plaintext settings to current-user DPAPI-protected storage.
- Added: Pester coverage for protected webhook storage, legacy migration, missing secret, and invalid protected data cases.

## [v1.48.0] - 2026-06-29

- Added: Network Tools app interface guard for restricting a selected executable to one allowed adapter using Windows Firewall/WFP interface filters.
- Added: Apply, remove, refresh, and list controls for NetForge-owned per-app interface rules.
- Added: Pester coverage for app interface guard validation, firewall rule naming, and rule row formatting.

## [v1.47.0] - 2026-06-29

- Added: Optional Discord webhook notification after successful profile applies from GUI, tray, scheduled, auto-apply, RDP, or CLI paths.
- Added: Diagnostics endpoint-policy controls for enabling the webhook and saving the Discord webhook URL.
- Added: Pester coverage for Discord webhook URL validation, redacted logging, and profile payload generation.

## [v1.46.0] - 2026-06-29

- Added: Integrated reachability wizard for DNS, gateway, route, TCP/firewall, and MTU checks from Network Tools.
- Changed: Network diagnostics actions wrap on smaller windows to keep all tools reachable.
- Added: Pester coverage for reachability target parsing and report formatting.

## [v1.45.0] - 2026-06-29

- Added: Network Tools RDP launch workflow that applies a saved profile, starts `mstsc.exe`, and monitors the client process.
- Added: Automatic network-state revert when the RDP client exits, plus manual RDP profile revert.
- Added: Pester coverage for conservative RDP host and `.rdp` file launch-plan parsing.

## [v1.44.0] - 2026-06-29

- Added: CLI profile apply with `-ApplyProfile`, optional `-AdapterName`, and `-Silent` for scripting.
- Changed: CLI applies profiles through the same validation, rollback snapshot, DNS, IP, and environment-action path as GUI/tray applies.
- Added: Pester coverage for CLI profile and adapter resolution.

## [v1.43.0] - 2026-06-29

- Added: Profile QR export/import as PNG using bundled QRCoder and ZXing.Net libraries.
- Added: Versioned compressed NetForge profile QR payloads with duplicate-safe import.
- Added: Pester coverage for QR payload round-trips and non-NetForge payload rejection.

## [v1.42.0] - 2026-06-29

- Added: Persistent compact mode checkbox for laptop-friendly density.
- Changed: Compact mode reduces window minimums and scales captured WPF margins, padding, and font sizes while preserving the default layout.
- Added: Pester coverage for compact-mode setting parsing and density scaling helpers.

## [v1.41.0] - 2026-06-29

- Added: Persistent header theme selector with GitHub Dark, Catppuccin Mocha, and Nord palettes.
- Changed: Core WPF palette brushes now update at runtime for backgrounds, text, borders, accents, hover, selection, and button states.
- Added: Pester coverage for theme catalog completeness and theme-name fallback behavior.

## [v1.40.0] - 2026-06-29

- Added: System tray mode with Open, Hide, Refresh, and Exit actions.
- Added: Tray quick DNS switching with categorized preset menus and rollback-protected apply.
- Added: Tray profile switching for saved profiles against the selected or first active adapter.

## [v1.39.0] - 2026-06-29

- Added: IPv4 First and IPv6 First adapter binding-priority presets in the interface metric panel.
- Changed: Binding priority presets set explicit IPv4/IPv6 metrics while preserving the existing manual and automatic metric controls.
- Added: Pester coverage for the IPv4-first and IPv6-first metric plans.

## [v1.38.0] - 2026-06-29

- Added: Hosts file group editor in Network Tools with add, toggle, remove, refresh, and apply actions.
- Added: NetForge-managed hosts section rendering that preserves unmanaged hosts lines and writes timestamped backups.
- Added: Pester coverage for hosts entry validation, section parsing/replacement, and group output formatting.

## [v1.37.0] - 2026-06-29

- Added: Static route editor in Network Tools for selected-adapter IPv4 and IPv6 manual routes.
- Added: Route validation for CIDR destination prefixes, matching next-hop address family, and route metrics.
- Added: Pester coverage for static route validation, manual-route filtering, and formatted route output.

## [v1.36.0] - 2026-06-29

- Added: Optional static IPv6 address, prefix length, and gateway controls to the IP Configuration tab.
- Changed: IP apply transactions now preserve and roll back manual IPv6 addresses and default routes.
- Added: Pester coverage for IPv6 address/prefix validation and optional IPv6 apply targets.

## [v1.35.0] - 2026-06-29

- Added: Timed endpoint latency histogram from the Diagnostics ping panel.
- Added: Bucketed latency distribution with min/avg/max, p50/p95, and loss percentage.
- Added: Duration validation and Pester coverage for histogram bucket/report formatting.

## [v1.34.0] - 2026-06-29

- Added: WiFi spectrum channel-utilization view after scans.
- Added: Per-BSSID parser retention for channel, signal, band, and radio data from `netsh wlan show networks mode=bssid`.
- Added: Pester coverage for channel aggregation and formatted spectrum output.

## [v1.33.0] - 2026-06-29

- Added: Selected-adapter cable/transceiver diagnostics from the Network Tools diagnostics row.
- Added: Best-effort report for adapter hardware, counters, and driver-exposed cable, SFP, DDM/DOM, optical, and transceiver properties.
- Changed: Diagnostics explicitly report when the selected adapter driver exposes no cable/SFP telemetry.
- Added: Pester coverage for cable/transceiver property matching and report formatting.

## [v1.32.0] - 2026-06-29

- Added: Start/stop packet capture from the Network Tools diagnostics row using Windows `pktmon`.
- Added: Capture output under `%APPDATA%\NetForge\Captures` with ETL plus Wireshark-readable `.pcapng` conversion.
- Added: Optional Wireshark launch when `wireshark.exe` is available, while keeping capture functional without Npcap/Wireshark.
- Added: Pester coverage for timestamped capture paths and packet-capture summary rendering.

## [v1.31.0] - 2026-06-29

- Added: Async TCP port scanner for host and bounded IPv4 CIDR targets from the Network Tools diagnostics row.
- Added: Compact LAN discovery port set for CIDR scans and broader common-service port set for single-host scans.
- Added: Open-service output with service labels, latency, target count, port set, and elapsed time.
- Added: Pester coverage for CIDR expansion, default port selection, and formatted scan results.

## [v1.30.0] - 2026-06-29

- Added: MTR-style continuous traceroute from the Network Tools diagnostics row.
- Added: Per-hop sent, received, loss, last, best, average, and worst latency history with destination detection.
- Changed: Continuous route probes run asynchronously with a five-second cycle and stop cleanly on window close.
- Added: Pester coverage for MTR history aggregation and rendered route table output.

## [v1.29.0] - 2026-06-29

- Added: Scheduled profile switching by day and 24-hour time.
- Added: Profile schema v3 schedule fields with editor controls, diff preview output, and one-minute DispatcherTimer evaluation.
- Changed: Scheduled profile applies reuse the existing rollback-protected profile apply path in quiet mode.
- Added: Pester coverage for schedule day/time normalization, due-minute matching, and invalid schedule rejection.

## [v1.28.0] - 2026-06-29

- Added: Import support for Windows WLAN profile XML files exported by `netsh wlan export profile`.
- Added: WLAN XML imports create DHCP/DNS-auto NetForge profiles with SSID auto-apply metadata while excluding wireless key material.
- Added: Pester coverage for namespaced WLAN XML parsing, SSID hex fallback, and invalid XML rejection.
- Changed: The import dialog now accepts NetForge JSON and WLAN XML files through the same validated dry-run import flow.

## [v1.27.0] - 2026-06-29

- Added: Profile schema v2 environment actions for Windows network category, system proxy, default printer, and mapped drives.
- Added: Profile editor controls for environment actions plus preview diff output for each configured action.
- Added: Rollback snapshot coverage for network category, system proxy, default printer, and mapped-drive state.
- Added: Pester coverage for schema v2 normalization, mapped-drive parsing, and invalid environment profile validation.
- Changed: Profile apply now runs optional environment actions inside the existing rollback mutation wrapper.

## [v1.26.0] - 2026-06-29

- Added: Diagnostics endpoint-policy panel for public-IP lookup and external speed-test controls.
- Added: Persisted `PublicIpLookupEnabled`, `ExternalSpeedTestEnabled`, and `SpeedTestEndpoint` settings.
- Changed: Speed test now uses a selected HTTPS-only endpoint with no hidden HTTP fallback.
- Added: Operation logs for public-IP and speed-test endpoint contacts, skips, failures, and policy saves.
- Added: Pester coverage for endpoint boolean parsing, HTTPS-only catalogs, invalid endpoint fallback, and old HTTP URL removal.

## [v1.25.0] - 2026-06-29

- Added: `strings/en-US.json` and `strings/es-ES.json` resource files for UI localization.
- Added: XAML localization pass that replaces static user-visible text from the resource table before WPF loads the window.
- Added: Runtime localized button/footer strings for controls that change state after launch.
- Added: Pester coverage for locale key parity, static XAML text coverage, dynamic localization keys, and fallback behavior.
- Changed: Release packaging and local checks now include the `strings` directory.

## [v1.24.0] - 2026-06-29

- Added: `dns-providers.json` catalog with provider capabilities for IPv4, IPv6, DoH, DoT, DoQ, filtering category, and DHCP/default entries.
- Added: SHA256 sidecar validation for the DNS provider catalog with embedded preset fallback if the catalog is missing, stale, or invalid.
- Changed: DNS preset list now loads from the validated catalog and shows capability tags in provider descriptions.
- Added: Pester coverage for catalog hash verification, provider conversion, encrypted DNS capability loading, and invalid-provider rejection.
- Changed: Release packaging and local checks now include and validate the DNS provider catalog files.

## [v1.23.0] - 2026-06-29

- Added: Release package builder now writes `NetForge-vX.Y.Z.zip.sha256` beside the zip.
- Added: Optional Authenticode signing for the staged `NetForge.ps1` when a valid code-signing certificate is available.
- Added: Local checks now validate the release zip and checksum file names and contents when `dist` exists.
- Added: README install instructions for verifying downloaded release archives with `certutil`.

## [v1.22.0] - 2026-06-28

- Added: Central `version.json` metadata for release version, date, and package name.
- Added: Version updater for script header, UI labels, README badge, changelog heading, and local working notes.
- Added: Release package builder that names the zip from version metadata and emits SHA256 metadata.
- Changed: Local checks now fail when version metadata drifts across script, README, changelog, working notes, or existing dist zip names.

## [v1.21.0] - 2026-06-28

- Added: Profile storage controls for choosing a custom folder, using a detected OneDrive folder, reverting to local storage, and checking path health.
- Added: Profile store migration with existing-profile copy, same-name conflict blocking, invalid-profile reporting, and backup manifest JSON.
- Added: Atomic app settings persistence for the selected profile store path.
- Added: Pester coverage for profile store path normalization, migration planning, conflict detection, manifest writing, and settings persistence.

## [v1.20.0] - 2026-06-28

- Added: DNS health output now shows configured adapter DNS, selected target resolvers, config leak guard, DoH/DoT endpoint probes, UDP fallback state, resolver latency, and DoQ local listener state.
- Added: DNS apply confirmation now previews target resolver latency and fallback reachability before changing adapter DNS.
- Added: Pester coverage for DNS health formatting, leak guard comparison, UDP probe validation, and DNS wire-query construction.

## [v1.19.0] - 2026-06-28

- Added: Automation names for primary WPF controls.
- Added: Explicit tab order for core adapter, IP, DNS, profile, and diagnostics workflows.
- Added: Accessibility smoke coverage in local Pester tests.

## [v1.18.0] - 2026-06-28

- Added: Local `tools\Test-NetForge.ps1` quality gate.
- Added: PSScriptAnalyzer allowlist settings and Pester tests for parser, profile validation, endpoint parsing, atomic writes, and network signature keys.

## [v1.17.0] - 2026-06-28

- Added: Network-change event handlers for profile auto-apply.
- Changed: Auto-apply now logs trigger sources and uses a five-minute timer fallback.
- Changed: Auto-apply suppresses repeated applies for the same profile and unchanged network signature.

## [v1.16.0] - 2026-06-28

- Added: Persistent operation logs under `%APPDATA%\NetForge\Logs`.
- Added: Crash log files for unhandled dispatcher/domain exceptions.
- Added: Diagnostics zip export with logs, profiles, and selected-adapter state.
- Changed: Empty catch blocks now record warning details.

## [v1.15.0] - 2026-06-28

- Added: Schema-versioned profile normalization and validation.
- Added: Atomic temp-file profile writes with duplicate-name protection.
- Added: Import dry-run summary with accepted/rejected profile rows in diagnostics output.

## [v1.14.0] - 2026-06-28

- Added: Rollback snapshots before IP, DNS, and profile apply operations.
- Added: Manual restore action for the last captured network state in Network Tools.
- Changed: IP, DNS, and profile apply paths now validate target fields before mutating adapter state.

## [v1.13.0] - 2026-06-28

- Added: Profile diff preview against the selected adapter.
- Added: Same/change comparison output for IP mode, address, prefix, gateway, DNS, and auto-apply match fields.

## [v1.12.0] - 2026-06-28

- Added: Profile auto-apply rules for current WiFi SSID and gateway MAC matching.
- Added: Capture-current-network helper in the profile editor.
- Added: Background auto-apply timer that applies the first matching profile to the active adapter.

## [v1.11.0] - 2026-06-28

- Added: NextDNS config ID helper for account-specific encrypted endpoint capture.
- Added: One-click population of DoH template, DoT host, and DoQ upstream fields for NextDNS accounts.

## [v1.10.0] - 2026-06-28

- Added: DoQ local proxy panel for external `dnsproxy.exe` compatible binaries.
- Added: DoQ proxy validation, start/stop controls, bootstrap DNS setting, and local DNS apply action for port 53 listeners.
- Changed: Window cleanup stops any NetForge-managed DoQ proxy process.

## [v1.9.0] - 2026-06-28

- Added: Encrypted DNS health testing for the selected DoH template and DoT host.
- Added: DoH HTTPS DNS-message probe and DoT TCP/TLS DNS-message probe against `example.com`.
- Changed: Health testing runs in a background job and reports per-protocol results in the DNS panel.

## [v1.8.0] - 2026-06-28

- Added: Windows DoT encryption registration using `netsh dns add encryption dothost` with `set encryption` fallback for existing entries.
- Added: DoT host metadata for Google, Cloudflare, Quad9, and AdGuard presets plus custom DoT host entry.
- Changed: Preset switching clears stale encrypted DNS metadata when the selected provider has no DoH or DoT endpoint.

## [v1.7.0] - 2026-06-27

- Added: Windows DoH encryption registration panel using `netsh dns add encryption` with `set encryption` fallback for existing entries.
- Added: DoH template metadata for Google, Cloudflare, Quad9, and AdGuard presets plus custom DoH template entry.

## [v1.6.0] - 2026-06-27

- Added: Adapter priority/interface metric editor for IPv4 and IPv6.
- Added: Automatic metric restore controls for selected address families.

## [v1.5.0] - 2026-06-27

- Added: Adapter-scoped MAC address override panel with validation, random local-unicast generation, apply, and revert.
- Added: Registry-backed `NetworkAddress` management with selected-adapter restart when the adapter is active.

## [v1.4.0] - 2026-06-27

- Added: Advanced adapter switch for Hyper-V, VMware, VirtualBox, VPN/TAP, and other virtual adapters.
- Changed: Adapter classification now labels advanced virtual adapter families separately from physical Ethernet.

## [v1.3.0] - 2026-06-27

- Added: Bluetooth PAN and cellular/mobile broadband adapter enumeration in the adapter list.
- Changed: Connection status and adapter details now use a shared adapter classification path for Ethernet, WiFi, VPN, Bluetooth PAN, and Cellular.

## [v1.2.0] - 2026-06-27

- Added: WiFi network scanner with signal, channel, band, security, and BSSID detail.
- Added: WiFi connect/disconnect controls using Windows WLAN profiles and generated profiles for open or secured personal networks.
- Changed: README version badge, install URLs, feature list, and ASCII-safe configuration storage tree.

## [v1.1.0] - %Y->- (HEAD -> main, tag: v1.1.0, origin/main)

- Added: Add project icon to README
- Added: Add screenshot to README
- v1.1.0 - Ping monitor, connection status, WiFi info, speed test, DNS lookup
- Initial commit - NetForge
