#!/usr/bin/env bash
# flutter-uat offline regression suite: no device, no network. Replays fabricated UI trees through
# uat.sh (UAT_XML) and bootstrap/coverage against a fabricated project. Each case is a bug we hit.
#   tests/run.sh        exit 0 = all pass
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; U="$HERE/../../lib/src/assets/scripts/uat.sh"; BS="$HERE/../../lib/src/assets/scripts/bootstrap.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; cd "$T"
export ADB=echo UAT_NO_VISITS=1
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
eq()  { [ "$2" = "$3" ] && ok || bad "$1: expected [$3] got [$2]"; }
has() { case "$2" in *"$3"*) ok ;; *) bad "$1: [$2] lacks [$3]" ;; esac; }
n() { echo "<node text=\"$1\" class=\"android.widget.$2\" content-desc=\"$3\" clickable=\"$4\" enabled=\"${6:-true}\" selected=\"${7:-false}\" bounds=\"$5\" />"; }
tree() { { echo '<hierarchy>'; cat; echo '</hierarchy>'; } > "$T/t.xml"; export UAT_XML="$T/t.xml"; }

# entities decode before matching (multi-line label, &amp;, &quot;)
tree <<X
$(n "" View "Phone Number&#10;Tab 1 of 2" true "[0,100][500,200]")
$(n "" View "Terms &amp; Conditions" true "[0,300][500,400]")
$(n "" View "Say &quot;hi&quot;" true "[0,500][500,600]")
$(n "" View " Login" true "[0,700][500,800]")
X
has entity-newline "$($U find "Phone Number Tab 1")" "Phone Number Tab 1 of 2"
has entity-amp "$($U find "Terms & Conditions")" "Terms & Conditions"
has entity-quot "$($U find 'Say "hi"')" 'Say "hi"'
has exact-trim "$($U find "Login" --exact)" "Login"

# id: selector (Semantics(identifier:) -> resource-id) and "||" fallbacks
rid() { echo "<node text=\"\" resource-id=\"$1\" class=\"android.view.View\" content-desc=\"\" clickable=\"$2\" enabled=\"true\" selected=\"false\" bounds=\"$3\" />"; }
tree <<X
$(rid "uat_menu" false "[0,100][100,200]")
$(rid "android:id/content" false "[0,0][1080,2000]")
$(rid "" true "[200,100][300,200]")
$(n "Save" Button "" true "[0,400][500,500]")
$(n "" Button "" true "[0,600][500,700]")
$(n "" Button "" true "[0,800][500,900]")
X
has id-hit "$($U find id:uat_menu)" "id=uat_menu"
eq id-center "$($U find id:uat_menu | cut -d' ' -f1,2)" "50 150"
eq id-skips-framework "$($U find id:content 2>/dev/null | wc -l | tr -d ' ')" "0"
eq id-exact-miss "$($U find id:uat --exact 2>/dev/null | wc -l | tr -d ' ')" "0"
has fallback-first-wins "$($U find 'id:uat_menu||Save||class:Button' 2>&1)" "id=uat_menu"
has fallback-to-label "$($U find 'id:nope||Save||class:Button' 2>&1)" "Save"
has fallback-says-so "$($U find 'id:nope||Save' 2>&1)" "fell back to 'Save'"
has fallback-to-class "$($U find 'id:nope||class:Button' 2>&1)" "fell back to 'class:Button'"
has fallback-tap-nth "$($U taplabel 'id:nope||class:Button' --nth 3 2>&1)" "tap 250 850"
has fallback-tap-id "$($U taplabel 'id:uat_menu||class:Button' 2>&1)" "tap 50 150"
eq fallback-none "$($U find 'id:nope||Nothing' 2>/dev/null | wc -l | tr -d ' ')" "0"

# stability scoring (no device): selftest asserts the counts on fabricated screens
has stability-selftest "$(python3 "$HERE/../../lib/src/assets/scripts/stability.py" --selftest 2>&1)" "selftest ok"
eq stability-needs-paths "$(python3 "$HERE/../../lib/src/assets/scripts/stability.py" >/dev/null 2>&1; echo $?)" "2"

# flow: a PASS must say when optional steps did not pass, and --quiet trims the report
tree <<X
$(n "Present" Button "" true "[0,100][500,200]")
X
printf 'name: opt\n? assert "Missing label"\nassert "Present"\n' > "$T/opt.flow"
fo="$(python3 "$HERE/../../lib/src/assets/scripts/flow.py" "$T/opt.flow" --report "$T/opt.md" 2>&1)"
has flow-optional-warns "$fo" "OPTIONAL step(s) did not pass"
has flow-still-pass "$fo" "result: **PASS**"
fq="$(python3 "$HERE/../../lib/src/assets/scripts/flow.py" "$T/opt.flow" --quiet --report "$T/opt.md" 2>&1)"
has flow-quiet-keeps-optional-row "$fq" "OPTIONAL-FAIL"
case "$fq" in *"| PASS |"*) bad "flow-quiet-hides-passing-rows" ;; *) ok ;; esac

