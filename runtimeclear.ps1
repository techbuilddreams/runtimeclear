<#
.SYNOPSIS
  RuntimeClear scanner for Windows: inventories Java runtimes and Oracle Java references.

.DESCRIPTION
  Copyright (c) 2026 Tech Build Dreams LLC. MIT License. https://runtimeclear.com

  WHAT THIS SCRIPT READS (read-only; it never modifies, moves or deletes anything):
    - Registry: HKLM\SOFTWARE\JavaSoft (and WOW6432Node) JavaHome values; Uninstall
      keys (DisplayName, Publisher, InstallLocation); Java Update policy values;
      the SunJavaUpdateSched Run value.
    - Folders: Program Files\{Java, Eclipse Adoptium, Amazon Corretto, Zulu, BellSoft,
      Microsoft\jdk-*, ...}, %USERPROFILE%\.jdks, .gradle\jdks, scoop\apps, and the
      `release` text file inside each Java home.
    - `where.exe java`, $env:JAVA_HOME.
    - Running java.exe / javaw.exe / jusched.exe: executable PATH ONLY (no arguments).
    - Scheduled task names containing "Java" and "Update".
    - With -Repo only: names of CI/container/build files and the single matching lines.
  WHAT IT EXECUTES: <java home>\bin\java.exe -version ONLY for a Java home without a
    usable `release` file (5 second timeout). -NoExec disables this.
  WHAT IT WRITES: exactly one JSON file (-Out).
  NETWORK: none. Nothing is sent anywhere. Get-Package is deliberately NOT used because
    it can try to download a package provider.
  PRIVILEGES: none required. Unreadable locations are listed under "warnings".
  Compatible with Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\runtimeclear.ps1 -Repo C:\src\billing
#>
[CmdletBinding()]
param(
    [string[]]$Repo = @(),   # scan these folders for Oracle Java references
    [switch]$NoSystem,       # skip installed-runtime discovery
    [switch]$NoExec,         # never run java.exe -version
    [switch]$Anonymize,      # hostname -> first 12 hex chars of its SHA-256
    [string]$Out = '',       # output file
    [switch]$Quiet,          # no summary
    [switch]$Version         # print version and exit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScannerVersion = '1.0.1'
$SiteUrl        = 'https://runtimeclear.com'
$JavaTimeoutMs  = 5000
$MaxText        = 300
$SkipDirs       = @('.git', 'node_modules', 'target', 'build', '.gradle', 'vendor')

if ($Version) { Write-Output "runtimeclear $ScannerVersion"; exit 0 }
foreach ($r in $Repo) {
    if (-not (Test-Path -LiteralPath $r -PathType Container)) {
        [Console]::Error.WriteLine("runtimeclear: -Repo is not a folder: $r"); exit 2
    }
}

# Test-only hooks used by tests/run.sh (not needed in normal use).
$NoSystemDefaults = ($env:RUNTIMECLEAR_NO_SYSTEM_DEFAULTS -eq '1')
$ExtraJvmDirs = @()
if ($env:RUNTIMECLEAR_EXTRA_JVM_DIRS) { $ExtraJvmDirs = $env:RUNTIMECLEAR_EXTRA_JVM_DIRS.Split([IO.Path]::PathSeparator) }

$Candidates = New-Object System.Collections.Generic.List[object]
$Installs   = New-Object System.Collections.Generic.List[object]
$References = New-Object System.Collections.Generic.List[object]
$AutoUpdate = New-Object System.Collections.Generic.List[object]
$Warnings   = New-Object System.Collections.Generic.List[string]
$Seen       = @{}

# ------------------------------------------------------------------ helpers ---
function Add-Warning([string]$Message) { $Warnings.Add($Message) }

# Run one discovery step; an unexpected error becomes a warning, not a crash.
function Invoke-Step([string]$Name, [scriptblock]$Body) {
    try { & $Body } catch { Add-Warning "$Name failed: $($_.Exception.Message)" }
}

# Property of an object or $null (StrictMode-safe).
function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-RegValues([string]$Key) {
    try { return Get-ItemProperty -LiteralPath $Key -ErrorAction Stop } catch { return $null }
}

# java.exe inside a home (bin/java without .exe only exists in the Linux test harness).
function Get-JavaExe([string]$HomeDir) {
    foreach ($n in @('java.exe', 'java')) {
        $p = Join-Path (Join-Path $HomeDir 'bin') $n
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}

# Follow symbolic links / junctions on the last path component.
function Resolve-LinkPath([string]$Path) {
    $p = $Path
    for ($i = 0; $i -lt 10; $i++) {
        try { $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop } catch { break }
        $target = @(Get-Prop $item 'Target') | Where-Object { $_ } | Select-Object -First 1
        if (-not (Get-Prop $item 'LinkType') -or -not $target) { break }
        if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path -Parent $p) $target }
        $p = $target
    }
    return [IO.Path]::GetFullPath($p)
}

