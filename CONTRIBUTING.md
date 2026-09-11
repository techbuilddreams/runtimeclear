# Contributing to RuntimeClear

Thanks for helping. RuntimeClear is two small scripts that people run on production machines,
often as root or Administrator. Every change is reviewed with that in mind.

- Found a security problem? Don't open an issue. Follow [SECURITY.md](SECURITY.md).
- Think a Java install got the wrong license status? See
  [Reporting a misclassification](#reporting-a-misclassification).
- Questions about a purchased report or billing: https://runtimeclear.com/support/

## Principles

These are not negotiable, and pull requests that break them will be closed:

1. **Read-only.** The scanners never install, change, move or delete anything. The only file
   they write is the JSON output (plus a private temp folder that `runtimeclear.sh` removes).
2. **No network.** No sockets, no downloads, no update checks, no telemetry. The test suite
   checks this with `strace` on Linux.
3. **No new dependencies.** bash 3.2 with the tools a stock macOS or Linux install has
   (`awk`, `sed`, `grep`, `find`), and PowerShell 5.1 without extra modules. No Python, jq or
   Node in the scanners.
4. **Facts, not verdicts.** The scanners record what is on disk. License decisions belong to
   the report and its documented rules ([docs/LICENSE-RULES.md](docs/LICENSE-RULES.md)).
5. **Both scripts stay in step.** A detection or JSON change goes into `runtimeclear.sh` and
   `runtimeclear.ps1` in the same pull request, with tests.

## Running the tests

### Linux

```sh
bash tests/run.sh
```

Needs `bash` and `python3`. Optional: `strace` enables the no-network test, and `pwsh`
enables the PowerShell parity tests. Set `RUNTIMECLEAR_TEST_PWSH=0` to skip those.

```sh
shellcheck runtimeclear.sh tests/run.sh      # settings are in .shellcheckrc
```

### macOS with the stock bash 3.2

`tests/run.sh` starts the scanner with `bash` from `PATH`. If Homebrew's bash comes first on
your `PATH`, put `/bin/bash` in front so the test really runs on 3.2:

```sh
mkdir -p /tmp/rc-bash32 && ln -sf /bin/bash /tmp/rc-bash32/bash
PATH="/tmp/rc-bash32:$PATH" /bin/bash tests/run.sh
```

bash 3.2 rules: no associative arrays, no `mapfile`/`readarray`, no `${var,,}`, and under
`set -u` never expand an empty array (`"${arr[@]}"`) without a guard.

### Windows PowerShell 5.1 and PowerShell 7

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1   # Windows PowerShell 5.1
pwsh -NoProfile -File tests/smoke.ps1                                 # PowerShell 7, any OS

Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path runtimeclear.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
```

PowerShell rules: keep `runtimeclear.ps1` ASCII-only (Windows PowerShell 5.1 misreads
non-ASCII text in files without a BOM) and avoid PowerShell 7-only syntax (`??`, `?.`, the
ternary operator, `&&` and `||` pipeline chains, `ForEach-Object -Parallel`).

CI runs all of the above on Ubuntu, macOS and Windows for every pull request.

## Reporting a misclassification

The scanner only reports facts. If the report at https://runtimeclear.com/report/ shows the
wrong status for a Java install, we need the facts it saw and a source for the status you
expect.

1. Run the scanner with `--anonymize` (bash) or `-Anonymize` (PowerShell).
2. Open the JSON file and copy **only** the entry from `installs` for the affected Java home.
   Keep `javaVersion`, `rawVersion`, `implementor`, `buildType`, `runtimeName`, `isJre`,
   `packageVendor`, `licenseFile` and `source` as they are. Replace usernames, hostnames and
   internal folder names in `path` with placeholders such as `/home/<user>/`.
3. Note the status the report showed (`free`, `at_risk`, `paid_license` or `needs_review`)
   and the status you expect.
4. Find a source: Oracle release notes, the license text shipped with the build, Oracle's
   Java SE FAQ or support roadmap, or the vendor's documentation. A link is best.
5. Open a [misclassification report](https://github.com/techbuilddreams/runtimeclear/issues/new?template=misclassification.yml).

Classification rules and their sources are listed in
[docs/LICENSE-RULES.md](docs/LICENSE-RULES.md). A change to a rule needs a citation.
When signals conflict or a version isn't documented, the correct status is `needs_review`.

## Pull requests

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Keep the change focused. Update the README (options, JSON schema, "What it reads") when
   behaviour changes.
3. Add or update tests in `tests/run.sh` and, for PowerShell behaviour, `tests/smoke.ps1`.
4. Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
5. Don't edit `SHA256SUMS` or the version numbers. Maintainers do that when releasing.

Files use LF line endings (`.gitattributes`) and the settings in `.editorconfig`.

## Releasing (maintainers)

1. Set the new version in `VERSION=` (`runtimeclear.sh`), `$ScannerVersion` (`runtimeclear.ps1`)
   and the expected version strings in `tests/run.sh`.
2. Move the `Unreleased` entries in `CHANGELOG.md` to `## [X.Y.Z] - YYYY-MM-DD` and update the
   compare links at the bottom.
3. `sha256sum runtimeclear.sh runtimeclear.ps1 > SHA256SUMS`
4. Commit, merge to `main` once CI is green, then `git tag vX.Y.Z && git push origin vX.Y.Z`.

The release workflow checks the version and checksums, runs the tests, attests the files and
publishes the GitHub release.

## Code of conduct

This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Report conduct issues
to support@runtimeclear.com.
