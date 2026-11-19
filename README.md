# flutter_uat

**An agent-friendly tool for agent-driven UAT of Flutter apps on Android.**

It gives an AI agent (or any script) a small, text-only way to see a running app, act on it, and
prove what happened, by **label instead of pixels**. It reads the app's accessibility
(semantics) tree through `adb`. There are no screenshots to interpret, no coordinates to guess,
and no change to the app.

- [For agents (start here)](#for-agents-start-here)
- [For people: normal usage](#for-people-normal-usage)
- [What has and has not been measured](#what-has-and-has-not-been-measured)

---

# For agents (start here)

## 1. Set up (once)

```
dart pub global activate flutter_uat
flutter_uat install-skill        # writes SKILL.md + CONTRACT.md to ~/.claude/skills/flutter-uat/
flutter_uat doctor               # must report a usable semantics tree for the app under test
```

Then **read the installed `SKILL.md`**. It is the full operating guide: every command, the working
rules that prevent false bugs, how to plan a flow, and what has been measured. This README is the
short version. For a non-Claude delegate (Codex and others) read `CONTRACT.md` too: it states the
sandbox the delegate needs.

Pass the device and package on every call, and run from the project root so `.uat` is found:
`flutter_uat -s emulator-5554 -p com.example.app <command>`. With several devices the tool refuses
to guess.

## 2. The loop

```
observe   flutter_uat labels                                  what can I act on?
act       flutter_uat taplabel "Sign in" --expect "Welcome" --wait 10
verify    flutter_uat waitfor "Welcome" 10 | assert "Welcome" | gone "Spinner"
record    flutter_uat flow FILE --report out.md   /   flutter_uat repeat 3 FILE...
```

- **Observe before every action** and after every state change. Labels are dynamic
  ("Arriving in 4 mins..."), so match a stable substring and never assume a name.
- **Put `--expect NEXT_LABEL` on every tap.** A tap that lands on the wrong thing then fails loudly
  instead of silently.
- **A wait is an assertion.** Prefer `waitfor` to a sleep.
- **Run a step by hand once before batching it into a flow.**

## 3. Exit codes: branch on these

| code | meaning | what to do |
|---|---|---|
| 0 | done | continue |
| 1 | not found, or the check failed | run `labels`, adjust the selector |
| 2 | usage or environment problem | fix the call or the setup |
| 3 | **refused** (destructive label, or form-filling not allowed) | **stop and ask a human** |
| 4 | the app was left (launcher, a browser) | relaunch, then retry once |
| 5 | the screen was unreadable (animating, busy) | look again before retrying |
| 6, 7 | old toolchain, or below the free-disk floor | stop: the host needs attention |

A TIMEOUT is a result to record, not something to retry blindly.

## 4. Selecting controls

1. By label: `taplabel "Save"`.
2. A field or icon with no label: `taplabel class:Button --nth 2`, `typein class:EditText --nth 1 "text"`.
   `flutter_uat unlabeled` lists them with live coordinates.
3. A chain, so the same flow works with or without stable ids:
   `taplabel 'id:save||Save||class:Button' --expect "Saved"`. It tries a `Semantics(identifier:)` id,
   then the label, then the class, and prints which one it used.
4. Overlapping nodes: `--at top|bottom`. Last resort: `tap X Y`, using coordinates from the same dump.

## 5. A flow file

One command per line, no `flutter_uat` prefix. `?` marks an optional step, `!` a step that must fail.

```
name: Sign in then open Settings
stop
launch
waitfor "Welcome" 40
? taplabel Login --exact              # the session may already be signed in
typein class:EditText --nth 1 user@example.com
taplabel "Sign in" --expect "Home" --wait 15
! assert "Error"
```

`flow` writes a markdown report (each step, the first line observed, timings, host load).
`repeat N FILE...` runs each flow N times and prints pass counts and the first failing step.

## 6. Rules an agent must follow

- **Exit 3 means stop and ask.** Do not rephrase the label or add `--force` to get past a refusal
  unless a human said to.
- **Use your own emulator** (`flutter_uat emu start AVD --port N`). Never stop or touch one you did
  not start; `emu stop` refuses others.
- **Test accounts and mock data only.** Never real credentials. Form filling is refused unless the
  project's `.uat` has `fill.allow=mock`. Do not point it at production data.
- **Wait for calm.** Above host load of about 8, timings and failures are not findings; `repeat` and
  the sweeps wait for it.
- **Clean up** what you create: `flutter_uat build --clean --yes`, and delete throwaway emulators.
- **Report honestly.** Say which selector rung each tap used, mark unverified claims as unverified,
  and list the controls you could not reach.
- Inside a flow, `raw`, `build`, `emu` and nested `flow` are denied.

## 7. What you cannot see

Map content and anything drawn without semantics is not in the tree; the tool says so instead of
guessing. Release builds work for everything above except `jump` and `sweep` (route jumping needs a
debuggable build).

---

# For people: normal usage

## Install

```
dart pub global activate flutter_uat
flutter_uat doctor                    # is a usable semantics tree present?
```

Requires `bash`, `adb` (Android platform-tools) and `python3` (for `flow`, `repeat`, `sweep`,
`walk`, `stability`). Built and measured on macOS; Linux is untested. **Android only.**

## Try it

```
flutter_uat labels                                   # what is on screen
flutter_uat taplabel "Sign in" --expect "Welcome"    # tap by label, check the next screen
flutter_uat typein class:EditText --nth 1 "hello"    # a field that has no label
flutter_uat waitfor "Dashboard" 30                   # wait as an assertion
flutter_uat flow login.flow                          # a scripted scenario, with a report
flutter_uat repeat 3 login.flow tabs.flow            # repeatability: pass counts, timings
```

## What it can drive

| Area | Commands |
|---|---|
| Read | `labels`, `find`, `unlabeled`, `merged`, `doctor` |
| Act | `taplabel`, `typein`, `scrollto`, `slide`, `backbtn`, `tap`, `swipe` |
| Wait / assert | `waitfor`, `gone`, `assert`, `settle` |
| Scenarios | `flow`, `repeat N` |
| Device / app | `emu`, `build`, `install`, `launch`, `stop`, `geo` |
| Coverage | `walk`, `coverage`, `routes`, `sweep`, `stability` |

System dialogs, tabs, sheets and forms are driven with the same commands.

## Optional app-side hooks

Nothing in the app is required. If you can edit it, two small hooks add exact route reporting and
route jumping (`flutter_uat install-hooks` copies them into `lib/uat/`). Both are inert unless the
app is built with `--dart-define=UAT_ROUTES=true`. Jumping needs a debuggable build; the route log
also works in release.

## Safety

Taps on destructive labels (logout, delete account, pay) are refused unless forced. It only stops
emulators it started. `build` refuses below a free-disk floor and cleans up only what it created.

---

# What has and has not been measured

Every number comes from one developer's machine (macOS, Android API 30/35 emulators).

- Scripted flows against an in-app mock backend: 21/21 repeat runs on a debug build and 21/21 on a
  release build (7 flows x 3), and 12/12 on a second app by an agent given only `SKILL.md`. The
  flows were written against the same builds, so this is **repeatability, not a forecast** for
  new flows.
- One windowed step (a button offered for about 12 seconds) failed 2 of 6 times under heavy
  host load. Host load is an input to every result.
- For controls with no label, `class:X --nth N` kept resolving to the same control in 43-45 of 45
  cases across font-scale, display-size and density changes; pixel positions fell to 25 of 45 on a
  display-size change. A proxy measure, one app.
- Not measured: iOS, physical devices, real backends, Linux hosts.

`SLA.md` (in the package under `lib/src/assets/skill/`) lists the conditions each promise holds under.

## License

See `LICENSE`.
