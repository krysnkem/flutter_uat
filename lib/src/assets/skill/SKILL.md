---
name: flutter-uat
description: >
  Drive and verify any Flutter app on an Android emulator/device by LABEL instead of pixel
  coordinates: read the semantics tree, tap/type/scroll by label, wait on labels as
  assertions, read logcat for crashes. Use when asked to device-test, UAT, click through,
  reproduce a bug on the emulator, or verify a flow in the running app, in any Flutter
  project. Works for multiple simultaneous emulators (roles).
---

# flutter-uat: label-driven touch navigation

Tool: `flutter_uat` (plain bash + adb + python3). Pass the device and package on every call:
`flutter_uat -s emulator-5554 -p com.example.app <command>`. In a shell, wrap it in a function
(`u(){ flutter_uat -s SERIAL -p PKG "$@"; }`); a `U="flutter_uat -s ..."` variable does not work under zsh.

**First use, in this order** (each step needs the one before it):
1. An emulator of your own: `flutter_uat emu create uat_a` (makes a throwaway AVD from an installed
   `google_apis` image; refuses if the name exists), then `flutter_uat emu start uat_a --port 5562`.
   Delete it when done: `flutter_uat emu stop emulator-5562` then `flutter_uat emu delete uat_a` (only AVDs this tool created).
2. `flutter_uat bootstrap` in the project root: toolchain, package id, routes. Read its `warnings:` block.
3. `flutter_uat -s emulator-5562 build debug --install`. If the pin is a floating channel (`.fvmrc` says `stable`) and the
   project's Gradle is older than that Flutter supports, the build fails (measured: Flutter 3.50.0 refused Gradle 8.14,
   minimum 9.3.1); rerun with `--sdk /path/to/older/flutter/bin/flutter` (the build prints the installed SDKs).
4. `flutter_uat launch`, then tap a first-run "Wait"/permission dialog if one appears (a fresh install can ANR once).
5. `flutter_uat doctor`: it needs the app in front, which is why it comes last.

**Why labels:** `uiautomator dump` exposes Flutter's semantics tree with fresh bounds.
`taplabel` taps the centre of a node found *now*, so keyboards, layout shifts, different
AVD sizes and animations cannot cause mis-taps the way remembered coordinates do.

Verification order, always: `labels`/`find`/`waitfor` → `logdump` → screenshot (only for
genuinely visual checks: layout, icons, theme). Exact values (amounts, codes, addresses)
come from `labels` output as strings, never from reading pixels.

Delegating to another agent (Codex etc.): `CONTRACT.md`.
Service levels (measured timings), known limits and the proposed `.uat` bootstrap profile: `SLA.md` (draft), copied next to this file by `flutter_uat install-skill`.

## Bootstrap (once per project, repeat when `--check` says STALE)

