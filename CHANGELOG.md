# Changelog

All notable changes to the RuntimeClear scanner (`runtimeclear.sh` and `runtimeclear.ps1`)
are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The public
interface is the command-line options and the JSON output (`runtimeclear.scan/v1`): removing
or renaming an option or a JSON field needs a new major version.

## [Unreleased]

### Added

- CI on every push and pull request: ShellCheck, the test suite on Ubuntu and on macOS with
  the system bash 3.2, PSScriptAnalyzer, and a PowerShell smoke test (`tests/smoke.ps1`) on
  Windows PowerShell 5.1 and PowerShell 7 (Windows and Linux).
- Release workflow: checks that the tag matches the version in both scripts, runs the tests,
  generates `SHA256SUMS`, and publishes GitHub artifact attestations for `runtimeclear.sh`,
  `runtimeclear.ps1` and `SHA256SUMS`.
- OpenSSF Scorecard, Dependabot updates for GitHub Actions, a contributing guide, a code of
  conduct, issue forms and a more detailed security policy.

### Fixed

- `tests/run.sh` now passes on macOS: the temp folder is resolved through symlinks
  (`/var` is a link to `/private/var`) and the expected platform follows the host.
  The scanners are unchanged.

## [1.0.1] - 2026-09-11

### Fixed

- Repo scans (`--repo`, `-Repo`) no longer report RuntimeClear's own files as Oracle
  references when the scanned folder contains a copy of RuntimeClear. Its test fixtures
  mention Oracle on purpose. Files are skipped when their folder, or the folder above it,
  contains `runtimeclear.sh`. Found while testing on a real Mac.

### Changed

- `docs/LICENSE-RULES.md` documents the bundled license text (`legal/java.base/LICENSE`,
  `LICENSE`, `COPYRIGHT`) as the strongest license signal. The scanner already records it
  in `installs[].licenseFile` (`OTN`, `NFTC`, `BCL` or `GPL`).
- `docs/LICENSE-RULES.md` records `BUILD_TYPE="commercial"` as observed on a real Oracle
  JDK 11.0.24 install, and its absence on Oracle OpenJDK 20.0.x builds.
- The report at runtimeclear.com now labels Homebrew builds "Homebrew OpenJDK" instead of
  "Linux distribution OpenJDK package". This change is in the report, not in the scanner:
  the JSON fields are the same as in 1.0.0.

## [1.0.0] - 2026-09-11

### Added

- `runtimeclear.sh` for Linux and macOS (bash 3.2 or later) and `runtimeclear.ps1` for
  Windows (PowerShell 5.1 or later). Both are read-only, open no network connections and
  need no administrator rights.
- Java install discovery: package databases (rpm, dpkg), the Windows registry, well-known
  folders, Homebrew, SDKMAN, jenv, asdf, IDE and build-tool JDK folders, `PATH`, `JAVA_HOME`
  and running `java` processes (executable path only).
- For each Java home: `JAVA_VERSION`, `JAVA_RUNTIME_VERSION`, `IMPLEMENTOR` and `BUILD_TYPE`
  from the `release` file, the bundled license text, and `java -version` with a 5-second
  timeout only when there is no `release` file (`--no-exec` / `-NoExec` turns this off).
- Auto-update signals: Java Update policy, `jusched.exe` and scheduled tasks on Windows, and
  Oracle's Java-Updater LaunchAgent on macOS.
- Repo scanning for Oracle Java references in Dockerfiles, Compose and Kubernetes YAML,
  GitHub Actions (`setup-java` with `distribution: oracle`), GitLab CI, Jenkinsfiles, shell
  and PowerShell scripts, `.sdkmanrc`, `.tool-versions`, `.java-version`, Gradle and Maven
  toolchains.
- JSON output format `runtimeclear.scan/v1`, `--anonymize` for the hostname, and a summary
  on stderr.
- `tests/run.sh`: end-to-end tests with fake Java homes and a fake repo, a no-network check
  under `strace`, and a comparison of the PowerShell and bash results under `pwsh`.

[Unreleased]: https://github.com/techbuilddreams/runtimeclear/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/techbuilddreams/runtimeclear/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/techbuilddreams/runtimeclear/releases/tag/v1.0.0
