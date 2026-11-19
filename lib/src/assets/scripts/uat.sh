#!/usr/bin/env bash
# flutter-uat — label-driven touch navigation for Flutter apps on Android emulators/devices.
# Project-agnostic. Reads the accessibility (semantics) tree via uiautomator, so taps land on
# fresh node bounds instead of remembered pixel coordinates.
#
#   uat.sh [-s SERIAL | --role NAME] [-p PACKAGE] <command> [args]
#
# Run `uat.sh help` for the command list. Optional per-project config: a `.uat` file in the
# project root (found by walking up from $PWD):
#     package=com.example.app
#     role.sender=emulator-5554
#     role.agent=emulator-5556
# Nothing here is read from the network or executed from that file; it is parsed as data.

set -u

ADB="${ADB:-}"
if [ -z "$ADB" ]; then
  if command -v adb >/dev/null 2>&1; then ADB=adb
  elif [ -x "${ANDROID_HOME:-}/platform-tools/adb" ]; then ADB="$ANDROID_HOME/platform-tools/adb"
  elif [ -x "${ANDROID_SDK_ROOT:-}/platform-tools/adb" ]; then ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
  elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then ADB="$HOME/Library/Android/sdk/platform-tools/adb"
  elif [ -x "$HOME/Android/Sdk/platform-tools/adb" ]; then ADB="$HOME/Android/Sdk/platform-tools/adb"
  else echo "adb not found; set ADB=/path/to/adb" >&2; exit 2; fi
fi

SERIAL="${ANDROID_SERIAL:-}"
ROLE=""
PKG="${UAT_PACKAGE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--serial) SERIAL="$2"; shift 2 ;;
    --role)      ROLE="$2"; shift 2 ;;
    -p|--package) PKG="$2"; shift 2 ;;
    *) break ;;
  esac
