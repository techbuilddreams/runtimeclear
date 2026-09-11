## Summary

<!-- What changes and why. Link the issue: "Fixes #123". -->

## Type of change

- [ ] Bug fix
- [ ] New detection or output field
- [ ] Documentation
- [ ] CI, tests or tooling

## Checklist

- [ ] `bash tests/run.sh` passes (on macOS, with `/bin/bash` 3.2 first on `PATH`)
- [ ] PowerShell changes: `tests/smoke.ps1` passes and PSScriptAnalyzer reports nothing
- [ ] `runtimeclear.sh` and `runtimeclear.ps1` behave the same, with tests for both
- [ ] Still read-only, no network access, no new dependencies
- [ ] bash 3.2 compatible; `runtimeclear.ps1` is ASCII-only and runs on Windows PowerShell 5.1
- [ ] README updated if options, JSON fields or "What it reads" changed
- [ ] Entry added under `## [Unreleased]` in `CHANGELOG.md`
- [ ] No changes to `SHA256SUMS` or version numbers (maintainers do that at release)