`flutter_uat bootstrap` prints what it discovers (package, flavors, SDK pin vs installed, Dart
minimum, AGP/Gradle/Kotlin, route count and hash, mock/e2e dart-defines, Makefile targets,
AVDs) plus host checks C1 (load below the user's limit, default 8) and C5 (free disk above the hard stop, default 5 GiB; set via `host-hygiene.sh config`), and the `.uat` block it would
write. It changes nothing. `bootstrap --write` refreshes only its generated block; your own
lines are kept. `bootstrap --check` exits 0 fresh / 1 stale (names the field) / 3 never run;
`doctor` runs it. `bootstrap --sdk` prints the Flutter binary to build with. Roles, sign-in
recipes and `unsafe=` labels are never guessed. A `skip.Cn=` line without a reason is a FAIL.

## Build and emulator lifecycle (tested 2026-11-17)

- `flutter_uat build [debug|release] [--flavor F] [-t FILE] [--define K=V] [--install]`: uses the SDK from
  `bootstrap --sdk`; defaults from `.uat` (`build.flavor= build.target= build.define=A=1,B=2
  build.args=` and `floor.disk_gib=`, default 5). It REFUSES (exit 7) below the disk floor and
  (exit 6) when bootstrap reports a toolchain measured to fail (sample app C AGP 7.3 on Flutter >= 3.35;
  override `--allow-old-toolchain`, or fix it in a scratch copy). After the build it reverts
  tracked files the tooling rewrote, only those that were clean before (your own uncommitted edits
  are kept: verified on sample app B). On failure it prints the log tail plus a hint (pinned SDK not
  installed; installed SDKs; `--sdk PATH`).
- `flutter_uat build --clean [--yes]` removes ONLY the output dirs this tool created (`build`,
  `.dart_tool`, `android/.gradle`), after `git check-ignore`; dry-run without `--yes`.
- `flutter_uat emu list | start AVD|--role R [--port N] [--wipe] | stop SERIAL`: `start` boots with
  `-no-snapshot-load`, waits for boot (21 s at load ~4), sets animations off, and never starts a
  second copy of a running AVD. `stop` refuses an emulator this tool did not start (exit 3) unless
  `--force`; stale registry entries are pruned by pid. `.uat`: `avd.NAME=` + `role.NAME=emulator-NNNN`.
- Measured: sample app A rider mock debug build 78 s (load 8.5; 171 s on an earlier cold run),
  repo clean afterwards. sample app B cannot be built here: its pin (Flutter 3.47.8) is not installed,
  3.35 fails on Dart, 3.50 fails on AGP 9.1.0 < 9.1.1. Not automated: the scratch-copy toolchain
  patch for old projects.

## Flow file in 10 lines (added after a cold test by an agent with only this doc, sample app B, 2026-11-19)

```
name: Login then tabs                  # title for the report
set EMAIL=test@bank.com                # variable, used as ${EMAIL}
stop                                   # a line is a subcommand WITHOUT the "flutter_uat" prefix
launch
waitfor "Welcome Back" 40
? taplabel Login --exact               # "?" = optional: use it for a sign-in that may already be done
typein class:EditText --nth 1 ${EMAIL} # unlabeled field, by class and position
taplabel "My Savings" --expect "Total Savings" --wait 10
! assert "Error"                       # "!" = must FAIL (absent)
```
Run: `flutter_uat -s SERIAL -p PKG flow FILE` and `flutter_uat -s SERIAL -p PKG repeat 3 FILE...` (the global `-s`/`-p` go BEFORE
`flow`/`repeat`). `repeat` prints a table of pass counts, median and min-max time and the first failing step; it waits for
host load < 8 before every run, and 3 runs of a 4-flow set take over 5 minutes (past a 3-minute tool limit: run it in the
background). Comment lines do not count as steps. `--force` on a `taplabel` is allowed inside a flow (needed for a Logout).
Start state: the app keeps its session across `stop`/`launch`, so decide per flow whether it can assume signed-in or
signed-out; make the sign-in steps optional (`?`) when either can occur. In a shell variable `U="flutter_uat -s ..."` does not
work under zsh: use a function (`u(){ flutter_uat -s SERIAL -p PKG "$@"; }`).
Pitfalls measured by agents writing flows cold:
- **Substring matching makes weak checks.** `--expect "Plan"` and `assert "Create"` pass when the word is already on screen
  (a title, the previous screen). Expect the most specific label of the NEXT screen.
- **`waitfor "A|B"` is not "either".** Extra arguments after the seconds are FAILURE labels (a branch check). For "either",
  use two optional steps or a check that fits both.
- **A PASS can hide a skipped path.** The result line now says how many optional (`?`) steps did not pass; read it. An
  optional sign-in or logout that failed means that path was not exercised.
- **Logging out to test login:** `? taplabel Logout --exact --force` then `waitfor "Login" 15` (a Logout label is refused
  without `--force`). The session persists across `stop`/`launch`, so decide per flow whether it starts signed in.
- **A tap can change tabs silently** ("View All" on a dashboard switches tabs), so a following `back` may leave the app (exit 4).
  Assert the screen you expect before going back.
- **Positions of later fields shift** after earlier ones are filled (`typein ... --nth 3` taps a different y each run);
  it still resolves to the same field.
- `repeat` prints a progress line per run to stderr (`[flow run 2/3] PASS 41s`) and the table at the end; `flow --quiet`
  prints only the result line and the failing or optional-failed steps.
`find LABEL` lists matches and exits 0 even when there are none (it prints nothing), so a `find` step passes vacuously.
Use `assert LABEL` (exit 1 if absent) or `waitfor LABEL SECS` as the check. On a root screen `backbtn`/`back` leaves the app
(exit 4), so write it as `? back` in a flow.
State flags (`[selected]`, `[checked]`, `[disabled]`) are printed by `labels`/`find` but are NOT matchable: `assert "Tab 1 [selected]"`
fails by construction (matching reads the label attributes only); assert on content instead.
The cold test: an agent given only this doc wrote 4 flows for sample app B (prebuilt release APK, mock login) and `repeat 3` passed
12/12 (login 29 s, tabs 32 s, create-form 44 s, read-only 48 s medians). All 7 screens were reached by label except the 3 text
fields, which need `class:EditText --nth N`. It is a pass on a deterministic mock, debugged on the same build; behaviour under
load above 8 was not measured.

## Writing a flow (the agent plans, the tool acts)

1. Read the project first: router file (screens and routes), `.uat`, README/CLAUDE.md for accounts,
   OTP source and mock switches. `coverage` lists routed screens not yet seen: target those.
2. Write a scenario matrix in the session scratchpad BEFORE acting: `#, scenario, steps, expected
   label/value, result`. Fill the result column with observed values, not just PASS.
3. Run it one step at a time: act, then `waitfor`/`assert` the next screen's label (or `--expect`),
   and read `labels` whenever a label is unknown. Batch a sequence only after it passed once by hand.
4. Per step, decide: refused (exit 3) means a destructive label, stop and ask; exit 5 means the screen
   was unreadable, look before retrying; a TIMEOUT is a result to record.

Worked example (a small sample app with a mock backend; each step below was run and passed in this form):

| # | Scenario | Steps | Expected |
|---|---|---|---|
| 1 | Sign in with a one-time code | `taplabel "Get Started" --expect "Create Account"`; `taplabel Login --exact --expect "Welcome Back"`; `typein class:EditText --nth 1 user@example.com`; `hidekb`; `typein class:EditText --nth 2 'example-password'`; `hidekb`; `taplabel Continue --exact`; `waitfor "Verification" 15`; `typein class:EditText 123456`; `taplabel Continue --exact` | `waitfor "Home" 30` matches |
| 2 | Open a tab and read a value | `taplabel "Wallet" --expect "Balance"`; `assert "0.00"` | the balance label is on screen |
| 3 | Open and close a bottom sheet | `taplabel "Set goals" --expect "Set daily target"`; `closesheet` | sheet closed, `gone "Set daily target"` |

The same sign-in written once as `.uat` `signin.steps=` is reused by `walk`. Mock OTP and test accounts
are project facts: put them in the project's own docs, not in this skill.

## Flows, typed input and exact coverage (added 2026-11-17; each tested live on sample app A rider mock, API 30)

- **`flutter_uat flow FILE [--keep-going]`**: a scripted scenario, one `flutter_uat` command per line, with `set K=V`
  / `${K}` / `${env:NAME}`, `? step` (optional), `! step` (must FAIL, e.g. `! assert "Log Out"`), and
  `recover:` lines run once (then the step retried once) when a step exits 4 or 5. Stops at the first failed
  required step unless `--keep-going`. `raw`, `build`, `emu`, `walk` are refused inside a flow; `clear` needs
  `--allow-clear`. Writes a markdown report with the observed output per step. Example:
  `example/login.flow` in the package is a generic starting point. The agent writes the flow.
- **`flutter_uat walk --fill`**: also types test data into text fields (type guessed from the field label and the
  label above it: email, phone, password, amount, otp, name, else text; override with `.uat` `fill.email=` etc.).
  REFUSED (exit 3) unless `.uat` says `fill.allow=mock` or `sandbox`: submitting forms can create real data.
  Measured: it typed into profile and password forms and saved a mock profile. `typein ... --replace` clears
  a field first (without it typein APPENDS to a prefilled value).
- **An app with no router** (`MaterialApp(home: ...)`) has no routes: `bootstrap` reports `routes: 0`. Skip the hooks, `jump` and `sweep`; drive it with flows and `walk` (measured by reading an app that was a single Library screen: nothing here applies).
- **Route hook (changes app code: `flutter_uat install-hooks` copies `uat_route_observer.dart` and `uat_jump.dart` into `lib/uat/`; add
  `UatRouteObserver()` to the router `observers:`; tab bodies need it in each `StatefulShellBranch`).** Build
  with `--define UAT_ROUTES=true` (inert otherwise). `flutter_uat routes` harvests `UAT_ROUTE class=...` lines from
  logcat; `coverage` then counts those screens EXACTLY and flags screens counted only from label guesses.
  Measured: the first hook logged go_router's `Builder` wrapper, so it now finds the first `*Screen`/`*Page`
  widget under the route. The label guess had a false positive (`PrivacyPolicyScreen`, a link text, never opened).
  Tested only in a scratch copy of sample app A; no app repo was modified. Tabs not covered by a branch observer
  show up only as label guesses.
- `walk` now waits for host load < 8 (up to 3 min), dismisses an Android "isn't responding" dialog with Wait,
  and recovers from a cold start. Typed-input walk on the mock rider app: 20 taps, 12 screens, 6 of 76 routed
  reached (4 exact), so coverage stays low: a walk cannot get past gated or data-dependent flows.

### Route jump (reach screens a walk cannot)

`flutter_uat jump /route/path` asks the app to `go()` straight to a route. Needs the `uat_jump.dart` hook from `install-hooks`
(call `UatJump.start(navigatorKey)` in `main()`) and a `UAT_ROUTES=true` debug build; the command is
passed through `run-as` into the app's cache dir, so release builds and non-debuggable APKs cannot be
driven this way. Replies `UAT_JUMP path=... result=ok`. Measured on sample app A rider (mock backend,
signed in): 45 routes jumped, 40 opened, 33 distinct screen classes confirmed by the route log.
Routes whose builder reads `state.extra` open blank (expected: the tool cannot supply the object).
`flutter_uat sweep [--match SUBSTR] [--paths FILE] [--list] [--no-recheck] [--gap REGEX] [--unlabeled]` jumps to every route
found in the router source (or a paths file), classifies each OPEN / BLANK / ERROR / CRASH / NOJUMP /
SKIPPED (destructive-looking paths) and re-jumps anything not OPEN alone after a clean relaunch, so a crash
that needs earlier screens is reported ORDER-DEPENDENT instead of as that route's fault. It also lists log
lines matching `--gap` (default `no fixture for`): backend calls the mock still does not answer.
Known weakness: jumping to the route that is already showing logs no new UAT_ROUTE line, so a repeat of the
current route can read as BLANK. Sample output: `example/jump_sweep_sample.tsv` in the package (older hand-run).
Verify a crash by re-jumping alone: one NPE seen in a sweep did not reproduce, so it is order-dependent.

### Flows against a mocked backend, and repeat runs

The sample flows (sign-in, wallet, saved places, history, funding, booking, cancel) each start from a cold launch so they are independent. `flutter_uat geo LAT LNG` pins the emulator GPS (default is California: fares came out
as millions). `flutter_uat repeat N FLOW...` runs each flow N times at calm host load and reports pass rate,
timing and the first failing step. Measured 2026-11-18, API 30 emulator, debug build, in-app mock backend:
21/21 runs passed (3 each of 7 signed-in flows; sign-in needs a fresh install so it is excluded).
Same flows on a RELEASE build (R8, signed, mock backend + UAT_ROUTES): 21/21 passed, medians within ~3 s of debug
(wallet 32 s, book ride 115 s); sign-in passed 17/18 on a fresh install. `jump` and `sweep` are debug-only.
Caveats: flows were written and debugged against this same build, so 100% is the repeatability of known-good
scripts, not a forecast for new flows. Cancel is only offered for ~12 s while the driver arrives, so the
cancel flows depend on step latency. Unlabeled controls (rating stars) are reached by `class:Button --nth N`.

## Regression suite

The package's own test suite (`dart test` in a checkout; the offline script checks live in `test/offline/run.sh`, no device): 63 checks replaying fabricated trees through the tool for the bugs
we hit (entities, exact trim, state flags, unlabeled coverage, `--at`, merged, unsafe guard, backbtn,
waitfor/assert/gone, bootstrap flavors/staleness/skip rule, coverage). Run it after any change to `flutter_uat`.

## Walk (tested 2026-11-17, needs python3)

`flutter_uat walk [--taps N] [--depth D] [--minutes M] [--root PROJECT] [--no-restart]` starts from a
fresh launch, signs in from `.uat`, taps every clickable label once per screen (depth-first), closes
sheets via Scrim, goes back with `backbtn`, switches bottom tabs, relaunches when it loses its
place, and writes a markdown report (screens, transitions, refusals, unlabeled controls, merged
nodes, log errors, coverage). `.uat` keys: `signin.when=LABEL` (run the steps only while that
label shows), `signin.steps=STEP; ? OPTIONAL STEP` (flutter_uat subcommands, shell quoting, `raw`
refused), `nag=A,B`, `back.unlabeled=X,Y@WxH`. Destructive labels are refused by the guard.
Measured on sample app A mock (API 30, host load 10-47): driver 14 taps / 11 screens, coverage 4
reached; rider 26 taps / 11 screens, coverage 7 reached (13% of routable, lower bound), sign-in with
OTP fully from `signin.steps`. Known gaps: forms and anything needing typed input stay unvisited;
walk closes sheets with `closesheet` and never presses back on a tab root (a list item that switches
tabs made it exit the app twice before the fix); with `--minutes 9` under load tabs may be partly explored.

## Coverage (tested 2026-11-17)

Every successful dump of an app records its label set (when it changed) in
`$TMPDIR/flutter-uat/visits-<package>.log`; `UAT_NO_VISITS=1` turns that off. `flutter_uat coverage`
lists the `*Screen`/`*Page` classes the router builds (`--all-screens` for Navigator-only apps),
derives label literals from each screen's source (own file plus `_partial.dart` siblings; literals
shared by several screens, code fragments, class-name strings and lowercase fragments are dropped)
and reports **reached / not reached / unmatchable**. A screen counts as reached only on a
whole-label match or a >= 14-char substring: short words ("Found", "Lagos") matched unrelated
screens in the first version. So the count is a LOWER BOUND. `.uat` `unreachable.<Class>=reason`
is printed beside a not-reached screen; `coverage --reset` starts a new walk.
Measured: sample app A 76 routed (22 unmatchable) vs an earlier manual router count of 83;
sample app E 60 routed, 1 reached after two read-only dumps of different screens (the agent trips
screen was NOT matched: shared text), fixture project exact (2 reached, 1 reason, 1 unmatchable).

