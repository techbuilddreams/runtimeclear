#!/usr/bin/env bash
# shellcheck disable=SC2016  # checks use sh -c '...' _ "$arg" on purpose
# tests/run.sh - end-to-end tests for runtimeclear.sh using fake Java homes and a
# fake repo built in a temp dir. Needs: bash, python3. Optional: strace, pwsh.
#
#   bash tests/run.sh            run all tests
#   bash tests/run.sh --update-example   also refresh examples/sample-scan-linux.json
#   RUNTIMECLEAR_TEST_PWSH=0 bash tests/run.sh   skip the pwsh parity tests even if pwsh exists
#
# Runs on Linux and on macOS with the stock /bin/bash 3.2.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
SCANNER="$HERE/../runtimeclear.sh"
EXAMPLE="$HERE/../examples/sample-scan-linux.json"
UPDATE_EXAMPLE=0; [ "${1:-}" = "--update-example" ] && UPDATE_EXAMPLE=1

# Resolve symlinks in the temp path (macOS: /var -> /private/var) so it matches the
# real paths the scanner reports.
FIX=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$FIX"' EXIT
case "$(uname -s)" in Darwin) PLATFORM=macos ;; *) PLATFORM=linux ;; esac
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
# Run a python3 check script from stdin; it prints "  ok   ..." / "  FAIL ..." lines.
py_checks() {
  python3 - "$@" >"$FIX/py.out" 2>&1
  cat "$FIX/py.out"
  PASS=$((PASS + $(grep -c '^  ok ' "$FIX/py.out")))
  FAIL=$((FAIL + $(grep -c -v '^  ok ' "$FIX/py.out")))
}

