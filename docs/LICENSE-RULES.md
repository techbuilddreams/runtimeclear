# RuntimeClear license rules

Rules version: `2026-09-11` · All sources last checked: **2026-09-11**
Engine: `web/report/rules.js` (`RULES_VERSION`, `LAST_CHECKED`). Tests: `node web/report/rules.test.js`.

> Not legal advice. RuntimeClear is not affiliated with Oracle. "Oracle" and "Java" are trademarks of Oracle and/or its affiliates.
> The license of a Java build is set by **the build you downloaded**, not by later events: Oracle's FAQ says
> "You may continue to use releases you have downloaded under the terms of the license under which you downloaded them." [FAQ]
> An installed NFTC build never becomes paid. Exposure comes from (1) Oracle builds that are already OTN, and (2) updating / pulling newer Oracle builds that are OTN.

## Status meanings

| Status | Meaning |
|---|---|
| `free` | Non-Oracle OpenJDK build, Oracle OpenJDK (GPLv2+CPE), or an Oracle JDK build under NFTC or BCL. |
| `at_risk` | Free today (NFTC), but the next Oracle update, image pull, or auto-update brings an OTN build. Oracle JDK 21 is the main case. |
| `paid_license` | Oracle JDK build under OTN. Commercial production use needs a Java SE subscription unless an OTN exception applies. |
| `needs_review` | Signals conflict, the vendor or version is unknown, Oracle GraalVM, version numbers not released as of the check date, or a vendor-neutral config line. |

## 1. Oracle JDK / JRE (identified as Oracle JDK, see §4)