function Add-Candidate([string]$Source, [string]$HomeDir, [string]$Vendor) {
    if ($HomeDir) { $Candidates.Add([pscustomobject]@{ Source = $Source; Home = $HomeDir.Trim().Trim('"'); Vendor = $Vendor }) }
}

# A java.exe path -> its Java home (the folder above bin).
function Add-JavaExeCandidate([string]$Source, [string]$ExePath) {
    $real = Resolve-LinkPath $ExePath
    $bin = Split-Path -Parent $real
    if ((Split-Path -Leaf $bin) -ne 'bin') {
        if ($real -like '*\Oracle\Java\javapath*') {
            Add-Warning "Oracle installer 'javapath' entry on PATH (placed by an Oracle JDK/JRE installer): $real"
        } else {
            Add-Warning "Skipped ${ExePath}: not inside a Java home (resolves to $real)."
        }
        return
    }
    Add-Candidate $Source (Split-Path -Parent $bin) $null
}

# Every folder below $Root (up to $Depth levels, $Root included) that has bin\java.exe.
# Does not descend into a Java home or through reparse points (junctions/symlinks).
function Find-JavaHomes([string]$Root, [int]$Depth) {
    $found = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $found }
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue(@($Root, 0))
    while ($queue.Count -gt 0) {
        $entry = $queue.Dequeue(); $dir = $entry[0]; $level = $entry[1]
        if (Get-JavaExe $dir) { $found.Add($dir); continue }
        if ($level -ge $Depth) { continue }
        try { $children = @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction Stop) }
        catch { Add-Warning "Not readable, skipped (run as Administrator to include): $dir"; continue }
        foreach ($c in $children) {
            $isLink = ($c.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($isLink) { if (Get-JavaExe $c.FullName) { $found.Add($c.FullName) } }
            else { $queue.Enqueue(@($c.FullName, ($level + 1))) }
        }
    }
    return $found
}

function Add-HomesBelow([string]$Source, [string]$Root, [int]$Depth) {
    foreach ($h in (Find-JavaHomes $Root $Depth)) { Add-Candidate $Source $h $null }
}

# ------------------------------------------------------------- discovery ---
function Find-UninstallEntries {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $v = Get-RegValues $key.PSPath
            $name = [string](Get-Prop $v 'DisplayName')
            $publisher = [string](Get-Prop $v 'Publisher')
            $location = [string](Get-Prop $v 'InstallLocation')
            if ($name -notmatch 'Java|JDK|JRE|OpenJDK|Corretto|Zulu|Temurin|Liberica|GraalVM') { continue }
            if ($name -like '*Java Auto Updater*') {
                $AutoUpdate.Add([ordered]@{ kind = 'windows-java-auto-updater'; enabled = $true
                    detail = "Installed program '$name' (publisher: $publisher)" })
                continue
            }
            if ($location -and (Get-JavaExe $location)) {
                Add-Candidate 'registry' $location $publisher
            } elseif ($publisher -like '*Oracle*') {
                Add-Warning "Oracle program '$name' is registered but has no usable InstallLocation; check it manually."
            }
        }
    }
}

function Find-JavaSoftRegistry {
    foreach ($base in @('HKLM:\SOFTWARE\JavaSoft', 'HKLM:\SOFTWARE\WOW6432Node\JavaSoft')) {
        foreach ($sub in @('JDK', 'JRE', 'Java Development Kit', 'Java Runtime Environment')) {
            $key = "$base\$sub"
            if (-not (Test-Path -LiteralPath $key)) { continue }
            foreach ($child in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
                $javaHome = Get-Prop (Get-RegValues $child.PSPath) 'JavaHome'
                if ($javaHome) { Add-Candidate 'registry' ([string]$javaHome) $null }
            }
        }
    }
}