done
cmd="${1:-help}"
[ $# -gt 0 ] && shift

# ---- project config (data only) -------------------------------------------------------
conf_file() {
  d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/.uat" ] && { echo "$d/.uat"; return; }
    d="$(dirname "$d")"
  done
}
conf_get() { f="$(conf_file)"; [ -n "$f" ] && awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$f"; }

# ---- device resolution ----------------------------------------------------------------
list_devices() { "$ADB" devices | awk 'NR>1 && $2=="device" {print $1}'; }

if [ "$cmd" = "build" ] || [ "$cmd" = "emu" ]; then
  [ -n "$SERIAL" ] && export ANDROID_SERIAL="$SERIAL"; [ -n "$PKG" ] && export UAT_PACKAGE="$PKG"
  [ "$cmd" = "build" ] && [ "${1:-}" = "--clean" ] || true
  exec "$(cd "$(dirname "$0")" && pwd)/$cmd.sh" "$@"
fi
if [ "$cmd" = "flow" ]; then
  [ -n "$SERIAL" ] && export ANDROID_SERIAL="$SERIAL"; [ -n "$PKG" ] && export UAT_PACKAGE="$PKG"
  command -v python3 >/dev/null 2>&1 || { echo "flow needs python3" >&2; exit 2; }
  exec python3 "$(cd "$(dirname "$0")" && pwd)/flow.py" "$@"
fi
if [ "$cmd" = "sweep" ]; then
  [ -n "$SERIAL" ] && export ANDROID_SERIAL="$SERIAL"; [ -n "$PKG" ] && export UAT_PACKAGE="$PKG"
  command -v python3 >/dev/null 2>&1 || { echo "sweep needs python3" >&2; exit 2; }
  exec python3 "$(cd "$(dirname "$0")" && pwd)/sweep.py" "$@"
fi
if [ "$cmd" = "stability" ]; then
  [ -n "$SERIAL" ] && export ANDROID_SERIAL="$SERIAL"; [ -n "$PKG" ] && export UAT_PACKAGE="$PKG"
  command -v python3 >/dev/null 2>&1 || { echo "stability needs python3" >&2; exit 2; }
  exec python3 "$(cd "$(dirname "$0")" && pwd)/stability.py" "$@"
fi
if [ "$cmd" = "repeat" ]; then
  [ -n "$SERIAL" ] && export ANDROID_SERIAL="$SERIAL"; [ -n "$PKG" ] && export UAT_PACKAGE="$PKG"
  command -v python3 >/dev/null 2>&1 || { echo "repeat needs python3" >&2; exit 2; }
  exec python3 "$(cd "$(dirname "$0")" && pwd)/repeat.py" "$@"
fi
if [ "$cmd" = "walk" ]; then
  [ -n "$SERIAL" ] && export ANDROID_SERIAL="$SERIAL"; [ -n "$PKG" ] && export UAT_PACKAGE="$PKG"
  command -v python3 >/dev/null 2>&1 || { echo "walk needs python3" >&2; exit 2; }
  exec python3 "$(cd "$(dirname "$0")" && pwd)/walk.py" "$@"
fi
if [ "$cmd" = "coverage" ]; then exec "$(cd "$(dirname "$0")" && pwd)/coverage.sh" "$@"; fi
if [ "$cmd" = "bootstrap" ]; then exec "$(cd "$(dirname "$0")" && pwd)/bootstrap.sh" "$@"; fi
if [ "$cmd" != "help" ] && [ "$cmd" != "devices" ] && [ -z "${UAT_XML:-}" ]; then
  if [ -z "$SERIAL" ] && [ -n "$ROLE" ]; then
    SERIAL="$(conf_get "role.$ROLE")"
    [ -z "$SERIAL" ] && { echo "no role.$ROLE in .uat (and no -s given)" >&2; exit 2; }
  fi
  if [ -z "$SERIAL" ]; then
    n=$(list_devices | wc -l | tr -d ' ')
    if [ "$n" = "1" ]; then SERIAL="$(list_devices)"
    else
      echo "device ambiguous ($n attached). Pass -s SERIAL, --role NAME, or set ANDROID_SERIAL:" >&2
      "$ADB" devices >&2; exit 2
    fi
  fi
  ADB_S=("$ADB" -s "$SERIAL")
else
  ADB_S=("$ADB")
fi

# ---- package resolution (lazy) --------------------------------------------------------
resolve_pkg() {
  [ -n "$PKG" ] && { echo "$PKG"; return; }
  p="$(conf_get package)"; [ -n "$p" ] && { echo "$p"; return; }
  root="$(dirname "$(conf_file)" 2>/dev/null)"; [ -z "$root" ] || [ "$root" = "." ] && root="$PWD"
  for g in "$root/android/app/build.gradle.kts" "$root/android/app/build.gradle"; do
    [ -f "$g" ] && p="$(grep -E 'applicationId' "$g" | head -1 | sed -E 's/.*["'\'']([A-Za-z0-9_.]+)["'\''].*/\1/')" && [ -n "$p" ] && { echo "$p"; return; }
  done
  "${ADB_S[@]}" shell dumpsys activity activities 2>/dev/null | tr -d '\r' 2>/dev/null \
    | awk '/mResumedActivity|topResumedActivity/ {for(i=1;i<=NF;i++) if ($i ~ /\//) {split($i,a,"/"); print a[1]; exit}}'
}

# ---- state dir (per device, so parallel emulators never share a dump) -----------------
_tmp="${TMPDIR:-/tmp}"; _tmp="${_tmp%/}"
STATE="$_tmp/flutter-uat/${SERIAL:-none}"
mkdir -p "$STATE"
UIXML="$STATE/ui.xml"

# Hard wall-clock limit for a host-side call (uiautomator can stall when the host is starved).
to() { secs="$1"; shift; if command -v perl >/dev/null 2>&1; then perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; else "$@"; fi; }

dump_ui() {
  out="${1:-$UIXML}"
  # UAT_XML=file replays a saved tree (offline analysis, regression fixtures); no device needed.
  if [ -n "${UAT_XML:-}" ]; then cp "$UAT_XML" "$out" || return 1; [ "$out" = "$UIXML" ] && record_visit; return 0; fi
  for _ in 1 2 3; do
    rm -f "$out"
    # The device-side file persists across dumps; if uiautomator fails, pull would serve the PREVIOUS
    # app's tree. Clear it first so a failed dump can never look like a successful one.
    "${ADB_S[@]}" shell rm -f /sdcard/uat_ui.xml >/dev/null 2>&1
    to "${UAT_DUMP_TIMEOUT:-25}" "${ADB_S[@]}" shell uiautomator dump /sdcard/uat_ui.xml >/dev/null 2>&1
    to 10 "${ADB_S[@]}" pull /sdcard/uat_ui.xml "$out" >/dev/null 2>&1
    if [ -s "$out" ]; then [ "$out" = "$UIXML" ] && record_visit; return 0; fi
    # "UiAutomationService already registered" (seen after an interrupted dump): a stale uiautomator
    # on the device blocks the next one. Kill it and give the registration time to clear.
    "${ADB_S[@]}" shell pkill -f uiautomator >/dev/null 2>&1
    sleep 2
  done
  return 1
}
# Every successful dump of an app records its label set (only when it changed) so `coverage` can
# tell which screens a walk reached. Keyed by the app's package, read from the dump itself.
record_visit() {
  [ -n "${UAT_NO_VISITS:-}" ] && return 0
  vp="$(grep -o ' package="[^"]*"' "$UIXML" | head -1 | cut -d'"' -f2)"
  case "$vp" in ""|com.android.*|com.google.android.*|*launcher*|*systemui*) return 0 ;; esac
  vt="$(nodes all "" | cut -d' ' -f4- | paste -sd'|' -)"; [ -z "$vt" ] && return 0
  vh="$(printf '%s' "$vt" | shasum | cut -c1-12)"
  [ "$(cat "$STATE/lastvisit" 2>/dev/null)" = "$vh" ] && return 0
  echo "$vh" > "$STATE/lastvisit"
  vl="$_tmp/flutter-uat/visits-$vp.log"; printf '%s\n' "$vt" >> "$vl"
  [ "$(wc -c < "$vl")" -gt 2000000 ] && { tail -n 1500 "$vl" > "$vl.t" && mv "$vl.t" "$vl"; }
  return 0
}
dump_failed() { echo "DUMP-FAILED (screen animating or device busy, or no semantics tree; try 'doctor')" >&2; exit 1; }

# nodes MODE PATTERN EXACT CLICKABLE
#  MODE=all   -> every labeled node
#  MODE=match -> nodes whose text, content-desc or hint contains (or, EXACT=1, equals) PATTERN
# Output: "CX CY CLICKABLE LABEL"; matches ONLY the label attributes, never resource-id/class.
_nodes_one() {
  awk -v mode="$1" -v pat="$2" -v exact="${3:-0}" -v onlyclick="${4:-0}" -v at="${5:-center}" -v lmax="${UAT_LABEL_MAX:-400}" '
    BEGIN { RS = "<"; p = tolower(pat) }
    # Decode XML entities BEFORE matching, so "Phone Number&#10;Tab 1" matches "Phone Number Tab 1".
    function dec(x) {
      gsub(/&#10;/, " ", x); gsub(/&#[0-9]+;/, "", x); gsub(/&#x[0-9a-fA-F]+;/, "", x); gsub(/&quot;/, "\"", x); gsub(/&apos;/, "\x27", x)
      gsub(/&lt;/, "<", x); gsub(/&gt;/, ">", x); gsub(/&amp;/, "\\&", x); return x
    }
    function attr(s, name,   r, m) {
      r = " " name "=\""
      m = index(s, r); if (!m) return ""
      s = substr(s, m + length(r)); return substr(s, 1, index(s, "\"") - 1)
    }
    /^node / {
      b = attr($0, "bounds"); if (b == "") next
      gsub(/\]\[/, ",", b); gsub(/[\[\]]/, "", b); split(b, c, ",")
      if (c[3] <= c[1] || c[4] <= c[2]) next
      t = dec(attr($0, "text")); d = dec(attr($0, "content-desc")); h = dec(attr($0, "hint"))
      lab = t; if (lab == "") lab = d; if (lab == "") lab = h
      cls = attr($0, "class"); sub(/.*\./, "", cls)
      clk = (attr($0, "clickable") == "true") ? 1 : 0
      if (mode == "match" && substr(pat, 1, 3) == "id:") {   # Semantics(identifier:) shows up as resource-id
        rid = attr($0, "resource-id"); q = tolower(substr(pat, 4))
        if (rid != "" && rid !~ /^android:id\// && (exact ? tolower(rid) == q : index(tolower(rid), q)) && (!onlyclick || clk))
          printf "%d %d %d <%s> id=%s\n", (c[1] + c[3]) / 2, (c[2] + c[4]) / 2, clk, cls, rid
        next
      }
      if (mode == "match" && substr(pat, 1, 6) == "class:") {   # unlabeled-field selector: class:EditText
        if (index(tolower(cls), tolower(substr(pat, 7))) && (!onlyclick || clk))
          printf "%d %d %d <%s>%s\n", (c[1] + c[3]) / 2, (c[2] + c[4]) / 2, clk, cls, (lab == "" ? "" : " " lab)
        next
      }
      if (mode == "unlabeled") {   # interactive nodes no label can reach (collected, resolved in END)
        W = (c[3] > W) ? c[3] : W; H = (c[4] > H) ? c[4] : H
        if (lab != "") { nl++; lx1[nl]=c[1]; ly1[nl]=c[2]; lx2[nl]=c[3]; ly2[nl]=c[4] }
        else if ((clk || cls ~ /EditText/) && (c[3]-c[1]) < 1070) {
          nc++; cx[nc]=(c[1]+c[3])/2; cy[nc]=(c[2]+c[4])/2; ck[nc]=clk; cc[nc]=cls
        }
        next
      }
      if (lab == "") next
      if (onlyclick && !clk) next
      if (mode == "match") {
        ok = 0
        n = split(t "\n" d "\n" h, parts, "\n")
        for (i = 1; i <= n; i++) {
          x = tolower(parts[i]); gsub(/^[ \t]+|[ \t]+$/, "", x); if (x == "") continue
          if (exact ? (x == p) : index(x, p)) { ok = 1; break }
        }
        if (!ok) next
      }
      ty = (c[2] + c[4]) / 2; hh = c[4] - c[2]; off = (hh / 4 < 120) ? hh / 4 : 120
      tx = (c[1] + c[3]) / 2; ww = c[3] - c[1]
      if (mode == "match" && at == "left") tx = c[1] + ((ww / 10 < 80) ? ww / 10 : 80)
      if (mode == "match" && at == "right") tx = c[3] - 20
      if (mode == "merged") {   # heuristic: tall clickable node holding a multi-line or long label
        W = (c[3] > W) ? c[3] : W; H = (c[4] > H) ? c[4] : H
        raw = attr($0, "text") attr($0, "content-desc")   # undecoded: newlines are still &#10;
        if (clk && (index(raw, "&#10;") || length(lab) > 60)) { nm++; mx[nm]=tx; my[nm]=ty; mh[nm]=hh; my1[nm]=c[2]; my2[nm]=c[4]; ml[nm]=substr(lab, 1, 80) }
        next
      }
      if (mode == "match" && at == "top") ty = c[2] + off
      if (mode == "match" && at == "bottom") ty = c[4] - off
      flags = ""
      if (attr($0, "selected") == "true") flags = flags " [selected]"
      if (attr($0, "checked") == "true") flags = flags " [checked]"
      if (attr($0, "enabled") == "false") flags = flags " [disabled]"
      printf "%d %d %d %s%s\n", tx, ty, clk, substr(lab, 1, lmax), flags
    }
    END {
      if (mode == "merged") {
        for (i = 1; i <= nm; i++) if (mh[i] > 0.12 * H)
          printf "%d %d y%d-%d MERGED? %s  -> try taplabel LABEL --at top|bottom\n", mx[i], my[i], my1[i], my2[i], ml[i]
        exit
      }
      if (mode != "unlabeled") exit
      for (i = 1; i <= nc; i++) {
        covered = 0
        for (j = 1; j <= nl; j++) {
          if (cx[i] >= lx1[j] && cx[i] <= lx2[j] && cy[i] >= ly1[j] && cy[i] <= ly2[j] &&
              (lx2[j]-lx1[j]) * (ly2[j]-ly1[j]) <= 0.25 * W * H) { covered = 1; break }
        }
        if (!covered) printf "%d %d %d <%s>\n", cx[i], cy[i], ck[i], cc[i]
      }
    }' "$UIXML"
}

# nodes MODE PATTERN ...: PATTERN may list fallbacks, "id:save||Save||class:Button": the first alternative that
# matches anything wins, and stderr says which one (so a report can show which rung a tap used).
nodes() {
  case "$1:$2" in
    match:*"||"*)
      _alts="$2"; _first=1
      while [ -n "$_alts" ]; do
        case "$_alts" in *"||"*) _a="${_alts%%||*}"; _alts="${_alts#*||}" ;; *) _a="$_alts"; _alts="" ;; esac
        _out="$(_nodes_one match "$_a" "${@:3}")"
        if [ -n "$_out" ]; then
          [ "$_first" = 1 ] || echo "selector: fell back to '$_a'" >&2
          printf '%s\n' "$_out"; return 0
        fi
        _first=0
      done
      return 0 ;;
  esac
  _nodes_one "$@"
}

# parse trailing flags: sets F_EXACT F_CLICK F_NTH F_DIR F_MAX, leaves positional args in ARGS
parse_flags() {
  F_EXACT=0; F_CLICK=0; F_NTH=1; F_DIR=down; F_MAX=8; F_AT=center; F_FORCE=0; F_REPLACE=0; F_EXPECT=""; F_WAIT=8; F_UNTIL=0; ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --exact) F_EXACT=1 ;;
      --clickable) F_CLICK=1 ;;
      --nth) F_NTH="$2"; shift ;;
      --dir) F_DIR="$2"; shift ;;
      --max) F_MAX="$2"; shift ;;
      --at) F_AT="$2"; shift ;;
      --force) F_FORCE=1 ;;
      --replace) F_REPLACE=1 ;;
      --expect) F_EXPECT="$2"; shift ;;
      --wait) F_WAIT="$2"; shift ;;
      --until) F_UNTIL="$2"; shift ;;
      *) ARGS+=("$1") ;;
    esac
    shift
  done
}

