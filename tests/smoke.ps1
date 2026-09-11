<#
.SYNOPSIS
  Smoke test for runtimeclear.ps1 under Windows PowerShell 5.1 and PowerShell 7.

.DESCRIPTION
  Builds fake Java homes and a fake repo in a temp folder, runs runtimeclear.ps1 in a
  child process of the same PowerShell edition, and checks the JSON it writes.
  No network access, no admin rights, nothing outside the temp folder is touched.

  Windows PowerShell 5.1:  powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1
  PowerShell 7 (any OS):   pwsh -NoProfile -File tests/smoke.ps1

  Keep this file ASCII-only and free of PowerShell 7-only syntax.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Scanner = Join-Path (Split-Path -Parent $PSScriptRoot) 'runtimeclear.ps1'
$OnWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$Fix = Join-Path ([IO.Path]::GetTempPath()) ('runtimeclear-smoke-' + [Guid]::NewGuid().ToString('N'))
$Script:Failures = 0
$Script:Passes = 0

function Assert-Check([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) {
        $Script:Passes++
        [Console]::Out.WriteLine("  ok   $Name")
    } else {
        $Script:Failures++
        [Console]::Out.WriteLine("  FAIL $Name $Detail")
    }
}

# Writes ASCII text with LF line endings and creates the parent folder.
function Write-TextFile([string]$Path, [string[]]$Line) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    [IO.File]::WriteAllText($Path, (($Line -join "`n") + "`n"), [Text.Encoding]::ASCII)
}

# A folder with bin/java.exe (an empty file: it must never be executed) and an optional release file.
function Add-FakeJavaHome([string]$Dir, [bool]$Jdk, [string[]]$Release) {
    Write-TextFile (Join-Path (Join-Path $Dir 'bin') 'java.exe') @('')
    if ($Jdk) {
        Write-TextFile (Join-Path (Join-Path $Dir 'bin') 'javac.exe') @('')
        Write-TextFile (Join-Path (Join-Path $Dir 'bin') 'javac') @('')
    }
    if ($Release) { Write-TextFile (Join-Path $Dir 'release') $Release }
}

function ConvertTo-QuotedArgument([string]$Value) { return '"' + $Value + '"' }

# Runs runtimeclear.ps1 in a new process of this PowerShell edition.
function Invoke-Scanner([string[]]$ScannerArgs, [string]$ExtraJvmDirs, [string]$WorkDir) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Process -Id $PID).Path
    $list = @('-NoProfile', '-NonInteractive')
    if ($OnWindows) { $list += @('-ExecutionPolicy', 'Bypass') }
    $list += @('-File', (ConvertTo-QuotedArgument $Scanner))
    foreach ($a in $ScannerArgs) { if ($a.StartsWith('-')) { $list += $a } else { $list += (ConvertTo-QuotedArgument $a) } }
    $psi.Arguments = $list -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $WorkDir
    $psi.EnvironmentVariables['RUNTIMECLEAR_NO_SYSTEM_DEFAULTS'] = '1'
    $psi.EnvironmentVariables['RUNTIMECLEAR_EXTRA_JVM_DIRS'] = $ExtraJvmDirs
    $proc = [Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(120000)) { try { $proc.Kill() } catch { $null = $_ }; throw 'runtimeclear.ps1 did not finish within 120 seconds' }
    return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $outTask.Result; StdErr = $errTask.Result }
}