## 0. Preconditions (check once per session)

1. Device: `flutter_uat devices`. One attached device is auto-picked. With several, pass
   `-s emulator-5554`, `--role NAME`, or export `ANDROID_SERIAL`. It refuses to guess.
2. Package: resolved from `-p`, `.uat`, `android/app/build.gradle(.kts)` `applicationId`,
   then the foreground app. Only `launch/stop/clear/link/install` need it.
3. **`flutter_uat doctor`**: confirms the foreground app is the one under test and that a
   labeled tree exists. A WARN right after launch usually means a text-less splash.
4. Once per AVD: `flutter_uat anims 0` (kills system animations; Flutter's own ~300 ms page
   transitions remain, `waitfor` absorbs them).

## Optional per-project config: `.uat` (repo root, plain data)

```
package=com.example.app
role.sender=emulator-5554
role.agent=emulator-5556
```

Look for it, and read the project's own docs (CLAUDE.md, README, `.llm/`, Makefile) for
build commands, sign-in recipes, test accounts and OTP sources. This skill deliberately
knows none of that. If the project has no `.uat` and runs several emulators, offer to
create one; never invent serials.

## Commands

```
READ   labels                        every labeled node: "CX CY CLICKABLE LABEL"
       find LABEL [--exact] [--clickable]
       doctor                        is a usable semantics tree present?
ACT    taplabel LABEL [--nth N] [--exact] [--clickable]
       typein LABEL TEXT             tap the field, then type
       scrollto LABEL [--dir down|up] [--max N]
       tap X Y | swipe X1 Y1 X2 Y2 [MS] | text STR | key CODE | back | home
WAIT   waitfor LABEL [SECS] [ALT...] MATCHED/TIMEOUT; ALT = failure labels (branch check)
       gone LABEL [SECS]             wait until it disappears (spinner, toast, dialog)
       assert LABEL [--exact]        exit 1 if absent
       settle [SECS]                 identical consecutive screenshots
APP    launch | stop | link URI | install APK | clear
LOGS   logclear | logdump            flutter + AndroidRuntime errors only
OTHER  shot/shotsmall [FILE] | anims 0|1 | raw <adb args>
```

