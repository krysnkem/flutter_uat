## 0.1.1

- Credit: `emu.sh` and `SKILL.md` began as work shared personally by David Adegoke (Cake Wallet); added an
  Acknowledgements section, a `NOTICE` file and source headers.

- `emu create NAME` makes a throwaway AVD from an installed `google_apis` image (it refuses an existing
  name); `emu delete NAME` removes only AVDs this tool created. The unknown-AVD error now points at it.
- `build` explains a Gradle-too-old-for-this-Flutter failure and lists installed SDKs for `--sdk`
  (measured: Flutter 3.50.0 refused Gradle 8.14, minimum 9.3.1). `bootstrap` warns about it up front.
- `install-skill` also copies `SLA.md`.
- The guide: a first-use order, no dead references to files that do not ship, a note for apps with no router.
- README leads with instructions for agents, then normal usage.
- `flow` says how many optional steps did not pass (a PASS can hide a skipped path) and has `--quiet`;
  `repeat` prints a progress line per run to stderr.
- No more `tr: Broken pipe` noise; the guide documents `find` exit codes, weak `--expect` substrings,
  `waitfor` failure labels, a logout recipe and the `uat.sh` to `flutter_uat` naming.
- `doctor` prints swap use, and `flow` and `repeat` report it and warn above 80%: re-runs at 94-95% swap and calm load scored
  15/21 and 8/16 against 21/21 before; swap is a warning sign, not an established cause.
- `taplabel LABEL --until SECS` waits for the label and taps from the same dump, so a short-lived button is not
  lost to the latency of a separate `waitfor` plus `taplabel`.
- Offline script suite: 66 checks.

## 0.1.0

- First packaged release of the flutter-uat tool as a Dart command-line package.
- `flutter_uat` wraps the bundled scripts (`uat.sh` and python helpers) and adds
  `install-hooks`, `install-skill`, `where` and `version`.
- Selector chains (`id:NAME||Label||class:Button`) with a fallback report.
- `sweep --unlabeled`, `stability`, `repeat`, `flow` and the offline script suite (59 checks).