screen_size() { "${ADB_S[@]}" shell wm size 2>/dev/null | tr -d '\r' 2>/dev/null | awk -F'[: x]+' '/Physical size/ {print $3, $4; exit}'; }

# Wraps text for `input text` on the device shell: spaces -> %s, whole thing single-quoted.
type_text() {
  esc="$(printf '%s' "$1" | sed -e "s/'/'\\\\''/g" -e 's/ /%s/g')"
  "${ADB_S[@]}" shell "input text '$esc'"
}

# Destructive labels are refused unless --force. Defaults can be switched off with
# `unsafe.defaults=off` in .uat; `unsafe=A,B` adds project labels.
UNSAFE_DEFAULTS="log out,logout,sign out,delete account,remove account,pay now,confirm payment"
unsafe_hit() { # LABEL -> prints the matching unsafe term, returns 0 if unsafe
  l="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  list="$(conf_get unsafe | tr '[:upper:]' '[:lower:]')"
  [ "$(conf_get unsafe.defaults)" = "off" ] || list="$UNSAFE_DEFAULTS,$list"
  OLDIFS="$IFS"; IFS=,
  for t in $list; do t="$(printf '%s' "$t" | sed -E 's/^ +| +$//g')"; [ -z "$t" ] && continue
    case "$l" in *"$t"*) IFS="$OLDIFS"; echo "$t"; return 0 ;; esac
  done
  IFS="$OLDIFS"; return 1
}

