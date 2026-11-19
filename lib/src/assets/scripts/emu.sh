#!/usr/bin/env bash
# flutter-uat emu: boot and stop Android emulators WITHOUT touching ones this tool did not start.
#
#   emu.sh list
#   emu.sh start AVD [--port N] [--wipe]      boot (no snapshot load), wait for boot, animations off
#   emu.sh start --role NAME                  AVD from .uat avd.NAME=, port from role.NAME=emulator-NNNN
#   emu.sh stop SERIAL [--force]              only emulators this tool started, unless --force
#   emu.sh create AVD [--api N] [--device ID] make a throwaway AVD (google_apis, host arch, no Play Store)
#   emu.sh delete AVD                         only AVDs this tool created
#
# Never starts a second copy of an AVD that is already running (it reports the running one).
set -u
ADB="${ADB:-$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")}"
EMU="${EMU:-$(command -v emulator || echo "$HOME/Library/Android/sdk/emulator/emulator")}"
_tmp="${TMPDIR:-/tmp}"; _tmp="${_tmp%/}"; SD="$_tmp/flutter-uat"; mkdir -p "$SD"; REG="$SD/started.txt"; touch "$REG"
HERE="$(cd "$(dirname "$0")" && pwd)"

AVDREG="$SD/avds.txt"; touch "$AVDREG"
sdk_root() { for r in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do [ -n "$r" ] && [ -d "$r/system-images" ] && { echo "$r"; return 0; }; done; return 1; }
avdmanager_bin() { command -v avdmanager || ls "$(sdk_root)"/cmdline-tools/*/bin/avdmanager 2>/dev/null | head -1; }
conf() { d="$PWD"; while [ "$d" != "/" ]; do [ -f "$d/.uat" ] && { awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$d/.uat"; return; }; d="$(dirname "$d")"; done; }
avd_of() { "$ADB" -s "$1" emu avd name 2>/dev/null | head -1 | tr -d '\r'; }
running_serial_for() { # AVD -> serial of a running emulator with that AVD
  for s in $("$ADB" devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1}'); do
    [ "$(avd_of "$s")" = "$1" ] && { echo "$s"; return 0; }
  done; return 1
}
port_free() { ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && ! lsof -nP -iTCP:"$(( $1 + 1 ))" -sTCP:LISTEN >/dev/null 2>&1; }

# drop registry entries whose emulator process is gone (a stale entry must never make a later,
# unrelated emulator on the same port look like ours)
if [ -s "$REG" ]; then
  tmpreg="$(mktemp)"; while read -r rs ra rp; do kill -0 "$rp" 2>/dev/null && echo "$rs $ra $rp"; done < "$REG" > "$tmpreg"; mv "$tmpreg" "$REG"
fi

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  list)
    for s in $("$ADB" devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1}'); do
      own=""; grep -q "^$s " "$REG" && own="  (started by uat)"
      echo "$s  $(avd_of "$s")$own"
    done
    echo "avds: $("$EMU" -list-avds 2>/dev/null | paste -sd, -)" ;;
  start)
    AVD=""; PORT=""; WIPE=0; ROLE=""
    while [ $# -gt 0 ]; do case "$1" in
      --port) PORT="$2"; shift 2 ;; --wipe) WIPE=1; shift ;; --role) ROLE="$2"; shift 2 ;; *) AVD="$1"; shift ;; esac; done
    if [ -n "$ROLE" ]; then
      AVD="$(conf "avd.$ROLE")"; ser="$(conf "role.$ROLE")"
      [ -z "$AVD" ] && { echo "no avd.$ROLE in .uat" >&2; exit 2; }
      [ -z "$PORT" ] && PORT="${ser#emulator-}"
    fi
    [ -z "$AVD" ] && { echo "usage: emu.sh start AVD [--port N] [--wipe] | --role NAME" >&2; exit 2; }
    "$EMU" -list-avds | grep -qx "$AVD" || { echo "unknown AVD '$AVD'. Known: $("$EMU" -list-avds | paste -sd, -). Create a throwaway one with: emu create $AVD" >&2; exit 2; }
    if s="$(running_serial_for "$AVD")"; then echo "ALREADY RUNNING: $AVD is $s (left alone; not started by this call)"; exit 0; fi
    if [ -z "$PORT" ]; then p=5554; while [ $p -le 5584 ]; do port_free $p && break; p=$((p + 2)); done; PORT=$p; fi
    port_free "$PORT" || { echo "port $PORT is in use; pick another with --port" >&2; exit 1; }
    flags=(-avd "$AVD" -port "$PORT" -no-snapshot-load -no-audio -no-boot-anim); [ "$WIPE" = 1 ] && flags+=(-wipe-data)
    log="$SD/emu-$PORT.log"; nohup "$EMU" "${flags[@]}" > "$log" 2>&1 &
    pid=$!; S="emulator-$PORT"; echo "$S $AVD $pid" >> "$REG"
    echo "starting $AVD on $S (pid $pid, log $log); load $(uptime | sed -E 's/.*averages?: ([0-9.]+).*/\1/')"
    SECONDS=0
    while [ $SECONDS -lt 240 ]; do
      kill -0 "$pid" 2>/dev/null || { echo "emulator exited early:" >&2; tail -5 "$log" >&2; sed -i '' "/^$S /d" "$REG"; exit 1; }
      [ "$("$ADB" -s "$S" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
      sleep 3
    done
    [ "$("$ADB" -s "$S" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] || { echo "not booted after ${SECONDS}s" >&2; exit 1; }
    echo "BOOTED $S in ${SECONDS}s"; ANDROID_SERIAL="$S" "$HERE/uat.sh" anims 0 ;;
  create)
    NAME="${1:-}"; [ -z "$NAME" ] && { echo "usage: emu.sh create AVD [--api N] [--device ID]" >&2; exit 2; }; shift
    API=""; DEV="pixel_5"
    while [ $# -gt 0 ]; do case "$1" in --api) API="$2"; shift 2 ;; --device) DEV="$2"; shift 2 ;; *) echo "unknown argument: $1" >&2; exit 2 ;; esac; done
    AM="$(avdmanager_bin)"; [ -x "$AM" ] || { echo "avdmanager not found (install Android cmdline-tools)" >&2; exit 2; }
    SR="$(sdk_root)" || { echo "no Android SDK with system-images found (set ANDROID_HOME)" >&2; exit 2; }
    "$EMU" -list-avds 2>/dev/null | grep -qx "$NAME" && { echo "AVD '$NAME' already exists (not touched)" >&2; exit 3; }
    case "$(uname -m)" in arm64|aarch64) ARCH=arm64-v8a ;; *) ARCH=x86_64 ;; esac
    if [ -z "$API" ]; then API="$(for d in "$SR"/system-images/android-*/google_apis/"$ARCH"; do [ -f "$d/package.xml" ] && echo "$d"; done | sed -E 's#.*/android-([0-9]+)/.*#\1#' | sort -n | tail -1)"; fi
    [ -f "$SR/system-images/android-$API/google_apis/$ARCH/package.xml" ] || { echo "no google_apis/$ARCH system image for API '${API:-?}' under $SR/system-images (installed: $(ls "$SR"/system-images 2>/dev/null | paste -sd' ' -))" >&2; exit 2; }
    OUT="$(echo no | "$AM" create avd -n "$NAME" -k "system-images;android-$API;google_apis;$ARCH" -d "$DEV" 2>&1)" \
      || { echo "avdmanager failed to create '$NAME': $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')" >&2; exit 1; }
    echo "$NAME" >> "$AVDREG"; echo "created AVD $NAME (API $API, $ARCH, $DEV)" ;;
  delete)
    NAME="${1:-}"; [ -z "$NAME" ] && { echo "usage: emu.sh delete AVD" >&2; exit 2; }
    grep -qx "$NAME" "$AVDREG" || { echo "REFUSED: AVD '$NAME' was not created by this tool." >&2; exit 3; }
    running_serial_for "$NAME" >/dev/null && { echo "AVD '$NAME' is running; stop it first" >&2; exit 3; }
    AM="$(avdmanager_bin)"; [ -x "$AM" ] || { echo "avdmanager not found" >&2; exit 2; }
    "$AM" delete avd -n "$NAME" >/dev/null 2>&1 || { echo "avdmanager failed to delete '$NAME'" >&2; exit 1; }
    sed -i '' "/^$NAME\$/d" "$AVDREG"; echo "deleted AVD $NAME" ;;
  stop)
    S="${1:-}"; [ -z "$S" ] && { echo "usage: emu.sh stop SERIAL [--force]" >&2; exit 2; }; shift
    force=0; [ "${1:-}" = "--force" ] && force=1
    if ! grep -q "^$S " "$REG" && [ "$force" != 1 ]; then
      echo "REFUSED: $S ($(avd_of "$S")) was not started by this tool. Use --force only if you own it." >&2; exit 3
    fi
    pid="$(awk -v s="$S" '$1==s {print $3}' "$REG")"
    perl -e 'alarm 10; exec @ARGV' "$ADB" -s "$S" emu kill >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do "$ADB" devices | grep -q "^$S" || break; sleep 1; done
    # `emu kill` can hang or be ignored: fall back to the process WE started (never an unknown pid)
    if "$ADB" devices | grep -q "^$S" && [ -n "$pid" ]; then kill "$pid" 2>/dev/null; sleep 4; fi
    "$ADB" devices | grep -q "^$S" && { echo "$S still listed" >&2; exit 1; }
    sed -i '' "/^$S /d" "$REG"; echo "stopped $S" ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
