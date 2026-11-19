#!/usr/bin/env bash
# flutter-uat build: build the app under test with the right SDK, leave the repo as found.
#
#   build.sh [debug|release] [--flavor F] [-t FILE] [--define K=V]... [--arg FLUTTER_FLAG]... [--arch arm64|x64]
#            [--install] [--keep-edits] [--allow-old-toolchain] [--min-free GIB] [--sdk PATH/bin/flutter] [--root DIR]
#   build.sh --clean [--yes]     delete the build output THIS tool created (dry-run without --yes)
#
# Defaults come from .uat: build.flavor= build.target= build.define=A=1,B=2 build.args=...
#                          floor.disk_gib= (default 5)
# Guarantees: refuses below the disk floor; refuses a toolchain bootstrap warns will fail;
# reverts tracked files the Flutter tooling rewrote (only ones that were clean before);
# remembers which output dirs it created so --clean removes only those.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"; BS="$HERE/bootstrap.sh"
SDKOVR=""; MODE=debug; FLAVOR=""; TARGET=""; ARCH=""; INSTALL=0; KEEP=0; OLDTC=0; MINFREE=""; ROOT=""; CLEAN=0; YES=0
DEFS=(); EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    debug|release|profile) MODE="$1"; shift ;;
    --flavor) FLAVOR="$2"; shift 2 ;;
    -t|--target) TARGET="$2"; shift 2 ;;
    --define) DEFS+=("$2"); shift 2 ;;
    --arg) EXTRA+=("$2"); shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --keep-edits) KEEP=1; shift ;;
    --allow-old-toolchain) OLDTC=1; shift ;;
    --min-free) MINFREE="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --sdk) SDKOVR="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then d="$PWD"; while [ "$d" != "/" ] && [ ! -f "$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done; ROOT="$d"; fi
[ -f "$ROOT/pubspec.yaml" ] || { echo "no pubspec.yaml found from $PWD" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"; cd "$ROOT" || exit 2
conf() { [ -f .uat ] && awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; exit}' .uat; }

_tmp="${TMPDIR:-/tmp}"; _tmp="${_tmp%/}"; SD="$_tmp/flutter-uat"; mkdir -p "$SD"
key="$(printf '%s' "$ROOT" | shasum | cut -c1-10)"; CREATED="$SD/created-$key.txt"
GEN="build .dart_tool android/.gradle"

if [ "$CLEAN" = 1 ]; then
  [ -s "$CREATED" ] || { echo "nothing recorded: this tool has not created build output for $ROOT"; exit 0; }
  while read -r p; do
    [ -e "$p" ] || continue
    if ! git check-ignore -q "$p" 2>/dev/null; then echo "SKIP $p (not gitignored: not touching it)"; continue; fi
    sz="$(du -sh "$p" | cut -f1)"
    if [ "$YES" = 1 ]; then rm -rf "$ROOT/$p" && echo "removed $p ($sz)"; else echo "would remove $p ($sz)"; fi
  done < "$CREATED"
  [ "$YES" = 1 ] && rm -f "$CREATED" || echo "(dry run; add --yes)"
  exit 0
fi

# defaults from .uat
[ -z "$FLAVOR" ] && FLAVOR="$(conf build.flavor)"
[ -z "$TARGET" ] && TARGET="$(conf build.target)"
if [ ${#DEFS[@]} -eq 0 ]; then d="$(conf build.define)"; [ -n "$d" ] && IFS=, read -r -a DEFS <<<"$d"; fi
read -r -a CONFARGS <<<"$(conf build.args)"; EXTRA=(${CONFARGS[@]+"${CONFARGS[@]}"} ${EXTRA[@]+"${EXTRA[@]}"})
[ -z "$MINFREE" ] && MINFREE="$(conf floor.disk_gib)"; MINFREE="${MINFREE:-5}"

# 1. disk floor
FREEK="$(df -Pk "$HOME" | awk 'NR==2{print $4}')"
if [ "$(awk -v k="$FREEK" -v m="$MINFREE" 'BEGIN{print (k < m*1048576) ? 1 : 0}')" = 1 ]; then
  echo "REFUSED: $(awk -v k="$FREEK" 'BEGIN{printf "%.1f", k/1048576}') GiB free is below the floor of $MINFREE GiB (floor.disk_gib in .uat, or --min-free)." >&2; exit 7
fi

# 2. SDK
SDK="${SDKOVR:-$("$BS" --sdk 2>/dev/null)}"; [ -x "$SDK" ] || { echo "no Flutter SDK found (see: uat.sh bootstrap)" >&2; exit 2; }

# 3. toolchain that is known to fail
tc="$("$BS" 2>/dev/null | grep -E '^  WARN (AGP|pubspec needs Dart)')"
if [ -n "$tc" ] && [ "$OLDTC" != 1 ]; then
  echo "REFUSED: bootstrap reports a toolchain problem that is measured to fail:" >&2; echo "$tc" >&2
  echo "Fix it in a scratch COPY of the project (never the repo), or pass --allow-old-toolchain to try anyway." >&2; exit 6
fi

# 4. baseline: tracked edits and output dirs that do not exist yet
BEFORE="$SD/before-$key.txt"; : > "$BEFORE"
IS_GIT=0; git rev-parse --git-dir >/dev/null 2>&1 && IS_GIT=1
[ "$IS_GIT" = 1 ] && git status --porcelain -uno | sed 's/^...//' | sort > "$BEFORE"
for p in $GEN; do [ -e "$p" ] || echo "$p" >> "$SD/new-$key.txt"; done

# 5. build
[ -z "$ARCH" ] && { [ "$(uname -m)" = arm64 ] && ARCH=arm64 || ARCH=x64; }
args=(build apk "--$MODE" --target-platform "android-$ARCH")
[ -n "$FLAVOR" ] && args+=(--flavor "$FLAVOR")
[ -n "$TARGET" ] && args+=(-t "$TARGET")
for d in ${DEFS[@]+"${DEFS[@]}"}; do args+=("--dart-define=$d"); done
args+=(${EXTRA[@]+"${EXTRA[@]}"})
LOG="$SD/build-$key.log"
echo "build: $SDK ${args[*]}"
echo "load: $(uptime | sed -E 's/.*averages?: ([0-9.]+).*/\1/')  free: $(awk -v k="$FREEK" 'BEGIN{printf "%.1f", k/1048576}') GiB  log: $LOG"
SECONDS=0; "$SDK" "${args[@]}" > "$LOG" 2>&1; rc=$?; T=$SECONDS

# 6. record what we created (even on failure: it is still ours to clean)
[ -f "$SD/new-$key.txt" ] && { for p in $(cat "$SD/new-$key.txt"); do [ -e "$p" ] && echo "$p"; done >> "$CREATED"; rm -f "$SD/new-$key.txt"; sort -u "$CREATED" -o "$CREATED"; }

# 7. revert tooling edits to tracked files that were clean before
if [ "$IS_GIT" = 1 ]; then
  AFTER="$SD/after-$key.txt"; git status --porcelain -uno | sed 's/^...//' | sort > "$AFTER"
  for f in $(comm -13 "$BEFORE" "$AFTER"); do
    if [ "$KEEP" = 1 ]; then echo "tooling edited (kept): $f"
    else git checkout -- "$f" && echo "reverted tooling edit: $f"; fi
  done
fi

if [ $rc -ne 0 ]; then
  echo "BUILD FAILED after ${T}s (exit $rc). Last lines:" >&2; tail -15 "$LOG" >&2
  if grep -qE 'requires SDK version|Try using the Flutter SDK version|current Dart SDK version' "$LOG"; then
    echo "HINT: the chosen SDK is too old for this project's dependencies. Installed SDKs: $(ls -d "$HOME"/fvm/versions/* "$HOME"/.fvm/versions/* 2>/dev/null | paste -sd' ' -)" >&2
    echo "      rerun with: uat.sh build ... --sdk <that path>/bin/flutter" >&2
  fi
  if grep -qE "Gradle version .* is lower than Flutter's minimum" "$LOG"; then
    echo "HINT: this Flutter SDK is newer than the project's Gradle wrapper allows (a floating pin such as 'stable' resolves to today's channel)." >&2
    echo "      Installed SDKs: $(ls -d "$HOME"/fvm/versions/* "$HOME"/.fvm/versions/* 2>/dev/null | paste -sd' ' -). Try an older one: build ... --sdk <that path>/bin/flutter" >&2
    echo "      Or upgrade android/gradle/wrapper/gradle-wrapper.properties in a COPY of the app." >&2
  fi
  pin="$("$BS" 2>/dev/null | grep -oE 'pinned SDK [^ ]+ is not installed' | head -1)"
  [ -n "$pin" ] && echo "HINT: $pin. The project was built for that exact SDK; install it (fvm install <version>) and use --sdk." >&2
  exit 1
fi
apk="$(grep -oE 'build/app/outputs/flutter-apk/[^ ]+\.apk' "$LOG" | tail -1)"
echo "BUILD OK in ${T}s: $ROOT/$apk ($(du -h "$apk" 2>/dev/null | cut -f1))"
if [ "$INSTALL" = 1 ]; then "$HERE/uat.sh" install "$ROOT/$apk"; fi
exit 0
