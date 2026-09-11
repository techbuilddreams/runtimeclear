#!/usr/bin/env bash
# runtimeclear.sh - inventory Java runtimes and Oracle Java references (Linux, macOS)
#
# Copyright (c) 2026 Tech Build Dreams LLC. MIT License. https://runtimeclear.com
#
# WHAT THIS SCRIPT READS (read-only; it never modifies, moves or deletes anything):
#   - Java home directories in well-known locations (listed in discover_linux,
#     discover_macos and discover_user_homes below) and the `release` text file
#     inside each one.
#   - `java` executables on $PATH and $JAVA_HOME (symlinks are resolved).
#   - Local package databases: `rpm -qa` / `rpm -ql` and `dpkg-query` / `dpkg -L`.
#   - `update-alternatives` (Linux) and `/usr/libexec/java_home -V` (macOS).
#   - Running processes named java: ONLY the executable path (/proc/<pid>/exe, or
#     argv[0] when that link is unreadable; on macOS `ps -o comm`). No other
#     command-line arguments are stored.
#   - With --repo only: names of CI/container/build files and the single lines
#     that match the patterns in the awk program below.
# WHAT IT EXECUTES: `<java home>/bin/java -version` ONLY for a Java home that has
#   no usable `release` file (5 second timeout). --no-exec disables this.
# WHAT IT WRITES: exactly one JSON file (--out). Temporary files go in a private
#   mktemp directory that is removed on exit.
# NETWORK: none. Nothing is sent anywhere. The JSON stays on this machine.
# PRIVILEGES: none required. Locations it cannot read are listed in "warnings".
#
# Compatible with bash 3.2 (stock macOS): no associative arrays, no mapfile.

set -u
LC_ALL=C; export LC_ALL          # predictable grep/sed/awk behaviour on bytes

VERSION="1.0.0"
SITE_URL="https://runtimeclear.com"
SCHEMA="runtimeclear.scan/v1"
JAVA_VERSION_TIMEOUT=5            # seconds allowed for `java -version`
MAX_TEXT=300                      # max bytes of a matched line kept in the JSON

usage() {
  cat <<EOF
runtimeclear $VERSION - find Java runtimes and Oracle Java references. Read-only, no network.

Usage: bash runtimeclear.sh [options]

  --repo <dir>   Also scan a source/config repo for Oracle Java references
                 (Dockerfiles, compose/k8s YAML, GitHub/GitLab CI, scripts,
                 .sdkmanrc, .tool-versions, .java-version, Gradle, Maven).
                 Repeatable.
  --no-system    Do not look for installed runtimes (repo scan only).
  --no-exec      Never run any java binary (versions of homes without a
                 'release' file are then reported as "unknown").
  --anonymize    Replace the hostname with the first 12 hex chars of its SHA-256.
  --out <file>   Output path (default: ./runtimeclear-scan-<host>-<UTC time>.json)
  --quiet        No summary on stderr.
  --help         Show this help.   --version   Show the version.

Open $SITE_URL/report and load the JSON; it is processed in your browser.
EOF
}

die() { printf 'runtimeclear: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------- options ---
REPOS=(); REPO_COUNT=0     # counter avoids "${REPOS[@]}" on an empty array (set -u, bash 3.2)
NO_SYSTEM=0; NO_EXEC=0; ANONYMIZE=0; QUIET=0; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)      [ $# -ge 2 ] || die "--repo needs a directory"
                 [ -d "$2" ] || die "--repo: not a directory: $2"
                 REPOS[REPO_COUNT]=$2; REPO_COUNT=$((REPO_COUNT + 1)); shift 2 ;;
    --no-system) NO_SYSTEM=1; shift ;;
    --no-exec)   NO_EXEC=1; shift ;;
    --anonymize) ANONYMIZE=1; shift ;;
    --out)       [ $# -ge 2 ] || die "--out needs a file name"; OUT=$2; shift 2 ;;
    --quiet|-q)  QUIET=1; shift ;;
    --help|-h)   usage; exit 0 ;;
    --version)   printf 'runtimeclear %s\n' "$VERSION"; exit 0 ;;
    *)           die "unknown option: $1 (see --help)" ;;
  esac
