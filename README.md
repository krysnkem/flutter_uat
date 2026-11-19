# flutter_uat

**Let an AI agent (or you) test a Flutter app on an Android emulator by reading what is on the screen, not by guessing where to tap.**

`flutter_uat` is a small command-line tool for **agent-driven UAT** (user acceptance testing). It reads the
app's accessibility tree through `adb`, so every tap, text entry and check is done **by label**, such as
"Sign in" or "Total Savings", instead of by pixel coordinates. It needs no change to your app, no screenshots
and no vision model.

```
flutter_uat taplabel "Sign in" --expect "Welcome back"
```

> **In one sentence:** it turns a running Flutter app into something an agent can see as text, act on with
> short commands, and prove things about with clear pass/fail exit codes.

- [How it works](#how-it-works)
- [For agents (start here)](#for-agents-start-here)
- [For people: normal usage](#for-people-normal-usage)
- [Everything it can do](#everything-it-can-do)
- [Strengths](#strengths)
- [What has and has not been measured](#what-has-and-has-not-been-measured)
- [Author and acknowledgements](#author-and-acknowledgements)

---

# How it works

Your app already describes itself to screen readers (Flutter's *semantics tree*). `flutter_uat` reads that
description, finds the thing you named, taps it, and tells you what happened.

```
  You or an AI agent
         │   flutter_uat taplabel "Sign in" --expect "Welcome back"
         ▼
  ┌───────────────┐        adb         ┌──────────────────────────────┐
  │  flutter_uat  │ ─────────────────▶ │  Android emulator or device  │
  │ (bash+python) │ ◀───────────────── │  running your Flutter app    │
  └───────────────┘   semantics tree   └──────────────────────────────┘
         │         (labels + positions, as text)
         ▼
  short text lines + an exit code the agent can branch on
  (and optional markdown reports)
```

## What one tap does

Every action looks at the screen **right now**, so a keyboard, a layout shift or a different screen size
cannot make it tap the wrong place the way remembered coordinates can.

```
 taplabel "Sign in" --expect "Welcome back"
        │
        ▼
  1. read the screen  ──▶  2. find the node labelled "Sign in"
                                   │ not found ──▶ exit 1  (look at `labels`, adjust)
                                   ▼
                          3. tap its centre
                                   │
                                   ▼
                          4. did "Welcome back" appear?
                                   │ yes ──▶ exit 0
                                   │ no  ──▶ tap once more, check again
                                   │              │ still no ──▶ exit 1 (a wrong tap fails loudly)
                                   ▼              ▼
                                 done          done
```

## The loop an agent runs

```
          ┌──────────── observe ────────────┐
          │   flutter_uat labels            │   what can I act on?
          ▼                                 │
        act   taplabel "X" --expect "Y"     │
          │                                 │
          ▼                                 │
       verify  waitfor "Y" | assert "Y"     │
          │                                 │
          ├── passed ──▶ next step ─────────┘
          │
          └── failed ──▶ read the exit code (table below), then adjust or stop
```

---

# For agents (start here)

## 1. Set up (once)

```
dart pub global activate flutter_uat
flutter_uat install-skill        # writes SKILL.md, CONTRACT.md, SLA.md to ~/.claude/skills/flutter-uat/
```

Then **read the installed `SKILL.md`**. It is the full operating guide: every command, the working rules that
prevent false bugs, how to plan a flow, and what has been measured. This README is the short version. For a
non-Claude delegate (Codex and others) read `CONTRACT.md` too: it states the sandbox the delegate needs.

First use, in this order (each step needs the one before it):

```
 1. flutter_uat emu create uat_a              a throwaway emulator of your own
    flutter_uat emu start uat_a --port 5562
 2. flutter_uat bootstrap                     toolchain, package id, routes (in the project root)
 3. flutter_uat -s emulator-5562 build debug --install
 4. flutter_uat launch                        tap "Wait" if a first-run ANR dialog appears
 5. flutter_uat doctor                        needs the app in front, so it comes last
```

Pass the device and package on every call, and run from the project root so `.uat` is found:
`flutter_uat -s emulator-5562 -p com.example.app <command>`. With several devices the tool refuses to guess.

## 2. The rules in the loop

- **Observe before every action** and after every state change. Labels are dynamic ("Arriving in 4 mins..."),
  so match a stable substring and never assume a name.
- **Put `--expect NEXT_LABEL` on every tap.** A tap that lands on the wrong thing then fails loudly instead of
  silently. Use the most specific label of the next screen: a word already on screen makes a weak check.
- **A wait is an assertion.** Prefer `waitfor` to a sleep.
- **Run a step by hand once before batching it into a flow.**

## 3. Exit codes: branch on these

```
 exit code ─┬─ 0  done                                      → continue
            ├─ 1  not found, or the check failed            → run `labels`, adjust the selector
            ├─ 2  usage or environment problem              → fix the call or the setup
            ├─ 3  REFUSED (destructive label, or form-fill  → STOP and ask a human
            │      not allowed)
            ├─ 4  the app was left (launcher, a browser)    → relaunch, then retry once
            ├─ 5  the screen was unreadable (animating)     → look again before retrying
            └─ 6,7 old toolchain / below the free-disk floor → stop: the host needs attention
```

A TIMEOUT is a result to record, not something to retry blindly.

## 4. Choosing how to select a control

The tool tries the most stable way first and only falls back when it has to. A chain lets one flow work
whether or not the app has stable ids, and the tool prints which rung it used.

```
 taplabel 'id:save||Save||class:Button' --expect "Saved"
              │      │        │
              │      │        └─ 3rd: by control class and position (works with no app changes)
              │      └────────── 2nd: by the visible label
              └───────────────── 1st: by a Semantics(identifier:) id, when the app has one
 (last resort: tap X Y, using coordinates from the same screen read)
```

Overlapping nodes: `--at top|bottom`. Icon-only buttons and unlabeled fields are listed by
`flutter_uat unlabeled`; reach them with `class:Button --nth 2` or `typein class:EditText --nth 1 "text"`.

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

`flow` writes a markdown report (each step, the first line observed, timings, host load) and says how many
optional steps did not pass, so a PASS cannot hide a skipped path. `repeat N FILE...` runs each flow N times and
prints pass counts and the first failing step.

## 6. Rules an agent must follow

- **Exit 3 means stop and ask.** Do not rephrase the label or add `--force` to get past a refusal unless a
  human said to.
- **Use your own emulator** (`emu create`, `emu start`). Never stop or touch one you did not start.
- **Test accounts and mock data only.** Never real credentials. Form filling is refused unless the project's
  `.uat` has `fill.allow=mock`. Do not point it at production data.
- **Wait for calm.** Above host load of about 8, or heavy swap use, timings and failures are not findings.
- **Clean up** what you create: `flutter_uat build --clean --yes`, and delete throwaway emulators with
  `emu delete`.
- **Report honestly.** Say which selector rung each tap used, mark unverified claims as unverified, and list
  the controls you could not reach.
- Inside a flow, `raw`, `build`, `emu` and nested `flow` are denied.

---

# For people: normal usage

## Install

```
dart pub global activate flutter_uat
flutter_uat doctor                    # is a usable semantics tree present?
```

Requires `bash`, `adb` (Android platform-tools) and `python3`. Built and measured on macOS; Linux is
untested. **Android only.**

## Try it on a running app

```
flutter_uat labels                                   # what is on screen
flutter_uat taplabel "Sign in" --expect "Welcome"    # tap by label, check the next screen
flutter_uat typein class:EditText --nth 1 "hello"    # a field that has no label
flutter_uat waitfor "Dashboard" 30                   # wait as an assertion
flutter_uat flow login.flow                          # a scripted scenario, with a report
flutter_uat repeat 3 login.flow tabs.flow            # repeatability: pass counts and timings
```

What `labels` prints, one line per thing you can act on (`x y clickable label`):

```
540 1034 0 Welcome to your savings app
540 1180 1 Sign in
540 1320 1 Create account
```

## Optional app-side hooks

Nothing in the app is required. If you can edit it, two small hooks add exact route reporting and route
jumping (`flutter_uat install-hooks` copies them into `lib/uat/`). Both are inert unless the app is built with
`--dart-define=UAT_ROUTES=true`. Jumping needs a debuggable build; the route log also works in release.

---

# Everything it can do

| Area | Commands | What it is for |
|---|---|---|
| **See** | `labels`, `find`, `unlabeled`, `merged`, `doctor` | read the screen as text; list unlabeled controls; check the app is in front |
| **Act** | `taplabel`, `typein`, `scrollto`, `slide`, `backbtn`, `tap`, `swipe`, `hidekb`, `closesheet` | tap, type, scroll, drag sliders, go back, close sheets |
| **Wait and check** | `waitfor`, `gone`, `assert`, `settle` | a wait is an assertion; check something is, or is not, there |
| **Scenarios** | `flow`, `repeat N` | scripted runs with step-by-step reports and pass counts |
| **Device and app** | `emu` (`create` `start` `stop` `delete`), `build`, `install`, `launch`, `stop`, `clear`, `geo` | make an emulator, build and install the app, set GPS |
| **Logs and proof** | `logclear`, `logdump`, `shot` | crash lines from logcat; a screenshot only when truly visual |
| **Find every screen** | `walk`, `coverage`, `routes`, `jump`, `sweep`, `stability` | explore, count reached screens, jump to routes, measure selector stability |

## Scenarios: flows and repeat runs

```
  login.flow ──▶ flow ──▶ step 1 PASS
  (plain text)           step 2 PASS
                         step 3 optional, did not pass   ──▶ markdown report
                         step 4 PASS                          (steps, timings, host load)
                              │
                              ▼
                      "3 of 4 required steps passed" or "all passed,
                       1 optional step did not pass: that path was NOT exercised"

  repeat 3 a.flow b.flow ──▶ waits for a calm host ──▶ runs each flow 3 times
                                                      ──▶ table: pass counts, median time,
                                                          first failing step
```

## Finding every screen: sweep and walk

Optional hooks let the app report each screen it shows, and let the tool jump straight to a route.

```
 build with --dart-define=UAT_ROUTES=true
        │
        ▼
 app logs "UAT_ROUTE class=… name=…"  ◀──── every screen the user (or the tool) reaches
        │
        ▼
 sweep: for each route in the router source
        jump ──▶ read labels ──▶ classify:
             OPEN    the screen has content
             BLANK   nothing readable (often a route that needs extra data)
             ERROR   a framework exception was logged
             CRASH   the app process died (re-checked alone to see if it reproduces)
        ──▶ one report, plus an inventory of unlabeled controls per screen
```

## Safety gates

```
 any command
     │
     ├─ taps a destructive label (logout, delete account, pay)?  ──▶ REFUSED, exit 3
     ├─ types into a form without `fill.allow` in .uat?           ──▶ REFUSED, exit 3
     ├─ stops an emulator it did not start?                       ──▶ REFUSED
     ├─ build with free disk below the floor?                     ──▶ refuses, exit 7
     └─ inside a flow: raw / build / emu / nested flow?           ──▶ not allowed
```

---

# Strengths

- **No change to your app.** It works from the accessibility tree your app already has. Optional hooks add exact
  route reporting but are never required.
- **Cheap for an agent.** Output is a few short text lines, so no vision model or screenshots are needed, and
  results are exact strings (amounts, codes, names), not pixels read by a model.
- **Hard to fool.** Every tap can name the screen it expects next, so a wrong tap fails loudly. Reports state
  when an optional step did not pass.
- **Honest exit codes.** Seven distinct codes tell an agent whether to retry, look, stop or ask a human.
- **Degrades gracefully.** Selector chains fall back from stable ids to labels to control class, and the tool says
  which one it used.
- **Safe to run unattended.** It refuses destructive taps and unsafe form filling, only touches emulators it
  started, and cleans up only what it created.
- **Works on release builds** for everything except route jumping.
- **Tested.** An offline suite replays fabricated screens with no device (66 checks), plus Dart tests, and the
  guide was checked by agents who had only the package.

---

# What has and has not been measured

Every number comes from one developer's machine (macOS, Android API 30/35 emulators).

- Scripted flows against an in-app mock backend: 21/21 repeat runs on a debug build and 21/21 on a release
  build (7 flows x 3). On a second app, two agents who had only the guide wrote their own flows and got 12/12 and
  later 15/15; a minimal one-screen app gave 12/12 but little evidence. The first app's flows were written against
  the same builds, so this is **repeatability, not a forecast** for new flows.
- On a host with heavy memory pressure the same flows scored 15/21 and then 8/16. Steps were slower and
  failures were scattered across unrelated steps. Swap use is reported as a warning sign, not an established
  cause. One windowed step (a button offered for about 12 seconds) is the most sensitive.
- For controls with no label, `class:X --nth N` kept resolving to the same control in 43-45 of 45 cases across
  font-scale, display-size and density changes; pixel positions fell to 25 of 45 on a display-size change.
  A proxy measure, one app.
- **Not measured:** iOS, physical devices, real backends, Linux hosts. Map contents and anything drawn without
  semantics cannot be read by label; the tool says so.

`SLA.md`, copied by `install-skill`, lists the conditions each promise holds under.

---

# Author and acknowledgements

**Christian Onyisi** · [christianonyisi.netlify.app](https://christianonyisi.netlify.app)

flutter_uat was inspired by **David Adegoke** (Cake Wallet), who shared an emulator helper and an agent guide
personally. Credit for that inspiration is his. The package itself is the work of the flutter_uat authors.
See `NOTICE`.

## License

See `LICENSE`.
