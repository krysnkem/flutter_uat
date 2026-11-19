#!/usr/bin/env bash
# flutter-uat bootstrap: discover what a Flutter project needs, check the host, write `.uat`.
#
#   bootstrap.sh [--root DIR] [--write | --check [--quiet] | --sdk]
#
#   (default)  print the discovery report and the .uat block it WOULD write (changes nothing)
#   --write    create/refresh the generated block in <root>/.uat (lines outside it are kept)
#   --check    compare the stored d.* fields with what the project says now.
#              exit 0 fresh | 1 stale | 3 never bootstrapped. --quiet prints only problems.
#   --sdk      print the Flutter binary to use for this project (pin, else global) and exit
#
# Data only: nothing is executed from .uat. Machine-specific values (SDK path, device serials)
# are reported but never written, because .uat is meant to be committed.
set -u

MODE=show; ROOT=""; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --write) MODE=write; shift ;;
    --check) MODE=check; shift ;;
    --sdk)   MODE=sdk; shift ;;
    --quiet) QUIET=1; shift ;;
    --root)  ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  d="$PWD"; while [ "$d" != "/" ] && [ ! -f "$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done; ROOT="$d"
fi
[ -f "$ROOT/pubspec.yaml" ] || { [ "$QUIET" = 1 ] || echo "no pubspec.yaml found from $PWD (not a Flutter project)" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"; cd "$ROOT" || exit 2
UAT="$ROOT/.uat"

join() { paste -sd, - ; }
ver_lt() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){if(x[i]+0<y[i]+0){print 1;exit} if(x[i]+0>y[i]+0){print 0;exit}} print 0}'; }

# ---- discovery -----------------------------------------------------------------------
APPG=""; for g in android/app/build.gradle.kts android/app/build.gradle; do [ -f "$g" ] && { APPG="$g"; break; }; done

PKG=""
if [ -n "$APPG" ]; then
  PKG="$(grep -E 'applicationId' "$APPG" | grep -v applicationIdSuffix | head -1 | sed -nE "s/.*[\"']([A-Za-z0-9_.]+)[\"'].*/\1/p")"
  [ -z "$PKG" ] && PKG="$(grep -E 'namespace' "$APPG" | head -1 | sed -nE "s/.*[\"']([A-Za-z0-9_.]+)[\"'].*/\1/p")"
fi