Matching is against `text`, `content-desc` and `hint` **only** (never resource-id or
class), case-insensitive substring unless `--exact`. Flutter buttons carry their label in
content-desc; the tool handles that.

## Working rules (each one prevents a false bug)

- **Ambiguity:** `labels` first when the label is unknown. If a label appears twice (tab
  name and screen title, list rows) use `--exact`, `--clickable`, or `--nth N`; do not
  guess. Nodes are in document order, which is roughly top-to-bottom.
- **Wait, don't sleep:** after every navigating tap, `waitfor 'Expected' 8 'Error' 'Failed'`.
  The wait is the assertion. A TIMEOUT is a result to record, not a reason to wait longer.
- **Forms:** `typein 'Phone number' '8012345678'`, then dismiss the keyboard with
  `hidekb` before tapping the submit button below it. Re-run `find` after,
  since the keyboard moves things (bounds are always fresh, so this is cheap).
- **Lists/off-screen targets:** `scrollto LABEL`, then `taplabel`. Not-in-tree is not the
  same as not-in-the-app: lazy lists only build visible rows.
- **DUMP-FAILED** means mid-animation or busy; retry once (the tool already retries
  internally 3×) before recording anything.
- **Deep links:** `link 'scheme://path?a=1&b=2'` uses plain `&`. Writing `\&` leaks a
  backslash into the value and produces fake data bugs. Cold start: `stop` then `link`.
