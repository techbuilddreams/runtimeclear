# RuntimeClear scanner

Find every Java runtime on a machine, and every Oracle Java reference in your repos, and write
the facts to one JSON file. Read-only, no network, no dependencies.

[![CI](https://github.com/techbuilddreams/runtimeclear/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/techbuilddreams/runtimeclear/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/techbuilddreams/runtimeclear/badge)](https://scorecard.dev/viewer/?uri=github.com/techbuilddreams/runtimeclear)
[![Latest release](https://img.shields.io/github/v/release/techbuilddreams/runtimeclear?sort=semver)](https://github.com/techbuilddreams/runtimeclear/releases/latest)
[![License: MIT](https://img.shields.io/github/license/techbuilddreams/runtimeclear)](LICENSE)

- `runtimeclear.sh` for Linux and macOS (bash 3.2 or later)
- `runtimeclear.ps1` for Windows (Windows PowerShell 5.1 or later, PowerShell 7)

Each script is a single file you can read in a few minutes. The header of each one lists
everything it reads. To turn the JSON into a license-exposure report, load it at
https://runtimeclear.com/report/. The report runs in your browser; the file is not uploaded.

## Contents

- [Quick start](#quick-start)
- [What it reads](#what-it-reads)
- [What it never does](#what-it-never-does)
- [Output](#output)
- [Classification and the report](#classification-and-the-report)
- [Platforms tested](#platforms-tested)
- [Known limitations](#known-limitations)
- [FAQ](#faq)
- [Contributing](#contributing) · [Security](#security) · [License](#license)

## Quick start

Every release attaches `runtimeclear.sh`, `runtimeclear.ps1` and `SHA256SUMS`. Releases built
by the [release workflow](.github/workflows/release.yml) also carry
[GitHub artifact attestations](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds)
that tie each file to the tagged commit and the workflow run that built it.

### Linux and macOS

```sh
base=https://github.com/techbuilddreams/runtimeclear/releases/latest/download
curl -fsSLO "$base/runtimeclear.sh" -O "$base/runtimeclear.ps1" -O "$base/SHA256SUMS"

sha256sum -c SHA256SUMS                  # macOS: shasum -a 256 -c SHA256SUMS
gh attestation verify runtimeclear.sh --repo techbuilddreams/runtimeclear   # optional, needs the GitHub CLI
less runtimeclear.sh                     # read it before you run it

bash runtimeclear.sh --repo .            # this machine + the repo in the current folder
sudo bash runtimeclear.sh                # optional: includes other users' processes and home folders
```

Nothing needs to be installed on remote hosts. To scan several over SSH:

```sh
while read -r h; do
  ssh "$h" 'bash -s -- --quiet --out runtimeclear.json' < runtimeclear.sh &&
    scp "$h:runtimeclear.json" "./scan-$h.json" && ssh -n "$h" rm -f runtimeclear.json
done < hosts.txt
```

The report accepts many JSON files at once.

### Windows

```powershell
$base = 'https://github.com/techbuilddreams/runtimeclear/releases/latest/download'
Invoke-WebRequest "$base/runtimeclear.ps1" -OutFile runtimeclear.ps1
Invoke-WebRequest "$base/SHA256SUMS" -OutFile SHA256SUMS

$expected = ((Select-String -Path .\SHA256SUMS -Pattern 'runtimeclear\.ps1$').Line -split '\s+')[0]
if ((Get-FileHash .\runtimeclear.ps1 -Algorithm SHA256).Hash -ieq $expected) { 'Checksum OK' } else { 'CHECKSUM MISMATCH - do not run' }
gh attestation verify runtimeclear.ps1 --repo techbuilddreams/runtimeclear   # optional, needs the GitHub CLI
notepad .\runtimeclear.ps1                                                   # read it before you run it

powershell -NoProfile -ExecutionPolicy Bypass -File .\runtimeclear.ps1 -Repo C:\src\payments-api
```

Run it from an elevated prompt to include other users' processes and profiles. Use 64-bit
PowerShell: a 32-bit session can miss 64-bit installs, and the script warns you if it's in one.

### Options

| bash | PowerShell | Meaning |
|---|---|---|
| `--repo <dir>` (repeatable) | `-Repo <dir>[,<dir>]` | Scan these folders for Oracle Java references |
| `--no-system` | `-NoSystem` | Skip installed-runtime discovery (repo scan only) |
| `--no-exec` | `-NoExec` | Never run `java -version`; affected versions are reported as `unknown` |
| `--anonymize` | `-Anonymize` | Hostname becomes the first 12 hex characters of its SHA-256 |
| `--out <file>` | `-Out <file>` | Default: `./runtimeclear-scan-<host>-<UTC timestamp>.json` |
| `--quiet` | `-Quiet` | No summary |
| `--help`, `--version` | `Get-Help .\runtimeclear.ps1`, `-Version` | |

## What it reads

**Java installs.** A "Java home" is a folder containing `bin/java`.

| Platform | Where it looks |
|---|---|
| Linux | `rpm -qa`/`rpm -ql` and `dpkg-query`/`dpkg -L` (records the package vendor), `/usr/lib/jvm`, `/usr/java`, `/opt` (4 levels deep), `/usr/local` (3 levels deep), `update-alternatives` |
| macOS | `/Library/Java/JavaVirtualMachines`, `~/Library/Java/JavaVirtualMachines`, the legacy `JavaAppletPlugin.plugin`, `/usr/libexec/java_home -V`, Homebrew `openjdk*` formulae and JDK casks |
| Windows | `HKLM\SOFTWARE\JavaSoft` (and `WOW6432Node`), Uninstall registry keys, `Program Files\{Java, Eclipse Adoptium, Amazon Corretto, Zulu, BellSoft, Semeru, Microsoft\jdk-*, ...}`, `where.exe java`, scoop |
| All | `java` on `PATH`, `$JAVA_HOME`, SDKMAN, jenv, asdf, `~/.gradle/jdks`, `~/.m2/jdks`, IntelliJ `~/.jdks`, running `java` processes (executable path only) |

As root or Administrator, it also checks every user's home folder.

For each Java home it reads:

- the plain-text `release` file (`JAVA_VERSION`, `JAVA_RUNTIME_VERSION`, `IMPLEMENTOR`, `BUILD_TYPE`)
- the first 64 KB of the bundled license text (`legal/java.base/LICENSE`, `LICENSE`, `jre/LICENSE`,
  `COPYRIGHT`) to record which license it names: `OTN`, `NFTC`, `BCL` or `GPL`. No text is copied
  into the JSON.
- only if there is **no** `release` file (for example a JRE bundled inside an application):
  the output of `<home>/bin/java -version`, with a 5-second timeout. `--no-exec` / `-NoExec`
  turns this off.

Symlinks are resolved and duplicates removed. A JDK 8's inner `jre/` folder counts as part of
that JDK, not as a second install.

**Auto-update signals.** Windows: the Java Update policy registry values (`EnableJavaUpdate`,
`EnableAutoUpdateCheck`), `jusched.exe` (whether the file exists, its Run key, and whether it's
running), scheduled tasks named like `*Java*Update*`. macOS: Oracle's Java-Updater LaunchAgent.

**Repos (`--repo`).** Oracle Java references, line by line. It skips `.git`, `node_modules`,
`target`, `build`, `.gradle` and `vendor`, binary files, and files over 1 MB:

| Files | Matches | `hint` |
|---|---|---|
| `Dockerfile*`, `*.dockerfile`, `*compose*.yml`, `*.yml`/`*.yaml` (k8s, Helm, CI) | `container-registry.oracle.com/java/`, `store/oracle/serverjre` | `oracle-image` |
| same | Docker Hub `openjdk:` images (deprecated) | `openjdk-deprecated-image` |
| same | `eclipse-temurin`, `amazoncorretto`, `azul/zulu*`, `bellsoft/liberica*`, `mcr.microsoft.com/openjdk`, `registry.access.redhat.com/ubi*/openjdk*` | `free-image` |
| `.github/workflows/*.yml` | `actions/setup-java` with `distribution: oracle` (adds any `java-version` within 5 lines) | `oracle-setup-java` |
| Dockerfiles, YAML, `.gitlab-ci.yml`, `Jenkinsfile`, `*.sh`, `*.ps1` | `download.oracle.com/java`, `oracle.com/java/technologies/downloads` | `oracle-download` |
| `.sdkmanrc` | `java=...-oracle` | `oracle-sdkman` |
| `.tool-versions` | `java oracle-...` | `oracle-vendor` |
| `.java-version` | first line (always recorded) | `oracle-vendor` or `unknown` |
| `*.gradle`, `*.gradle.kts` | `JvmVendorSpec.ORACLE`, `vendor = "oracle"` | `oracle-vendor` |
| `pom.xml`, `toolchains.xml` | `<vendor>oracle</vendor>` | `oracle-vendor` |

Only the matching line is stored, cut off at 300 characters.

## What it never does

- **No network access.** The scripts never open a socket. The test suite runs a full scan under
  `strace` and fails if an `AF_INET` or `AF_INET6` socket is opened. The PowerShell script avoids
  `Get-Package` on purpose, because that cmdlet can try to download a package provider.
- **No changes.** Nothing is installed, uninstalled, updated, moved or deleted. The only file it
  writes is the JSON output (`runtimeclear.sh` also uses a private temp folder that it removes on exit).
- **No license decisions.** The scanner records versions, vendors, build types, license-text
  names and file lines. The report decides license status, and anything it can't decide is
  marked "needs review".
- **No extra data.** It doesn't read process arguments, environment variables other than `PATH`
  and `JAVA_HOME`, or file contents beyond a single matched line.
- **No sudo required.** Anything it can't read is listed under `warnings` in the JSON.

`--anonymize` only hashes the hostname. Paths such as `/home/alice/.sdkman/...` and repo folder
names stay in the file, so **review the JSON before you share it**. It's plain text.

## Output

The summary goes to stderr:

```
RuntimeClear scan complete.
  Java runtimes found:         8
  Built by Oracle:             6  (Oracle JDK/JRE and Oracle's own OpenJDK builds)
  Oracle references in repos:  10  (of 16 references recorded)
  Warnings:                    0
  Output:                      ./runtimeclear-scan-app-prod-03-20260911T141238Z.json

Load the JSON at https://runtimeclear.com/report - it's processed in your browser, nothing is uploaded.
```

An excerpt from the JSON file:

```json
{
  "schema": "runtimeclear.scan/v1",
  "scanner": {"name": "runtimeclear", "version": "1.0.1", "platform": "linux"},
  "scannedAt": "2026-09-11T14:12:38Z",
  "host": {"hostname": "app-prod-03", "os": "Red Hat Enterprise Linux 9.4 (Plow)", "arch": "x86_64"},
  "installs": [
    {"path": "/usr/lib/jvm/jdk-17-oracle-x64", "source": "filesystem", "javaVersion": "17.0.13",
     "rawVersion": "17.0.13+10-LTS-268", "implementor": "Oracle Corporation", "buildType": "commercial",
     "runtimeName": null, "isJre": false, "packageVendor": null, "licenseFile": null}
  ],
  "references": [
    {"file": "billing-service/Dockerfile", "line": 1, "kind": "dockerfile",
     "text": "FROM container-registry.oracle.com/java/jdk:21", "hint": "oracle-image"}
  ],
  "autoUpdate": [],
  "warnings": []
}
```

Full examples are in [`examples/`](examples/). `sample-scan-linux.json` is real scanner output
from the test fixtures, with the temp-folder paths renamed to typical install locations.
`sample-scan-windows.json` was written by hand for demos.

### JSON schema (`runtimeclear.scan/v1`)

| Field | Notes |
|---|---|
| `scanner.platform` | `linux`, `macos` or `windows` |
| `host.hostname` | The real hostname, or a 12-hex-character SHA-256 prefix with `--anonymize` |
| `installs[].path` | Real path of the Java home, with symlinks resolved |
| `installs[].source` | How the install was found first: `rpm`, `dpkg`, `registry`, `homebrew`, `sdkman`, `jenv`, `asdf`, `process`, `path`, `filesystem`. When several methods find the same install, they win in that order (Windows: `registry` > `process` > `path` > `filesystem`). |
| `installs[].javaVersion` | Exactly as `JAVA_VERSION` reports it, not normalized (`1.8.0_202`, `17.0.13`, `21`). `unknown` if it couldn't be read. |
| `installs[].rawVersion` | `JAVA_RUNTIME_VERSION`, or the build string from `java -version`. Falls back to `javaVersion`. |
| `installs[].implementor` | `IMPLEMENTOR` from `release`. `unknown` when missing; some Oracle JDK 8 builds don't set it. |
| `installs[].buildType` | `BUILD_TYPE` from `release` (Oracle JDK builds say `commercial`), otherwise `null` |
| `installs[].runtimeName` | `Java(TM) SE Runtime Environment` or `OpenJDK Runtime Environment`. Only set when `java -version` was run, otherwise `null`. |
| `installs[].isJre` | `true` when `bin/javac` is missing |
| `installs[].packageVendor` | rpm `VENDOR`, dpkg `Maintainer`, or the Windows Uninstall `Publisher`. `null` otherwise. |
| `installs[].licenseFile` | `OTN`, `NFTC`, `BCL` or `GPL` from the first bundled license text that names one, otherwise `null` |
| `references[].file` | `<repo folder name>/<path inside repo>`, with `/` separators on every OS |
| `references[].kind` | `dockerfile`, `compose`, `k8s` (any other YAML), `github-actions`, `gitlab-ci`, `script` (also `Jenkinsfile`), `sdkman`, `asdf`, `jenv`, `gradle-toolchain`, `maven-toolchain` |
| `references[].hint` | See the repo table above |
| `autoUpdate[]` | `{kind, enabled, detail}`. `enabled` is `true`, `false`, or `null` when it couldn't be determined. |
| `warnings[]` | Locations it couldn't read, `java -version` timeouts, running JVMs whose JDK was deleted on disk, and similar notes |

Removing or renaming a field requires a new schema id and a new major version
(see [CHANGELOG.md](CHANGELOG.md)).

## Classification and the report

The scanner doesn't classify anything. The report at **https://runtimeclear.com/report/** reads
the JSON in your browser and gives each install and reference one of four statuses:

| Status | Meaning |
|---|---|
| `free` | Non-Oracle OpenJDK build, Oracle OpenJDK (GPLv2 with Classpath Exception), or an Oracle JDK build under NFTC or BCL |
| `at_risk` | Free today (NFTC), but the next Oracle update, image pull or auto-update brings an OTN build |
| `paid_license` | Oracle JDK build under OTN: commercial production use needs a Java SE subscription unless an OTN exception applies |
| `needs_review` | Conflicting signals, unknown vendor or version, or a case the rules can't decide |

The rules, their sources and the date each source was checked are in
[docs/LICENSE-RULES.md](docs/LICENSE-RULES.md). A build's license is set by the build you
downloaded: an installed NFTC build does not become paid later.

The scanner is free and MIT-licensed. You can also process the JSON yourself; the schema above
is the contract.

## Platforms tested

[CI](.github/workflows/ci.yml) runs on every push and pull request:

| Platform | Shell | What runs |
|---|---|---|
| Ubuntu (latest GitHub runner) | bash 5 | `tests/run.sh`: fixture scans, timeouts, JSON escaping, no-network check under `strace` |
| Ubuntu | PowerShell 7 | `runtimeclear.ps1` compared field by field with `runtimeclear.sh`; `tests/smoke.ps1` |
| macOS (latest GitHub runner) | system `/bin/bash` 3.2 | `tests/run.sh` |
| Windows (latest GitHub runner) | Windows PowerShell 5.1 and PowerShell 7 | PSScriptAnalyzer, `tests/smoke.ps1` |

ShellCheck runs on `runtimeclear.sh` and the test harness. The tests use fake Java homes and a
fake repo, so they don't depend on the Java versions installed on the runner.

## Known limitations

- It only searches the locations listed above. A JDK bundled inside an application folder
  elsewhere, such as `/srv/app/jre` or `D:\Apps\Vendor\jre`, is only found if it's running,
  on `PATH`, or registered.
- It doesn't look inside container images or VM disks. Use `--repo` on the Dockerfiles and
  manifests that build them.
- Repo matching works line by line with simple patterns. It can miss a reference built from
  variables (`FROM ${BASE_IMAGE}`).
- Repo scans skip files whose folder, or the folder above it, contains `runtimeclear.sh`, so that
  a copy of RuntimeClear isn't reported. If you keep `runtimeclear.sh` in the root of a repo you
  scan, files in the root and its direct subfolders are skipped: scan from a copy kept elsewhere.
- On Windows, symlinks and junctions are only resolved on the last path component.

## FAQ

**Does it send my data anywhere?**
No. The scripts open no network connections, and the report processes the JSON in your browser.
You decide whether to share the file.

**Do I need root or Administrator?**
No. Without it, the scan misses other users' home folders and processes, and lists what it
couldn't read under `warnings`.

**Why does it run `java -version` at all?**
Only for a Java home without a `release` file, where there is no other reliable version source.
It never runs anything else. Use `--no-exec` / `-NoExec` to skip it; those versions become `unknown`.

**Why bash 3.2 and PowerShell 5.1?**
They are what stock macOS and Windows Server ship. A scanner that needs an upgrade first
doesn't get run on the machines that matter.

**Does it tell me whether I owe Oracle money?**
No. It records facts. The report applies documented rules and marks uncertain cases
"needs review". Neither is legal advice.

**Can I use the JSON without the website?**
Yes. The format is documented above and versioned.

**The report shows the wrong status for one of my installs.**
Please open a [misclassification report](https://github.com/techbuilddreams/runtimeclear/issues/new?template=misclassification.yml)
with the redacted install entry and a source. [CONTRIBUTING.md](CONTRIBUTING.md#reporting-a-misclassification)
explains what to include.

## Contributing

Bug reports, detections for install locations we miss, and fixes are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first: the scanners must stay read-only, offline and
dependency-free. This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## Security

Please report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md). Don't open
a public issue.

## License

MIT. Copyright (c) 2026 Tech Build Dreams LLC. See [LICENSE](LICENSE).

## Trademarks and legal notice

RuntimeClear is a technical inventory tool and **not legal advice**. Your license obligations
depend on your agreements with Oracle; confirm them with Oracle or qualified counsel.
Tech Build Dreams LLC is **not affiliated with, endorsed by, or sponsored by Oracle**.
Oracle and Java are registered trademarks of Oracle and/or its affiliates. Other names may be
trademarks of their respective owners.