# Waits up to SECS for LABEL to appear. 0 = seen, 1 = readable screens but label absent,
# 2 = no dump ever succeeded (screen state UNKNOWN: never retry a tap on that).
wait_label() {
  st=$(date +%s); readable=0
  while [ $(( $(date +%s) - st )) -lt "$2" ]; do
    if dump_ui "$UIXML"; then
      readable=1
      [ -n "$(nodes match "$1" 0 0 | head -1)" ] && return 0
    fi
    sleep 1
  done
  [ "$readable" = 1 ] && return 1 || return 2
}

tap_match() { # LABEL -> taps Nth match; returns 1 if none
  dump_ui "$UIXML" || { [ "${F_UNTIL:-0}" -gt 0 ] && return 1; dump_failed; }
  line="$(nodes match "$1" "$F_EXACT" "$F_CLICK" "$F_AT" | sed -n "${F_NTH}p")"
  [ -z "$line" ] && return 1
  if [ "$F_FORCE" != 1 ] && hit="$(unsafe_hit "${line#* * * }")"; then
    echo "REFUSED: '${line#* * * }' matches unsafe term '$hit'. Use --force only if the task requires it." >&2; exit 3
  fi
  set -- $line
  echo "tap $1 $2  (${line#* * * })"
  "${ADB_S[@]}" shell input tap "$1" "$2"
}

case "$cmd" in
  help|-h|--help)
    cat <<'EOF'
flutter-uat: label-driven touch navigation. uat.sh [-s SERIAL|--role NAME] [-p PKG] <cmd>

READ      labels                       every labeled node: "CX CY CLICKABLE LABEL"
          unlabeled                    interactive nodes with NO label (reach via class:EditText[--nth N])
          routes [--reset]             screens the app itself reported (needs the route hook; exact coverage)
          closesheet                   close a bottom sheet (Scrim, swipe handle, back); reports how
          merged                       tall clickable nodes with long/multi-line labels (centre tap may miss the button)
          find LABEL [--exact] [--clickable]
          dump [FILE]                  raw UI XML
          doctor                       is a usable semantics tree present?
ACT       taplabel LABEL [--nth N] [--exact] [--clickable] [--until SECS] [--at top|bottom]  (merged nodes: center may miss the button)
          taplabel ... [--expect LABEL [--wait S]]  verify the next screen; retry the tap once if it is not seen
          taplabel refuses destructive labels (Log out, Delete account, Pay now, .uat unsafe=) unless --force
          typein LABEL TEXT [--replace]  tap the field, then type (--replace clears it first)
          slide LABEL                  swipe a slider from its left end to its right end
          backbtn                      labeled Back, else .uat back.unlabeled (X,Y@WxH), else system back
          nags                         dismiss nag= dialogs listed in .uat
          scrollto LABEL [--dir down|up] [--max N]   swipe until LABEL appears
          tap X Y | swipe X1 Y1 X2 Y2 [MS] | text STR | key CODE | back | home | hidekb
WAIT      waitfor LABEL [SECS] [ALT...]   MATCHED/TIMEOUT; extra labels = failure branches
          gone LABEL [SECS]            wait until LABEL disappears
          assert LABEL [--exact]       exit 1 if absent now
          settle [SECS]                wait for identical consecutive screenshots