# ------------------------------------------------------------- fixtures ---
MARKER="$FIX/java-was-executed"
# make_home <dir> <jdk|jre> [release lines...]  (no release lines = no release file)
make_home() {
  local dir="$FIX/jvm/$1" type=$2; shift 2
  mkdir -p "$dir/bin"
  # This stub must never run: the scanner reads `release` instead.
  printf '#!/bin/sh\necho "%s" >>"%s"\n' "$dir" "$MARKER" >"$dir/bin/java"
  chmod +x "$dir/bin/java"
  [ "$type" = jdk ] && : >"$dir/bin/javac"
  if [ $# -gt 0 ]; then printf '%s\n' "$@" >"$dir/release"; fi
}
make_home jdk-21-oracle-x64 jdk 'IMPLEMENTOR="Oracle Corporation"' \
  'JAVA_RUNTIME_VERSION="21.0.4+8-LTS-274"' 'JAVA_VERSION="21.0.4"' 'BUILD_TYPE="commercial"'
mkdir -p "$FIX/jvm/jdk-21-oracle-x64/legal/java.base" && printf 'Oracle No-Fee Terms and Conditions (NFTC)\n' >"$FIX/jvm/jdk-21-oracle-x64/legal/java.base/LICENSE"
make_home jdk1.8.0_202 jdk 'JAVA_VERSION="1.8.0_202"' 'OS_NAME="Linux"' 'BUILD_TYPE="commercial"'
mkdir -p "$FIX/jvm/jdk1.8.0_202/jre/bin" && cp "$FIX/jvm/jdk1.8.0_202/bin/java" "$FIX/jvm/jdk1.8.0_202/jre/bin/java"
make_home jre1.8.0_351 jre 'JAVA_VERSION="1.8.0_351"' 'IMPLEMENTOR="Oracle Corporation"' 'BUILD_TYPE="commercial"'
make_home jdk-17-oracle-x64 jdk 'IMPLEMENTOR="Oracle Corporation"' \
  'JAVA_RUNTIME_VERSION="17.0.13+10-LTS-268"' 'JAVA_VERSION="17.0.13"' 'BUILD_TYPE="commercial"'
make_home temurin-21-jdk-amd64 jdk 'IMPLEMENTOR="Eclipse Adoptium"' \
  'IMPLEMENTOR_VERSION="Temurin-21.0.4+7"' 'JAVA_RUNTIME_VERSION="21.0.4+7-LTS"' 'JAVA_VERSION="21.0.4"'
make_home java-17-amazon-corretto jdk 'IMPLEMENTOR="Amazon.com Inc."' \
  'JAVA_RUNTIME_VERSION="17.0.12+7-LTS"' 'JAVA_VERSION="17.0.12"'
printf 'IMPLEMENTOR="Oracle Corporation"\r\nJAVA_VERSION="21"\r\nJAVA_RUNTIME_VERSION="21+35-2513"\r\n' >"$FIX/release-crlf"
make_home jdk-21 jdk && mv "$FIX/release-crlf" "$FIX/jvm/jdk-21/release"   # Oracle OpenJDK (jdk.java.net), CRLF
# Bundled JRE without a release file: the scanner has to run its java -version.
mkdir -p "$FIX/jvm/legacyapp/jre/bin"
cat >"$FIX/jvm/legacyapp/jre/bin/java" <<'EOF'
#!/bin/sh
echo 'Picked up JAVA_TOOL_OPTIONS: -Dfile.encoding=UTF-8' >&2
echo 'java version "1.8.0_391"' >&2
echo 'Java(TM) SE Runtime Environment (build 1.8.0_391-b13)' >&2
echo 'Java HotSpot(TM) 64-Bit Server VM (build 25.391-b13, mixed mode)' >&2
EOF
chmod +x "$FIX/jvm/legacyapp/jre/bin/java"
ln -s jdk-21-oracle-x64 "$FIX/jvm/default"            # duplicate via symlink

# Second fixture set: a hanging java, and a path that needs JSON escaping.
mkdir -p "$FIX/jvm2/hang-jdk/bin"
printf '#!/bin/sh\nsleep 30\n' >"$FIX/jvm2/hang-jdk/bin/java"; chmod +x "$FIX/jvm2/hang-jdk/bin/java"
W="$FIX/jvm2/odd \"name\" \\ dir"
mkdir -p "$W/bin" && : >"$W/bin/java" && chmod +x "$W/bin/java"
printf 'JAVA_VERSION="11.0.24"\nIMPLEMENTOR="Azul Systems, Inc."\n' >"$W/release"

# Fake repo.
R="$FIX/repo"
mkdir -p "$R/docker" "$R/k8s" "$R/.github/workflows" "$R/scripts" "$R/node_modules/pkg" "$R/build"
printf 'FROM container-registry.oracle.com/java/jdk:21\nRUN curl -LO https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz\nCMD ["java","-jar","app.jar"]\n' >"$R/Dockerfile"
printf 'FROM openjdk:17-jdk-slim\n' >"$R/docker/app.dockerfile"
printf 'services:\n  app:\n    image: eclipse-temurin:21-jre\n' >"$R/docker-compose.yml"
printf 'spec:\n  containers:\n    - image: "openjdk:11"\n    - image: mcr.microsoft.com/openjdk/jdk:21-ubuntu\n    - image: azul/zulu-openjdk:17\n' >"$R/k8s/deployment.yaml"
cat >"$R/.github/workflows/build.yml" <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/setup-java@v4
        with:
          distribution: 'oracle'
          java-version: '21'
EOF
printf 'build:\n  image: store/oracle/serverjre:8\n' >"$R/.gitlab-ci.yml"
printf "sh 'wget https://www.oracle.com/java/technologies/downloads/#java8'\n" >"$R/Jenkinsfile"
printf '#!/bin/sh\n# tab\there "quoted" back\\slash \377 bad-byte\nwget https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.tar.gz\n' >"$R/scripts/install.sh"
printf 'java=21.0.4-oracle\n' >"$R/.sdkmanrc"
printf 'nodejs 20.1.0\njava oracle-21.0.4\n' >"$R/.tool-versions"
printf '21\n' >"$R/.java-version"
printf 'java {\n  toolchain {\n    languageVersion = JavaLanguageVersion.of(21)\n    vendor = JvmVendorSpec.ORACLE\n  }\n}\n' >"$R/build.gradle"
printf '<toolchain><provides><version>21</version><vendor>oracle</vendor></provides></toolchain>\n' >"$R/pom.xml"
# Must all be ignored: skipped dirs, oversized file, binary file.
printf 'FROM container-registry.oracle.com/java/jdk:21\n' >"$R/node_modules/pkg/Dockerfile"
printf 'FROM container-registry.oracle.com/java/jdk:21\n' >"$R/build/Dockerfile"
{ printf 'image: container-registry.oracle.com/java/jdk:21\n'; head -c 1100000 /dev/zero | tr '\0' 'x'; } >"$R/big.yml"
printf 'download.oracle.com/java\000\001\002' >"$R/scripts/binary.sh"

# ----------------------------------------------------------------- run ---
OUT="$FIX/scan.json"
echo "Test 1: fixture scan"
RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm" \
  bash "$SCANNER" --repo "$R" --out "$OUT" 2>"$FIX/stderr1"
check "exit code 0" [ $? -eq 0 ]
check "valid JSON (python3 -m json.tool)" sh -c 'python3 -m json.tool "$1" >/dev/null' _ "$OUT"
check "summary: 8 runtimes" grep -q 'Java runtimes found: *8$' "$FIX/stderr1"
check "summary: 6 built by Oracle" grep -q 'Built by Oracle: *6 ' "$FIX/stderr1"
check "summary: 10 Oracle references" grep -q 'Oracle references in repos: *10 ' "$FIX/stderr1"
check "no java executed for homes with a release file" [ ! -e "$MARKER" ]

py_checks "$OUT" "$FIX" "$PLATFORM" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); fix = sys.argv[2]; platform = sys.argv[3]
fails = 0
def t(name, cond):
    global fails
    print(("  ok   " if cond else "  FAIL ") + name)
    fails += 0 if cond else 1
