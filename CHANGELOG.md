## 0.1.1

- `emu create NAME` makes a throwaway AVD from an installed `google_apis` image (it refuses an existing
  name); `emu delete NAME` removes only AVDs this tool created. The unknown-AVD error now points at it.
- `build` explains a Gradle-too-old-for-this-Flutter failure and lists installed SDKs for `--sdk`
  (measured: Flutter 3.50.0 refused Gradle 8.14, minimum 9.3.1). `bootstrap` warns about it up front.
- `install-skill` also copies `SLA.md`.
- The guide: a first-use order, no dead references to files that do not ship, a note for apps with no router.
- README leads with instructions for agents, then normal usage.

## 0.1.0

- First packaged release of the flutter-uat tool as a Dart command-line package.
- `flutter_uat` wraps the bundled scripts (`uat.sh` and python helpers) and adds
  `install-hooks`, `install-skill`, `where` and `version`.
- Selector chains (`id:NAME||Label||class:Button`) with a fallback report.
- `sweep --unlabeled`, `stability`, `repeat`, `flow` and the offline script suite (59 checks).