done

# Test-only hooks (used by tests/run.sh; not needed in normal use):
#   RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1  skip every real system location
#   RUNTIMECLEAR_EXTRA_JVM_DIRS=a:b    extra directories searched for Java homes
NO_SYSTEM_DEFAULTS=${RUNTIMECLEAR_NO_SYSTEM_DEFAULTS:-0}
EXTRA_JVM_DIRS=${RUNTIMECLEAR_EXTRA_JVM_DIRS:-}

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t runtimeclear) || die "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT
: >"$TMP/candidates"; : >"$TMP/installs"; : >"$TMP/refs"; : >"$TMP/warnings"; : >"$TMP/seen"

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      PLATFORM=linux ;;
esac

# ---------------------------------------------------------------- helpers ---
log()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*" >&2; }
warn() { printf '%s\n' "$*" >>"$TMP/warnings"; }

[ "$(uname -s)" = Darwin ] || [ "$(uname -s)" = Linux ] ||
  warn "Unsupported OS '$(uname -s)': scanned with the Linux rules."

# Print $1 as a JSON string literal. Control characters become spaces, bytes
# that are not valid UTF-8 are dropped (when iconv exists), \ and " are escaped.
json_str() {
  local s=$1
  case "$s" in
    *[![:print:]]*)
      s=$(printf '%s' "$s" | tr '\011\012\015' '   ' | tr -d '\000-\037\177')
      if command -v iconv >/dev/null 2>&1; then
        s=$(printf '%s' "$s" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
      fi ;;
  esac
  case "$s" in
    *\\*|*\"*) s=$(printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g') ;;
  esac
  printf '"%s"' "$s"
}

# JSON string, or null when empty.
json_str_or_null() { if [ -n "$1" ]; then json_str "$1"; else printf 'null'; fi; }

# Resolve symlinks without GNU `readlink -f` (not available on older macOS).
real_path() {
  local p=$1 target n=0 dir
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    target=$(readlink "$p") || break
    case "$target" in
      /*) p=$target ;;
      *)  p=$(dirname "$p")/$target ;;
    esac
    n=$((n + 1))
  done
  if [ -d "$p" ]; then
    (cd -P "$p" 2>/dev/null && pwd -P) || printf '%s\n' "$p"
  else
    dir=$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P) || dir=$(dirname "$p")
    printf '%s/%s\n' "$dir" "$(basename "$p")"
  fi
}

# Run a command with a time limit. Uses `timeout` when present (GNU coreutils),
# otherwise runs it in the background and kills it after the limit (macOS).
run_with_timeout() {
  local secs=$1 pid n=0
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$n" -ge $((secs * 10)) ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
    n=$((n + 1))
  done
  wait "$pid"
}

# Candidates are collected first (one per line: source, type, vendor, path) and
# inspected later, so the first discovery method that finds a home names its
# "source". Order of discovery = priority. An empty vendor is stored as "-"
# because `read` collapses consecutive tabs.
add_home() { printf '%s\thome\t%s\t%s\n' "$1" "${3:--}" "$2" >>"$TMP/candidates"; }
add_bin()  { printf '%s\tbin\t%s\t%s\n'  "$1" "${3:--}" "$2" >>"$TMP/candidates"; }

# Print every */bin/java below $1, at most $2 levels deep (symlinks followed).
find_java_bins() {
  local dir=$1 depth=$2
  [ -e "$dir" ] || return 0
  if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
    warn "Not readable, skipped (run as root to include): $dir"
    return 0
  fi
  find -L "$dir" -maxdepth "$depth" -type f -name java -path '*/bin/java' 2>/dev/null
}

# add_bins_below <source> <dir> <depth>
add_bins_below() {
  local f
  find_java_bins "$2" "$3" >"$TMP/found"
  while IFS= read -r f <&3; do add_bin "$1" "$f"; done 3<"$TMP/found"
}

# Value of KEY="value" from a Java `release` file (quotes and CR removed).
release_value() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1 | tr -d '\r' | sed -e 's/^"//' -e 's/"$//'
}

