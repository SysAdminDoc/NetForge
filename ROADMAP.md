# Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

### IPv6 & Advanced

- [ ] P1 -- Move Update-ConnectionStatus networking calls to background runspace
  Why: ConnStatusTimer fires every 30s and runs Get-NetIPAddress, Get-NetRoute, netsh wlan show interfaces synchronously on the UI thread.
  Where: `NetForge.ps1` Update-ConnectionStatus, Update-WifiInfo

- [ ] P1 -- Consolidate duplicate networking cmdlet calls in Update-AdapterDisplay / Update-AdapterDetails
  Why: 10+ networking cmdlet calls with 3 duplicates (Get-NetIPInterface, Get-NetRoute, Get-NetIPAddress) every time adapter selection changes.
  Where: `NetForge.ps1` Update-AdapterDisplay, Update-AdapterDetails

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

- [ ] P3 -- Add maximum entry count per hosts group
  Why: No limit on entries per group or total groups allows unbounded hosts file growth via crafted import.
  Where: `NetForge.ps1` ConvertTo-HostsManagedSection
