# PSScriptAnalyzer settings for runtimeclear.ps1 and tests/*.ps1.
# CI: Invoke-ScriptAnalyzer -Path <file> -Settings ./PSScriptAnalyzerSettings.psd1
# Every excluded rule has a reason. Do not add exclusions to silence a real finding.
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Internal helpers such as Find-JavaHomes and Get-FileRefs return collections;
        # the plural reads correctly and the functions are not exported.
        'PSUseSingularNouns',
        # Four best-effort calls (Process.Kill on a timed-out java.exe, the optional CIM
        # OS caption, a process path and the Administrator check) ignore failures on purpose:
        # the scan must continue and the JSON must still be written.
        'PSAvoidUsingEmptyCatchBlock'
    )

    Rules        = @{
        # The scripts must parse on Windows PowerShell 5.1 as well as PowerShell 7.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