- **Non-visual outcomes** (silent failure, gray screen, crash): `logclear` → act →
  `logdump`.
- **Distinguish harness artifacts from app bugs** before recording a failure: quoting,
  stale coordinates (avoid by never using raw `tap X Y` when a label exists), and
  dump-during-animation. Reproduce once more with `labels` output in hand.
- **Stale installs:** after `install`, confirm `lastUpdateTime` (the command prints it).
  A snapshot boot can resurrect an old build; prefer booting with `-no-snapshot-load`.
- One emulator is serial: never interleave two scenarios on one device. Different
  devices (roles) can run in parallel; state files are per serial.
- Long batteries (10+ scenarios): run the loop in a subagent and return only the filled
  matrix, so dumps don't pile up in the main context.

## Semantics are off

Measured (clean runs, device-side dump file cleared per dump, accessibility services
verified off): sample app E debug 3/3 cold starts with a labeled tree (3-11 s, host load ~11);
sample app B release (APK only, no source) on API 35 and API 30; sample app A rider and driver
(debug, mock API); sample app C (debug, mock API); sample app D (debug). No app needed a switch.
So the default assumption is that the tree exists, and an empty-looking first dump is
usually a **text-less splash screen**, not missing semantics: `waitfor` a known label
before concluding anything. API 30 behaves like API 35 (needs `mResumedActivity` parsing,
which the tool now does).

Only if a tree never appears (bare FlutterView, 0 labels well after the splash):
1. `grep -rn "ensureSemantics" lib/` for an existing dart-define switch and use it.
2. Otherwise **propose and wait for approval** (app-code change):
   ```dart
   const _e2e = bool.fromEnvironment('E2E');
   // in main(), after WidgetsFlutterBinding.ensureInitialized():
   if (_e2e) SemanticsBinding.instance.ensureSemantics();
   ```
   built with `--dart-define=E2E=true`; off by default (a semantics tree has a cost).
Enabling an Android accessibility service from the host was tried on sample app E and was NOT
shown to be necessary; do not use it as a first move.

## Patterns measured on sample apps (maps, mock API)

- **Merged nodes:** Flutter can merge a button and the text under it into ONE node. The
  centre then lands on the text, not the button (sample app A driver "Arrived": node spans
  y 1083-2400, real button at the top). Use `taplabel LABEL --at top` (or `bottom`).
  Symptom: tap reports success, screen does not change.
- **Dynamic labels:** "Accept Ride (00:00)", "Ride KabuKabu" (was "Choose a ride" one step
  earlier), "Arriving in 4 mins...". Match a stable substring; run `labels` after each
  state change instead of assuming a name. Multi-line labels (`Phone Number&#10;Tab 1 of 2`)
  match as single-spaced text.
- **Swipe sliders** ("Go Online") are not tappable: a tap does nothing. Find the row with
  `labels`, then `swipe <knob-x> <row-y> <end-x> <row-y> 600`.
- **Placeholders are not in the tree:** a field's hint text ("Pickup Location") may not be
  exposed at all; target fields with `class:EditText --nth N`. After typing, the value
  appears as the node's text (assertable). A field can be labelled only by its validation
  message ("Password Input is required.").
- **Icon-only controls** (star ratings, close/back, call/chat, password toggles, menu icons)
  are listed by `unlabeled` with live coordinates; `tap X Y` those from the same
  dump. Report them as findings.
- **Maps:** the map is ONE node ("Google Map", sometimes "Map Marker"). Everything around
  it is labelled. Content inside it is unreachable by label; assert on surrounding UI state
  (e.g. trip progress text "37%, Driving to destination") instead.
- **System dialogs** (notification, location) are native, fully visible, and driven with the
  same commands: `taplabel Allow --exact`, `taplabel 'While using the app'`.
- **Whole flows can be asserted from labels alone:** the scripted ride (arriving -> arrived
  -> driving 0..100% -> rate driver) was followed end to end with no screenshot.
- **Mock/fixture builds** (`--dart-define=MOCK_API=true` style) make runs deterministic, but
  check whether the actors share the mock: sample app A's rider and driver each run their own
  fixture server, so they are NOT coupled across two emulators.
