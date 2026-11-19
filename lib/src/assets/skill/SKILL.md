---
name: flutter-uat
description: >
  Drive and verify a Flutter app on an Android emulator by LABEL, not pixels: read the screen as text, tap,
  type, wait and assert, run scripted flows and repeat them. Use to device-test, UAT, click through, reproduce
  a bug, or verify a flow in a running Flutter app.
---

# flutter_uat (short guide)

> Inspired by an agent guide shared by David Adegoke (Cake Wallet). See NOTICE. Full detail: `REFERENCE.md`.

Command: `flutter_uat -s SERIAL -p PACKAGE <command>` (run from the project root so `.uat` is found).
It reads the app's accessibility tree through `adb`: text out, an exit code you can branch on.

## First use (in order)
1. `emu create uat_a` then `emu start uat_a --port 5562` (your own emulator; never touch others).
2. `bootstrap` (toolchain, package id, routes). Read its warnings.
3. `-s emulator-5562 build debug --install`. If the build says Gradle is too old for this Flutter,
   rerun with `--sdk /path/to/older/flutter/bin/flutter`.
4. `launch` (tap "Wait" if a first-run ANR dialog shows), then `doctor` (needs the app in front).

## The loop
`labels` (observe) -> `taplabel "X" --expect "NEXT" --wait 10` (act + verify) -> `waitfor`/`assert` (check).
- Observe before and after each state change. Labels are dynamic: match a stable substring.
- Put `--expect` on every tap, with the most specific label of the NEXT screen (a word already on screen is a weak check).
- A wait is an assertion: prefer `waitfor "X" SECS` to sleeping. `taplabel X --until SECS` waits then taps from one read.

## Commands
- See: `labels`, `find`, `unlabeled`, `doctor`. NB `find` exits 0 with no output on no match: use `assert`.
- Act: `taplabel`, `typein`, `scrollto`, `slide`, `backbtn`, `hidekb`, `closesheet`, `tap X Y`, `swipe`.
- Check: `waitfor LABEL SECS`, `gone LABEL SECS`, `assert LABEL` (`waitfor "A|B"` is NOT "either").
- App/device: `launch`, `stop`, `install`, `clear`, `geo LAT LNG`, `logdump`, `shot` (only for visual checks).
- Scenarios: `flow FILE [--quiet]`, `repeat N FILE...` (run in the background; prints at the end).
- Screens: `walk`, `coverage`, `routes`, `jump`, `sweep [--unlabeled]`, `stability` (the last needs the optional hooks).

## Exit codes
0 done | 1 not found/check failed (read `labels`, adjust) | 2 usage/environment | **3 REFUSED: stop and ask a human** |
4 app left (relaunch, retry once) | 5 screen unreadable (look again) | 6,7 old toolchain / disk below floor (stop).

## Selecting controls
`taplabel 'id:save||Save||class:Button' --nth 1`: tries a `Semantics(identifier:)` id, then the label, then the
class and position, and says which. Unlabeled fields/icons: `class:EditText --nth N`, `class:Button --nth N`
(`unlabeled` lists them). Overlaps: `--at top|bottom`. Last resort: `tap X Y` from the same read.

## Flow file
One command per line, no `flutter_uat` prefix. `?` = optional step, `!` = must fail, `set K=V` / `${K}`.
```
name: Sign in
stop
launch
waitfor "Welcome" 40
? taplabel Login --exact
typein class:EditText --nth 1 user@example.com
taplabel "Sign in" --expect "Home" --wait 15
! assert "Error"
```
The result line counts optional steps that did not pass: a PASS can hide a skipped path. Start each flow with
`stop`/`launch`/`waitfor` so flows are independent (the session persists across restarts).

## Rules
- Exit 3 = stop and ask. Never add `--force` or rephrase a label to get past a refusal unless a human said so.
- Test accounts and mock data only; form filling is refused unless `.uat` has `fill.allow=mock`.
- Wait for calm: host load above ~8 or swap above ~80% makes timings and failures not app findings.
- Clean up: `build --clean --yes` and `emu delete` what you created. Report which selector rung each tap used,
  mark unverified claims, list what you could not reach.
- Inside a flow `raw`, `build`, `emu`, nested `flow` are denied. `back` on a root screen leaves the app (exit 4): use `? back`.

## More
`REFERENCE.md`: every command, selector pitfalls, bootstrap/build/emulator details, hooks and sweep, measured
behaviours. `CONTRACT.md`: what a delegate agent (Codex etc.) needs. `SLA.md`: what each promise holds under.
