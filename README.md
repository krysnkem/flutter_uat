# flutter_uat

Drive and verify Flutter apps on Android emulators and devices **by label instead of pixel
coordinates**. It reads the app's accessibility (semantics) tree through `adb`, so an agent
or a script can tap, type, wait and assert on what the user sees, with no change to the app.

```
flutter_uat labels                              # what is on screen
flutter_uat taplabel "Sign in" --expect "Welcome" --wait 10
flutter_uat typein class:EditText --nth 1 "hello"   # a field with no label
flutter_uat waitfor "Dashboard" 30
flutter_uat flow login.flow                     # a scripted scenario with a report
flutter_uat repeat 3 login.flow tabs.flow       # repeatability: pass counts and timings
```

## Install

```
dart pub global activate flutter_uat        # once published
dart pub global activate --source path .    # from a checkout
flutter_uat doctor                          # is a usable semantics tree present?
```

Requires `bash`, `adb` (Android platform-tools) and `python3` (for `flow`, `repeat`,
`sweep`, `walk`, `stability`). macOS is the platform it was built and measured on; Linux is
untested. **Android only.** iOS is not supported.

## What it does

| Area | Commands |
|---|---|
| Read | `labels`, `find`, `unlabeled`, `merged`, `doctor` |
| Act | `taplabel`, `typein`, `scrollto`, `slide`, `backbtn`, `tap`, `swipe` |
| Wait / assert | `waitfor`, `gone`, `assert`, `settle` |
| Scenarios | `flow` (one command per line, optional `?` and negated `!` steps), `repeat N` |
| Device / app | `emu`, `build`, `install`, `launch`, `stop`, `geo` |
| Coverage | `walk`, `coverage`, `routes`, `sweep`, `stability` |

Selectors can be chained so a flow works whether or not the app has stable identifiers:
`taplabel 'id:save||Save||class:Button' --nth 1 --expect "Saved"` tries a
`Semantics(identifier:)` id first, then the visible label, then the control class, and reports
which one it used.

## Optional app-side hooks

Nothing in the app is required. If you can edit it, two small hooks add exact route
reporting and route jumping (`flutter_uat install-hooks` copies them into `lib/uat/`). Both are
inert unless the app is built with `--dart-define=UAT_ROUTES=true`. Route jumping needs a
debuggable build; the route log also works in release.

## For AI agents

`flutter_uat install-skill` copies `SKILL.md` (the full operating guide, with the measured
behaviours and the working rules) and `CONTRACT.md` into `~/.claude/skills/flutter-uat/`.
An agent that had only that document wrote and repeated working flows for an app it had
not seen (see below).

## What has and has not been measured

Every number comes from one developer's machine (macOS, Android API 30/35 emulators).

- Scripted flows against an in-app mock backend: 21/21 repeat runs on a debug build and 21/21
  on a release build (7 flows x 3), and 12/12 on a second app by an agent given only `SKILL.md`.
  The flows were written against the same builds, so this is **repeatability, not a forecast** for
  new flows.
- One windowed step (a button offered for about 12 seconds) failed 2 of 6 times when the host
  was heavily loaded. Host load is an input: above about 8 timings are not findings, and
  `repeat` waits for calm.
- Selectors for controls that have no label: `class:X --nth N` kept resolving to the same
  control in 43-45 of 45 cases across font-scale, display-size and density changes; pixel
  positions fell to 25 of 45 on a display-size change. A proxy measure, one app.
- Not measured: iOS, physical devices, real backends, Linux hosts.

See `SLA.md` in the installed skill folder for the conditions each promise holds under.

## Safety

The tool refuses taps on destructive labels (logout, delete account, pay) unless forced, never
touches emulators it did not start, and refuses to build below a free-disk floor. Do not point
it at production data: `typein` and flows submit real forms if you tell them to.

## License

See `LICENSE`.
