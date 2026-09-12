# Security policy

The RuntimeClear scanner runs on production machines, often as root or Administrator, so we
treat its safety promises as security properties.

## Supported versions

Security fixes are released as a new patch version of the latest minor release.

| Version | Supported |
|---|---|
| 1.0.x (latest: 1.0.1) | Yes |
| Earlier versions | No, upgrade to the latest release |

## What counts as a vulnerability

- a network connection of any kind
- a write to any file other than the JSON output (and the private temp folder `runtimeclear.sh`
  removes on exit)
- running anything other than `<java home>/bin/java -version`
- recording data the README says is not collected (process arguments, environment variables
  other than `PATH` and `JAVA_HOME`, file contents beyond the matched line)
- output that stops being valid JSON, or that injects content, because of a crafted path,
  file name or file content
- anything in the release process that could let a published asset differ from the tagged
  source: the release workflow, checksums or attestations

## Reporting a vulnerability

Please report privately. Do not open a public issue, pull request or discussion.

1. **GitHub private vulnerability reporting (preferred):**
   [Report a vulnerability](https://github.com/techbuilddreams/runtimeclear/security/advisories/new)
2. **Email:** support@runtimeclear.com with "SECURITY" in the subject.

Include the scanner version (`--version` / `-Version`), the operating system and shell version,
steps or a proof of concept, and the impact you expect. Remove hostnames, usernames and
internal paths you don't want to share.

## What to expect

RuntimeClear is maintained by one person. These are targets, not guarantees:

| Step | Target |
|---|---|
| Acknowledge your report | 3 business days |
| Initial assessment (confirmed or not, severity) | 7 days |
| Fix released for a confirmed high or critical issue | 30 days |
| Public disclosure | Coordinated with you once a fix is released, at most 90 days after the report |

Fixes are announced in the release notes and, when warranted, a GitHub security advisory.
We credit reporters unless you ask us not to. We will not take legal action against good-faith
research that follows this policy, avoids privacy violations and service disruption, and gives
us reasonable time to fix the issue.

## Scope

In scope: `runtimeclear.sh`, `runtimeclear.ps1`, the tests, and this repository's release
workflow and release assets.

Out of scope here: the runtimeclear.com website, the browser report and the payment
verification endpoint. Their security policy and contact are published at
https://runtimeclear.com/.well-known/security.txt.

## Verifying downloads

Every release built by the release workflow attaches `runtimeclear.sh`, `runtimeclear.ps1` and
`SHA256SUMS`, each with a GitHub artifact attestation. Before running a download:

```sh
sha256sum -c SHA256SUMS                    # macOS: shasum -a 256 -c SHA256SUMS
gh attestation verify runtimeclear.sh --repo techbuilddreams/runtimeclear
```