t("top-level keys exactly per schema", list(d) == ["schema","scanner","scannedAt","host","installs","references","autoUpdate","warnings"])
t("schema id", d["schema"] == "runtimeclear.scan/v1")
t("scanner block", d["scanner"] == {"name":"runtimeclear","version":"1.0.1","platform":platform})
keys = ["path","source","javaVersion","rawVersion","implementor","buildType","runtimeName","isJre","packageVendor","licenseFile"]
t("every install has exactly the schema keys", all(list(i) == keys for i in d["installs"]))
by = {i["path"].replace(fix + "/jvm/", ""): i for i in d["installs"]}
t("8 installs, de-duplicated (symlink + JDK8 jre/ folded)", sorted(by) == sorted([
  "jdk-21-oracle-x64","jdk1.8.0_202","jre1.8.0_351","jdk-17-oracle-x64","temurin-21-jdk-amd64",
  "java-17-amazon-corretto","jdk-21","legacyapp/jre"]))
o = by.get("jdk-21-oracle-x64", {})
t("oracle 21: version/raw/implementor/buildType", (o.get("javaVersion"), o.get("rawVersion"), o.get("implementor"), o.get("buildType")) == ("21.0.4","21.0.4+8-LTS-274","Oracle Corporation","commercial"))
t("oracle 21: runtimeName null (from release), isJre false, packageVendor null", o.get("runtimeName") is None and o.get("isJre") is False and o.get("packageVendor") is None)
t("oracle 21: licenseFile NFTC from legal/java.base/LICENSE", o.get("licenseFile") == "NFTC")
e = by.get("jdk1.8.0_202", {})
t("8u202: raw version kept, implementor unknown", (e.get("javaVersion"), e.get("rawVersion"), e.get("implementor"), e.get("buildType")) == ("1.8.0_202","1.8.0_202","unknown","commercial"))
t("8u351 JRE: isJre true", by.get("jre1.8.0_351", {}).get("isJre") is True)
t("17.0.13 oracle commercial", by.get("jdk-17-oracle-x64", {}).get("buildType") == "commercial")
tm = by.get("temurin-21-jdk-amd64", {})
t("temurin: implementor, buildType null", tm.get("implementor") == "Eclipse Adoptium" and tm.get("buildType") is None)
t("corretto: 17.0.12", by.get("java-17-amazon-corretto", {}).get("javaVersion") == "17.0.12")
oj = by.get("jdk-21", {})
t("oracle openjdk (CRLF release): no buildType, CR stripped", (oj.get("javaVersion"), oj.get("rawVersion"), oj.get("implementor"), oj.get("buildType")) == ("21","21+35-2513","Oracle Corporation",None))
lg = by.get("legacyapp/jre", {})
t("no-release JRE: parsed from java -version", (lg.get("javaVersion"), lg.get("rawVersion"), lg.get("runtimeName"), lg.get("isJre")) == ("1.8.0_391","1.8.0_391-b13","Java(TM) SE Runtime Environment",True))
t("all sources = filesystem", all(i["source"] == "filesystem" for i in d["installs"]))

