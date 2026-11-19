# flutter-uat: contract for non-Claude agents (Codex, others)

Tool: `flutter_uat` (bash + adb; `walk` also needs python3).
Read SKILL.md for the commands. Everything below is what a delegate must know without it.

- **Delegation sandbox:** `read-only` is NOT enough for anything that taps, installs or builds (adb and
  `build` write outside the repo; `build` writes `build/`). Use `workspace-write` up front; mid-run approval
  is auto-declined in this setup. Reads (`labels`, `find`, `doctor`, `coverage`, `bootstrap`) are safe read-only
  only if adb is reachable from the sandbox: (verify) not tested from Codex.
- **Pass absolute paths and the device:** `-s emulator-NNNN` (or `ANDROID_SERIAL`), `-p PACKAGE`. Run from the
  project root so `.uat` is found. With several devices the tool refuses to guess.
- **Never touch emulators you did not start:** use `flutter_uat emu start/stop`; `stop` refuses others.
- **Delete what you build:** `flutter_uat build --clean --yes` after installing; remove throwaway AVDs.
- **Destructive labels are refused (exit 3):** Log Out, Delete Account, Pay Now, and `.uat` `unsafe=`.
  `--force` only if the task explicitly requires it.
- **Reply shape:** a verdict plus observed values (label text, counts), not pasted dumps.
- Exit codes: 1 not found/failed, 2 usage/environment, 3 refused, 4 left the app, 5 screen unreadable
  (state UNKNOWN: do not retry the tap), 6 old toolchain, 7 below disk floor.

Verified: the scripts have no dependency on Claude Code (checked with a minimal `env -i`; the offline suite
`tests/run.sh` passes 29/29 that way). NOT verified: an actual Codex run (no Codex MCP tool or `codex` binary
exists in this session), so the sandbox notes above come from the delegation contract, not from a test.