# ------------------------------------------------------ system discovery ---
discover_packages() {
  # Package names that can contain a Java runtime (library packages like
  # libfoo-java are excluded on purpose).
  local pkg_re='jdk|jre|^java-[0-9]|^java-latest|openjdk|corretto|zulu|temurin|liberica|graalvm|sapmachine|oracle-java'
  local name _ver vendor _status bin tab
  tab=$(printf '\t')
  if command -v rpm >/dev/null 2>&1; then
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{VENDOR}\n' 2>/dev/null |
      awk -F'\t' -v re="$pkg_re" '$1 ~ re && $1 !~ /^lib/' >"$TMP/rpm"
    while IFS="$tab" read -r name _ver vendor <&3; do
      [ "$vendor" = "(none)" ] && vendor=""
      rpm -ql "$name" 2>/dev/null </dev/null | grep '/bin/java$' >"$TMP/pkgfiles"
      while IFS= read -r bin <&4; do add_bin rpm "$bin" "$vendor"; done 4<"$TMP/pkgfiles"
    done 3<"$TMP/rpm"
  fi
  if command -v dpkg-query >/dev/null 2>&1; then
    # db:Status-Abbrev is added so removed-but-not-purged packages are ignored.
    dpkg-query -W -f='${db:Status-Abbrev}\t${binary:Package}\t${Version}\t${Maintainer}\n' 2>/dev/null |
      grep '^ii' | awk -F'\t' -v re="$pkg_re" '$2 ~ re && $2 !~ /^lib/' >"$TMP/dpkg"
    while IFS="$tab" read -r _status name _ver vendor <&3; do
      dpkg -L "$name" 2>/dev/null </dev/null | grep '/bin/java$' >"$TMP/pkgfiles"
      while IFS= read -r bin <&4; do add_bin dpkg "$bin" "$vendor"; done 4<"$TMP/pkgfiles"
    done 3<"$TMP/dpkg"
  fi
}