function Find-Processes {
    $noPath = 0
    foreach ($p in @(Get-Process -Name 'java', 'javaw' -ErrorAction SilentlyContinue)) {
        $exe = $null
        try { $exe = Get-Prop $p 'Path' } catch { }   # executable path only; arguments are not read
        if ($exe) { Add-JavaExeCandidate 'process' $exe } else { $noPath++ }
    }
    if ($noPath -gt 0) { Add-Warning "$noPath running java process(es) without a readable path (run as Administrator to include)." }
}

function Find-PathAndJavaHome {
    if ($env:JAVA_HOME) { Add-Candidate 'path' $env:JAVA_HOME $null }
    $where = Get-Command 'where.exe' -ErrorAction SilentlyContinue
    if ($where) {
        # where.exe writes "INFO: Could not find files" to stderr when java is not on PATH;
        # with 'Stop', Windows PowerShell 5.1 would turn that into an exception.
        $ErrorActionPreference = 'SilentlyContinue'
        foreach ($line in @(& $where.Path 'java' 2>$null)) {
            if ($line -and (Test-Path -LiteralPath $line -PathType Leaf)) { Add-JavaExeCandidate 'path' $line }
        }
    }
}

function Find-Filesystem {
    $programDirs = @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) |
        Where-Object { $_ } | Select-Object -Unique
    foreach ($pf in $programDirs) {
        foreach ($vendorDir in @('Java', 'Eclipse Adoptium', 'Eclipse Foundation', 'Amazon Corretto',
                                 'Zulu', 'BellSoft', 'Semeru', 'SapMachine', 'OpenJDK', 'RedHat')) {
            Add-HomesBelow 'filesystem' (Join-Path $pf $vendorDir) 2
        }
        $ms = Join-Path $pf 'Microsoft'
        if (Test-Path -LiteralPath $ms) {
            foreach ($d in @(Get-ChildItem -LiteralPath $ms -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue)) {
                Add-HomesBelow 'filesystem' $d.FullName 0
            }
        }
    }
    # Per-user tool folders. As Administrator, every profile under C:\Users is included.
    $profiles = @($env:USERPROFILE)
    if ($IsAdmin -and $env:SystemDrive) {
        $profiles += @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName })
    }
    foreach ($prof in ($profiles | Where-Object { $_ } | Select-Object -Unique)) {
        Add-HomesBelow 'filesystem' (Join-Path $prof '.jdks') 1
        Add-HomesBelow 'filesystem' (Join-Path $prof '.gradle\jdks') 2
        Add-HomesBelow 'filesystem' (Join-Path $prof '.m2\jdks') 2
        Add-HomesBelow 'filesystem' (Join-Path $prof 'scoop\apps') 2
    }
    if ($env:ProgramData) { Add-HomesBelow 'filesystem' (Join-Path $env:ProgramData 'scoop\apps') 2 }
}

function Find-AutoUpdate {
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Update\Policy', 'HKLM:\SOFTWARE\JavaSoft\Java Update\Policy')) {
        $v = Get-RegValues $key
        if ($null -eq $v) { continue }
        $update = Get-Prop $v 'EnableJavaUpdate'
        $check = Get-Prop $v 'EnableAutoUpdateCheck'
        $enabled = $null                      # null = could not determine
        if ($null -ne $update) { $enabled = ([int]$update -eq 1) }
        $AutoUpdate.Add([ordered]@{ kind = 'windows-java-update-policy'; enabled = $enabled
            detail = "$key EnableJavaUpdate=$update EnableAutoUpdateCheck=$check" })
    }
    $evidence = @()
    $running = $false
    foreach ($dir in @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ } | Select-Object -Unique) {
        $exe = Join-Path $dir 'Common Files\Java\Java Update\jusched.exe'
        if (Test-Path -LiteralPath $exe) { $evidence += "present: $exe" }
    }
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        if (Get-Prop (Get-RegValues $key) 'SunJavaUpdateSched') { $evidence += "starts at logon: $key\SunJavaUpdateSched"; $running = $true }
    }
    if (@(Get-Process -Name 'jusched' -ErrorAction SilentlyContinue).Count -gt 0) { $evidence += 'jusched.exe is running'; $running = $true }
    if ($evidence.Count -gt 0) {
        $enabled = $null
        if ($running) { $enabled = $true }
        $AutoUpdate.Add([ordered]@{ kind = 'windows-java-update-scheduler'; enabled = $enabled; detail = ($evidence -join '; ') })
    }
    if (Get-Command 'Get-ScheduledTask' -ErrorAction SilentlyContinue) {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*Java*Update*' })) {
            $AutoUpdate.Add([ordered]@{ kind = 'windows-scheduled-task'; enabled = ([string]$t.State -ne 'Disabled')
                detail = "Scheduled task $($t.TaskPath)$($t.TaskName) (state: $($t.State))" })
        }
    }
}