FLAVORS=""
[ -n "$APPG" ] && FLAVORS="$(awk '
  BEGIN { on=0; depth=0; started=0 }
  /productFlavors/ && on==0 { on=1 }
  on==1 {
    line=$0
    if (started==1 && depth==1 && match(line, /^[ \t]*(create\(")?[A-Za-z0-9_]+("\))?[ \t]*\{/)) {
      s=substr(line, RSTART, RLENGTH); gsub(/create\("|"\)|[ \t{]/, "", s); print s
    }
    o=gsub(/\{/, "{", line)
    c=gsub(/\}/, "}", line)
    depth=depth+o-c
    if (o>0) { started=1 }
    if (started==1 && depth<=0) { exit }
  }' "$APPG" | join)"

PIN=""
[ -f .fvmrc ] && PIN="$(sed -nE 's/.*"flutter"[ ]*:[ ]*"([^"]+)".*/\1/p' .fvmrc | head -1)"
[ -z "$PIN" ] && [ -f .fvm/fvm_config.json ] && PIN="$(sed -nE 's/.*"flutterSdkVersion"[ ]*:[ ]*"([^"]+)".*/\1/p' .fvm/fvm_config.json | head -1)"

SDKBIN=""; SDKNOTE=""
if [ -n "$PIN" ]; then
  for c in "$HOME/fvm/versions/$PIN/bin/flutter" "$HOME/.fvm/versions/$PIN/bin/flutter" "$ROOT/.fvm/flutter_sdk/bin/flutter"; do
    [ -x "$c" ] && { SDKBIN="$c"; break; }
  done
  [ -z "$SDKBIN" ] && SDKNOTE="pinned SDK $PIN is not installed here (a committed .fvm/flutter_sdk symlink may point into another user's home)"
fi
if [ -z "$SDKBIN" ]; then
  g="$(command -v flutter || true)"
  if [ -n "$g" ]; then SDKBIN="$g"; [ -n "$SDKNOTE" ] && SDKNOTE="$SDKNOTE; falling back to the global one"; fi
fi
[ "$MODE" = sdk ] && { [ -n "$SDKBIN" ] && { echo "$SDKBIN"; exit 0; } || { echo "no Flutter SDK found" >&2; exit 1; }; }

FV=""; DV=""
if [ -n "$SDKBIN" ]; then
  real="$(perl -MCwd=realpath -e 'print realpath(shift)' "$SDKBIN" 2>/dev/null)"; [ -z "$real" ] && real="$SDKBIN"
  SROOT="$(dirname "$(dirname "$real")")"
  FV="$(sed -nE 's/.*"frameworkVersion"[ ]*:[ ]*"([^"]+)".*/\1/p' "$SROOT/bin/cache/flutter.version.json" 2>/dev/null | head -1)"
  [ -z "$FV" ] && FV="$(head -1 "$SROOT/version" 2>/dev/null)"
  DV="$(head -1 "$SROOT/bin/cache/dart-sdk/version" 2>/dev/null)"
fi
DMIN="$(awk '/^environment:/ {e=1; next} e && /^[^ \t#]/ {e=0} e && /sdk:/ {print; exit}' pubspec.yaml | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"

AGP="$(cat android/settings.gradle* android/build.gradle* 2>/dev/null | grep -E 'com\.android\.(application|tools\.build:gradle)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
GRADLE="$(sed -nE 's/.*gradle-([0-9.]+)-(all|bin).*/\1/p' android/gradle/wrapper/gradle-wrapper.properties 2>/dev/null | head -1)"
KOTLIN="$(cat android/settings.gradle* android/build.gradle* 2>/dev/null | grep -E 'org\.jetbrains\.kotlin|kotlin_version|kotlin-gradle-plugin' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

RFILES="$(grep -rlE 'GoRoute\(|GoRouter\(|onGenerateRoute|GetPage\(|AutoRoute\(' lib 2>/dev/null | sort)"
NROUTES="$(grep -rhoE 'GoRoute\(|GetPage\(|AutoRoute\(' lib 2>/dev/null | wc -l | tr -d ' ')"
RHASH=""; [ -n "$RFILES" ] && RHASH="$(echo "$RFILES" | while read -r f; do cat "$f"; done | shasum | cut -c1-12)"
ENVN="$(grep -rhoE "fromEnvironment\([[:space:]]*['\"][A-Za-z0-9_]+['\"]" lib 2>/dev/null | grep -oE "[A-Za-z0-9_]+['\"]$" | tr -d "'\"" | sort -u | join)"
MOCKS="$(echo "$ENVN" | tr , '\n' | grep -E 'MOCK|E2E|SEMANTIC|SCENARIO|UAT|DEMO' | join)"

MK=""; [ -f Makefile ] && MK="$(grep -oE '^[a-zA-Z][a-zA-Z0-9_-]*:' Makefile | tr -d : | sort -u | head -20 | join)"
CFG=""; [ -d config ] && CFG="$(ls config/*.json 2>/dev/null | while read -r f; do basename "$f"; done | join)"
DOCS=""; for f in README.md CLAUDE.md AGENTS.md Makefile .llm; do [ -e "$f" ] && DOCS="$DOCS $f"; done

# fields whose change should trigger a re-bootstrap (machine-independent only)
dlines() {
  echo "d.package=$PKG"; echo "d.flavors=$FLAVORS"; echo "d.flutter_pin=$PIN"; echo "d.dart_min=$DMIN"
  echo "d.agp=$AGP"; echo "d.gradle=$GRADLE"; echo "d.kotlin=$KOTLIN"
  echo "d.router_hash=$RHASH"; echo "d.routes=$NROUTES"; echo "d.env_switches=$ENVN"
}

# ---- .uat helpers --------------------------------------------------------------------
user_part() { [ -f "$UAT" ] && awk '/^# --- flutter-uat bootstrap/{skip=1} !skip{print} /^# --- end bootstrap/{skip=0}' "$UAT"; }
user_has() { user_part | grep -qE "^$1="; }
skipval() { [ -f "$UAT" ] && awk -F= -v k="skip.$1" '$1==k {v=$0; sub(/^[^=]*=/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); print (v==""?"__empty__":v); exit}' "$UAT"; }

# ---- check mode ----------------------------------------------------------------------
if [ "$MODE" = check ]; then
  if ! grep -q '^d\.' "$UAT" 2>/dev/null; then
    [ "$QUIET" = 1 ] && echo "bootstrap: not bootstrapped (run: uat.sh bootstrap --write)" || echo "NOT BOOTSTRAPPED: no generated block in $UAT"
    exit 3
  fi
  stale=0
  while IFS= read -r line; do
    k="${line%%=*}"; now="${line#*=}"
    old="$(grep -E "^$k=" "$UAT" | head -1 | sed 's/^[^=]*=//')"
    if [ "$old" != "$now" ]; then
      stale=1; echo "STALE ${k#d.}: was '${old}' now '${now}'"
    fi
  done <<EOF
$(dlines)
EOF
  [ "$stale" = 1 ] && { echo "re-bootstrap: uat.sh bootstrap --write"; exit 1; }
  [ "$QUIET" = 1 ] || echo "FRESH: .uat matches the project"
  exit 0
fi

# ---- host conditions -----------------------------------------------------------------
BAD=0
check() { # ID ok(1/0) description detail
  sk="$(skipval "$1")"
  if [ "$sk" = "__empty__" ]; then echo "  $1 FAIL  skip.$1 is set but has no reason"; BAD=1
  elif [ "$2" = 1 ]; then echo "  $1 PASS  $3 ($4)"
  elif [ -n "$sk" ]; then echo "  $1 SKIP  $3 ($4) -- $sk"
  else echo "  $1 FAIL  $3 ($4)"; BAD=1; fi
}
LOAD="$(uptime | sed -E 's/.*averages?: ([0-9.]+).*/\1/')"
FREEK="$(df -Pk "$HOME" | awk 'NR==2{print $4}')"
FREEG="$(awk -v k="$FREEK" 'BEGIN{printf "%.1f", k/1048576}')"
MAXLOAD=8; MINFREEG=5   # fallback limits when host-hygiene is not installed
# one source of truth for load and free disk: host-hygiene guard, when installed (fallback = the values above)
GUARD="$HOME/.claude/skills/host-hygiene/scripts/host-hygiene.sh"
if [ -x "$GUARD" ]; then
  GKV="$("$GUARD" guard --kv 2>/dev/null || true)"
  GL="$(printf '%s\n' "$GKV" | sed -n 's/^load=//p')"; GF="$(printf '%s\n' "$GKV" | sed -n 's/^free_gb=//p')"
  GML="$(printf '%s\n' "$GKV" | sed -n 's/^max_load=//p')"; GHG="$(printf '%s\n' "$GKV" | sed -n 's/^hard_gb=//p')"
  [ -n "$GML" ] && MAXLOAD="$GML"; [ -n "$GHG" ] && MINFREEG="$GHG"
  if [ -n "$GL" ] && [ -n "$GF" ]; then LOAD="$GL"; FREEG="$GF"; FREEK="$(awk -v g="$GF" 'BEGIN{printf "%d", g*1048576}')"; fi
fi
ok1=$(awk -v l="$LOAD" -v m="$MAXLOAD" 'BEGIN{print (l<m)?1:0}'); ok5=$(awk -v k="$FREEK" -v m="$MINFREEG" 'BEGIN{print (k>=m*1048576)?1:0}')

ADB="${ADB:-$(command -v adb || ls "$HOME/Library/Android/sdk/platform-tools/adb" 2>/dev/null || true)}"
AVDS=""; EMU="$(command -v emulator || ls "$HOME/Library/Android/sdk/emulator/emulator" 2>/dev/null || true)"
[ -n "$EMU" ] && AVDS="$("$EMU" -list-avds 2>/dev/null | join)"
SERIALS=""; [ -n "$ADB" ] && SERIALS="$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}' | join)"

WARN=""
addw() { WARN="$WARN
  WARN $1"; }
case "${PIN:-}" in stable|beta|master|main) FLOATPIN=1 ;; *) FLOATPIN=0 ;; esac
[ -n "$SDKNOTE" ] && addw "$SDKNOTE"
[ -z "$SDKBIN" ] && addw "no Flutter SDK found (install one or set the pin)"
[ -z "$APPG" ] && addw "no android/app/build.gradle(.kts): not an Android-capable project"
[ -z "$PKG" ] && [ -n "$APPG" ] && addw "could not read applicationId"
if [ -n "$AGP" ] && [ -n "$FV" ] && [ "$(echo "$AGP" | cut -d. -f1)" -lt 8 ] 2>/dev/null && [ "$(ver_lt "$FV" 3.35.0)" = 0 ]; then
  addw "AGP $AGP with Flutter $FV: measured to FAIL on Flutter >= 3.35 (AGP 7.3/Gradle 7.6, sample app C). Upgrade the toolchain or build in a scratch copy; do not edit the repo without asking."
fi
if [ -n "$DMIN" ] && [ -n "$DV" ] && [ "$(ver_lt "$DV" "$DMIN")" = 1 ]; then
  addw "pubspec needs Dart >= $DMIN but the chosen SDK has Dart $DV (sample app D needed a newer SDK)"
fi
# measured: Flutter 3.50.0 refused a project whose Gradle wrapper was 8.14 ("lower than Flutter's minimum supported version of 9.3.1")
if [ -n "${FV:-}" ] && [ -n "${GRADLE:-}" ] && [ "$(printf '%s\n%s\n' "$FV" 3.50.0 | sort -V | head -1)" = "3.50.0" ] \
   && [ "$(printf '%s\n%s\n' "$GRADLE" 9.3.1 | sort -V | head -1)" != "9.3.1" ]; then
  addw "Flutter $FV with Gradle $GRADLE: Flutter 3.50.0 was measured to refuse Gradle 8.14 (needs 9.3.1). ${PIN:+pin '$PIN' floats with the channel; }try an older installed SDK (build --sdk PATH/bin/flutter) or upgrade the wrapper in a copy"
fi
[ -z "$ADB" ] && addw "adb not found (set ADB=/path/to/adb)"

# ---- generated block -----------------------------------------------------------------
gen() {
  echo "# --- flutter-uat bootstrap (generated; refresh with: uat.sh bootstrap --write) ---"
  [ -n "$PKG" ] && ! user_has package && echo "package=$PKG"
  user_has build.debug || echo "build.debug=flutter build apk --debug"
  dlines
  echo "# To fill in by hand (never guessed):"
  echo "#   role.<name>=<emulator serial>      signin.<role>=<mock|otp-source|none>"
  echo "#   unsafe=Log Out,Delete Account,Pay  skip.<C1|C3|C5>=<reason>"
  echo "# --- end bootstrap ---"
}

if [ "$MODE" = write ]; then
  tmp="$(mktemp)"; { user_part; gen; } > "$tmp" && mv "$tmp" "$UAT"
fi

if [ "$MODE" = show ] || [ "$MODE" = write ]; then
  echo "project:   $ROOT"
  echo "package:   ${PKG:-?}   flavors: ${FLAVORS:-none}"
  echo "flutter:   ${FV:-?} (dart ${DV:-?}) via ${SDKBIN:-none}   pin: ${PIN:-none}   pubspec dart >= ${DMIN:-?}"
  echo "android:   AGP ${AGP:-?}  Gradle ${GRADLE:-?}  Kotlin ${KOTLIN:-?}"
  echo "routes:    $NROUTES in $(echo "$RFILES" | grep -c .) file(s) (hash ${RHASH:-none})"
  echo "env flags: ${ENVN:-none}"
  echo "  mock/e2e candidates: ${MOCKS:-none}"
  echo "make:      ${MK:-none}   config/: ${CFG:-none}   docs:${DOCS:- none}"
  echo "emulators: running [${SERIALS:-none}]  avds [${AVDS:-none}]   (roles are never guessed)"
  echo "conditions:"
  check C1 "$ok1" "host load < $MAXLOAD" "load $LOAD"
  check C5 "$ok5" ">= $MINFREEG GiB free" "${FREEG} GiB free"
  echo "  C2/C3/C4 are device checks: run 'uat.sh doctor' and 'uat.sh anims 0'"
  [ -n "$WARN" ] && echo "warnings:$WARN"
  if [ "$MODE" = write ]; then echo "wrote: $UAT"; else echo "--- would write ---"; gen; fi
  exit $BAD
fi