discover_processes() {
  local pid exe unreadable=0
  if [ "$PLATFORM" = macos ]; then
    # On macOS `comm` is the full executable path. (pgrep cannot print paths.)
    # shellcheck disable=SC2009
    ps -axo comm= 2>/dev/null | grep '/bin/java$' >"$TMP/procs"
    while IFS= read -r exe <&3; do add_bin process "$exe"; done 3<"$TMP/procs"
    return 0
  fi
  ps -eo pid=,comm= 2>/dev/null | awk '$2 == "java" { print $1 }' >"$TMP/procs"
  while IFS= read -r pid <&3; do
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null)
    if [ -z "$exe" ]; then
      # Not root: fall back to argv[0] only; the remaining arguments are discarded.
      exe=$(tr '\000' '\n' <"/proc/$pid/cmdline" 2>/dev/null | head -n 1)
    fi
    case "$exe" in
      "")                  unreadable=$((unreadable + 1)) ;;
      *" (deleted)")       warn "Running JVM (pid $pid) uses a Java that was deleted or upgraded on disk: ${exe% (deleted)}" ;;
      /*/bin/java)         add_bin process "$exe" ;;
      *)                   unreadable=$((unreadable + 1)) ;;
    esac
  done 3<"$TMP/procs"
  [ "$unreadable" -eq 0 ] ||
    warn "$unreadable running java process(es) had no readable absolute executable path (run as root to include)."
}

discover_path_and_java_home() {
  local d old_ifs=$IFS
  [ -n "${JAVA_HOME:-}" ] && [ -d "$JAVA_HOME" ] && add_home path "$JAVA_HOME"
  IFS=:
  for d in $PATH; do
    [ -n "$d" ] && [ -f "$d/java" ] && add_bin path "$d/java"
  done
  IFS=$old_ifs
}

discover_linux() {
  add_bins_below filesystem /usr/lib/jvm 4
  add_bins_below filesystem /usr/java 4
  add_bins_below filesystem /opt 4
  add_bins_below filesystem /usr/local 3
  if command -v update-alternatives >/dev/null 2>&1 || command -v alternatives >/dev/null 2>&1; then
    # Debian prints paths with --list; RHEL's tool prints them with --display.
    { update-alternatives --list java 2>/dev/null || alternatives --display java 2>/dev/null; } |
      awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\/.*\/bin\/java$/) print $i }' >"$TMP/alts"
    local bin
    while IFS= read -r bin <&3; do add_bin filesystem "$bin"; done 3<"$TMP/alts"
  fi
}

discover_homebrew() {
  local d
  for d in /opt/homebrew/opt/openjdk* /usr/local/opt/openjdk*; do
    [ -e "$d" ] && add_bins_below homebrew "$d" 6
  done
  for d in /opt/homebrew/Caskroom/* /usr/local/Caskroom/*; do
    case "$(basename "$d")" in
      oracle-jdk*|temurin*|corretto*|zulu*|microsoft-openjdk*|sapmachine*|liberica*|graalvm*)
        add_bins_below homebrew "$d" 7 ;;
    esac
  done
}

discover_macos() {
  local d line
  for d in /Library/Java/JavaVirtualMachines/*/Contents/Home; do
    [ -d "$d" ] && add_home filesystem "$d"
  done
  d="/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home"
  [ -d "$d" ] && add_home filesystem "$d"
  if [ -x /usr/libexec/java_home ]; then
    # Lines look like:  21.0.4 (arm64) "Oracle Corporation" - "Java SE 21.0.4" /Library/...
    /usr/libexec/java_home -V 2>&1 >/dev/null | sed -n 's/^.*" \(\/.*\)$/\1/p' >"$TMP/jhome"
    while IFS= read -r line <&3; do add_home filesystem "$line"; done 3<"$TMP/jhome"
  fi
  # Oracle's Java auto-updater for the legacy JRE 8 installer.
  d=/Library/LaunchAgents/com.oracle.java.Java-Updater.plist
  if [ -f "$d" ]; then
    printf '{"kind": "macos-oracle-java-updater", "enabled": true, "detail": %s}\n' \
      "$(json_str "LaunchAgent present: $d (whether it is loaded was not checked)")" >>"$TMP/autoupdate"
  fi
}