# --------------------------------------------------------- inspect a home ---
function Get-JavaVersionOutput([string]$Exe) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe; $psi.Arguments = '-version'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync(); $outTask = $proc.StandardOutput.ReadToEndAsync()
    if (-not $proc.WaitForExit($JavaTimeoutMs)) {
        try { $proc.Kill() } catch { }
        Add-Warning "'java -version' timed out after $($JavaTimeoutMs / 1000)s: $Exe"
        return ''
    }
    return ($errTask.Result + "`n" + $outTask.Result)
}

function Get-LicenseFileHint([string]$HomeDir) {
    # Which license text did this build ship with? Reads at most 64 KB of each file; nothing is copied into the JSON.
    foreach ($rel in @('legal\java.base\LICENSE', 'LICENSE', 'jre\LICENSE', 'COPYRIGHT', 'jre\COPYRIGHT')) {
        $f = Join-Path $HomeDir $rel
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        try {
            $fs = [System.IO.File]::OpenRead($f)
            try {
                $buf = New-Object byte[] 65536
                $n = $fs.Read($buf, 0, $buf.Length)
                $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
            } finally { $fs.Dispose() }
        } catch { continue }
        if ($text -like '*Oracle Technology Network License Agreement*') { return 'OTN' }
        if ($text -like '*No-Fee Terms and Conditions*') { return 'NFTC' }
        if ($text -like '*Binary Code License*') { return 'BCL' }
        if ($text -like '*GNU General Public License*') { return 'GPL' }
    }
    return $null
}

function Read-JavaHome([string]$HomeDir, [string]$Source, [string]$Vendor) {
    $javaVersion = ''; $rawVersion = ''; $implementor = ''; $buildType = ''; $runtimeName = ''
    $releaseFile = Join-Path $HomeDir 'release'
    if (Test-Path -LiteralPath $releaseFile -PathType Leaf) {
        $release = @{}
        try {
            foreach ($line in (Get-Content -LiteralPath $releaseFile -ErrorAction Stop)) {
                if ($line -match '^([A-Z_]+)=(.*)$') { $release[$Matches[1]] = $Matches[2].Trim().Trim('"') }
            }
        } catch { Add-Warning "Not readable: $releaseFile" }
        $javaVersion = [string]$release['JAVA_VERSION']; $rawVersion = [string]$release['JAVA_RUNTIME_VERSION']
        $implementor = [string]$release['IMPLEMENTOR']; $buildType = [string]$release['BUILD_TYPE']
    }
    if (-not $javaVersion) {
        if ($NoExec) {
            Add-Warning "No release file and -NoExec given; version unknown: $HomeDir"
        } else {
            $text = Get-JavaVersionOutput (Get-JavaExe $HomeDir)
            # Version line: java version "1.8.0_202"  |  openjdk version "21.0.4" 2024-07-16 LTS
            if ($text -match ' version "([^"]*)"') { $javaVersion = $Matches[1] }
            $rtLine = @($text -split "`r?`n" | Where-Object { $_ -like '*Runtime Environment*' }) | Select-Object -First 1
            if ($rtLine) {
                if ($rtLine -like '*Java(TM) SE Runtime Environment*') { $runtimeName = 'Java(TM) SE Runtime Environment' }
                elseif ($rtLine -like '*OpenJDK Runtime Environment*') { $runtimeName = 'OpenJDK Runtime Environment' }
                if ($rtLine -match '\(build ([^)]*)\)') { $rawVersion = $Matches[1] }
                # Vendor only when the runtime line names it explicitly.
                if ($rtLine -like '*Temurin*') { $implementor = 'Eclipse Adoptium' }
                elseif ($rtLine -like '*Corretto*') { $implementor = 'Amazon.com Inc.' }
                elseif ($rtLine -like '*Zulu*') { $implementor = 'Azul Systems, Inc.' }
                elseif ($rtLine -like '*Microsoft*') { $implementor = 'Microsoft' }
            }
        }
    }
    if (-not $rawVersion) { $rawVersion = $javaVersion }
    if (-not $javaVersion) { $javaVersion = 'unknown' }
    if (-not $rawVersion) { $rawVersion = 'unknown' }
    if (-not $implementor) { $implementor = 'unknown' }
    $javac = (Test-Path -LiteralPath (Join-Path $HomeDir 'bin\javac.exe')) -or (Test-Path -LiteralPath (Join-Path (Join-Path $HomeDir 'bin') 'javac'))
    $Installs.Add([ordered]@{
        path = $HomeDir; source = $Source; javaVersion = $javaVersion; rawVersion = $rawVersion
        implementor = $implementor
        buildType = $(if ($buildType) { $buildType } else { $null })
        runtimeName = $(if ($runtimeName) { $runtimeName } else { $null })
        isJre = (-not $javac)
        packageVendor = $(if ($Vendor) { $Vendor } else { $null })
        licenseFile = (Get-LicenseFileHint $HomeDir)
    })
}