- **Never chain a new flow blind.** A multi-step sequence typed OTP into the phone field
  because the driver form had a password step. Verify with `labels` per step until a flow
  is known, then batch it.

## More measured behaviours

- **Guard every snapshot.** Pressing `back` on a tab/login root exits the app and the next
  `labels` then describes the launcher (or Chrome). Check `doctor` says OK (foreground =
  app) before trusting a screen dump. Some links open an external browser ("Legal").
- **Return with the app's own control first:** pushed screens often have a labelled `Back`
  (sample app B) or an UNLABELED header button at a fixed spot (sample app A, always ~(74,206)); system
  `back` works for both but not for modal sheets (see below).
- **Modal bottom sheets** show as `Scrim` + `Dismiss` (the drag handle). `flutter_uat closesheet` closes
  one: Scrim tap, then swipe down the handle, then back (max 2, aborts if the app is left), and says
  which worked. Measured on sample app A's "Set goals" sheet (API 30): Scrim centre/top/bottom taps 8/8
  closed it, with the keyboard shown or hidden; swipe down 1/1; system back needs 1-2 presses (the
  first hides the keyboard); `taplabel Dismiss` (the handle) did NOT close it 0/2. An earlier note
  that the sheet was undismissable could not be reproduced; the walk's "lost" events there were
  walker bookkeeping (it pressed back on a tab root), now fixed. Only the Scrim step is proven as a
  chain; the swipe and back fallbacks were each tested alone.
- **State flags:** `labels` appends `[selected]`, `[checked]`, `[disabled]` when the app sets
  them (tabs expose `[selected]`; a read-only field showed `[disabled]`). Many apps do NOT set
  them on custom toggles (sample app C On/Off/Schedule, sample app A "Book a ride"), so a selected
  segment is invisible to the tree: use a screenshot or assert the resulting content.
- **Long merged labels:** one node can hold a whole card including its button
  ("... Rider Information ... Start Trip"). `labels` allows 400 chars (`UAT_LABEL_MAX`); to press
  the embedded button use `taplabel LABEL --at bottom|top`. A 160-char cut once hid "Start Trip".
- **Exact match ignores surrounding whitespace** (" Login" with a leading space exists).
- **A swallowed first tap** happened twice in sample app C (first "Login" tap after "Skip"); the
  second tap worked. Always `waitfor` the next screen's label and retry once.
- **Deterministic scenarios:** a mock switch (`MOCK_SCENARIO=outage`) gives exact values to
  assert (battery 41%, "Turn Off Generator" alert), and `gone 'Turn Off Generator'` verifies
  dismissal. Scripted rides can be followed state by state from labels.
- **Nag screens repeat** (sample app A driver "Enable Location Access" on every home entry);
  handle with `taplabel 'Maybe Later'` when present.
- **Never tap destructive controls** in an automated walk (Log Out, Delete Account, Pay).
- **Inert links exist:** sample app B "Register"/"Forgot Password?" have no route. Check the router
  before calling a non-navigating tap a tool failure.
- **Fields become labelled once they hold a value** (the value is the label), so
  `typein class:EditText --nth N` is the stable way to reach them before and after input.

## Guards and helpers (added 2026-11-17; offline fixtures AND live on sample app A rider/driver, API 30)

- **Destructive taps are refused** (exit 3): defaults `log out, logout, sign out, delete account,
  remove account, pay now, confirm payment`; add project terms with `unsafe=A,B` in `.uat`;
  `unsafe.defaults=off` opts out; `--force` overrides one call.
- **`taplabel LABEL --expect NEXT [--wait S]`**: waits for NEXT, retries the tap ONCE if it is
  not seen (the swallowed first tap), then fails. Only use where a repeat tap is harmless.
- **`merged`** lists tall clickable nodes with long or multi-line labels (heuristic) and hints
  `--at top|bottom`. **`slide LABEL`** swipes left end to right end (knob-at-left is an
  assumption: verify per app). **`backbtn`**: labeled Back/Navigate up/Close, else `.uat`
  `back.unlabeled=74,206@1080x2400` (scaled; tapped only if an unlabeled control is really
  there), else system back. **`nags`** taps the first present label of `.uat` `nag=A,B`.
- **Offline replay:** `UAT_XML=saved.xml ADB=echo flutter_uat <cmd>` runs read/tap logic against a
  saved tree with no device (taps are printed, not sent).
- Live results: guard refused and did not tap; `--expect` verified a transition, and a retry
  re-resolved a layout shift (Continue moved 1865 to 1928 after a validation message);
  `backbtn` tapped the real unlabeled back button (it sat at (105,168), not (74,206): it taps
  the control it FOUND near the configured spot); `merged` flagged the driver trip card;
  `slide` went online (the "Go Online" label node is only the text: the knob is an unlabeled,
  non-clickable View on the same row, which `slide` now finds).
- `--expect` exits 5 (UNKNOWN) and does NOT retry when no dump succeeds: the first version
  re-tapped a screen it could not read. A timer + map screen once gave 6 failed dumps in a row;
  cause seen in logcat: "UiAutomationService already registered" (a stale uiautomator after an
  interrupted call). `dump_ui` now kills it and waits 2 s; 3 deliberate interruptions each
  recovered in 4-5 s. Not proven that this was the only cause of the first failure.