# Per-user tool managers. As root, every home directory is included.
discover_user_homes() {
  local homes h
  homes=${HOME:-}
  if [ "$(id -u)" = 0 ]; then
    for h in /home/* /Users/*; do [ -d "$h" ] && homes="$homes:$h"; done
  fi
  local old_ifs=$IFS
  IFS=:
  for h in $homes; do
    IFS=$old_ifs
    [ -n "$h" ] || continue
    add_bins_below sdkman "$h/.sdkman/candidates/java" 4
    add_bins_below jenv "$h/.jenv/versions" 4
    add_bins_below asdf "$h/.asdf/installs/java" 4
    add_bins_below filesystem "$h/.gradle/jdks" 4
    add_bins_below filesystem "$h/.m2/jdks" 4
    add_bins_below filesystem "$h/.jdks" 4
    add_bins_below filesystem "$h/Library/Java/JavaVirtualMachines" 4
  done
  IFS=$old_ifs
}

# Which license text did this build ship with? Reads only the first 64 KB of
# the license files inside the Java home (no contents are copied into the JSON).
license_file_hint() {
  local home=$1 f
  for f in "$home/legal/java.base/LICENSE" "$home/LICENSE" "$home/jre/LICENSE" "$home/COPYRIGHT" "$home/jre/COPYRIGHT"; do
    [ -f "$f" ] && [ -r "$f" ] || continue
    if head -c 65536 "$f" | grep -q 'Oracle Technology Network License Agreement'; then printf 'OTN'; return; fi
    if head -c 65536 "$f" | grep -q 'No-Fee Terms and Conditions'; then printf 'NFTC'; return; fi
    if head -c 65536 "$f" | grep -q 'Binary Code License'; then printf 'BCL'; return; fi
    if head -c 65536 "$f" | grep -q 'GNU General Public License'; then printf 'GPL'; return; fi
  done
}

# ------------------------------------------------------ inspect one home ---
N_INSTALLS=0; N_ORACLE=0

inspect_home() {
  local home=$1 source=$2 vendor=$3
  local rel="$home/release" jv="" rv="" impl="" bt="" rn="" is_jre=false out rc line
  if [ -f "$rel" ] && [ -r "$rel" ]; then
    jv=$(release_value "$rel" JAVA_VERSION)
    rv=$(release_value "$rel" JAVA_RUNTIME_VERSION)
    impl=$(release_value "$rel" IMPLEMENTOR)
    bt=$(release_value "$rel" BUILD_TYPE)
  elif [ -f "$rel" ]; then
    warn "Not readable: $rel"
  fi
  # No usable release file: ask the binary itself (unless --no-exec).
  if [ -z "$jv" ]; then
    if [ "$NO_EXEC" -eq 1 ]; then
      warn "No release file and --no-exec given; version unknown: $home"
    else
      out="$TMP/java-version.out"
      run_with_timeout "$JAVA_VERSION_TIMEOUT" "$home/bin/java" -version </dev/null >"$out" 2>&1
      rc=$?
      [ "$rc" -eq 124 ] && warn "'java -version' timed out after ${JAVA_VERSION_TIMEOUT}s: $home"
      # Version line: java version "1.8.0_202"  |  openjdk version "21.0.4" 2024-07-16 LTS
      # (not always line 1: "Picked up JAVA_TOOL_OPTIONS: ..." can come first)
      jv=$(sed -n 's/^.* version "\([^"]*\)".*$/\1/p' "$out" | head -n 1)
      [ -n "$jv" ] || warn "Could not read a version from: $home/bin/java -version"
      line=$(grep -m 1 'Runtime Environment' "$out")
      case "$line" in
        *"Java(TM) SE Runtime Environment"*) rn="Java(TM) SE Runtime Environment" ;;
        *"OpenJDK Runtime Environment"*)     rn="OpenJDK Runtime Environment" ;;
      esac
      # Vendor only when the runtime line names it explicitly.
      case "$line" in
        *Temurin*)   impl="Eclipse Adoptium" ;;
        *Corretto*)  impl="Amazon.com Inc." ;;
        *Zulu*)      impl="Azul Systems, Inc." ;;
        *Microsoft*) impl="Microsoft" ;;
        *SapMachine*) impl="SAP SE" ;;
      esac
      rv=$(printf '%s' "$line" | sed -n 's/^.*(build \([^)]*\)).*$/\1/p')
    fi
  fi
  [ -n "$rv" ] || rv=$jv
  [ -n "$jv" ] || jv=unknown
  [ -n "$rv" ] || rv=unknown
  [ -n "$impl" ] || impl=unknown
  [ -f "$home/bin/javac" ] || is_jre=true
  local lic; lic=$(license_file_hint "$home")

  printf '{"path": %s, "source": %s, "javaVersion": %s, "rawVersion": %s, "implementor": %s, "buildType": %s, "runtimeName": %s, "isJre": %s, "packageVendor": %s, "licenseFile": %s}\n' \
    "$(json_str "$home")" "$(json_str "$source")" "$(json_str "$jv")" "$(json_str "$rv")" \
    "$(json_str "$impl")" "$(json_str_or_null "$bt")" "$(json_str_or_null "$rn")" \
    "$is_jre" "$(json_str_or_null "$vendor")" "$(json_str_or_null "$lic")" >>"$TMP/installs"

  # Summary count only ("built by Oracle"); license status is the report's job.
  N_INSTALLS=$((N_INSTALLS + 1))
  local oracle=0
  case "$rn" in *"Java(TM)"*) oracle=1 ;; esac
  [ "$bt" = commercial ] && oracle=1
  case "$impl" in *Oracle*) case "$rn" in *OpenJDK*) ;; *) oracle=1 ;; esac ;; esac
  N_ORACLE=$((N_ORACLE + oracle))
}

# Turn every candidate into a real Java home, drop duplicates, inspect it.
process_candidates() {
  local source type vendor path home parent tab
  tab=$(printf '\t')
  while IFS="$tab" read -r source type vendor path <&3; do
    if [ "$type" = bin ]; then
      home=$(real_path "$path")
      case "$home" in
        */bin/java) home=${home%/bin/java} ;;
        *) warn "Skipped $path: resolves to $home, which is not inside a Java home."; continue ;;
      esac
      [ -n "$home" ] || continue
    else
      home=$(real_path "$path")
    fi
    [ "$vendor" = "-" ] && vendor=""
    # A JDK 8 contains a jre/ subdirectory; report the JDK once, not twice.
    case "$home" in
      */jre) parent=${home%/jre}; [ -f "$parent/bin/java" ] && home=$parent ;;
    esac
    # macOS /usr/bin/java is Apple's stub; running it can pop up an install dialog.
    [ "$PLATFORM" = macos ] && [ "$home" = /usr ] && continue
    if [ ! -f "$home/bin/java" ]; then
      warn "Skipped $path (found via $source): no readable Java home at $home."
      continue
    fi
    grep -Fxq -- "$home" "$TMP/seen" && continue
    printf '%s\n' "$home" >>"$TMP/seen"
    inspect_home "$home" "$source" "$vendor"
  done 3<"$TMP/candidates"
}

