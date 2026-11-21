# flutter_uat benchmark

Measures what an agent costs to do a fixed task with `flutter_uat`, one headless Claude run per
(arm, task, run), the same way every time. Not shipped in the pub package.

    python3 bench/run.py --arm short --task t1_dashboard --runs 5 --serial emulator-5568

- Arms (`bench/arms/*.md`) are the guide appended to the system prompt: `short`, `full`, `none`.
- Tasks (`--tasks FILE`, see `tasks.example.json`) have expected substrings; success never relies on the agent's own claim.
- The agent may run only `flutter_uat` commands (`dontAsk` + `--allowedTools "Bash(flutter_uat:*)"`).
- Results are JSON lines in `bench/results/`: cost, turns, tokens (incl. cache), wall time.
- Judge a change by cost per successful task, with success rate as a gate.

Results are kept private (they contain app data). Copy `tasks.example.json` to `private/<app>.json` and pass `--tasks`; `--mcp marionette` swaps in marionette_mcp for comparison.
Caveats: the tasks are easy (even the `none` arm passes), one app, one model, one emulator, warm prompt cache.
