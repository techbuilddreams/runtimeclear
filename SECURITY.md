# Security policy

The RuntimeClear scanner runs on production machines, often as root or Administrator. We treat
any of the following as a security bug:

- a network connection of any kind
- a write to any file other than the JSON output
- running something other than `<java home>/bin/java -version`
- recording data the README says is not collected (process arguments, environment variables,
  file contents beyond the matched line)
- output that stops being valid JSON because of a crafted path or file

## Reporting

- **Non-sensitive issues** (wrong detection, parsing bugs, crashes): open a GitHub issue at
  https://github.com/techbuilddreams/runtimeclear/issues.
- **Sensitive issues** (anything above that could be abused): email
  **lsramos@techbuilddreams.com** with steps to reproduce. Please don't open a public issue
  until a fix is released.

RuntimeClear is maintained by a small team. We aim to reply within 3 business days and will credit
reporters in the release notes unless you ask us not to.

## Supported versions

Security fixes go into the latest release only. Always verify downloads against the
`SHA256SUMS` file attached to the GitHub release.