# taplabel --until: wait-then-tap from one dump; times out with exit 1
tree <<X
$(n "Cancel ride" Button "" true "[0,100][500,200]")
X
has until-taps "$($U taplabel 'Cancel ride' --until 3 2>&1)" "tap 250 150"
t0=$(date +%s); $U taplabel 'No such label' --until 2 >/dev/null 2>&1; rc=$?; t1=$(date +%s)
eq until-timeout-exit "$rc" "1"
[ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 6 ] && ok || bad "until-timeout-took-$((t1 - t0))s"

# state flags
tree <<X
$(n "" View "Rides Tab 2 of 4" true "[0,100][500,200]" true true)
$(n "" View "Name" true "[0,300][500,400]" true false)
$(n "" View "Locked" true "[0,500][500,600]" false)
X
has flag-selected "$($U find "Rides")" "[selected]"
has flag-disabled "$($U find "Locked")" "[disabled]"

# unlabeled: a field covered by a small labeled wrapper is not reported; a bare one is
tree <<X
$(n "" EditText "" true "[100,1000][900,1100]")
$(n "" View "Covered" true "[50,1500][950,1700]")
$(n "" Button "" true "[200,1550][300,1650]")
X
out="$($U unlabeled)"; has unlabeled-bare "$out" "<EditText>"; case "$out" in *"250 1600"*) bad "unlabeled-covered reported" ;; *) ok ;; esac
has class-selector "$($U find class:EditText)" "<EditText>"

# --at top / bottom on a tall merged node
tree <<X
$(n "" View "Arrived&#10;Rider Information&#10;Start Trip" true "[0,1083][1080,2400]")
X
eq at-center "$($U find Arrived | cut -d' ' -f2)" "1741"
eq at-top "$($U find Arrived --at top | cut -d' ' -f2)" "1203"
eq at-bottom "$($U find Arrived --at bottom | cut -d' ' -f2)" "2280"
has merged-flag "$($U merged)" "MERGED?"

# unsafe guard: refuse (exit 3), --force overrides, .uat adds, defaults can be switched off
tree <<X
$(n "" View "Log Out" true "[0,100][500,200]")
$(n "" View "Cancel booking" true "[0,300][500,400]")
$(n "" View "Payments" true "[0,500][500,600]")
X
$U taplabel "Log Out" >/dev/null 2>&1; eq guard-refuse $? 3
$U taplabel "Log Out" --force >/dev/null 2>&1; eq guard-force $? 0
$U taplabel "Payments" >/dev/null 2>&1; eq guard-allows-payments $? 0
printf 'unsafe=Cancel booking\n' > .uat; $U taplabel "Cancel booking" >/dev/null 2>&1; eq guard-uat-term $? 3
printf 'unsafe.defaults=off\n' > .uat; $U taplabel "Log Out" >/dev/null 2>&1; eq guard-defaults-off $? 0; rm .uat

# backbtn: finds an unlabeled control near the configured spot and taps ITS centre
tree <<X
$(n "" Button "" true "[40,128][170,208]")
X
printf 'back.unlabeled=74,206@1080x2400\n' > .uat; has backbtn-found "$($U backbtn 2>&1)" "tap 105 168"; rm .uat

# waitfor / assert / gone
tree <<X
$(n "" View "Home" true "[0,100][500,200]")
X
has waitfor "$($U waitfor Home 2)" MATCHED
$U assert Nowhere >/dev/null 2>&1; eq assert-absent $? 1
has gone-timeout "$($U gone Home 1 2>&1)" "STILL PRESENT"