| Product line | Version range | License | Free for commercial production? | Status | Primary citation(s) | Checked |
|---|---|---|---|---|---|---|
| Oracle JDK/JRE 6 | 6 – 6u45 (last public, archive) | BCL | Yes, for general-purpose desktops and servers. "Commercial Features" and embedded use are excluded | free (EOL) | [Java 6 archive (BCL)](https://www.oracle.com/java/technologies/javase-java-archive-javase6-downloads.html), [BCL text](https://www.oracle.com/downloads/licenses/binary-code-license.html) | 2026-09-11 |
| Oracle JDK/JRE 6 | > 6u45 | not a public release | Unknown | needs_review | same | 2026-09-11 |
| Oracle JDK/JRE 7 | 7 – 7u80 (last public, archive) | BCL | Yes (same BCL caveats) | free (EOL) | [Java 7 archive (BCL)](https://www.oracle.com/java/technologies/javase/javase7-archive-downloads.html) | 2026-09-11 |
| Oracle JDK/JRE 7 | > 7u80 | not a public release | Unknown | needs_review | same | 2026-09-11 |
| Oracle JDK/JRE ≤ 5 | any | pre-Oracle / Sun | Unknown | needs_review | — (not covered) | 2026-09-11 |
| Oracle JDK/JRE 8 | 8 – **8u202** (1.8.0_202-b08, released Jan 15 2019) | BCL | Yes (BCL caveats: Commercial Features such as JFR through `-XX:+UnlockCommercialFeatures`, and embedded use, need a separate license) | free (no longer patched) | [8u202 release notes](https://www.oracle.com/java/technologies/javase/8u202-relnotes.html), [Java 8 archive "8u202 and earlier" (BCL)](https://www.oracle.com/java/technologies/javase/javase8-archive-downloads.html), [FAQ: releases before Apr 16 2019 are the only BCL releases](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| Oracle JDK/JRE 8 | 8u203 – 8u210 | no public release uses these numbers | Unknown | needs_review | same | 2026-09-11 |
| Oracle JDK/JRE 8 | **8u211+** (1.8.0_211-b12, released Apr 16 2019) and later (8u212 PSU, … 8u501/8u503) | OTN | **No.** Free only for personal, development/testing/prototyping/demo use, Oracle-approved products, and OCI | paid_license | [8u211 release notes](https://www.oracle.com/java/technologies/javase/8u211-relnotes.html), [Java 8 archive "8u211 and later" (OTN)](https://www.oracle.com/java/technologies/javase/javase8u211-later-archive-downloads.html), [java.com license notice](https://www.java.com/en/download/release_notice.jsp), [FAQ](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| Oracle JDK 9 | 9, 9.0.1, 9.0.4 | BCL | Yes (BCL caveats) | free (EOL) | [Java 9 archive (BCL)](https://www.oracle.com/java/technologies/javase/javase9-archive-downloads.html) | 2026-09-11 |
| Oracle JDK 10 | 10, 10.0.1, 10.0.2 | BCL | Yes (BCL caveats) | free (EOL) | [Java 10 archive (BCL)](https://www.oracle.com/java/technologies/java-archive-javase10-downloads.html) | 2026-09-11 |
| Oracle JDK 11 | **all** releases from GA (11.0.0, Sep 2018) onward | OTN (and My Oracle Support) | No | paid_license | [JDK 11 release notes: "Oracle JDK will be released under OTN License"](https://www.oracle.com/java/technologies/javase/11-relnote-issues.html), [FAQ table: "Java 11 – Oracle JDK, all releases"](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| Oracle JDK 12–16 | all releases | OTN | No | paid_license (verified for 12, 13, 14, 15 and 16. The SPEC's "edge case" worry did not hold up) | [12](https://www.oracle.com/java/technologies/javase/12-relnote-issues.html), [13](https://www.oracle.com/java/technologies/javase/13-relnote-issues.html), [14](https://www.oracle.com/java/technologies/javase/14-relnote-issues.html), [15](https://www.oracle.com/java/technologies/javase/15-relnote-issues.html), [16](https://www.oracle.com/java/technologies/javase/16-relnote-issues.html) release notes: "Oracle JDK is released under the OTN License" | 2026-09-11 |
| Oracle JDK 17 | 17 – **17.0.12** (Jul 2024; releases through Sep 2024) | NFTC | Yes | free (no longer patched under NFTC) | [FAQ table](https://www.oracle.com/java/technologies/javase/jdk-faqs.html), [Support roadmap](https://www.oracle.com/java/technologies/java-se-support-roadmap.html) | 2026-09-11 |
| Oracle JDK 17 | **17.0.13+** (17.0.13+10, released **Oct 15 2024**), currently up to 17.0.20.1 | OTN | No | paid_license | [17.0.13 release notes: "first JDK 17 update release made available under the OTN"](https://www.oracle.com/java/technologies/javase/17-0-13-relnotes.html), [roadmap](https://www.oracle.com/java/technologies/java-se-support-roadmap.html), [blog, Apr 16 2024](https://blogs.oracle.com/java/jdk-17-approaches-endofpermissive-license) | 2026-09-11 |
| Oracle JDK 18, 19, 20, 22, 23, 24 | all releases | NFTC | Yes | free (EOL, no updates) | [FAQ table: "Six-month non-LTS … Oracle JDK, all releases – NFTC"](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| Oracle JDK 21 | 21 – **21.0.12** (21.0.12+7, Jul 21 2026) and **21.0.12.1** (21.0.12.1+1, Aug 18 2026). This is the last release so far | NFTC | Yes, for that build. The **next** update is OTN | **at_risk** | [21.0.12 release notes](https://www.oracle.com/java/technologies/javase/21-0-12-relnotes.html), [21.0.12.1 release notes](https://www.oracle.com/java/technologies/javase/21-0-12-1-relnotes.html), [blog Aug 14 2026: "all updates through and including September 2026 are available under the NFTC"](https://blogs.oracle.com/java/jdk-21-approaches-end-of-permissive-license), [FAQ](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| Oracle JDK 21 | 21.0.12.2 and higher 21.0.12.x | not released as of 2026-09-11. NFTC if Oracle ships it in Sep 2026, OTN if it ships later | Unknown | needs_review | same | 2026-09-11 |
| Oracle JDK 21 | **21.0.13+**, the Oct 2026 CPU (**Oct 20 2026**) onward. *Planned, not yet released* | OTN (planned) | No | paid_license (planned) | [roadmap: "Updates of JDK 21 released after September of 2026, are planned to be offered under the Java SE OTN license"](https://www.oracle.com/java/technologies/java-se-support-roadmap.html), [blog](https://blogs.oracle.com/java/jdk-21-approaches-end-of-permissive-license), [CPU dates](https://www.oracle.com/security-alerts/) | 2026-09-11 |
| Oracle JDK 25 | 25 – 25.0.12 (currently 25.0.4.1). NFTC is planned "until September of 2028" | NFTC | Yes | free | [FAQ: "Oracle JDK 25 updates are planned to be made available under the NFTC until September of 2028"](https://www.oracle.com/java/technologies/javase/jdk-faqs.html), [roadmap](https://www.oracle.com/java/technologies/java-se-support-roadmap.html) | 2026-09-11 |
| Oracle JDK 25 | ≥ 25.0.13 (would be Oct 2028 or later) | unknown / planned OTN | Unknown | needs_review | same | 2026-09-11 |
| Oracle JDK 26 | all (currently 26.0.2.1) | NFTC | Yes | free | [FAQ: non-LTS releases are NFTC "for their entire planned six-month support life"](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| Oracle JDK ≥ 27 | any | not released as of the check date | Unknown | needs_review | — | 2026-09-11 |

**The October 2026 CPU is update 21.0.13.** This is inferred from Oracle's numbering: every CPU raises the update number by one (21.0.12 = Jul 2026 CPU; 17.0.13 = Oct 2024 CPU). Oracle's pages name the *date*, not the version.

### OTN exceptions (always shown as a note, never used to mark something free)
The OTN license allows free use only for: Personal Use ("solely on a desktop or laptop computer under such Individual's control only to run Personal Applications"); Development Use ("to develop, test, prototype and demonstrate Your Applications"); running Oracle-approved products (Schedule A/B); and use on Oracle Cloud Infrastructure. "If You want to use the Programs for any purpose other than as expressly permitted … You must obtain … a valid Program license." Source: [OTN license text](https://www.oracle.com/downloads/licenses/javase-license1.html) (updated Apr 10 2019). Per the [FAQ](https://www.oracle.com/java/technologies/javase/jdk-faqs.html), "If you are using Java on a desktop or laptop computer as part of any business operations, that is not personal use." Checked 2026-09-11.

NFTC grants free use "including in commercial and production use", and allows redistribution as long as it is not for a fee ([NFTC text](https://www.oracle.com/downloads/licenses/no-fee-license.html), [FAQ](https://www.oracle.com/java/technologies/javase/jdk-faqs.html)). Checked 2026-09-11.

## 2. Oracle OpenJDK, GraalVM, and non-Oracle distributions

| Product | License | Free for commercial production? | Status | Citation | Checked |
|---|---|---|---|---|---|
| Oracle OpenJDK builds (jdk.java.net) | GPLv2+CPE | Yes. Oracle updates each release for only about 6 months (e.g., 21 "releases through January 2024") | free (with an action to move to a maintained build) | [FAQ table](https://www.oracle.com/java/technologies/javase/jdk-faqs.html), [jdk.java.net](https://jdk.java.net/26/) | 2026-09-11 |
| Oracle GraalVM (GFTC; for JDK 17 the GraalVM OTN license applies after Sep 2024; for JDK 21 GraalVM OTN is planned from the Oct 2026 CPU) | GFTC / GraalVM OTN, depending on version | Depends | needs_review | [GFTC text](https://www.oracle.com/downloads/licenses/graal-free-license.html), [blog (GraalVM for JDK 21)](https://blogs.oracle.com/java/jdk-21-approaches-end-of-permissive-license), [graalvm.org downloads](https://www.graalvm.org/downloads/), [FAQ: "GraalVM for JDK 24 was the final version … licensed and supported as part of Oracle Java SE Products"](https://www.oracle.com/java/technologies/javase/jdk-faqs.html) | 2026-09-11 |
| GraalVM Community Edition | GPLv2+CPE | Yes | free | [setup-java README license table](https://github.com/actions/setup-java/blob/main/README.md), [OpenJDK GPLv2+CE](https://openjdk.org/legal/gplv2+ce.html) | 2026-09-11 |
| Eclipse Temurin (Adoptium) | GPLv2+CPE ("no licensing fees") | Yes | free | [adoptium.net/temurin](https://adoptium.net/temurin/), [Docker image license](https://github.com/docker-library/docs/blob/master/eclipse-temurin/license.md) | 2026-09-11 |
| Amazon Corretto | GPLv2+CPE, "at no cost" | Yes | free | [Corretto FAQ](https://aws.amazon.com/corretto/faqs/) | 2026-09-11 |
| Azul Zulu (community builds) | GPLv2+CE, "zero licensing fees" (Zulu SA subscriber builds are paid support) | Yes | free | [Azul Core](https://www.azul.com/products/core/) | 2026-09-11 |
| BellSoft Liberica JDK | "completely free to use in production" | Yes | free | [Liberica JDK](https://bell-sw.com/libericajdk/) | 2026-09-11 |
| Microsoft Build of OpenJDK | "no-cost … free for anyone to deploy anywhere" | Yes | free | [Microsoft Learn](https://learn.microsoft.com/en-us/java/openjdk/overview) | 2026-09-11 |
| Red Hat build of OpenJDK | GPL, no-cost; support comes with a subscription | Yes | free | [Red Hat Developer](https://developers.redhat.com/products/openjdk/overview) | 2026-09-11 |
| SAP SapMachine | "completely free to use in development and production" | Yes | free | [sapmachine.io](https://sapmachine.io/) | 2026-09-11 |
| IBM Semeru Runtimes (Open Edition GPLv2+CE; Certified Edition no-cost IBM license) | Vendor | Yes | free | [Semeru downloads](https://developer.ibm.com/languages/java/semeru-runtimes/downloads/), [IBM blog: no-cost Certified Edition](https://developer.ibm.com/blogs/launch-of-ibm-semeru-runtime-certified-edition-11/) | 2026-09-11 |
| Unrecognised vendor, `OpenJDK Runtime Environment`, no Oracle commercial marker | GPLv2+CPE (OpenJDK build) | Yes | free | [OpenJDK branding defaults](https://github.com/openjdk/jdk21u/blob/master/make/conf/branding.conf) | 2026-09-11 |
| IBM SDK (non-Semeru), ISV-bundled JDKs, anything else | Unknown | Unknown | needs_review | — | 2026-09-11 |

Vendor support contracts are separate from the license to *use* the binaries. None of these vendors requires a paid subscription to run their builds in production.

## 3. References (Dockerfiles, CI, SDK managers, build tools)

| Reference | What it pulls | Status | Citation | Checked |
|---|---|---|---|---|
| `actions/setup-java` `distribution: oracle`, `java-version: 21` (or `21.x`, pinned `21.0.≤12`) | major only: `https://download.oracle.com/java/21/latest/jdk-21_<os>-<arch>_bin.<ext>`, falling back to `/java/21/archive/jdk-<ver>_…`. Oracle JDK only for 17+. Oracle says the JDK 21 `latest` URLs "will cease to work on October of 2026" | **at_risk**: NFTC today, but the job stops getting (or failing to get) NFTC updates in Oct 2026, and newer 21 updates are OTN | [setup-java oracle installer.ts](https://github.com/actions/setup-java/blob/main/src/distributions/oracle/installer.ts), [Oracle script-friendly URLs](https://www.oracle.com/java/technologies/jdk-script-friendly-urls/) | 2026-09-11 |
| setup-java `oracle` with 25 / 26 / `latest` | NFTC builds (`latest` resolves to the newest GA feature release using the Adoptium API) | free | same + [setup-java README](https://github.com/actions/setup-java/blob/main/README.md) | 2026-09-11 |
| setup-java `oracle` with 17 | The JDK 17 `latest` URLs "stopped working on October of 2024". Archive URLs for ≤17.0.12 were promised "at least until October of 2025" | needs_review (probably failing or pinned) | [script-friendly URLs](https://www.oracle.com/java/technologies/jdk-script-friendly-urls/) | 2026-09-11 |
| setup-java `oracle`, java-version not on the matched line | — | needs_review | — | 2026-09-11 |
| setup-java `oracle-openjdk` | jdk.java.net GPL builds | free | [setup-java README](https://github.com/actions/setup-java/blob/main/README.md) | 2026-09-11 |
| `download.oracle.com/java/<N>/latest/…` in scripts | 21 → at_risk; 25/26 → free; 17 → needs_review (URL retired) | as listed | [script-friendly URLs](https://www.oracle.com/java/technologies/jdk-script-friendly-urls/) | 2026-09-11 |
| `download.oracle.com/java/<N>/archive/jdk-<ver>…` | a pinned NFTC build → version rules from §1 | per version | same | 2026-09-11 |
| `container-registry.oracle.com/java/jdk:<tag>` | OCR "JDK repository has images with **every** JDK release" (needs a free Oracle account, Oracle standard terms). A floating tag follows the newest update of that line | floating `8`/`11`/`17` → paid_license (newest builds are OTN); floating `21` → at_risk; `25`/`26` → free; pinned version tags → §1 rules; no tag or `latest` → needs_review | [ops.java download guide (Oracle)](https://ops.java/supporthandbook/downloadguide), [oracle/docker-images OracleJava README](https://github.com/oracle/docker-images/blob/main/OracleJava/README.md) | 2026-09-11 |
| `container-registry.oracle.com/java/jdk-no-fee-term:<tag>` | "images with JDK releases covered by the NFTC license. No login is required." | `21` → at_risk (receives no further 21 patches after Sep 2026; getting them from Oracle means OTN); `17` → free but unpatched; 25/26 → free | same | 2026-09-11 |
| `container-registry.oracle.com/java/openjdk:<tag>` | GPL Oracle OpenJDK images | free | same | 2026-09-11 |
| `container-registry.oracle.com/java/serverjre:8`, `store/oracle/serverjre:8` (retired Docker Store) | Server JRE 8. The update inside decides BCL vs OTN | floating OCR `8` → paid_license; Docker Store image → needs_review | same | 2026-09-11 |
| `container-registry.oracle.com/graalvm/*` | Oracle GraalVM (GFTC/OTN), except `*community*` images (GPL) | needs_review / free | [GFTC](https://www.oracle.com/downloads/licenses/graal-free-license.html) | 2026-09-11 |
| Docker Hub `openjdk:<tag>` | "This image is officially deprecated … find and use suitable replacements ASAP"; only EA tags have been updated since July 2022. GPL builds | free, with an action to switch to `eclipse-temurin` | [docker-library openjdk deprecation notice](https://github.com/docker-library/docs/blob/master/openjdk/deprecated.md), [Docker Hub](https://hub.docker.com/_/openjdk) | 2026-09-11 |
| `eclipse-temurin`, `amazoncorretto`, `azul/zulu-openjdk*`, `bellsoft/liberica-*`, `mcr.microsoft.com/openjdk/jdk`, `registry.access.redhat.com/ubi*/openjdk-*`, `sapmachine`, `ibm-semeru-runtimes` | vendor OpenJDK | free | vendor pages (§2) | 2026-09-11 |
| SDKMAN `…-oracle` | Oracle JDK → §1 by version; `-graal` → needs_review; `-graalce`, `-open`, `-tem`, `-amzn`, … → free | per version | [sdkman.io/jdks](https://sdkman.io/jdks/) | 2026-09-11 |
| asdf / jenv lines that mention `oracle` | Oracle JDK → §1 by version; version-only lines → needs_review | per version | — | 2026-09-11 |
| Gradle `vendor = JvmVendorSpec.ORACLE` | matches any JDK whose vendor is Oracle (Oracle JDK **or** Oracle OpenJDK) | needs_review | [Gradle toolchains](https://docs.gradle.org/current/userguide/toolchains.html) | 2026-09-11 |
| Maven toolchains `<vendor>oracle</vendor>` | free-text match against each machine's `~/.m2/toolchains.xml` | needs_review | [Maven toolchains guide](https://maven.apache.org/guides/mini/guide-using-toolchains.html) | 2026-09-11 |

CI build and test jobs count as "develop, test, prototype and demonstrate", which OTN allows. The exposure is OTN builds that end up in production images or on servers. Every OTN reference carries that note.

## 4. Detection signals (how an install is identified as Oracle JDK)

| Signal | Meaning | Confidence / source |
|---|---|---|
| `java -version` runtime name `Java(TM) SE Runtime Environment` | Oracle JDK/JRE (Oracle GraalVM also prints it, so GraalVM is checked first) | Oracle JDK 11 release notes: "Oracle JDK will say `java` and include LTS. OpenJDK (when produced by Oracle) will say OpenJDK and not include the Oracle-specific LTS identifier." [link](https://www.oracle.com/java/technologies/javase/11-relnote-issues.html) (checked 2026-09-11) |
| bundled license text (`legal/java.base/LICENSE`, `LICENSE`, `COPYRIGHT`) naming OTN / NFTC / BCL / GPL | the license the build shipped with | Strongest signal when present; disagreement with version rules → needs_review. Oracle OpenJDK 20.0.x and Azul/Homebrew builds observed with GPL text (2026-09-11) |
| `release` file `BUILD_TYPE="commercial"` | Oracle JDK (commercial build) | **Not documented by Oracle.** The open-source build (`make/ReleaseFile.gmk` in openjdk/jdk21u) never writes `BUILD_TYPE`, so the key comes from Oracle's closed build. Widely observed in Oracle JDK release files; confirmed on a real Oracle JDK 11.0.24 macOS install on 2026-09-11 (`IMPLEMENTOR="Oracle Corporation"`, `JAVA_RUNTIME_VERSION="11.0.24+7-LTS-271"`), while Oracle OpenJDK 20.0.x builds on the same machine had no `BUILD_TYPE`. Treated as a strong signal |
| `IMPLEMENTOR="Oracle Corporation"` | Oracle JDK **or** Oracle OpenJDK (jdk.java.net). **Not enough on its own** | OpenJDK's default `COMPANY_NAME=N/A` ([branding.conf](https://github.com/openjdk/jdk21u/blob/master/make/conf/branding.conf)), so only Oracle-produced builds say Oracle. Engine returns needs_review when this is the only signal |
| `OpenJDK Runtime Environment` | an OpenJDK (GPL) build | OpenJDK default branding `PRODUCT_NAME=OpenJDK`, `PRODUCT_SUFFIX="Runtime Environment"` |
| rpm/dpkg vendor "Oracle" | **not used**: Oracle Linux ships GPL OpenJDK packages too | engine ignores it for Oracle JDK detection |
| Oracle signal (`BUILD_TYPE=commercial` or `Java(TM) SE`) **and** OpenJDK signal (OpenJDK runtime name or a non-Oracle implementor) | conflict | needs_review |
| `GraalVM` in implementor, runtime name, version or path | GraalVM (Community → free; otherwise needs_review) | — |
| `javaVersion` and `rawVersion` give different results | conflict | needs_review |

## 5. Auto-update

| Entry | Status | Why | Citation | Checked |
|---|---|---|---|---|
| `windows-java-update-scheduler` / `macos-oracle-java-updater`, enabled | at_risk | Java Update "periodically checks for new versions" and "ask[s] your permission to upgrade". Every Oracle Java 8 release since 8u211 (Apr 16 2019) is OTN, so accepting an update on a business machine installs an OTN build | [What is Java Update?](https://www.java.com/en/download/help/java_update.html), [java.com license notice](https://www.java.com/en/download/release_notice.jsp) | 2026-09-11 |
| same, disabled | free (informational) | will not offer builds | same | 2026-09-11 |
| other kinds | needs_review | — | — | — |

Also noted (not auto-classified): winget's `Oracle.JavaRuntimeEnvironment` manifests are 8u251+ builds (OTN), so `winget upgrade --all` on a machine with an Oracle JRE installs OTN builds. Source: [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs/tree/master/manifests/o/Oracle/JavaRuntimeEnvironment) (checked 2026-09-11).

## 6. Oracle Java SE Universal Subscription list price (used by `estimateCost`)

| Total employees | USD per employee per month |
|---|---|
| 1 – 999 | $15.00 |
| 1,000 – 2,999 | $12.00 |
| 3,000 – 9,999 | $10.50 |
| 10,000 – 19,999 | $8.25 |
| 20,000 – 29,999 | $6.75 |
| 30,000 – 39,999 | $5.70 |
| 40,000 – 49,999 | $5.25 |
| 50,000+ | contact Oracle |

- The whole employee count is priced at its tier's rate. Annual cost = monthly × 12.
- "Employee" per the price list: "(i) all of Your full-time, part-time, temporary employees, and (ii) all of the full-time employees, part-time employees and temporary employees of Your agents, contractors, outsourcers, and consultants" that support your internal business operations. **This counts every employee, not only Java users.**
- Sources: [Oracle Java SE Universal Subscription Global Price List (PDF)](https://www.oracle.com/a/ocom/docs/corporate/pricing/java-se-subscription-pricelist-5028356.pdf). The tiers were read from the March 1 2023 edition of that PDF, via a university mirror, because oracle.com's robots.txt blocks automated fetching. Oracle's [Java SE Universal Subscription FAQ](https://www.oracle.com/java/technologies/java-se-subscription-faq.html) confirms "Pricing starts at $15/employee per month. Published tier pricing is as low as $5.25 per month and can be even lower for customers with more than 50k employees." Checked 2026-09-11.
- **Could not verify directly**: whether Oracle has published a newer edition of the price list with different middle tiers. The UI must label the result "list price, estimate".

## 7. Migration commands (used by `migrationSteps`)

| Platform | Command source | Checked |
|---|---|---|
| linux-deb (Temurin) | [adoptium.net/installation/linux](https://adoptium.net/installation/linux/) (apt repo + `temurin-<N>-jdk`) | 2026-09-11 |
| linux-rpm (Temurin) | same. Uses `sudo tee` instead of the docs' `sudo cat <<EOF >` (that form does not write as root) | 2026-09-11 |
| linux-deb / linux-rpm (Corretto) | [Corretto Linux install](https://docs.aws.amazon.com/corretto/latest/corretto-21-ug/generic-linux-install.html) | 2026-09-11 |
| Oracle JDK removal (Linux/macOS) | [Oracle JDK 21 Linux install guide](https://docs.oracle.com/en/java/javase/21/install/installation-jdk-linux-platforms.html) (`rpm -e jdk-21`, `dpkg -r jdk-21`), [macOS guide](https://docs.oracle.com/en/java/javase/21/install/installation-jdk-macos.html), [java.com mac JRE uninstall](https://www.java.com/en/download/help/mac_uninstall_java.html) | 2026-09-11 |
| macos | `brew install --cask temurin@21` (adoptium.net source; casks `temurin@8/11/17/21/25` and `corretto@8/11/17/21/25` exist in Homebrew/homebrew-cask) | 2026-09-11 |
| windows | `winget install EclipseAdoptium.Temurin.21.JDK` (adoptium.net source; winget-pkgs has Temurin 8, 11, 16–26 JDK/JRE and `Amazon.Corretto.<N>.JDK`) | 2026-09-11 |
| docker | `FROM eclipse-temurin:21-jdk` / `21-jre` (docker-library/official-images) | 2026-09-11 |
| github-actions | `actions/setup-java@v6`, `distribution: 'temurin'` ([setup-java README](https://github.com/actions/setup-java/blob/main/README.md)) | 2026-09-11 |
| sdkman | `sdk list java`, `sdk install java <id>-tem`, `sdk default java <id>`, `sdk env init` ([sdkman.io/usage](https://sdkman.io/usage/)) | 2026-09-11 |
| gradle | `vendor = JvmVendorSpec.ADOPTIUM`, foojay resolver plugin ([Gradle 9.7.1 docs](https://docs.gradle.org/current/userguide/toolchains.html)) | 2026-09-11 |
| maven | toolchains.xml + `maven-toolchains-plugin` 3.3.0 ([guide](https://maven.apache.org/guides/mini/guide-using-toolchains.html), [plugin](https://maven.apache.org/plugins/maven-toolchains-plugin/)) | 2026-09-11 |

## 8. Not verified from an official source (flagged)

1. `BUILD_TYPE="commercial"` as an Oracle JDK marker. Oracle does not document it (see §4), though it was observed on a real Oracle JDK 11.0.24 install (2026-09-11). The engine still requires no conflicting OpenJDK signal.
2. That jdk.java.net Oracle OpenJDK builds set `IMPLEMENTOR="Oracle Corporation"`. The engine returns needs_review when implementor is the only signal.
3. Oracle JDK **21.0.13** being the first OTN build is inferred from CPU numbering. Oracle only says "October 2026 CPU". It is also not released yet.
4. Middle price tiers ($12.00 to $5.70) come from the March 2023 price list edition. The current oracle.com PDF could not be fetched (robots.txt).
5. The license terms of `container-registry.oracle.com/java/jdk` pinned-version images beyond the JDK's own license ("Standard Oracle Terms" for registry access). Pinned NFTC-version tags are classified by JDK version, with a note.
6. SDKMAN suffixes other than `tem`, `oracle`, `graal` and `amzn` (e.g., `zulu`, `librca`, `ms`, `sapmchn`, `sem`, `graalce`, `open`) come from SDKMAN's current listing conventions, not a fetched page.
7. Temurin deb/rpm packages for non-LTS 26 (`temurin-26-jdk`). The engine notes to check the repo tree.

## 9. Engine contract notes (for the report UI)

- Every classification includes `status`, `product`, `license` (one of `NFTC`, `OTN`, `BCL`, `GPLv2+CPE`, `Vendor OpenJDK`, `Unknown`), `reason`, `action`, `citations` (at least one, always URLs from this file) and `replacement`. The engine also adds `notes` (OTN exceptions, BCL caveats, "you keep the license you downloaded under"). Oracle GraalVM uses `license: "Unknown"`; the reason explains the GFTC vs GraalVM OTN split.
- `parseVersion` also returns `interim`, `patch`, `build` and `ea`. `patch` is needed to tell 21.0.12.1 (NFTC) apart from a hypothetical 21.0.12.2.
- `summarize` removes duplicate installs (same host, path and version found through several sources). Each item has `entry` (the raw scan object), and the result has `warnings`, `rulesVersion` and `lastChecked`.
- `estimateCost` also returns `citations`. Show it as "list-price estimate", never as a quote.
