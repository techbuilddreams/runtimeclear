# RuntimeClear scanner

Two small scripts that list the Java runtimes on a machine, plus Oracle Java references
in your repos, and write the results to one JSON file.

- `runtimeclear.sh` for Linux and macOS (bash 3.2+)
- `runtimeclear.ps1` for Windows (PowerShell 5.1+)

They are **read-only**, make **no network connections**, and don't need root. MIT licensed.
Please read the source before you run it. Each script starts with a header that lists
everything it reads.

To turn the JSON into a license-exposure report, open **https://runtimeclear.com/report**.
The report runs in your browser, so the file never leaves your machine.

---

## What it does

**Finds Java installs** (a "Java home" is a folder containing `bin/java`):

| Platform | Where it looks |
|---|---|
| Linux | `rpm -qa`/`rpm -ql` and `dpkg-query`/`dpkg -L` (records the package vendor), `/usr/lib/jvm`, `/usr/java`, `/opt` (4 levels deep), `/usr/local` (3 levels deep), `update-alternatives` |
| macOS | `/Library/Java/JavaVirtualMachines`, `~/Library/Java/JavaVirtualMachines`, the legacy `JavaAppletPlugin.plugin`, `/usr/libexec/java_home -V`, Homebrew `openjdk*` formulae and JDK casks |
| Windows | `HKLM\SOFTWARE\JavaSoft` (and `WOW6432Node`), Uninstall registry keys, `Program Files\{Java, Eclipse Adoptium, Amazon Corretto, Zulu, BellSoft, Semeru, Microsoft\jdk-*, ...}`, `where.exe java`, scoop |
| All | `java` on `PATH`, `$JAVA_HOME`, SDKMAN, jenv, asdf, `~/.gradle/jdks`, `~/.m2/jdks`, IntelliJ `~/.jdks`, running `java` processes (executable path only) |

As root or Administrator, it also checks every user's home folder.

For each Java home it reads the plain-text `release` file (`JAVA_VERSION`, `JAVA_RUNTIME_VERSION`,
`IMPLEMENTOR`, `BUILD_TYPE`). If a home has **no** `release` file (for example, a JRE bundled
inside an app), the scanner runs `<home>/bin/java -version` with a 5-second timeout. Pass
`--no-exec` / `-NoExec` if you don't want it to run any binary. Symlinks are resolved and
duplicates are removed. A JDK 8's inner `jre/` folder counts as part of that JDK, not as a
second install.

**Windows only: auto-update signals.** It checks the Java Update policy registry values
(`EnableJavaUpdate`, `EnableAutoUpdateCheck`), `jusched.exe` (whether the file exists, its Run
key, and whether it's running), scheduled tasks named like `*Java*Update*`, and the
"Java Auto Updater" program entry. On macOS it checks for Oracle's Java-Updater LaunchAgent.

**Scans repos (`--repo`) for Oracle Java references.** It skips `.git`, `node_modules`, `target`,
`build`, `.gradle` and `vendor`, plus binary files and files over 1 MB:

| Files | Matches | `hint` |
|---|---|---|
| `Dockerfile*`, `*.dockerfile`, `*compose*.yml`, `*.yml/*.yaml` (k8s, Helm, CI) | `container-registry.oracle.com/java/`, `store/oracle/serverjre` | `oracle-image` |
| same | Docker Hub `openjdk:` images (deprecated) | `openjdk-deprecated-image` |
| same | `eclipse-temurin`, `amazoncorretto`, `azul/zulu*`, `bellsoft/liberica*`, `mcr.microsoft.com/openjdk`, `registry.access.redhat.com/ubi*/openjdk*` | `free-image` |
| `.github/workflows/*.yml` | `actions/setup-java` with `distribution: oracle` (adds any `java-version` found within 5 lines) | `oracle-setup-java` |
| Dockerfiles, YAML, `.gitlab-ci.yml`, `Jenkinsfile`, `*.sh`, `*.ps1` | `download.oracle.com/java`, `oracle.com/java/technologies/downloads` | `oracle-download` |
| `.sdkmanrc` | `java=...-oracle` | `oracle-sdkman` |
| `.tool-versions` | `java oracle-...` | `oracle-vendor` |
| `.java-version` | first line (always recorded) | `oracle-vendor` or `unknown` |
| `*.gradle`, `*.gradle.kts` | `JvmVendorSpec.ORACLE`, `vendor = "oracle"` | `oracle-vendor` |
| `pom.xml`, `toolchains.xml` | `<vendor>oracle</vendor>` | `oracle-vendor` |

Only the matching line is stored, cut off at 300 characters.

## What it does NOT do

- **No network access.** The scripts never open a socket. The test suite runs the full scan under
  `strace` and checks that no `AF_INET` or `AF_INET6` socket is opened. The PowerShell script
  avoids `Get-Package` on purpose, because that cmdlet can try to download a package provider.
- **No changes.** Nothing is installed, uninstalled, updated, moved or deleted. The only file
  it writes is the JSON output.
- **No license decisions.** The scanner only records facts: versions, vendors, build type and file
  lines. Deciding license status is the report's job, and anything it can't decide is marked
  "needs review".
- **No extra data.** It doesn't read process arguments, environment variables (other than `PATH`
  and `JAVA_HOME`), or file contents beyond a single matched line.