- A typed email once lost its tail ("driver" instead of "user@example.com") at host load ~10-13;
  not reproduced in 3 clean repeats. After `typein`, `find` the value before submitting.
- **Two mock apps cannot share one emulator** (sample app A rider + driver both bind 127.0.0.1:47811;
  the second shows a blank white screen and logs `Address already in use`). `stop` the other first.
- Not yet built: the modal-sheet escape (the only measured recipe is restart the app).

## Unlabeled interactive controls

`labels` lists only nodes with text/content-desc/hint. Controls with none are invisible
to it. `flutter_uat unlabeled` lists them (`CX CY CLICKABLE <Class>`), and `class:EditText`
works as a selector everywhere a LABEL does (`typein class:EditText 8012345678`,
`find class:EditText`, `--nth N` for the second field). Measured: sample app E's phone field
is an unlabeled `EditText` (flagged NAF) until text is typed, after which it exposes its
formatted value ("808 012 3456"), which can be asserted.

## Host health (measure before you trust a timing)

**Swap matters as much as load (measured 2026-11-19).** A re-run of the same seven flows went from 21/21 to 15/21 with
2-3x slower steps while `uptime` showed a calm load (5-7) but swap was 94% used (13.6 of 14.3 GB). `doctor` now prints
`swap used`, and `flow` and `repeat` report it; above about 80% treat failures and timings as environment, free memory
(close apps, stop other emulators) and re-run. This is the likely cause, not proven: per-run swap was not logged in the
failing run.

The emulator shares the host CPU. At host load average ~35 (Spotlight, WindowServer) the
app hit "sample app E isn't responding" during startup and dumps took 12-21 s, versus a steady
~2 s at load < 8. `doctor` prints the load. If it is high, wait; do not record failures
or slow dumps as app findings. If an ANR dialog appears: `raw shell am force-stop <pkg>`
then `key 3`.

## Keyboard

`key 111` does NOT dismiss the keyboard on the tested image; `flutter_uat hidekb` (sends back
only if the keyboard is shown) does.

## Reaching unlabeled controls: the tool must work with the app as it is (measured 2026-11-18, sample app A rider, debug, API 30)

Assume NO app-code access and no app-side hooks. Everything below the first rung needs nothing from the app;
the app-side rungs are optional extras, never prerequisites. Use the first rung that resolves, and say in the
report which rung each tap used (anything below rung 1 is a brittleness note).

| Rung | Needs from the app | Status |
|---|---|---|
| 1. label (`taplabel "Text"`) | nothing | built, the default |
| 2. `class:X --nth N` (`class:Button`, `class:EditText`, `class:ImageView`) | nothing | built; MOST STABLE no-edit option |
| 3. `backbtn` (proximity to a `.uat back.unlabeled` hint) | one `.uat` line | built, back button only |
| 4. `--at top|bottom|left|right` among overlapping labeled nodes | nothing | built |
| 5. pixel tap from `unlabeled` coordinates, same-screen read | nothing | built; last resort |
| 6. `id:NAME` (resource-id from `Semantics(identifier: 'x')`) | a one-line app edit | built and tested live (below) |
| 7. widget-tree dump joined to bounds | debug build + VM service | NOT achieved (below) |

Always put `--expect NEXT_LABEL` on a positional tap so a wrong tap fails loudly.

**Inventory (45 rider routes, `sweep --unlabeled`, re-measured WITH the mock backend on; the first pass ran without
`MOCK_API=true` by mistake and gave 42 open / 50 controls).** 41 opened, 3 blank, 1 crash. 30 of the 41 open screens
have at least one unlabeled control; 47 controls: Button 21 (the back button, at two screen positions), EditText 14,
View 8, ImageView 3, CheckBox 1. So about 35 of 47 are already served by `backbtn` and `class:EditText`; the hard
remainder is about 12 (View, ImageView, CheckBox). Flow-only screens (a rating sheet during a ride) are not in this
count: route jump cannot reach them.

**Stability (`flutter_uat stability --paths FILE`, re-run with the mock on: 39 readable screens, 45 controls, 12 ambiguous; identical to the first no-mock run on 29 screens; a PROXY: does the
selector still resolve to the same relative control, not what a tap does).**

| layout change | `class:X --nth` | pixel position (scaled) | nearest-label anchor |
|---|---|---|---|
| font scale 1.3 | 45/45 | 37/45 | 40/45 |
| font scale 2.0 | 43/45 | 32/45 | 39/45 |
| display 900x1950 | 44/45 | 25/45 | 39/45 |
| density 560 | 44/45 | 25/45 | 39/45 |

`nth` only breaks when the number of controls of that class changes. Pixel position collapses when the display
size changes. The nearest-label anchor scored WORSE than `nth`, so it was not built. Part of the reason is structural: two
same-class siblings share the same nearest label, so the anchor cannot tell them apart even on an UNCHANGED
screen (offline selftest `stability.py --selftest` asserts this: 2 of 3 on identical screens). Caveats: one app, most ambiguous cases are two text fields in a row, one screen (`choose-contact`) was
unreadable in every pass: jumping there raises a system contacts-permission dialog and the dismissal gave up
when a dump failed under host load (fixed: an unreadable dump is retried, not read as "no dialog"; baseline then read 3 controls). Chat-route crash stack (captured 2026-11-18, same app): `FATAL EXCEPTION: Thread-8 java.lang.NullPointerException: Attempt to invoke virtual
method 'boolean com.chatsdk.adapter.EMAChatClient.isLogout()' on a null object reference at
com.chatsdk.EMClient.logout`, i.e. the a third-party chat SDK SDK's logout runs while its native client was never initialised
(the mock never starts it). It is a background-thread crash, so a sweep attributes it to whichever route is open at the time (chat in one run, saved-places in the next); it did not reproduce on a clean cold chat jump, so who calls logout and when is NOT determined. Second finding: once
the permission has been denied twice Android treats it as permanent and the app sends the user to the system App info
page, so later visits to that route leave the app (correctly reported as exit 4 / unreadable, an app behaviour not a tool fault).

