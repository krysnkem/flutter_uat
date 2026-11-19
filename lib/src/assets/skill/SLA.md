# flutter-uat SLA v1.0 (2026-11-17): Android emulators, debug builds

What the tool promises, under which conditions, and what the agent must do otherwise.
Every number is from this machine's runs (sample app A, sample app B, sample app C, sample app D, sample app E;
API 30 and 35). Anything not measured is marked **(unmeasured)**.

**Scope of v1.0:** Android emulators (API 30; API 35 on the 16 KB Play image), debug builds,
macOS host, Flutter apps with a semantics tree. Out of scope until measured: iOS, release builds
of apps you can build yourself, physical devices, Windows/Linux hosts. Timings in section 2b are
the only numbers promised; they hold at host load < 8 (C1) and are not promised above it.

## 1. Conditions that make the promises hold (defaults, enforced by `doctor`)

| # | Condition | Check | If it fails |
|---|---|---|---|
| C1 | Host load average < 8 | `doctor` prints it | Wait. Record NO timing or failure as an app finding. |
| C2 | Foreground app = app under test | `doctor` exits non-zero otherwise | `launch`; never read a tree from the launcher. |
| C3 | System animations off (`anims 0`) | once per AVD | run it. |
| C4 | Labeled tree present (>= 1 labeled node) | `doctor` | `waitfor` a known label first; empty first dump = text-less splash. Only then follow SKILL.md "Semantics are off". |
| C5 | >= 5 GiB free on host before a build | `df` | Stop. Builds grew `~/.gradle` ~10 GB this session. |
| C6 | Accessibility services off | not required | (measured: no service needed) |

Opt-out is per project, in `.uat`, by naming the condition and a reason, e.g.
`skip.C3=app has its own animation tests`. Silent opt-out is not allowed.

## 2. Service levels

| Tier | Promise | Measured basis |
|---|---|---|
| T1 Read | `labels`/`find`/`waitfor` return a fresh tree | ~2 s per dump at load < 8; 3 s to 11 s from cold start at load ~11; 12-21 s at load ~35 (out of SLA) |
| T2 Act | `taplabel`/`typein`/`scrollto` hit the node as of the dump just taken | tool re-dumps and retries dumps 3x; tap success is NOT screen change, always `waitfor` the result |
| T3 Assert | `waitfor`/`gone`/`assert` give a deterministic verdict | label-only flows (scripted ride, outage scenario) asserted with zero screenshots |
| T4 Diagnose | `logdump` shows crashes/errors, tokens redacted | bearer + refresh tokens redacted after a leak was found |

Response contract: every command ends in an explicit result (MATCHED / TIMEOUT /
DUMP-FAILED / exit code). A TIMEOUT is a result to report, never a reason to loop.

## 2b. Measured service levels (2026-11-17; debug builds, host load 4.4-8.7, n=3 per cell, load logged per run)

Cold start = `stop`, `launch`, then time until a known label is in the tree. Dump = one `labels` call, 5 per run.

| App | API 30 cold | API 30 dump | API 35* cold | API 35* dump |
|---|---|---|---|---|
| sample app D | 3, 3, 3 s | 1.7 s | 4, 4, 4 s | 2.1 s |
| sample app B | 6, 6, 6 s | 1.7 s | 6, 7, 6 s | 2.1 s |
| sample app A rider (mock) | 9, 8, 7 s | 1.6-1.8 s | not measurable (see below) | 2.0-3.6 s |

*API 35 = the 16 KB page-size Play image (the only API 35 image installed here), so it is not
the same image family as the API 30 google_apis one. Spread between runs was 0-2 s at load < 8.
Dump latency rose to 3.0-3.6 s on the one API 35 run where load went 7 -> 12: keep C1 (load < 8).

Finding: on API 35 every sample app A rider cold start timed out (174-189 s, 3/3) because the Android
13+ notification permission dialog (`com.google.android.permissioncontroller`) sat on top, so the
app's own labels never appeared. `launch` reported this correctly. It is a harness condition, not
an app failure: handle it first (`taplabel Allow --exact` or `Don't allow`) and then `waitfor`.
Not measured: release builds, physical devices, cold start after `clear`, API 35 google_apis image.

## 3. Known limits (the SLA does NOT cover these)

| Limit | Workaround |
|---|---|
| Icon-only controls (back buttons, star ratings, password toggles, call/chat) have no label | `unlabeled` then `tap X Y` from the same dump; report as a finding |
| Merged nodes: centre tap hits the wrong child | `--at top|bottom` |
| Map contents are one node | assert on surrounding UI |
| Swipe sliders ignore taps | `swipe` |
| Modal bottom sheet "Set goals" could not be dismissed by Scrim, Dismiss or back | `stop` + `launch` |
| Custom toggles often expose no `[selected]` state | assert resulting content or one screenshot |
| First tap after some transitions is swallowed (sample app C) | `waitfor` next label, retry once |
| Camera/QR, vendor push, biometrics, TalkBack | state the gap |
| Old Android toolchain (AGP < 8 on Flutter >= 3.35) | `build` refuses; scratch-copy patch is manual |
| Pinned SDK not installed (sample app B 3.47.8) | install it (`fvm install`) and pass `--sdk` |
| iOS | **(unmeasured)** not supported |
| Release builds of other APKs without source | worked on sample app B (label tree present); other obfuscation cases **(unmeasured)** |

## 4. Coverage promise per app (what "done" means)

An agent reports per run: screens reached / screens routed (from the router file), plus the
list of unreachable ones with the reason (unwired, commented out, needs real backend,
needs hardware). Measured baseline: sample app B 9/9, sample app C 8/12 (4 unwired), sample app D 1/1
reachable, sample app A about 56%.

## 5. Bootstrap / profile (proposed, not yet implemented)

One-time per project, stored as `.uat` (data only, committed):

```
package=com.example.app
build.debug=<command>              # e.g. make run debug local
build.mock=<command with MOCK flag>
sdk=<flutter path or fvm version>  # pinned SDK may be missing (sample app A)
role.<name>=<avd or serial>
signin.<role>=<how: mock | otp-source path | none>
back.unlabeled=74,206              # known unlabeled header button
unsafe=Log Out,Delete Account,Pay  # never tapped by walks
skip.<Cn>=<reason>
```

Rebootstrap triggers (re-run discovery, rewrite `.uat`): applicationId change, Flutter/AGP
bump, new flavor, router file changed (re-count screens), new emulator role. Measured
reasons these matter: old AGP 7.3/Gradle 7.6 failed on Flutter >= 3.35 (sample app C), Dart ^3.13
needed a newer SDK (sample app D), a pinned SDK symlink pointed to another user's home
(sample app A).

## 6. Status and what v1.0 does not promise

Done: bootstrap (C1, C5; `.uat` profile), build/emu lifecycle, guards (`unsafe`, `--expect`, `closesheet`,
`backbtn`, `nags`, `slide`, `merged`), `coverage`, `walk`, offline suite (29 checks), timings (3 apps,
2 API levels, n=3), CONTRACT.md for other agents.

**Coverage target (decided):** no guaranteed percentage. A walk reports reached / routed with unmatchable
screens separated, as a LOWER BOUND (measured 5-16% on sample app A, 57% on sample app B in one bounded walk each).
Screens behind forms, maps, sliders, hardware or a real backend are listed as unreached with the reason.

Open (not promised):
1. Release-build and physical-device timings. 2. A real Codex delegation (CONTRACT.md is untested).
3. sample app C: old toolchain needs a manual scratch-copy patch. 4. iOS (next phase, own SLA).
5. Re-measure after any Android Studio / emulator / system-image upgrade.
