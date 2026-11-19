#!/usr/bin/env bash
# flutter-uat coverage: which of the app's ROUTED screens did a walk actually reach?
#
#   coverage.sh [--root DIR] [--all-screens] [--show-hints] [--reset] [--log]
#
# Every successful UI dump of an app records its label set (when it changed) into a visit log
# keyed by package. This command lists the screen classes the router builds, derives distinctive
# label literals for each from its source, and checks them against the visit log.
#   reached        a literal unique to that screen was seen on a visited screen
#   not reached    literals exist but none was seen
#   unmatchable    the screen has no literal that no other screen shares: it can't be told apart
# A heuristic from source strings, NOT proof: dynamic text and localisation hide screens.
# `.uat` may carry `unreachable.<Class>=reason` for screens a walk cannot reach (unwired, needs
# backend or hardware); those reasons are printed next to "not reached".
set -u
ROOT=""; ALL=0; HINTS=0; RESET=0; SHOWLOG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;; --all-screens) ALL=1; shift ;; --show-hints) HINTS=1; shift ;;
    --reset) RESET=1; shift ;; --log) SHOWLOG=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;; *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$ROOT" ]; then d="$PWD"; while [ "$d" != "/" ] && [ ! -f "$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done; ROOT="$d"; fi
[ -f "$ROOT/pubspec.yaml" ] || { echo "no pubspec.yaml found from $PWD" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"; cd "$ROOT" || exit 2
conf() { [ -f .uat ] && awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; exit}' .uat; }

_tmp="${TMPDIR:-/tmp}"; _tmp="${_tmp%/}"; SD="$_tmp/flutter-uat"
PKG="$(conf package)"
if [ -z "$PKG" ]; then
  for g in android/app/build.gradle.kts android/app/build.gradle; do
    [ -f "$g" ] && PKG="$(grep -E 'applicationId' "$g" | grep -v applicationIdSuffix | head -1 | sed -nE "s/.*[\"']([A-Za-z0-9_.]+)[\"'].*/\1/p")" && [ -n "$PKG" ] && break
  done
fi
# flavors add a suffix; the visit log is matched by prefix so rider/driver walks both count
LOGS="$(ls "$SD"/visits-"$PKG"*.log 2>/dev/null)"
RLOGS="$(ls "$SD"/routes-"$PKG"*.log 2>/dev/null)"
[ "$SHOWLOG" = 1 ] && { echo "package: $PKG"; echo "logs: ${LOGS:-none}"; exit 0; }
if [ "$RESET" = 1 ]; then rm -f "$SD"/visits-"$PKG"*.log "$SD"/routes-"$PKG"*.log; echo "visit log cleared for $PKG*"; exit 0; fi

# ---- 1. screens the router builds ---------------------------------------------------------
RFILES="$(grep -rlE 'GoRoute\(|GetPage\(|AutoRoute\(|onGenerateRoute|MaterialPageRoute|CupertinoPageRoute' lib 2>/dev/null | sort)"
if [ "$ALL" = 1 ] || [ -z "$RFILES" ]; then
  [ -z "$RFILES" ] && echo "no router files found: listing every *Screen/*Page class under lib/ instead"
  CLASSES="$(grep -rhoE 'class [A-Z][A-Za-z0-9]*(Screen|Page) ' lib 2>/dev/null | awk '{print $2}' | sort -u)"
else
  CLASSES="$(echo "$RFILES" | while read -r f; do grep -hoE '\b[A-Z][A-Za-z0-9]*(Screen|Page)\(' "$f"; done | tr -d '(' | sort -u)"
fi
[ -z "$CLASSES" ] && { echo "no screen classes found"; exit 0; }

# ---- 2. label literals per screen (own file + its `_partial.dart` siblings) ----------------
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
: > "$W/hints.tsv"
echo "$CLASSES" | while read -r C; do
  f="$(grep -rlE "class $C( |<|\{)" lib 2>/dev/null | head -1)"; [ -z "$f" ] && { echo "$C" >> "$W/external.txt"; continue; }
  dir="$(dirname "$f")"
  { cat "$f"; for p in "$dir"/_*.dart; do [ -f "$p" ] && cat "$p"; done; } 2>/dev/null \
    | grep -oE "'[^'\$\\\\]{4,60}'|\"[^\"\$\\\\]{4,60}\"" | sed -E "s/^.(.*).\$/\1/" \
    | awk '/^[A-Z0-9]/ && !/^(package|dart|assets|http)/ && /[A-Za-z]/ && (/ / || !/[a-z][A-Z]/) && !/[(){}=&<>|]|^_|[a-z]_[A-Za-z]| error$/ && !/^[a-z0-9_.\/:-]+$/ && !/\.(png|svg|json|dart)$/' | sort -u \
    | while read -r h; do printf '%s\t%s\t%s\n' "$C" "$h" "$f"; done >> "$W/hints.tsv"
done

# literals shared by several screens cannot identify any of them
awk -F'\t' 'NF>=2 && $2!="" {n[$2]++} END {for (k in n) if (n[k]==1) print k}' "$W/hints.tsv" > "$W/unique.txt"

# ---- 3. visited label text, lowercased ---------------------------------------------------
if [ -z "$LOGS" ]; then echo "package $PKG: no visit log yet (walk the app with uat.sh first; every dump is recorded)"; VIS=""
else cat $LOGS | tr '[:upper:]' '[:lower:]' | sed 's/^/|/; s/$/|/' > "$W/visits.txt"; VIS=1; fi
NVIS="$( [ -n "$VIS" ] && cat $LOGS | wc -l | tr -d ' ' || echo 0)"

# ---- 4. verdict per screen ---------------------------------------------------------------
reached=0; notr=0; unm=0; total=0; : > "$W/out.txt"; touch "$W/external.txt"
[ -n "$RLOGS" ] && cat $RLOGS | sort -u > "$W/routes.txt" || : > "$W/routes.txt"
for C in $CLASSES; do
  grep -qx "$C" "$W/external.txt" && continue
  total=$((total + 1))
  if grep -qx "$C" "$W/routes.txt"; then reached=$((reached + 1)); echo "reached	$C	route log (exact)" >> "$W/out.txt"; continue; fi
  mine="$(awk -F'\t' -v c="$C" 'NR==FNR {u[$0]=1; next} $1==c && $2!="" && ($2 in u) {print $2}' "$W/unique.txt" "$W/hints.tsv")"
  if [ -z "$mine" ]; then unm=$((unm + 1)); echo "unmatchable	$C	no label unique to this screen" >> "$W/out.txt"; continue; fi
  hit=""; nh=0; strong=""
  if [ -n "$VIS" ]; then
    while IFS= read -r h; do
      lh="$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')"
      if grep -qF -- "|$lh|" "$W/visits.txt" || { [ "${#lh}" -ge 14 ] && grep -qF -- "$lh" "$W/visits.txt"; }; then
        nh=$((nh + 1)); [ -z "$hit" ] && hit="$h"; [ "${#lh}" -ge 14 ] && strong=1
      fi
    done <<EOF
$mine
EOF
    # one short word ("Password", "CARD") also appears on unrelated screens: need 2 distinct hits or one long label
    [ "$nh" -lt 2 ] && [ -z "$strong" ] && hit=""
  fi
  if [ -n "$hit" ]; then reached=$((reached + 1)); echo "reached	$C	saw \"$hit\"" >> "$W/out.txt"
  else
    notr=$((notr + 1)); why="$(conf "unreachable.$C")"
    if [ -n "$why" ]; then note="reason: $why"; else note="expects e.g. \"$(echo "$mine" | head -1)\""; fi
    echo "not reached	$C	$note" >> "$W/out.txt"
  fi
done

echo "package: $PKG   walks recorded: $NVIS label sets   route log: $(wc -l < "$W/routes.txt" | tr -d ' ') screens reported by the app"
echo "screens routed: $total   reached: $reached   not reached: $notr   unmatchable: $unm"
echo "(reached / (routed - unmatchable) = $(awk -v r=$reached -v t=$total -v u=$unm 'BEGIN{d=t-u; if (d>0) printf "%d%%", 100*r/d; else print "n/a"}'))"
if [ -s "$W/routes.txt" ]; then
  g="$(grep -c '^reached	[^	]*	saw' "$W/out.txt")"
  [ "$g" -gt 0 ] && echo "(note: $g of $reached reached screens come from label guesses only, not the route log; they may be false positives. --show-hints lists them)"
fi
echo "(lower bound: reached needs 2 distinct label hits or one >=14-char label; screens sharing all their text stay unmatchable)"
echo "--- not reached"; grep '^not reached' "$W/out.txt" | cut -f2- | sed 's/\t/  /' | sort
if [ -s "$W/routes.txt" ]; then
  extra="$(comm -13 <(echo "$CLASSES" | sort -u) "$W/routes.txt" | paste -sd' ' -)"
  [ -n "$extra" ] && echo "(reported by the app but not in the router inventory: $extra)"
fi
[ -s "$W/external.txt" ] && echo "(not counted, no source under lib/: $(paste -sd' ' "$W/external.txt"))"
echo "--- unmatchable"; grep '^unmatchable' "$W/out.txt" | cut -f2 | paste -sd' ' - | fold -s -w 110
[ "$HINTS" = 1 ] && { echo "--- reached"; grep '^reached' "$W/out.txt" | cut -f2- | sed 's/\t/  /' | sort; }
exit 0