refs = {(r["file"].split("/",1)[1], r["line"], r["kind"], r["hint"]) for r in d["references"]}
expected = {
  ("Dockerfile",1,"dockerfile","oracle-image"), ("Dockerfile",2,"dockerfile","oracle-download"),
  ("docker/app.dockerfile",1,"dockerfile","openjdk-deprecated-image"),
  ("docker-compose.yml",3,"compose","free-image"),
  ("k8s/deployment.yaml",3,"k8s","openjdk-deprecated-image"), ("k8s/deployment.yaml",4,"k8s","free-image"),
  ("k8s/deployment.yaml",5,"k8s","free-image"),
  (".github/workflows/build.yml",6,"github-actions","oracle-setup-java"),
  (".gitlab-ci.yml",2,"gitlab-ci","oracle-image"), ("Jenkinsfile",1,"script","oracle-download"),
  ("scripts/install.sh",3,"script","oracle-download"), (".sdkmanrc",1,"sdkman","oracle-sdkman"),
  (".tool-versions",2,"asdf","oracle-vendor"), (".java-version",1,"jenv","unknown"),
  ("build.gradle",4,"gradle-toolchain","oracle-vendor"), ("pom.xml",1,"maven-toolchain","oracle-vendor"),
}
t("references: exactly the 16 expected (file, line, kind, hint)", refs == expected)
if refs != expected:
    print("  FAIL missing:", sorted(expected - refs)); print("  FAIL extra:", sorted(refs - expected))
t("skipped node_modules/, build/, >1MB and binary files", not any(x in r["file"] for r in d["references"] for x in ("node_modules","/build/","big.yml","binary.sh")))
t("file paths are prefixed with the repo folder name", all(r["file"].startswith("repo/") for r in d["references"]))
gh = [r for r in d["references"] if r["hint"] == "oracle-setup-java"]
t("setup-java text includes nearby java-version", bool(gh) and "java-version: '21'" in gh[0]["text"])
t("every reference has exactly the schema keys", all(list(r) == ["file","line","kind","text","hint"] for r in d["references"]))
t("autoUpdate is an empty array (no system locations scanned)", d["autoUpdate"] == [])
t("no warnings", d["warnings"] == [])
sys.exit(1 if fails else 0)
PY