function Invoke-Candidates {
    foreach ($c in $Candidates) {
        try { $homeDir = Resolve-LinkPath $c.Home } catch { continue }
        $homeDir = $homeDir.TrimEnd('\', '/')
        if ((Split-Path -Leaf $homeDir) -eq 'jre') {            # JDK 8: report the JDK once
            $parent = Split-Path -Parent $homeDir
            if (Get-JavaExe $parent) { $homeDir = $parent }
        }
        if (-not (Get-JavaExe $homeDir)) {
            Add-Warning "Skipped $($c.Home) (found via $($c.Source)): no readable Java home."; continue
        }
        $key = $homeDir.ToLowerInvariant()
        if ($Seen.ContainsKey($key)) { continue }
        $Seen[$key] = $true
        try { Read-JavaHome $homeDir $c.Source $c.Vendor }
        catch { Add-Warning "Could not inspect ${homeDir}: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------- repo scanning ---
function Get-RefKind([string]$Name, [string]$RelPath) {
    if ("/$RelPath" -like '*/.github/workflows/*.yml' -or "/$RelPath" -like '*/.github/workflows/*.yaml') { return 'github-actions' }
    if ($Name -like 'Dockerfile*' -or $Name -like '*.dockerfile') { return 'dockerfile' }
    if ($Name -match '^(docker-)?compose.*\.ya?ml$') { return 'compose' }
    if ($Name -eq '.gitlab-ci.yml') { return 'gitlab-ci' }
    if ($Name -like '*.yml' -or $Name -like '*.yaml') { return 'k8s' }
    if ($Name -like 'Jenkinsfile*' -or $Name -like '*.sh' -or $Name -like '*.ps1') { return 'script' }
    if ($Name -eq '.sdkmanrc') { return 'sdkman' }
    if ($Name -eq '.tool-versions') { return 'asdf' }
    if ($Name -eq '.java-version') { return 'jenv' }
    if ($Name -like '*.gradle' -or $Name -like '*.gradle.kts') { return 'gradle-toolchain' }
    if ($Name -eq 'toolchains.xml' -or $Name -eq 'pom.xml') { return 'maven-toolchain' }
    return $null
}

function Test-TextFile([string]$Path) {
    $bytes = New-Object byte[] 8000
    $fs = [IO.File]::OpenRead($Path)
    try { $n = $fs.Read($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
    if ($n -eq 0) { return $false }
    return ([Array]::IndexOf($bytes, [byte]0, 0, $n) -lt 0)
}

# Same rules as the awk program in runtimeclear.sh. Returns @{line; hint; text} items.
function Get-FileRefs([string]$Path, [string]$Kind) {
    $lines = @([IO.File]::ReadAllLines($Path))
    $hits = New-Object System.Collections.Generic.List[object]
    $oracleDist = @(); $setupJava = $false; $jenvDone = $false
    $imageKinds = @('dockerfile', 'compose', 'k8s', 'gitlab-ci', 'github-actions')
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i] -replace "`t", ' '
        $n = $i + 1; $hint = $null
        if ($imageKinds -contains $Kind) {
            if ($line -match 'container-registry\.oracle\.com/java/|store/oracle/serverjre') { $hint = 'oracle-image' }
            elseif ($line -match '(^|[^a-z0-9._-])openjdk:') { $hint = 'openjdk-deprecated-image' }
            elseif ($line -match 'eclipse-temurin|amazoncorretto|azul/zulu|bellsoft/liberica|mcr\.microsoft\.com/openjdk|registry\.access\.redhat\.com/ubi[0-9]*/openjdk') { $hint = 'free-image' }
        }
        if (-not $hint -and ($imageKinds + 'script') -contains $Kind -and
            $line -match 'download\.oracle\.com/java|oracle\.com/java/technologies/downloads') { $hint = 'oracle-download' }
        if (-not $hint) {
            switch ($Kind) {
                'github-actions' {
                    if ($line -match 'actions/setup-java') { $setupJava = $true }
                    if ($line -match '^ *-? *distribution: *["'']?oracle["'']? *(#.*)?$') { $oracleDist += $i }
                }
                'sdkman' { if ($line -match '^ *java *=.*-oracle') { $hint = 'oracle-sdkman' } }
                'asdf'   { if ($line -match '^ *java +.*oracle') { $hint = 'oracle-vendor' } }
                'jenv'   { if (-not $jenvDone -and $line.Trim()) {
                               $jenvDone = $true
                               if ($line -match 'oracle') { $hint = 'oracle-vendor' } else { $hint = 'unknown' } } }
                'gradle-toolchain' {
                    if ($line -match 'jvmvendorspec\.oracle' -or
                        $line -match 'vendor *(=|\.set *\() *(jvmvendorspec\.matching *\()?["'']oracle') { $hint = 'oracle-vendor' } }
                'maven-toolchain' { if ($line -match '<vendor> *oracle *</vendor>') { $hint = 'oracle-vendor' } }
            }
        }
        if ($hint) { $hits.Add(@{ line = $n; hint = $hint; text = $line }) }
    }
    if ($setupJava) {
        foreach ($i in $oracleDist) {
            $text = $lines[$i] -replace "`t", ' '
            for ($j = [Math]::Max(0, $i - 5); $j -le [Math]::Min($lines.Count - 1, $i + 5); $j++) {
                if ($lines[$j] -match 'java-version') { $text = "$text | " + ($lines[$j].Trim() -replace '^[- ]+', ''); break }
            }
            $hits.Add(@{ line = $i + 1; hint = 'oracle-setup-java'; text = $text })
        }
    }
    return @($hits | Sort-Object { $_.line })
}

function Invoke-RepoScan([string]$RepoPath) {
    $root = (Resolve-Path -LiteralPath $RepoPath).ProviderPath.TrimEnd('\', '/')
    $repoName = Split-Path -Leaf $root
    $files = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $items = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) }
        catch { Add-Warning "Not readable: $dir"; continue }
        foreach ($it in $items) {
            if ($it.PSIsContainer) {
                $isLink = ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)
                if (-not $isLink -and $SkipDirs -notcontains $it.Name) { $stack.Push($it.FullName) }
            } elseif ($it.Length -le 1048576) { $files.Add($it.FullName) }
        }
    }
    foreach ($f in ($files | Sort-Object)) {
        $rel = $f.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        # Skip RuntimeClear's own copy (its test fixtures mention Oracle on purpose).
        $fdir = Split-Path -Parent $f
        if ((Test-Path -LiteralPath (Join-Path $fdir 'runtimeclear.sh')) -or (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $fdir) 'runtimeclear.sh'))) { continue }
        $kind = Get-RefKind (Split-Path -Leaf $f) $rel
        if (-not $kind) { continue }
        try {
            if (-not (Test-TextFile $f)) { continue }
            foreach ($h in (Get-FileRefs $f $kind)) {
                $text = [string]$h.text
                if ($text.Length -gt $MaxText) { $text = $text.Substring(0, $MaxText) }
                $References.Add([ordered]@{ file = "$repoName/$rel"; line = [int]$h.line; kind = $kind; text = $text; hint = $h.hint })
            }
        } catch { Add-Warning "Not readable: $f" }
    }
}