function Read-ScanFile([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    return [pscustomobject]@{ HasBom = $hasBom; Text = $text; Json = ($text | ConvertFrom-Json) }
}

$versionLine = Select-String -LiteralPath $Scanner -Pattern "^\`$ScannerVersion = '([^']+)'" | Select-Object -First 1
$ExpectedVersion = $versionLine.Matches[0].Groups[1].Value
[Console]::Out.WriteLine("PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), scanner $ExpectedVersion")

try {
    # ------------------------------------------------------------ fixtures ---
    $jvm = Join-Path $Fix 'jvm'
    Add-FakeJavaHome (Join-Path $jvm 'jdk-21-oracle-x64') $true @('IMPLEMENTOR="Oracle Corporation"', 'JAVA_RUNTIME_VERSION="21.0.4+8-LTS-274"', 'JAVA_VERSION="21.0.4"', 'BUILD_TYPE="commercial"')
    Write-TextFile (Join-Path $jvm 'jdk-21-oracle-x64/legal/java.base/LICENSE') @('Oracle No-Fee Terms and Conditions (NFTC)')
    Add-FakeJavaHome (Join-Path $jvm 'jre1.8.0_351') $false @('JAVA_VERSION="1.8.0_351"', 'IMPLEMENTOR="Oracle Corporation"', 'BUILD_TYPE="commercial"')
    Add-FakeJavaHome (Join-Path $jvm 'temurin-21-jdk') $true @('IMPLEMENTOR="Eclipse Adoptium"', 'JAVA_RUNTIME_VERSION="21.0.4+7-LTS"', 'JAVA_VERSION="21.0.4"')
    $noRelease = Join-Path $Fix 'jvm-norelease'
    Add-FakeJavaHome (Join-Path $noRelease 'legacyapp/jre') $false @()

    $repo = Join-Path $Fix 'repo'
    Write-TextFile (Join-Path $repo 'Dockerfile') @('FROM container-registry.oracle.com/java/jdk:21', 'RUN curl -LO https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.zip')
    Write-TextFile (Join-Path $repo 'docker-compose.yml') @('services:', '  app:', '    image: eclipse-temurin:21-jre')
    Write-TextFile (Join-Path $repo '.github/workflows/build.yml') @('jobs:', '  build:', '    steps:', '      - uses: actions/setup-java@v4', '        with:', "          distribution: 'oracle'", "          java-version: '21'")
    Write-TextFile (Join-Path $repo '.sdkmanrc') @('java=21.0.4-oracle')
    Write-TextFile (Join-Path $repo 'pom.xml') @('<toolchain><provides><version>21</version><vendor>oracle</vendor></provides></toolchain>')
    Write-TextFile (Join-Path $repo 'build.gradle') @('java {', '  toolchain {', '    languageVersion = JavaLanguageVersion.of(21)', '    vendor = JvmVendorSpec.ORACLE', '  }', '}')
    Write-TextFile (Join-Path $repo 'node_modules/pkg/Dockerfile') @('FROM container-registry.oracle.com/java/jdk:21')
    $cwd = Join-Path $Fix 'cwd'
    [void](New-Item -ItemType Directory -Path $cwd -Force)

    # ------------------------------------------------------ 1. fixture scan ---
    [Console]::Out.WriteLine('Test 1: fixture scan')
    $outFile = Join-Path $Fix 'scan.json'
    $r = Invoke-Scanner @('-Repo', $repo, '-Out', $outFile) $jvm $cwd
    Assert-Check 'exit code 0' ($r.ExitCode -eq 0) $r.StdErr
    Assert-Check 'JSON file written' (Test-Path -LiteralPath $outFile)
    $scan = Read-ScanFile $outFile
    $d = $scan.Json
    Assert-Check 'UTF-8 without BOM' (-not $scan.HasBom)
    Assert-Check 'top-level keys in schema order' (($d.PSObject.Properties.Name -join ',') -eq 'schema,scanner,scannedAt,host,installs,references,autoUpdate,warnings')
    Assert-Check 'schema id' ($d.schema -eq 'runtimeclear.scan/v1')
    Assert-Check 'scanner block' ($d.scanner.name -eq 'runtimeclear' -and $d.scanner.version -eq $ExpectedVersion -and $d.scanner.platform -eq 'windows')
    Assert-Check 'scannedAt is UTC ISO 8601' ($scan.Text -match '"scannedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"')
    foreach ($k in @('installs', 'references', 'autoUpdate', 'warnings')) {
        Assert-Check "$k serialized as a JSON array" ($scan.Text -match ('"' + $k + '":\s*\['))
    }
    $installs = @($d.installs)
    Assert-Check '3 installs found' ($installs.Count -eq 3) "(got $($installs.Count))"
    $keys = 'path,source,javaVersion,rawVersion,implementor,buildType,runtimeName,isJre,packageVendor,licenseFile'
    Assert-Check 'every install has exactly the schema keys' (@($installs | Where-Object { ($_.PSObject.Properties.Name -join ',') -ne $keys }).Count -eq 0)
    $o = @($installs | Where-Object { $_.path -like '*jdk-21-oracle-x64' }) | Select-Object -First 1
    Assert-Check 'oracle 21: version, raw version, implementor, build type' ($null -ne $o -and $o.javaVersion -eq '21.0.4' -and $o.rawVersion -eq '21.0.4+8-LTS-274' -and $o.implementor -eq 'Oracle Corporation' -and $o.buildType -eq 'commercial')
    Assert-Check 'oracle 21: licenseFile NFTC, isJre false, source filesystem' ($null -ne $o -and $o.licenseFile -eq 'NFTC' -and $o.isJre -eq $false -and $o.source -eq 'filesystem')
    $jre = @($installs | Where-Object { $_.path -like '*jre1.8.0_351' }) | Select-Object -First 1
    Assert-Check '8u351 JRE: isJre true, raw version falls back to JAVA_VERSION' ($null -ne $jre -and $jre.isJre -eq $true -and $jre.rawVersion -eq '1.8.0_351')
    $tem = @($installs | Where-Object { $_.path -like '*temurin-21-jdk' }) | Select-Object -First 1
    Assert-Check 'temurin: implementor, buildType null' ($null -ne $tem -and $tem.implementor -eq 'Eclipse Adoptium' -and $null -eq $tem.buildType)

    $expected = @(
        'repo/.github/workflows/build.yml|6|github-actions|oracle-setup-java',
        'repo/.sdkmanrc|1|sdkman|oracle-sdkman',
        'repo/build.gradle|4|gradle-toolchain|oracle-vendor',
        'repo/docker-compose.yml|3|compose|free-image',
        'repo/Dockerfile|1|dockerfile|oracle-image',
        'repo/Dockerfile|2|dockerfile|oracle-download',
        'repo/pom.xml|1|maven-toolchain|oracle-vendor'
    ) | Sort-Object
    $refs = @($d.references)
    $got = @($refs | ForEach-Object { "$($_.file)|$($_.line)|$($_.kind)|$($_.hint)" }) | Sort-Object
    Assert-Check 'references: exactly the 7 expected (file, line, kind, hint)' (($got -join ';') -eq ($expected -join ';')) ("got: " + ($got -join '; '))
    $gh = @($refs | Where-Object { $_.hint -eq 'oracle-setup-java' }) | Select-Object -First 1
    Assert-Check 'setup-java text includes the nearby java-version' ($null -ne $gh -and $gh.text -like "*java-version: '21'*")
    Assert-Check 'node_modules is skipped' (@($refs | Where-Object { $_.file -like '*node_modules*' }).Count -eq 0)
    Assert-Check 'autoUpdate and warnings are empty' (@($d.autoUpdate).Count -eq 0 -and @($d.warnings).Count -eq 0)
    Assert-Check 'summary: 3 runtimes, 2 Oracle, 6 Oracle references' ($r.StdErr -match 'Java runtimes found:\s+3' -and $r.StdErr -match 'Built by Oracle:\s+2 ' -and $r.StdErr -match 'Oracle references in repos:\s+6 ')

    # ------------------------------ 2. -NoExec, -Anonymize, -Quiet, default name ---
    [Console]::Out.WriteLine('Test 2: -NoExec, -Anonymize, -Quiet and the default output name')
    $r = Invoke-Scanner @('-NoExec', '-Anonymize', '-Quiet') $noRelease $cwd
    Assert-Check 'exit code 0' ($r.ExitCode -eq 0) $r.StdErr
    Assert-Check '-Quiet prints nothing' ([string]::IsNullOrEmpty($r.StdErr.Trim()) -and [string]::IsNullOrEmpty($r.StdOut.Trim()))
    $written = @(Get-ChildItem -LiteralPath $cwd -Filter 'runtimeclear-scan-*.json')
    Assert-Check 'default output name runtimeclear-scan-<12hex>-<UTC>.json' ($written.Count -eq 1 -and $written[0].Name -match '^runtimeclear-scan-[0-9a-f]{12}-\d{8}T\d{6}Z\.json$')
    if ($written.Count -eq 1) {
        $n = (Read-ScanFile $written[0].FullName).Json
        Assert-Check 'hostname anonymized to 12 hex chars' ($n.host.hostname -match '^[0-9a-f]{12}$')
        $only = @($n.installs)
        Assert-Check 'no release file + -NoExec: one install, version unknown' ($only.Count -eq 1 -and $only[0].javaVersion -eq 'unknown' -and $only[0].isJre -eq $true)
        Assert-Check 'no release file + -NoExec: warning recorded' (@($n.warnings | Where-Object { $_ -like '*-NoExec*' }).Count -eq 1)
        Assert-Check 'single install still serialized as an array' ((Read-ScanFile $written[0].FullName).Text -match '"installs":\s*\[')
    }

    # ------------------------------------------------ 3. options and errors ---
    [Console]::Out.WriteLine('Test 3: -Version and option errors')
    $r = Invoke-Scanner @('-Version') '' $cwd
    Assert-Check '-Version prints the version' ($r.ExitCode -eq 0 -and $r.StdOut.Trim() -eq "runtimeclear $ExpectedVersion") $r.StdOut
    $r = Invoke-Scanner @('-Repo', (Join-Path $Fix 'does-not-exist')) '' $cwd
    Assert-Check 'missing -Repo folder exits 2' ($r.ExitCode -eq 2) "(exit $($r.ExitCode))"
} finally {
    Remove-Item -LiteralPath $Fix -Recurse -Force -ErrorAction SilentlyContinue
}

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine("RESULT: $($Script:Passes) passed, $($Script:Failures) failed")
if ($Script:Failures -gt 0) { exit 1 }
exit 0