echo "Test 2: timeout, JSON escaping, --anonymize, default output name"
mkdir -p "$FIX/cwd"
START=$(date +%s)
( cd "$FIX/cwd" && RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm2" \
    bash "$SCANNER" --anonymize --quiet 2>"$FIX/stderr2" )
ELAPSED=$(( $(date +%s) - START ))
OUT2=""; for f in "$FIX"/cwd/runtimeclear-scan-*.json; do OUT2=$f; done
check "default output name runtimeclear-scan-<12hex>-<UTC>.json" \
  sh -c "basename '$OUT2' | grep -Eq '^runtimeclear-scan-[0-9a-f]{12}-[0-9]{8}T[0-9]{6}Z\.json$'"
check "--quiet prints nothing" [ ! -s "$FIX/stderr2" ]
check "hanging java killed within ~5s (took ${ELAPSED}s)" [ "$ELAPSED" -le 9 ]
py_checks "$OUT2" <<'PY'
import json, sys, re, socket, hashlib
d = json.load(open(sys.argv[1]))
ok = True
def t(n, c):
    global ok; print(("  ok   " if c else "  FAIL ") + n); ok = ok and c
t("hostname anonymized to sha256 prefix", d["host"]["hostname"] == hashlib.sha256(socket.gethostname().encode()).hexdigest()[:12])
odd = [i for i in d["installs"] if "odd" in i["path"]]
t("path with quote and backslash round-trips", bool(odd) and odd[0]["path"].endswith('odd "name" \\ dir'))
hang = [i for i in d["installs"] if i["path"].endswith("hang-jdk")]
t("hanging java: version unknown", bool(hang) and hang[0]["javaVersion"] == "unknown" and hang[0]["runtimeName"] is None)
t("timeout reported in warnings", any("timed out" in w for w in d["warnings"]))
sys.exit(0 if ok else 1)
PY

echo "Test 3: --no-exec, --no-system, option errors"
RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm" bash "$SCANNER" --no-exec --quiet --out "$FIX/noexec.json"
check "--no-exec: legacy JRE version unknown + warning" python3 -c "
import json,sys; d=json.load(open('$FIX/noexec.json'))
j=[i for i in d['installs'] if i['path'].endswith('legacyapp/jre')][0]
sys.exit(0 if j['javaVersion']=='unknown' and any('--no-exec' in w for w in d['warnings']) else 1)"
RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm" bash "$SCANNER" --no-system --repo "$R" --quiet --out "$FIX/nosys.json"
check "--no-system: installs is [] and references still found" python3 -c "
import json,sys; d=json.load(open('$FIX/nosys.json')); sys.exit(0 if d['installs']==[] and len(d['references'])==16 else 1)"
bash "$SCANNER" --bogus >/dev/null 2>&1; check "unknown option exits 2" [ $? -eq 2 ]
bash "$SCANNER" --repo "$FIX/does-not-exist" >/dev/null 2>&1; check "missing --repo dir exits 2" [ $? -eq 2 ]
bash "$SCANNER" --help | grep -q -- '--anonymize'; check "--help lists flags" [ $? -eq 0 ]
check "--version" sh -c "bash '$SCANNER' --version | grep -q '^runtimeclear 1.0.1$'"

echo "Test 4: fallback timeout without GNU 'timeout' (macOS code path)"
if [ "$(uname -s)" = Linux ]; then
  mkdir -p "$FIX/notimeout"
  for f in /usr/bin/* /bin/*; do
    n=$(basename "$f"); [ "$n" = timeout ] || [ -e "$FIX/notimeout/$n" ] || ln -s "$f" "$FIX/notimeout/$n"
  done
  START=$(date +%s)
  PATH="$FIX/notimeout" RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm2:$FIX/jvm" \
    bash "$SCANNER" --quiet --out "$FIX/notimeout.json"
  ELAPSED=$(( $(date +%s) - START ))
  check "background+kill timeout works (took ${ELAPSED}s)" [ "$ELAPSED" -le 9 ]
  check "fallback run still parses java -version" python3 -c "
import json,sys; d=json.load(open('$FIX/notimeout.json'))
sys.exit(0 if any(i['javaVersion']=='1.8.0_391' for i in d['installs']) and any('timed out' in w for w in d['warnings']) else 1)"
else
  echo "  skip (not Linux)"
fi

echo "Test 5: no network syscalls, full system scan (strace)"
if command -v strace >/dev/null 2>&1 && strace -f -o /dev/null true 2>/dev/null; then
  strace -f -e trace=connect,sendto,socket -o "$FIX/strace.txt" bash "$SCANNER" --repo "$R" --quiet --out "$FIX/real.json"
  check "no socket()/connect() calls to AF_INET/AF_INET6" sh -c "! grep -E 'AF_INET6?' '$FIX/strace.txt'"
  check "real system scan is valid JSON" sh -c 'python3 -m json.tool "$1" >/dev/null' _ "$FIX/real.json"
else
  echo "  skip (strace not available)"
fi

echo "Test 6: runtimeclear.ps1 under pwsh gives the same results as runtimeclear.sh"
if [ "${RUNTIMECLEAR_TEST_PWSH:-1}" = 0 ]; then
  echo "  skip (RUNTIMECLEAR_TEST_PWSH=0)"
elif command -v pwsh >/dev/null 2>&1; then
  PS1="$HERE/../runtimeclear.ps1"
  check "ps1 parses without errors" sh -c "pwsh -NoProfile -Command '\$t=\$null;\$e=\$null;[void][System.Management.Automation.Language.Parser]::ParseFile(\"$PS1\",[ref]\$t,[ref]\$e); exit \$e.Count'"
  # Crude guard against PowerShell 7-only syntax (?? ?. ternary, && || chains, -Parallel).
  check "ps1 has no PS7-only operators" sh -c "! grep -nE '\\?\\?|\\?\\.|\\) \\? |&&|\\|\\||-Parallel|\\bclean \\{' '$PS1'"
  RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm" \
    pwsh -NoProfile -File "$PS1" -Repo "$R" -Out "$FIX/ps.json" 2>"$FIX/stderr-ps"
  check "ps1 exit code 0" [ $? -eq 0 ]
  check "ps1 summary: 8 runtimes, 6 Oracle, 10 Oracle refs" sh -c "grep -q 'Java runtimes found: *8$' '$FIX/stderr-ps' && grep -q 'Built by Oracle: *6 ' '$FIX/stderr-ps' && grep -q 'Oracle references in repos: *10 ' '$FIX/stderr-ps'"
  py_checks "$OUT" "$FIX/ps.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); p = json.load(open(sys.argv[2]))
def t(n, c): print(("  ok   " if c else "  FAIL ") + n)
t("ps1: top-level keys per schema", list(p) == list(b))
t("ps1: platform windows", p["scanner"] == {"name":"runtimeclear","version":"1.0.1","platform":"windows"})
t("ps1: host has hostname/os/arch", list(p["host"]) == ["hostname","os","arch"])
key = lambda i: i["path"]
t("ps1: installs identical to bash (all fields)", sorted(p["installs"], key=key) == sorted(b["installs"], key=key))
if sorted(p["installs"], key=key) != sorted(b["installs"], key=key):
    for x, y in zip(sorted(p["installs"], key=key), sorted(b["installs"], key=key)):
        if x != y: print("  FAIL  ps1:", x, "\n  FAIL bash:", y)
rk = lambda r: (r["file"], r["line"], r["kind"], r["hint"])
t("ps1: references identical to bash (file, line, kind, hint)", sorted(map(rk, p["references"])) == sorted(map(rk, b["references"])))
bt = {rk(r): r["text"] for r in b["references"]}
same_text = all(bt.get(rk(r)) == r["text"] for r in p["references"] if "install.sh" not in r["file"])
t("ps1: matched text identical (except invalid-UTF-8 test line)", same_text)
t("ps1: arrays stay arrays", all(isinstance(p[k], list) for k in ("installs","references","autoUpdate","warnings")))
PY
  RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm/jdk-21" \
    pwsh -NoProfile -File "$PS1" -Quiet -Anonymize -Out "$FIX/ps1.json"
  check "ps1: single install and empty arrays serialize as arrays" python3 -c "
import json,sys; d=json.load(open('$FIX/ps1.json'))
sys.exit(0 if isinstance(d['installs'],list) and len(d['installs'])==1 and d['references']==[] and d['warnings']==[] and len(d['host']['hostname'])==12 else 1)"
  # Windows forbids " and \ in names, so the ps1 gets its own odd (but legal) name.
  W3="$FIX/jvm3/odd 'name' [x] & \$y"
  mkdir -p "$W3/bin" "$FIX/jvm3/hang-jdk" && : >"$W3/bin/java" && printf 'JAVA_VERSION="11.0.24"\n' >"$W3/release"
  cp -r "$FIX/jvm2/hang-jdk/bin" "$FIX/jvm3/hang-jdk/"
  RUNTIMECLEAR_NO_SYSTEM_DEFAULTS=1 RUNTIMECLEAR_EXTRA_JVM_DIRS="$FIX/jvm3" \
    pwsh -NoProfile -File "$PS1" -Quiet -Out "$FIX/ps2.json"
  check "ps1: timeout + odd folder name ([ ] ' & \$)" python3 -c "
import json,sys; d=json.load(open('$FIX/ps2.json'))
sys.exit(0 if any(i['path'].endswith(\"odd 'name' [x] & \$y\") and i['javaVersion']=='11.0.24' for i in d['installs']) and any('timed out' in w for w in d['warnings']) else 1)"
else
  echo "  skip (pwsh not installed)"
fi

echo "Test 7: example files and fixture output match the v1 schema (keys, types, enums)"
py_checks "$HERE/../examples/sample-scan-linux.json" "$HERE/../examples/sample-scan-windows.json" "$OUT" <<'PY'
import json, sys
SOURCES = {"filesystem","path","rpm","dpkg","registry","sdkman","homebrew","jenv","asdf","process"}
KINDS = {"dockerfile","compose","k8s","github-actions","gitlab-ci","sdkman","asdf","jenv","gradle-toolchain","maven-toolchain","script"}
HINTS = {"oracle-image","oracle-setup-java","oracle-sdkman","oracle-vendor","openjdk-deprecated-image","free-image","unknown",
         "oracle-download"}   # oracle-download: scanner addition, see README
def errors(d):
    e = []
    if list(d) != ["schema","scanner","scannedAt","host","installs","references","autoUpdate","warnings"]: e.append("top keys")
    if d["schema"] != "runtimeclear.scan/v1": e.append("schema")
    if d["scanner"]["platform"] not in ("linux","macos","windows"): e.append("platform")
    for i in d["installs"]:
        if i["source"] not in SOURCES: e.append("source " + i["source"])
        if not all(isinstance(i[k], str) for k in ("path","javaVersion","rawVersion","implementor")): e.append("install strings")
        if i["buildType"] is not None and not isinstance(i["buildType"], str): e.append("buildType")
        if i["runtimeName"] not in (None, "Java(TM) SE Runtime Environment", "OpenJDK Runtime Environment"): e.append("runtimeName")
        if not isinstance(i["isJre"], bool): e.append("isJre")
    for r in d["references"]:
        if r["kind"] not in KINDS or r["hint"] not in HINTS or not isinstance(r["line"], int): e.append("ref %r" % r)
    for a in d["autoUpdate"]:
        if list(a) != ["kind","enabled","detail"] or a["enabled"] not in (True, False, None): e.append("autoUpdate")
    if not all(isinstance(w, str) for w in d["warnings"]): e.append("warnings")
    return e
for f in sys.argv[1:]:
    errs = errors(json.load(open(f)))
    print(("  ok   " if not errs else "  FAIL ") + "schema: " + f.split("/")[-1] + ("" if not errs else " " + "; ".join(errs)))
PY

if [ "$UPDATE_EXAMPLE" -eq 1 ]; then
  # Example for docs/demo: fixture paths shown as typical install locations.
  sed -e "s#$FIX/jvm/legacyapp/jre#/opt/legacyapp/jre#g" -e "s#$FIX/jvm/jdk-21\"#/opt/jdk-21\"#g" \
      -e "s#$FIX/jvm/#/usr/lib/jvm/#g" \
      -e 's#"file": "repo/#"file": "billing-service/#' \
      -e 's#"hostname": "[^"]*"#"hostname": "app-prod-03"#' -e 's#"os": "[^"]*"#"os": "Red Hat Enterprise Linux 9.4 (Plow)"#' \
      "$OUT" >"$EXAMPLE"
  python3 -m json.tool "$EXAMPLE" >/dev/null && echo "  updated $EXAMPLE"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
