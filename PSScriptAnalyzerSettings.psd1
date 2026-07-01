@{
    ExcludeRules = @(
        # WPF event handlers assign $_ and other automatic variables in closures
        'PSAvoidAssignmentToAutomaticVariable',
        # No Write-Host in production but may appear in debugging helpers
        'PSAvoidUsingWriteHost',
        # Runspace scriptblocks reference outer-scope parameters by design
        'PSReviewUnusedParameter',
        # Normalize-*, Toggle-*, Apply-* are internal; script does not export modules
        'PSUseApprovedVerbs',
        # Script-scope state variables ($script:Foo = $null) are assigned once and used later
        'PSUseDeclaredVarsMoreThanAssignments',
        # 35+ GUI functions (Set-*, Save-*, Invoke-*) mutate adapter/DNS/profile state through WPF buttons, not interactive CLI; ShouldProcess is inappropriate
        'PSUseShouldProcessForStateChangingFunctions',
        # Internal function names use plural nouns for collections
        'PSUseSingularNouns',
        # Runspace scriptblocks ($ps.AddScript) intentionally capture outer-scope variables via closure; $using: is only valid in PS remoting/Start-Job, not [PowerShell]::Create() runspaces
        'PSUseUsingScopeModifierInNewRunspaces'
    )
}