APP       launch | stop | link URI | install APK | clear
OBSERVE   shot [FILE] | shotsmall [FILE] [PX] | logclear | logdump
DEVICE    devices | anims 0|1 | raw <adb args>
PROJECT   bootstrap [--write|--check|--sdk]   discover the project, check host, write .uat
          build [debug|release] [--flavor F] [-t FILE] [--define K=V] [--install]   build with the right SDK, repo left as found
          flow FILE [--keep-going]      run a scripted scenario: a step per line, assertion per step, markdown report
          walk [--taps N] [--depth D] [--minutes M] [--root PROJECT]   bounded label crawl + markdown report (needs python3)
          coverage [--all-screens] [--reset]   routed screens reached by the recorded walks (heuristic, from source strings)
          build --clean [--yes]        remove ONLY the build output this tool created
          emu list | start AVD|--role R [--port N] [--wipe] | stop SERIAL   never touches emulators it did not start
Order of trust: labels/find/waitfor > logdump > screenshots (only for visual checks).
EOF
    ;;
  devices) "$ADB" devices -l ;;
  tap)   "${ADB_S[@]}" shell input tap "$1" "$2" ;;
  swipe) "${ADB_S[@]}" shell input swipe "$1" "$2" "$3" "$4" "${5:-300}" ;;
  text)  type_text "$1" ;;
  key)   "${ADB_S[@]}" shell input keyevent "$1" ;;
  back)  "${ADB_S[@]}" shell input keyevent 4 ;;
  hidekb) # dismiss the soft keyboard only if shown (KEYCODE 111 does NOT work; back does, but navigates if no keyboard)
    if "${ADB_S[@]}" shell dumpsys input_method 2>/dev/null | grep -q 'mInputShown=true'; then
      "${ADB_S[@]}" shell input keyevent 4; echo "keyboard hidden"; else echo "no keyboard"; fi ;;
  home)  "${ADB_S[@]}" shell input keyevent 3 ;;
  shot)
    out="${1:-$STATE/shot.png}"; "${ADB_S[@]}" exec-out screencap -p > "$out"; echo "$out" ;;
  shotsmall)
    out="${1:-$STATE/shot.png}"; "${ADB_S[@]}" exec-out screencap -p > "$out"
    if command -v sips >/dev/null 2>&1; then sips -Z "${2:-640}" "$out" >/dev/null
    elif command -v convert >/dev/null 2>&1; then convert "$out" -resize "${2:-640}x${2:-640}" "$out"; fi
    echo "$out" ;;
  dump)  out="${1:-$UIXML}"; dump_ui "$out" || dump_failed; echo "$out" ;;
  labels) dump_ui "$UIXML" || dump_failed; nodes all "" ;;
  unlabeled) dump_ui "$UIXML" || dump_failed; nodes unlabeled "" ;;
  find)
    parse_flags "$@"; dump_ui "$UIXML" || dump_failed
    nodes match "${ARGS[0]}" "$F_EXACT" "$F_CLICK" "$F_AT" ;;
  taplabel)
    parse_flags "$@"
    if [ "${F_UNTIL:-0}" -gt 0 ]; then
      # wait-then-tap in ONE step: tap from the same dump that first shows the label, so a short-lived
      # button (offered for ~12 s) is not lost to the latency of a separate waitfor plus taplabel
      _end=$(( $(date +%s) + F_UNTIL ))
      until tap_match "${ARGS[0]}"; do
        [ "$(date +%s)" -ge "$_end" ] && { echo "TIMEOUT after ${F_UNTIL}s: no node matching: ${ARGS[0]}" >&2; exit 1; }
        sleep 0.3
      done
    else
      tap_match "${ARGS[0]}" || { echo "no node matching: ${ARGS[0]} (nth $F_NTH)" >&2; exit 1; }
    fi
    if [ -n "$F_EXPECT" ]; then   # first tap after some transitions is swallowed: verify, retry ONCE
      wait_label "$F_EXPECT" "$F_WAIT"; rc=$?
      if [ $rc = 0 ]; then echo "EXPECT ok: $F_EXPECT"
      elif [ $rc = 2 ]; then echo "EXPECT UNKNOWN: screen not readable for ${F_WAIT}s (animating or busy); NOT retrying the tap. Check with 'labels'/'shot'." >&2; exit 5
      else
        echo "expected '$F_EXPECT' not seen after ${F_WAIT}s; retrying the tap once"
        tap_match "${ARGS[0]}" || { echo "target gone on retry; EXPECT FAILED: $F_EXPECT" >&2; exit 1; }
        wait_label "$F_EXPECT" "$F_WAIT"; rc=$?
        if [ $rc = 0 ]; then echo "EXPECT ok after retry: $F_EXPECT"
        else echo "EXPECT FAILED: $F_EXPECT" >&2; exit 1; fi
      fi
    fi ;;
  slide)  # swipe slider: knob = the leftmost small node on the label's row (often an unlabeled, non-clickable View)
    parse_flags "$@"; dump_ui "$UIXML" || dump_failed
    a="$(nodes match "${ARGS[0]}" "$F_EXACT" 0 left | head -1)"
    [ -z "$a" ] && { echo "no node matching: ${ARGS[0]}" >&2; exit 1; }
    read -r lx ly _ <<<"$(nodes match "${ARGS[0]}" "$F_EXACT" 0 | head -1)"
    read -r W _ <<<"$(screen_size)"; W="${W:-1080}"
    knob="$(awk -v cx="$lx" -v cy="$ly" 'BEGIN{RS="<"}
      /^node /{ s=$0; m=index(s," bounds=\""); if(!m) next; s=substr(s,m+9); s=substr(s,1,index(s,"\"")-1)
        gsub(/\]\[/,",",s); gsub(/[\[\]]/,"",s); split(s,c,","); w=c[3]-c[1]; yy=(c[2]+c[4])/2
        if (yy>cy-70 && yy<cy+70 && c[3]<cx && w>=60 && w<=300 && (best==""||c[1]<bx)) {bx=c[1]; best=(c[1]+c[3])/2 " " yy} }
      END{print best}' "$UIXML")"
    if [ -n "$knob" ]; then read -r x1 y <<<"$knob"; src="knob found on the row"
    else read -r x1 y _ <<<"$a"; src="no knob node found: assuming the label's left end (verify)"; fi
    x2=$(( W - 70 ))
    echo "swipe $x1 $y -> $x2 $y ($src); then waitfor the result"
    "${ADB_S[@]}" shell input swipe "$x1" "$y" "$x2" "$y" 600 ;;
  backbtn)  # labeled Back first; else the .uat back.unlabeled spot (only if an unlabeled control is really there); else system back
    dump_ui "$UIXML" || dump_failed
    for l in "Back" "Navigate up" "Close"; do
      line="$(nodes match "$l" 1 0 | head -1)"
      [ -n "$line" ] && { set -- $line; echo "tap $1 $2 (labeled: $l)"; "${ADB_S[@]}" shell input tap "$1" "$2"; exit 0; }
    done
    spec="$(conf_get back.unlabeled)"
    if [ -n "$spec" ]; then
      xy="${spec%@*}"; ref="${spec#*@}"; [ "$ref" = "$spec" ] && ref=""
      bx="${xy%,*}"; by="${xy#*,}"; read -r W H <<<"$(screen_size)"
      if [ -n "$ref" ] && [ -n "${W:-}" ]; then bx=$(( bx * W / ${ref%x*} )); by=$(( by * H / ${ref#*x} )); fi
      hit="$(nodes unlabeled "" | awk -v x="$bx" -v y="$by" '{dx=$1-x; dy=$2-y; if (dx<0) dx=-dx; if (dy<0) dy=-dy; if (dx<=60 && dy<=60) {print; exit}}')"
      if [ -n "$hit" ]; then read -r hx hy _ <<<"$hit"; echo "tap $hx $hy (unlabeled control found near the .uat back.unlabeled spot)"; "${ADB_S[@]}" shell input tap "$hx" "$hy"; exit 0; fi
      echo "back.unlabeled=$spec set, but no unlabeled control near ($bx,$by) on this screen; using system back" >&2
    fi
    echo "system back"; "${ADB_S[@]}" shell input keyevent 4
    # back on a root screen leaves the app (measured): say so instead of letting the next dump describe the launcher
    sleep 1; pk="$(resolve_pkg)"
    fg="$("${ADB_S[@]}" shell dumpsys activity activities 2>/dev/null | tr -d '\r' 2>/dev/null | awk '/topResumedActivity|mResumedActivity/ {for(i=1;i<=NF;i++) if ($i ~ /\//) {split($i,a,"/"); print a[1]; exit}}')"
    if [ -n "$pk" ] && [ "$fg" != "$pk" ]; then echo "WARN: back left the app (foreground is '$fg'); 'launch' to return" >&2; exit 4; fi ;;
  nags)  # dismiss known nag dialogs listed in .uat as nag=Maybe Later,Not now (nothing is dismissed by default)
    list="$(conf_get nag)"; [ -z "$list" ] && { echo "no nag= in .uat; nothing to dismiss"; exit 0; }
    dump_ui "$UIXML" || dump_failed
    OLDIFS="$IFS"; IFS=,; n=0
    for l in $list; do l="$(printf '%s' "$l" | sed -E 's/^ +| +$//g')"
      line="$(nodes match "$l" 1 0 | head -1)"
      [ -n "$line" ] && { IFS=" " read -r nx ny _ <<<"$line"; echo "dismiss '$l': tap $nx $ny"; "${ADB_S[@]}" shell input tap "$nx" "$ny"; n=$((n+1)); break; }
    done
    IFS="$OLDIFS"; [ "$n" = 0 ] && echo "no nag present" ;;
  merged) dump_ui "$UIXML" || dump_failed; nodes merged "" ;;
  geo)  # geo LAT LNG: set the emulator GPS (emulators only). Default emulator GPS is California.
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || { echo "usage: geo LAT LNG   (e.g. geo 6.5244 3.3792 for Lagos)" >&2; exit 2; }
    case "${ANDROID_SERIAL:-${SERIAL:-}}" in emulator-*) ;; *) "${ADB_S[@]}" get-serialno 2>/dev/null | grep -q '^emulator-' || { echo "geo works on emulators only" >&2; exit 2; } ;; esac
    "${ADB_S[@]}" emu geo fix "$2" "$1" 2>&1 | tr -d '\r' 2>/dev/null | head -1; echo "gps set to lat=$1 lng=$2" ;;
  jump)  # jump PATH: ask the app (snippets/uat_jump.dart, UAT_ROUTES build) to go(PATH); logs UAT_JUMP
    [ -n "${1:-}" ] || { echo "usage: jump /route/path" >&2; exit 2; }
    pk="$(resolve_pkg)"; [ -n "$pk" ] || { echo "no package" >&2; exit 2; }
    "${ADB_S[@]}" logcat -c 2>/dev/null
    ra="$("${ADB_S[@]}" shell "run-as $pk sh -c 'echo \"go $1\" > cache/uat_cmd'" 2>&1 | head -2)"
    case "$ra" in *"not debuggable"*) echo "jump needs a debuggable build: this is a release (or non-debuggable) APK. Build debug with --dart-define=UAT_ROUTES=true." >&2; exit 2 ;; esac
    [ -n "$ra" ] && echo "$ra" >&2
    for _ in 1 2 3 4 5 6; do sleep 0.7
      r="$("${ADB_S[@]}" logcat -d -s flutter 2>/dev/null | tr -d '\r' 2>/dev/null | grep -o 'UAT_JUMP path=[^ ]* result=.*' | tail -1)"
      [ -n "$r" ] && { echo "$r"; case "$r" in *result=ok*) exit 0 ;; *) exit 1 ;; esac; }
    done
    echo "no UAT_JUMP reply (is the app running a UAT_ROUTES build with UatJump.start installed?)"; exit 1 ;;
  routes)  # harvest UAT_ROUTE lines (snippets/uat_route_observer.dart, build with UAT_ROUTES=true) from logcat
    rp="$(resolve_pkg)"; rl="$_tmp/flutter-uat/routes-${rp:-app}.log"
    [ "${1:-}" = "--reset" ] && { rm -f "$rl"; "${ADB_S[@]}" logcat -c 2>/dev/null; echo "route log cleared (logcat too)"; exit 0; }
    "${ADB_S[@]}" logcat -d -s flutter 2>/dev/null | tr -d '\r' 2>/dev/null | grep -o 'UAT_ROUTE class=[^ ]*' | sed 's/UAT_ROUTE class=//' | grep -vx -- '-' >> "$rl" 2>/dev/null
    [ -f "$rl" ] && { sort -u "$rl" -o "$rl"; cat "$rl"; } || echo "no UAT_ROUTE lines yet (was the app built with --dart-define=UAT_ROUTES=true and the observer installed?)" ;;
  closesheet)  # close a modal bottom sheet: Scrim tap (measured 8/8), then swipe down the drag handle, then back
    scrim_on() { dump_ui "$UIXML" && [ -n "$(nodes match Scrim 1 0 | head -1)" ]; }
    scrim_on || { echo "no sheet open (no Scrim node)"; exit 0; }
    F_EXACT=1; F_CLICK=0; F_NTH=1; F_AT=center; F_FORCE=1
    tap_match Scrim >/dev/null && sleep 1.5 && { scrim_on || { echo "closed (Scrim tap)"; exit 0; }; }
    line="$(nodes match Dismiss 1 0 | head -1)"; read -r W H <<<"$(screen_size)"
    if [ -n "$line" ]; then read -r hx hy _ <<<"$line"; "${ADB_S[@]}" shell input swipe "$hx" "$hy" "$hx" "$(( ${H:-2400} - 60 ))" 300; sleep 1.5
      scrim_on || { echo "closed (swipe down)"; exit 0; }; fi
    pk="$(resolve_pkg)"
    for _ in 1 2; do
      "${ADB_S[@]}" shell input keyevent 4; sleep 1.5
      fg="$("${ADB_S[@]}" shell dumpsys activity activities 2>/dev/null | tr -d '\r' 2>/dev/null | awk '/topResumedActivity|mResumedActivity/ {for(i=1;i<=NF;i++) if ($i ~ /\//) {split($i,a,"/"); print a[1]; exit}}')"
      [ -n "$pk" ] && [ "$fg" != "$pk" ] && { echo "WARN: back left the app; 'launch' to return" >&2; exit 4; }
      scrim_on || { echo "closed (back)"; exit 0; }
    done
    echo "STILL OPEN after Scrim, swipe and back: restart the app (stop + launch)" >&2; exit 1 ;;
  typein)
    parse_flags "$@"
    tap_match "${ARGS[0]}" || { echo "no field matching: ${ARGS[0]}" >&2; exit 1; }
    sleep 0.5
    if [ "$F_REPLACE" = 1 ]; then   # clear the field first: cursor to end, then 60 deletes
      "${ADB_S[@]}" shell 'input keyevent 123; for i in $(seq 1 60); do input keyevent 67; done'
    fi
    type_text "${ARGS[1]}" ;;
  scrollto)
    parse_flags "$@"; read -r W H <<<"$(screen_size)"; W="${W:-1080}"; H="${H:-2000}"
    x=$((W / 2)); hi=$((H * 7 / 10)); lo=$((H * 3 / 10))
    i=0
    while [ "$i" -le "$F_MAX" ]; do
      dump_ui "$UIXML" || dump_failed
      line="$(nodes match "${ARGS[0]}" "$F_EXACT" "$F_CLICK" | head -1)"
      if [ -n "$line" ]; then echo "FOUND after $i swipes: $line"; exit 0; fi
      if [ "$F_DIR" = down ]; then "${ADB_S[@]}" shell input swipe "$x" "$hi" "$x" "$lo" 400
      else "${ADB_S[@]}" shell input swipe "$x" "$lo" "$x" "$hi" 400; fi
      sleep 0.6; i=$((i + 1))
    done
    echo "NOT FOUND after $F_MAX swipes: ${ARGS[0]}" >&2; exit 1 ;;
  waitfor)
    first="$1"; limit="${2:-12}"; shift; [ $# -gt 0 ] && shift
    start=$(date +%s)
    while [ $(( $(date +%s) - start )) -lt "$limit" ]; do
      if dump_ui "$UIXML"; then
        for lbl in "$first" "$@"; do
          if [ -n "$(nodes match "$lbl" 0 0 | head -1)" ]; then
            echo "MATCHED after $(( $(date +%s) - start ))s: $lbl"; exit 0
          fi
        done
      fi
      sleep 1
    done
    echo "TIMEOUT after ${limit}s: $first $*"; exit 1 ;;
  gone)
    lbl="$1"; limit="${2:-12}"; start=$(date +%s)
    while [ $(( $(date +%s) - start )) -lt "$limit" ]; do
      if dump_ui "$UIXML" && [ -z "$(nodes match "$lbl" 0 0 | head -1)" ]; then
        echo "GONE after $(( $(date +%s) - start ))s: $lbl"; exit 0
      fi
      sleep 1
    done
    echo "STILL PRESENT after ${limit}s: $lbl"; exit 1 ;;
  assert)
    parse_flags "$@"; dump_ui "$UIXML" || dump_failed
    line="$(nodes match "${ARGS[0]}" "$F_EXACT" 0 | head -1)"
    if [ -n "$line" ]; then echo "PASS: $line"; else echo "FAIL: not on screen: ${ARGS[0]}"; exit 1; fi ;;
  settle)
    limit="${1:-8}"; start=$(date +%s)
    "${ADB_S[@]}" exec-out screencap -p > "$STATE/a.png"
    while [ $(( $(date +%s) - start )) -lt "$limit" ]; do
      sleep 1; "${ADB_S[@]}" exec-out screencap -p > "$STATE/b.png"
      if cmp -s "$STATE/a.png" "$STATE/b.png"; then echo "settled"; exit 0; fi
      mv "$STATE/b.png" "$STATE/a.png"
    done
    echo "not settled after ${limit}s (cursors/spinners never settle; not a failure)" ;;
  launch)
    p="$(resolve_pkg)"; [ -z "$p" ] && { echo "cannot resolve package; pass -p or add package= to .uat" >&2; exit 2; }
    # 'monkey' silently fails to foreground the app on tested images; resolve the activity and am start it.
    act="$("${ADB_S[@]}" shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$p" 2>/dev/null | tr -d '\r' 2>/dev/null | tail -1)"
    case "$act" in */*) ;; *) echo "no launcher activity for $p (installed?)" >&2; exit 1 ;; esac
    "${ADB_S[@]}" shell am start -n "$act" >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8; do
      sleep 1
      fg="$("${ADB_S[@]}" shell dumpsys activity activities 2>/dev/null | tr -d '\r' 2>/dev/null | awk '/topResumedActivity|mResumedActivity/ {for(i=1;i<=NF;i++) if ($i ~ /\//) {split($i,a,"/"); print a[1]; exit}}')"
      [ "$fg" = "$p" ] && { echo "launched $p"; exit 0; }
    done
    echo "launch requested but foreground is '$fg'" >&2; exit 1 ;;
  stop)
    p="$(resolve_pkg)"; "${ADB_S[@]}" shell am force-stop "$p" && echo "stopped $p" ;;
  clear)
    p="$(resolve_pkg)"; "${ADB_S[@]}" shell pm clear "$p" ;;
  link)
    p="$(resolve_pkg)"; uri="$1"
    # single-quote device-side; use plain & between params, never \&
    "${ADB_S[@]}" shell "am start -a android.intent.action.VIEW -d '$uri' $p" ;;
  install)
    "${ADB_S[@]}" install -r "$1"
    p="$(resolve_pkg)"; [ -n "$p" ] && "${ADB_S[@]}" shell dumpsys package "$p" | grep -E 'lastUpdateTime|versionName' ;;
  logclear) "${ADB_S[@]}" logcat -c ;;
  logdump)
    # Apps often log Authorization headers and tokens; never let them reach agent context.
    "${ADB_S[@]}" logcat -d 'flutter:V' 'AndroidRuntime:E' '*:S' \
      | sed -E 's/(Bearer )[A-Za-z0-9._~+\/=-]+/\1<redacted>/g; s/((refresh|access|id)_?token|authorization|password|otp|secret|api_?key)([":= ]+)[^ ,}"]+/\1\3<redacted>/Ig' ;;
  anims)
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
      "${ADB_S[@]}" shell settings put global "$k" "${1:-0}"
    done
    echo "animation scales set to ${1:-0}" ;;
  doctor)
    "$(cd "$(dirname "$0")" && pwd)/bootstrap.sh" --check --quiet 2>/dev/null | sed -E 's/^(bootstrap: )?/bootstrap: /'
    echo "adb:     $ADB"; echo "device:  $SERIAL"; echo "package: $(resolve_pkg)"
    echo "size:    $(screen_size)"
    fg="$("${ADB_S[@]}" shell dumpsys activity activities 2>/dev/null | tr -d '\r' 2>/dev/null | awk '/topResumedActivity|mResumedActivity/ {for(i=1;i<=NF;i++) if ($i ~ /\//) {split($i,a,"/"); print a[1]; exit}}')"
    echo "foreground: $fg"
    echo "host load: $(uptime | sed -E 's/.*averages?: ([0-9.]+).*/\1/') (timings and ANRs are meaningless above ~8)"
    sw="$(sysctl -n vm.swapusage 2>/dev/null | awk '{gsub(/M/,""); if ($3>0) printf "%d", 100*$6/$3}')"
    [ -n "$sw" ] && echo "swap used: ${sw}% (above ~80% the emulator slows even when load is calm)"
    if [ -n "$(resolve_pkg)" ] && [ "$fg" != "$(resolve_pkg)" ]; then
      echo "FAIL: foreground is '$fg', not the app under test. Run 'launch' (or open it) first."; exit 1
    fi
    if dump_ui "$UIXML"; then
      total=$(grep -o '<node ' "$UIXML" | wc -l | tr -d ' ')
      labeled=$(nodes all "" | wc -l | tr -d ' ')
      echo "nodes:   $total total, $labeled labeled"
      if [ "$labeled" -lt 2 ]; then
        echo "WARN: (almost) no labeled nodes. Either the app is still on a text-less splash (wait and"
        echo "      retry: 'waitfor' a known label), or Flutter semantics are off. See SKILL.md."
        exit 1
      fi
      echo "OK: semantics tree present"
    else
      echo "FAIL: uiautomator dump produced nothing (no semantics tree, or a profile/release build"
      echo "      that never built one). See SKILL.md 'Semantics are off'."; exit 1
    fi ;;
  raw) "${ADB_S[@]}" "$@" ;;
  *) echo "unknown command: $cmd (try: help)" >&2; exit 1 ;;
esac