**`id:` selector and fallback chains (built and tested 2026-11-18).** `id:NAME` matches the node's resource-id
(substring, or equal with `--exact`; framework ids like `android:id/content` are ignored). Any selector may be a
chain separated by `||`; the first alternative that matches wins, and stderr says `selector: fell back to 'X'`
when it was not the first, so the report shows which rung was used:
`taplabel 'id:uat_menu||Menu||class:ImageView' --nth 1 --expect "Saved Places"`.
Write chains id-first so an app that adds identifiers later gets the stable path with no flow change; an app
without them falls through to label, then class+nth. `--nth` applies to the alternative that matched.
Live (sample app A, debug, API 30): with the id present the tap hit `<View> id=uat_menu` at (124,241); with the id
absent it fell back to `class:ImageView` and hit the same spot (124,241); both reached "Saved Places"; no match
exits 1; a wrong `--expect` exits 1. Caveat found: `class:X` also matches LABELED nodes of that class, so with a
drawer open `class:ImageView --nth 1` picked "Notifications"; use it on a clean screen or add `--clickable`.
Offline suite 57/57 (9 new cases).

**`Semantics(identifier:)`** (rung 6): in a debug build, wrapping a control with
`Semantics(identifier: 'uat_menu', child: ...)` made the dump carry `resource-id="uat_menu"` with the control's
bounds, at the same spot as the unlabeled ImageView. Release build verified 2026-11-19: `Semantics(identifier: 'uat_get_started')` on the onboarding button gave `id=uat_get_started` in a RELEASE dump, and `taplabel 'id:uat_get_started||Get Started||class:Button' --expect "Create Account"` tapped it (the node reports clickable=0 but the centre tap worked). The release fallback path was not re-run (it was proven on debug). Unverified: other widget types. Most apps
will not have identifiers, so this is only a bonus when the team can add them.

**Widget-tree dump** (rung 7): not achieved. The app was installed with adb, not `flutter run`, so no VM service
address reached the host (`autodiscover_app` found nothing, no logcat line, `flutter attach` did not connect in
40 s). Untested through `flutter run`. Even connected it is debug-only, so never the main strategy.

Gaps: the rating stars were reached by `class:Button --nth 6` (one screen, one measurement); no tap-outcome
ground truth exists because back buttons do nothing after a jump (no stack) and the chat route crashes the app.

**Cancel-flow timing under load (measured 2026-11-19, sample app A debug + mock, API 30, fresh AVD).** Normal load (about 6-7):
`cancel_ride` 3/3 (median 79 s), `cancel_wait` 3/3 (58 s). With 6 CPU burners (load 14 rising to 26): `cancel_ride` 3/3
(95 s), `cancel_wait` 1/3, both failures at `taplabel "Cancel ride"` ("no node matching": the 12 s mock window had closed).
So the windowed step is the fragile one: it survived load roughly doubled for `cancel_ride` but not for `cancel_wait`,
where the tap follows more steps. Mitigation in the flow, not the tool: tap `Cancel ride` the moment `waitfor` returns, keep
no other step between them. Host load is a real input; the repeat runner's default waits for load < 8 for this reason.

An earlier set of attempts the same day went 0/6 and was wrongly read as a flow regression. Causes, none of them the flows:
a first cold start of a freshly installed debug app ANRs (do one warm-up launch and tap "Wait" before measuring), host load
15-30 from other applications, an emulator already disturbed by sweeps and perturbations, and flows that started without
`launch`. On a fresh AVD with a warm-up, sign-in persisted across `stop`/`launch` and `cancel_ride` passed 21/21 steps.
`build.define=UAT_ROUTES=true,MOCK_API=true` in `.uat` matters: a build without MOCK_API runs against no backend.

## Coverage limit: controls with no label at all

Flutter infers labels for `Text`, buttons and `TextField` hints. Icon-only buttons, map
markers, custom `GestureDetector`s and image-only tiles often have none, so `labels`
will not list them. Report them as a finding ("unreachable by label: <where>") and
suggest `Semantics(label: …, button: true)` / `tooltip:` on the widget. Reach it by `class:X --nth N` with `--expect`
(see the ladder above), a pixel tap last, and say so in the report.

## What an emulator cannot drive

Camera/QR scanning, real push notifications from the vendor, TalkBack sweeps, biometric
prompts (partly). State the gap in the report instead of skipping silently.

## Method

1. Write a scenario matrix first (number, scenario, input, expected, result) in the
   session scratchpad; fill the result column with *observed values*, not just PASS.
2. One behaviour per fire. Batch known-good sequences; verify once at the checkpoint.
3. Finish with a verdict line and an honest list of gaps (unlabeled controls, undriven
   hardware, anything unexercised).