# -------------------------------------------------------------------- main ---
$IsAdmin = $false
try {
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Add-Warning 'Running in 32-bit PowerShell: 64-bit Java installs may be missed. Use 64-bit PowerShell.'
}

if (-not $NoSystem) {
    if (-not $Quiet) { [Console]::Error.WriteLine('Looking for Java runtimes (read-only, no network)...') }
    if (-not $NoSystemDefaults) {
        Invoke-Step 'Uninstall registry'  { Find-UninstallEntries }
        Invoke-Step 'JavaSoft registry'   { Find-JavaSoftRegistry }
        Invoke-Step 'Running processes'   { Find-Processes }
        Invoke-Step 'PATH and JAVA_HOME'  { Find-PathAndJavaHome }
        Invoke-Step 'Program folders'     { Find-Filesystem }
        Invoke-Step 'Java auto-update'    { Find-AutoUpdate }
    }
    foreach ($d in $ExtraJvmDirs) { if ($d) { Add-HomesBelow 'filesystem' $d 3 } }
    Invoke-Candidates
}
foreach ($r in $Repo) {
    if (-not $Quiet) { [Console]::Error.WriteLine("Scanning repo: $r") }
    Invoke-Step "Repo $r" { Invoke-RepoScan $r }
}

$hostName = $env:COMPUTERNAME
if (-not $hostName) { $hostName = [Environment]::MachineName }
if ($Anonymize) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hostName))
    $hostName = (-join ($hash | ForEach-Object { $_.ToString('x2') })).Substring(0, 12)
}
$osName = [Environment]::OSVersion.VersionString
try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $osName = "$($os.Caption) $($os.Version)" } catch { }
$arch = $env:PROCESSOR_ARCHITEW6432
if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
switch ($arch) { 'AMD64' { $arch = 'x86_64' } 'ARM64' { $arch = 'arm64' } 'x86' { $arch = 'x86' } default { if (-not $arch) { $arch = 'unknown' } } }