# --------------------------------------------------------- repo scanning ---
# One awk pass per file. Prints: <line number> TAB <hint> TAB <matched line>.
cat >"$TMP/refs.awk" <<'AWK'
function emit(n, hint, text) {
  printf "%d\t%s\t%s\n", n, hint, substr(text, 1, maxtext)
}
{
  line = $0
  sub(/\r$/, "", line)
  gsub(/\t/, " ", line)
  low = tolower(line)
  if (kind == "github-actions") lines[NR] = line     # kept for the java-version lookup in END

  if (kind ~ /^(dockerfile|compose|k8s|gitlab-ci|github-actions)$/) {
    hint = ""
    if (low ~ /container-registry\.oracle\.com\/java\// || low ~ /store\/oracle\/serverjre/)
      hint = "oracle-image"
    else if (low ~ /^openjdk:/ || low ~ /[^a-z0-9._-]openjdk:/)
      hint = "openjdk-deprecated-image"      # Docker Hub "openjdk" official image
    else if (low ~ /eclipse-temurin|amazoncorretto|azul\/zulu|bellsoft\/liberica|mcr\.microsoft\.com\/openjdk|registry\.access\.redhat\.com\/ubi[0-9]*\/openjdk/)
      hint = "free-image"
    if (hint != "") { emit(NR, hint, line); next }
  }
  if (kind ~ /^(dockerfile|compose|k8s|gitlab-ci|github-actions|script)$/) {
    if (low ~ /download\.oracle\.com\/java|oracle\.com\/java\/technologies\/downloads/) {
      emit(NR, "oracle-download", line); next
    }
  }
  if (kind == "github-actions") {
    if (low ~ /actions\/setup-java/) setup_java = 1
    if (low ~ /^[ ]*-?[ ]*distribution:[ ]*["']?oracle["']?[ ]*(#.*)?$/) oracle_dist[NR] = 1
  }
  if (kind == "sdkman" && low ~ /^[ ]*java[ ]*=.*-oracle/) emit(NR, "oracle-sdkman", line)
  if (kind == "asdf" && low ~ /^[ ]*java[ ]+.*oracle/) emit(NR, "oracle-vendor", line)
  if (kind == "jenv" && line !~ /^[ ]*$/ && !jenv_done) {
    emit(NR, (low ~ /oracle/) ? "oracle-vendor" : "unknown", line); jenv_done = 1
  }
  if (kind == "gradle-toolchain" &&
      (low ~ /jvmvendorspec\.oracle/ || low ~ /vendor[ ]*(=|\.set[ ]*\()[ ]*(jvmvendorspec\.matching[ ]*\()?["']oracle/))
    emit(NR, "oracle-vendor", line)
  if (kind == "maven-toolchain" && low ~ /<vendor>[ ]*oracle[ ]*<\/vendor>/)
    emit(NR, "oracle-vendor", line)
}
END {
  # setup-java with distribution: oracle -> add a java-version found within 5 lines.
  if (!setup_java) exit
  for (n in oracle_dist) {
    text = lines[n]
    for (i = n - 5; i <= n + 5; i++)
      if (i > 0 && i <= NR && tolower(lines[i]) ~ /java-version/) {
        v = lines[i]; sub(/^[ -]+/, "", v); text = text " | " v; break
      }
    emit(n, "oracle-setup-java", text)
  }
}
AWK

N_REFS=0; N_ORACLE_REFS=0

scan_repo() {
  local root name f rel base kind n hint text tab
  tab=$(printf '\t')
  root=$(cd -P "$1" 2>/dev/null && pwd -P) || { warn "Repo not readable: $1"; return 0; }
  name=$(basename "$root")
  find "$root" \( -name .git -o -name node_modules -o -name target -o -name build \
      -o -name .gradle -o -name vendor \) -type d -prune -o -type f -size -1025k \
      \( -name 'Dockerfile*' -o -name '*.dockerfile' -o -name '*.yml' -o -name '*.yaml' \
      -o -name 'Jenkinsfile*' -o -name '*.sh' -o -name '*.ps1' -o -name .sdkmanrc \
      -o -name .tool-versions -o -name .java-version -o -name '*.gradle' \
      -o -name '*.gradle.kts' -o -name toolchains.xml -o -name pom.xml \) -print \
      2>/dev/null | sort >"$TMP/repofiles"
  while IFS= read -r f <&3; do
    [ -r "$f" ] || { warn "Not readable: $f"; continue; }
    grep -Iq . "$f" 2>/dev/null || continue          # skip binary and empty files
    rel=${f#"$root"/}
    base=$(basename "$f")
    case "$base" in
      Dockerfile*|*.dockerfile)                                     kind=dockerfile ;;
      docker-compose*.yml|docker-compose*.yaml|compose*.yml|compose*.yaml) kind=compose ;;
      .gitlab-ci.yml)                                               kind=gitlab-ci ;;
      *.yml|*.yaml)                                                 kind=k8s ;;
      Jenkinsfile*|*.sh|*.ps1)                                      kind=script ;;
      .sdkmanrc)                                                    kind=sdkman ;;
      .tool-versions)                                               kind=asdf ;;
      .java-version)                                                kind=jenv ;;
      *.gradle|*.gradle.kts)                                        kind=gradle-toolchain ;;
      *)                                                            kind=maven-toolchain ;;
    esac
    case "/$rel" in
      */.github/workflows/*.yml|*/.github/workflows/*.yaml) kind=github-actions ;;
    esac
    awk -v kind="$kind" -v maxtext="$MAX_TEXT" -f "$TMP/refs.awk" "$f" 2>/dev/null |
      sort -n >"$TMP/matches"
    while IFS="$tab" read -r n hint text <&4; do
      printf '{"file": %s, "line": %d, "kind": %s, "text": %s, "hint": %s}\n' \
        "$(json_str "$name/$rel")" "$n" "$(json_str "$kind")" "$(json_str "$text")" \
        "$(json_str "$hint")" >>"$TMP/refs"
      N_REFS=$((N_REFS + 1))
      case "$hint" in oracle-*) N_ORACLE_REFS=$((N_ORACLE_REFS + 1)) ;; esac
    done 4<"$TMP/matches"
  done 3<"$TMP/repofiles"
}

# ------------------------------------------------------------------ main ---
: >"$TMP/autoupdate"
if [ "$NO_SYSTEM" -eq 0 ]; then
  log "Looking for Java runtimes (read-only, no network)..."
  if [ "$NO_SYSTEM_DEFAULTS" != 1 ]; then
    # Priority for "source": package database > tool manager > running process
    # > PATH/JAVA_HOME > plain folder search.
    [ "$PLATFORM" = linux ] && discover_packages
    [ "$PLATFORM" = macos ] && discover_homebrew
    discover_user_homes
    discover_processes
    discover_path_and_java_home
    if [ "$PLATFORM" = macos ]; then discover_macos; else discover_linux; fi
  fi
  if [ -n "$EXTRA_JVM_DIRS" ]; then
    old_ifs=$IFS; IFS=:
    for d in $EXTRA_JVM_DIRS; do IFS=$old_ifs; add_bins_below filesystem "$d" 4; done
    IFS=$old_ifs
  fi
  process_candidates
fi

if [ "$REPO_COUNT" -gt 0 ]; then
  for r in "${REPOS[@]}"; do
    log "Scanning repo: $r"
    scan_repo "$r"
  done
fi

HOSTNAME_VALUE=$(hostname 2>/dev/null || uname -n)
if [ "$ANONYMIZE" -eq 1 ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    HOSTNAME_VALUE=$(printf '%s' "$HOSTNAME_VALUE" | sha256sum | cut -c1-12)
  elif command -v shasum >/dev/null 2>&1; then
    HOSTNAME_VALUE=$(printf '%s' "$HOSTNAME_VALUE" | shasum -a 256 | cut -c1-12)
  else
    HOSTNAME_VALUE=anonymous
    warn "--anonymize: no sha256 tool found; hostname replaced with 'anonymous'."
  fi
fi

if [ "$PLATFORM" = macos ]; then
  OS_NAME="$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
else
  # Parsed, not sourced: /etc/os-release is never executed.
  OS_NAME=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  [ -n "$OS_NAME" ] || OS_NAME=$(uname -sr)
fi
ARCH=$(uname -m)
SCANNED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$OUT" ] || OUT="./runtimeclear-scan-$HOSTNAME_VALUE-$(date -u +%Y%m%dT%H%M%SZ).json"

# Print a JSON array from a temp file that holds one JSON value per line.
json_array() {
  awk 'NR == 1 { printf "[\n" } NR > 1 { printf ",\n" } { printf "    %s", $0 }
       END { if (NR > 0) printf "\n  ]"; else printf "[]" }' "$1"
}

: >"$TMP/warnings.json"
while IFS= read -r w <&3; do json_str "$w" >>"$TMP/warnings.json"; printf '\n' >>"$TMP/warnings.json"; done 3<"$TMP/warnings"

{
  printf '{\n'
  printf '  "schema": "%s",\n' "$SCHEMA"
  printf '  "scanner": {"name": "runtimeclear", "version": "%s", "platform": "%s"},\n' "$VERSION" "$PLATFORM"
  printf '  "scannedAt": "%s",\n' "$SCANNED_AT"
  printf '  "host": {"hostname": %s, "os": %s, "arch": %s},\n' \
    "$(json_str "$HOSTNAME_VALUE")" "$(json_str "$OS_NAME")" "$(json_str "$ARCH")"
  printf '  "installs": %s,\n' "$(json_array "$TMP/installs")"
  printf '  "references": %s,\n' "$(json_array "$TMP/refs")"
  printf '  "autoUpdate": %s,\n' "$(json_array "$TMP/autoupdate")"
  printf '  "warnings": %s\n' "$(json_array "$TMP/warnings.json")"
  printf '}\n'
} >"$OUT" || die "cannot write $OUT"

N_WARN=$(wc -l <"$TMP/warnings" | tr -d ' ')
log ""
log "RuntimeClear scan complete."
log "  Java runtimes found:         $N_INSTALLS"
log "  Built by Oracle:             $N_ORACLE  (Oracle JDK/JRE and Oracle's own OpenJDK builds)"
log "  Oracle references in repos:  $N_ORACLE_REFS  (of $N_REFS references recorded)"
log "  Warnings:                    $N_WARN"
log "  Output:                      $OUT"
log ""
log "Load the JSON at $SITE_URL/report - it's processed in your browser, nothing is uploaded."
exit 0