- **No sudo required.** Anything it can't read is listed under `warnings` in the JSON.

`--anonymize` only hashes the hostname. Paths such as `/home/alice/.sdkman/...` and repo folder
names are still in the file, so **review the JSON before you share it**. It's plain text.

## Usage

### Linux / macOS

```sh
curl -LO https://github.com/techbuilddreams/runtimeclear/releases/latest/download/runtimeclear.sh
curl -LO https://github.com/techbuilddreams/runtimeclear/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing     # macOS: shasum -a 256 runtimeclear.sh, compare by eye
less runtimeclear.sh                         # read it first

bash runtimeclear.sh --repo .                # this machine + the repo in the current folder
sudo bash runtimeclear.sh                    # optional: includes other users' processes and homes
```

To scan several hosts over SSH, nothing needs to be installed on them:

```sh
while read -r h; do
  ssh "$h" 'bash -s -- --quiet --out runtimeclear.json' < runtimeclear.sh &&
    scp "$h:runtimeclear.json" "./scan-$h.json" && ssh -n "$h" rm -f runtimeclear.json
done < hosts.txt
```

The report accepts many JSON files at once.

### Windows

```powershell
Invoke-WebRequest https://github.com/techbuilddreams/runtimeclear/releases/latest/download/runtimeclear.ps1 -OutFile runtimeclear.ps1
Get-FileHash .\runtimeclear.ps1 -Algorithm SHA256    # compare with SHA256SUMS from the release
notepad .\runtimeclear.ps1                           # read it first

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
| `--anonymize` | `-Anonymize` | Hostname becomes the first 12 hex chars of its SHA-256 |
| `--out <file>` | `-Out <file>` | Default: `./runtimeclear-scan-<host>-<UTC timestamp>.json` |
| `--quiet` | `-Quiet` | No summary |
| `--help`, `--version` | `Get-Help .\runtimeclear.ps1`, `-Version` | |

## Sample output

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
  "scanner": {"name": "runtimeclear", "version": "1.0.0", "platform": "linux"},
  "scannedAt": "2026-09-11T14:12:38Z",
  "host": {"hostname": "app-prod-03", "os": "Red Hat Enterprise Linux 9.4 (Plow)", "arch": "x86_64"},
  "installs": [
    {"path": "/usr/lib/jvm/jdk-17-oracle-x64", "source": "filesystem", "javaVersion": "17.0.13",
     "rawVersion": "17.0.13+10-LTS-268", "implementor": "Oracle Corporation", "buildType": "commercial",
     "runtimeName": null, "isJre": false, "packageVendor": null}
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

## JSON schema (`runtimeclear.scan/v1`)

| Field | Notes |
|---|---|
| `scanner.platform` | `linux`, `macos` or `windows` |
| `host.hostname` | The real hostname, or a 12-hex-char SHA-256 prefix with `--anonymize` |
| `installs[].path` | Real path of the Java home, with symlinks resolved |
| `installs[].source` | How the install was found first: `rpm`, `dpkg`, `registry`, `homebrew`, `sdkman`, `jenv`, `asdf`, `process`, `path`, `filesystem`. When several methods find the same install, they win in that order (Windows: `registry` > `process` > `path` > `filesystem`). |
| `installs[].javaVersion` | Exactly as `JAVA_VERSION` reports it, not normalized (`1.8.0_202`, `17.0.13`, `21`). `unknown` if it couldn't be read. |
| `installs[].rawVersion` | `JAVA_RUNTIME_VERSION`, or the build string from `java -version`. Falls back to `javaVersion`. |
| `installs[].implementor` | `IMPLEMENTOR` from `release`. It's `unknown` when missing; some Oracle JDK 8 builds don't set it. |
| `installs[].buildType` | `BUILD_TYPE` from `release` (Oracle JDK builds say `commercial`), otherwise `null` |
| `installs[].runtimeName` | `Java(TM) SE Runtime Environment` or `OpenJDK Runtime Environment`. Only set when `java -version` was run, otherwise `null`. |
| `installs[].isJre` | `true` when `bin/javac` is missing |
| `installs[].packageVendor` | rpm `VENDOR`, dpkg `Maintainer`, or the Windows Uninstall `Publisher`. `null` otherwise. |
| `references[].file` | `<repo folder name>/<path inside repo>`, with `/` separators on every OS |
| `references[].kind` | `dockerfile`, `compose`, `k8s` (any other YAML), `github-actions`, `gitlab-ci`, `script` (also `Jenkinsfile`), `sdkman`, `asdf`, `jenv`, `gradle-toolchain`, `maven-toolchain` |
| `references[].hint` | See the table above |
| `autoUpdate[]` | `{kind, enabled, detail}`. `enabled` is `true`, `false`, or `null` when it couldn't be determined. |
| `warnings[]` | Locations it couldn't read, `java -version` timeouts, running JVMs whose JDK was deleted on disk, and similar notes |

## Testing

```sh
bash tests/run.sh
```

The tests build fake Java homes in a temp folder: Oracle JDK 21.0.4, 17.0.13, 8u202 and a JRE 8u351;
Temurin 21, Corretto 17, and Oracle's OpenJDK 21 with CRLF line endings; a bundled JRE with no
`release` file; a `java` that hangs; and a symlinked duplicate. They also build a fake repo
with every reference type, plus files the scanner must ignore. The tests check:

- the exact JSON fields
- that `java` is never run when a `release` file exists
- both timeout code paths
- JSON escaping
- the no-network check with `strace`
- that `runtimeclear.ps1`, run under `pwsh`, produces the same installs and references as the bash script

Needs `python3`. `strace` and `pwsh` are optional.

Two hidden environment variables exist only for the tests: `RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1` skips
the real system locations, and `RUNTIMECLEAR_EXTRA_JVM_DIRS` adds fixture folders.

## Known limitations

- It only searches the locations listed above. A JDK bundled inside an application folder
  elsewhere, such as `/srv/app/jre` or `D:\Apps\Vendor\jre`, is only found if it's running,
  on `PATH`, or registered.
- It doesn't look inside container images or VM disks. Use `--repo` on the Dockerfiles and
  manifests that build them.
- Repo matching works line by line with simple patterns. It can miss a reference built from
  variables (`FROM ${BASE_IMAGE}`).
- On Windows, symlinks and junctions are only resolved on the last path component.

## Releases and checksums

Every GitHub release attaches `runtimeclear.sh`, `runtimeclear.ps1` and a `SHA256SUMS` file generated
from those exact files with `sha256sum runtimeclear.sh runtimeclear.ps1 > SHA256SUMS`. Check the hash
before you run anything you downloaded.

## Security

See [SECURITY.md](SECURITY.md).

## Not legal advice

RuntimeClear is a technical inventory tool, **not legal advice**. Your license obligations
depend on your agreements with Oracle; confirm them with Oracle or qualified counsel.
Tech Build Dreams LLC is **not affiliated with, endorsed by, or sponsored by Oracle**.
Oracle and Java are registered trademarks of Oracle and/or its affiliates. Other names may be
trademarks of their respective owners.

## License

MIT. Copyright (c) 2026 Tech Build Dreams LLC. See [LICENSE](LICENSE).