$now = (Get-Date).ToUniversalTime()
$inv = [Globalization.CultureInfo]::InvariantCulture
if (-not $Out) { $Out = "runtimeclear-scan-$hostName-$($now.ToString("yyyyMMdd'T'HHmmss'Z'", $inv)).json" }

# Build with ordered hashtables so keys follow the schema; .ToArray() keeps
# 0- and 1-element lists as JSON arrays.
$doc = [ordered]@{
    schema     = 'runtimeclear.scan/v1'
    scanner    = [ordered]@{ name = 'runtimeclear'; version = $ScannerVersion; platform = 'windows' }
    scannedAt  = $now.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $inv)
    host       = [ordered]@{ hostname = $hostName; os = $osName; arch = $arch }
    installs   = $Installs.ToArray()
    references = $References.ToArray()
    autoUpdate = $AutoUpdate.ToArray()
    warnings   = $Warnings.ToArray()
}
$json = ConvertTo-Json -InputObject $doc -Depth 6
$outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
[IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding $false))   # UTF-8, no BOM

$oracle = 0
foreach ($i in $Installs) {
    $isOracle = ([string]$i.runtimeName -like '*Java(TM)*') -or ($i.buildType -eq 'commercial') -or
                ($i.implementor -like '*Oracle*' -and [string]$i.runtimeName -notlike '*OpenJDK*')
    if ($isOracle) { $oracle++ }
}
$oracleRefs = @($References | Where-Object { $_.hint -like 'oracle-*' }).Count
if (-not $Quiet) {
    $summary = @('', 'RuntimeClear scan complete.',
        "  Java runtimes found:         $($Installs.Count)",
        "  Built by Oracle:             $oracle  (Oracle JDK/JRE and Oracle's own OpenJDK builds)",
        "  Oracle references in repos:  $oracleRefs  (of $($References.Count) references recorded)",
        "  Auto-update signals:         $($AutoUpdate.Count)",
        "  Warnings:                    $($Warnings.Count)",
        "  Output:                      $outPath", '',
        "Load the JSON at $SiteUrl/report - it's processed in your browser, nothing is uploaded.")
    foreach ($s in $summary) { [Console]::Error.WriteLine($s) }
}
exit 0
