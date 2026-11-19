# flutter_uat

**An agent-friendly tool for agent-driven UAT of Flutter apps on Android.**

It gives an AI agent (or any script) a small, text-only way to see a running app, act on it, and
prove what happened, by **label instead of pixels**. It reads the app's accessibility
(semantics) tree through `adb`. There are no screenshots to interpret, no coordinates to guess,
and no change to the app.

```
flutter_uat labels                                   # observe: what is on screen
flutter_uat taplabel "Sign in" --expect "Welcome"    # act, and verify the next screen
flutter_uat typein class:EditText --nth 1 "hello"    # a field that has no label
flutter_uat waitfor "Dashboard" 30                   # wait as an assertion
flutter_uat flow login.flow                          # a scenario, with a report
flutter_uat repeat 3 login.flow tabs.flow            # is it repeatable? pass counts, timings
```

## Why it suits an agent

- **Text in, text out.** Every command prints short lines (`CX CY CLICKABLE LABEL`) an agent can
  read cheaply. No vision model is needed.
- **Exit codes that mean something.** The agent can branch on them without parsing prose:

  | code | meaning | what the agent should do |
  |---|---|---|
  | 0 | done | continue |
  | 1 | not found, or the check failed | read `labels`, adjust |
  | 2 | usage or environment problem | fix the call or the setup |
  | 3 | **refused** (destructive label, or form-filling not allowed) | stop and ask a human |
  | 4 | the app was left (back to the launcher, a browser) | relaunch, then retry |
  | 5 | the screen was unreadable (animating, busy) | look again before retrying |
  | 6, 7 | old toolchain, or below the free-disk floor | stop; the host needs attention |

- **Every action can verify itself.** `--expect NEXT_LABEL` makes a tap fail loudly when it landed
  on the wrong thing, which is the main way agents go wrong silently.
- **Works with the app as it is.** Selector chains degrade gracefully, so a flow keeps working
  whether or not the app has stable ids: `taplabel 'id:save||Save||class:Button'` tries a
  `Semantics(identifier:)` id, then the visible label, then the control class, and reports which
  rung it used.
- **A written playbook for the agent.** `flutter_uat install-skill` copies `SKILL.md` (commands,
  working rules, measured behaviours, how to plan a flow) and `CONTRACT.md` (what a delegate agent
  must know) into `~/.claude/skills/flutter-uat/`. An agent given only that document wrote and
  repeated working flows for an app it had not seen.
- **Reports an agent can hand back.** `flow` and `repeat` write markdown with each step, the first
  line observed, timings and host load, so a result is evidence rather than a claim.

## The agent loop

```
observe   flutter_uat labels            what can I act on?
act       flutter_uat taplabel X --expect Y --wait 10
verify    flutter_uat waitfor Y 10 | assert Y | gone Z
record    flutter_uat flow FILE --report out.md   /   repeat N FILE...
```

Plan a flow, run it once by hand, then batch it. A flow is a plain file, one command per line:

```
name: Sign in then open Settings
stop
launch
waitfor "Welcome" 40
? taplabel Login --exact              # "?" optional step
typein class:EditText --nth 1 user@example.com
taplabel "Sign in" --expect "Home" --wait 15
! assert "Error"                      # "!" must fail (the text must be absent)
```

## Install

```
dart pub global activate flutter_uat
flutter_uat doctor                    # is a usable semantics tree present?
flutter_uat install-skill             # give the agent its playbook
```

Requires `bash`, `adb` (Android platform-tools) and `python3` (for `flow`, `repeat`, `sweep`,
`walk`, `stability`). Built and measured on macOS; Linux is untested. **Android only.**

## What it can drive

| Area | Commands |
|---|---|
| Read | `labels`, `find`, `unlabeled`, `merged`, `doctor` |
| Act | `taplabel`, `typein`, `scrollto`, `slide`, `backbtn`, `tap`, `swipe` |
| Wait / assert | `waitfor`, `gone`, `assert`, `settle` |
| Scenarios | `flow`, `repeat N` |
| Device / app | `emu`, `build`, `install`, `launch`, `stop`, `geo` |
| Coverage | `walk`, `coverage`, `routes`, `sweep`, `stability` |

Controls with no label (icon-only buttons, unlabeled fields) are listed by `unlabeled` and reached
with `class:X --nth N`. System dialogs, tabs, sheets and forms are driven with the same commands.
Map content and anything drawn without semantics cannot be read by label; the tool says so.

## Optional app-side hooks

Nothing in the app is required. If you can edit it, two small hooks add exact route reporting and
route jumping (`flutter_uat install-hooks` copies them into `lib/uat/`). Both are inert unless
the app is built with `--dart-define=UAT_ROUTES=true`. Jumping needs a debuggable build; the route
log also works in release.

## Guardrails for autonomous use

An agent can run unattended without doing damage:

- Taps on destructive labels (logout, delete account, pay) are **refused (exit 3)** unless forced.
- Form filling is refused unless the project's `.uat` file allows it (`fill.allow=mock`).
- It only stops emulators **it started**, never yours.
- `build` refuses below a free-disk floor and cleans up only what it created.
- `repeat` and the sweeps wait for calm host load; above about 8 timings are not findings.
- Inside a flow, `raw`, `build`, `emu` and nested `flow` are denied.

Do not point it at production data.

## What has and has not been measured

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