# flow runner: pass/negate/optional/variables/stop-on-fail/denied commands
tree <<X
$(n "" View "Home" true "[0,100][500,200]")
$(n "" View "Welcome Rider" true "[0,300][500,400]")
X
cat > f1.flow <<'F'
name: fixture
set WHO=Rider
assert "Welcome ${WHO}"
! assert "Nowhere"
? assert "Optional missing"
waitfor Home 2
F
"$U" flow f1.flow --report "$T/f1.md" >/dev/null 2>&1; eq flow-pass $? 0
has flow-optional "$(cat "$T/f1.md")" "OPTIONAL-FAIL"
printf 'assert Nowhere\nassert Home\n' > f2.flow
"$U" flow f2.flow --report "$T/f2.md" >/dev/null 2>&1; eq flow-fail-exit $? 1
has flow-skip-after-fail "$(cat "$T/f2.md")" "SKIPPED"
"$U" flow f2.flow --keep-going --report "$T/f2k.md" >/dev/null 2>&1; has flow-keep-going "$(cat "$T/f2k.md")" "| PASS |"
printf 'raw shell id\n' > f3.flow
"$U" flow f3.flow --report "$T/f3.md" >/dev/null 2>&1; has flow-denies-raw "$(cat "$T/f3.md")" "not allowed in a flow"
printf 'taplabel "Log Out"\n' > f4.flow; tree <<X
$(n "" View "Log Out" true "[0,100][500,200]")
X
"$U" flow f4.flow --report "$T/f4.md" >/dev/null 2>&1; has flow-guard-refusal "$(cat "$T/f4.md")" "REFUSED"

# walk --fill refuses without an explicit fill.allow
d0="$(mktemp -d)"; (cd "$d0" && "$U" walk --fill >/dev/null 2>&1); eq walk-fill-refused $? 3; rm -rf "$d0"

# bootstrap + coverage against a fabricated project
P="$T/proj"; mkdir -p "$P/lib" "$P/android/app"; cd "$P"
printf 'name: x\nenvironment:\n  sdk: ^3.5.0\n' > pubspec.yaml
printf 'android {\n defaultConfig { applicationId = "com.fx.app" }\n productFlavors {\n  create("dev") { dimension = "e" }\n  create("prod") { dimension = "e" }\n }\n}\n' > android/app/build.gradle.kts
echo 'final r=[GoRoute(builder:(c,s)=>const AScreen()),GoRoute(builder:(c,s)=>const BScreen())];' > lib/r.dart
echo "class AScreen { x(){ Text('Welcome back to the app'); Text('Sign in to continue'); } }" > lib/a.dart
echo "class BScreen { x(){ Text('Secret admin console'); Text('Hidden tools panel'); } }" > lib/b.dart
has bs-flavors "$("$BS" --root "$P" | sed -n 2p)" "dev,prod"
has bs-package "$("$BS" --root "$P" | sed -n 2p)" "com.fx.app"
"$BS" --root "$P" --write >/dev/null; "$BS" --root "$P" --check >/dev/null; eq bs-fresh $? 0
echo 'final r=[GoRoute(),GoRoute(),GoRoute()];' >> lib/r.dart; "$BS" --root "$P" --check >/dev/null; eq bs-stale $? 1
printf 'skip.C1=\n' >> .uat; has bs-skip-needs-reason "$("$BS" --root "$P")" "has no reason"
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR/flutter-uat"; printf 'Welcome back to the app|Sign in to continue\n' > "$TMPDIR/flutter-uat/visits-com.fx.app.log"
cov="$("$HERE/../../lib/src/assets/scripts/coverage.sh" --root "$P")"; has cov-reached "$cov" "reached: 1"; has cov-not-reached "$cov" "BScreen"

printf 'BScreen\n' > "$TMPDIR/flutter-uat/routes-com.fx.app.log"
cov="$("$HERE/../../lib/src/assets/scripts/coverage.sh" --root "$P")"; has cov-route-log-exact "$cov" "reached: 2"; has cov-route-log-label "$("$HERE/../../lib/src/assets/scripts/coverage.sh" --root "$P" --show-hints)" "route log (exact)"
# sweep: route discovery from source (no device), param fill, match filter, destructive paths named
mkdir -p "$T/sw/lib/routing" && : > "$T/sw/pubspec.yaml"
cat > "$T/sw/lib/routing/rider_routes.dart" <<'D'
class Names {
  static const String home = '/rider/home';
  static const String logout = "/rider/logout";
  static const String detail = '/rider/ride/:id';
  static const inferred = "/rider/inferred-type";
}
D
cat > "$T/sw/lib/routing/driver_routes.dart" <<'D'
final r = GoRoute(path: '/driver/earnings', builder: (c, s) => const X());
D
sl="$($U sweep --root "$T/sw" --list 2>/dev/null)"
has sweep-const "$sl" "/rider/home"
has sweep-path-literal "$sl" "/driver/earnings"
has sweep-inferred-type "$sl" "/rider/inferred-type"
has sweep-param "$sl" "/rider/ride/1   (param filled with 1)"
sl2="$($U sweep --root "$T/sw" --match rider --list 2>/dev/null)"
case "$sl2" in *driver*) bad "sweep --match leaked driver" ;; *) ok ;; esac
$U sweep --root "$T/nope" --list >/dev/null 2>&1; eq sweep-no-project "$?" "2"
$U jump >/dev/null 2>&1; eq jump-usage "$?" "2"

echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
