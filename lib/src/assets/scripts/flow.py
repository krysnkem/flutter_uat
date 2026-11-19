#!/usr/bin/env python3
"""flutter-uat flow: run a scripted scenario, step by step, with an assertion per step and a report.

  uat.sh [-s SERIAL] [-p PKG] flow FILE [--keep-going] [--report FILE] [--allow-clear] [--var K=V]...

FILE format (plain text, one step per line; blank lines and '#' comments ignored):

  name: Rider sign-in                      title for the report
  set EMAIL=user@example.com                 variable; use as ${EMAIL}; ${env:NAME} reads the environment
  taplabel "Get Started" --expect "Create Account" --wait 10     any uat.sh command, shell quoting
  typein "ex. hello@sample app A.com" ${EMAIL}
  ? taplabel "While using the app"         optional step: failure is recorded but does not stop the flow
  ! assert "Error"                         negated step: it must FAIL (exit != 0), e.g. "this must be absent"
  waitfor "Account Verification" 15        a wait is an assertion
  recover: launch                          steps to run once when a step fails with exit 5 (screen unreadable)
                                           or 4 (left the app), then the failed step is retried ONCE

A step passes when the command exits 0. The run stops at the first failed required step unless
--keep-going. Exit 0 = every required step passed. `raw`, `build`, `emu` are refused; `clear` (wipes app
data) needs --allow-clear. Destructive-label refusals (exit 3) are failures like any other.
Report: markdown with the observed first output line of every step, timings and host load.
"""
import argparse, os, re, shlex, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
U = os.path.join(HERE, "uat.sh")
ap = argparse.ArgumentParser()
ap.add_argument("file")
ap.add_argument("--keep-going", action="store_true")
ap.add_argument("--report", default="")
ap.add_argument("--allow-clear", action="store_true")
ap.add_argument("--var", action="append", default=[])
A = ap.parse_args()

DENY = {"raw", "build", "emu", "flow", "walk"} | (set() if A.allow_clear else {"clear"})
vars_ = dict(v.split("=", 1) for v in A.var if "=" in v)


def sub(s):
    s = re.sub(r"\$\{env:([A-Za-z0-9_]+)\}", lambda m: os.environ.get(m.group(1), ""), s)
    return re.sub(r"\$\{([A-Za-z0-9_]+)\}", lambda m: vars_.get(m.group(1), m.group(0)), s)


def uat(args, timeout=120):
    try:
        r = subprocess.run([U, *args], capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"


def load():
    out = subprocess.run("uptime", capture_output=True, text=True).stdout
    m = re.search(r"averages?: ([0-9.]+)", out)
    return m.group(1) if m else "?"


title, steps, recover = os.path.basename(A.file), [], []
for n, raw in enumerate(open(A.file), 1):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("name:"):
        title = line[5:].strip(); continue
    if line.startswith("recover:"):
        recover.append(line[8:].strip()); continue
    m = re.match(r"^set\s+([A-Za-z0-9_]+)=(.*)$", line)
    if m:
        vars_[m.group(1)] = sub(m.group(2)); continue
    steps.append((n, line))

rows, failed_required = [], 0
t_all = time.time()
l0 = load()
stop = False
for n, line in steps:
    if stop:
        rows.append((n, line, "SKIPPED", "-", "-")); continue
    optional = negate = False
    body = line
    while body[:1] in "?!":
        optional |= body[0] == "?"; negate |= body[0] == "!"
        body = body[1:].lstrip()
    try:
        parts = [sub(p) for p in shlex.split(body)]
    except ValueError as e:
        rows.append((n, line, "ERROR", f"bad quoting: {e}", "-")); failed_required += 1; stop = not A.keep_going; continue
    if not parts or parts[0] in DENY:
        rows.append((n, line, "ERROR", f"command not allowed in a flow: {parts[0] if parts else ''}", "-"))
        failed_required += 1; stop = not A.keep_going; continue
    t0 = time.time()
    rc, out = uat(parts)
    if rc in (4, 5) and recover and not negate:
        for r in recover:
            uat(shlex.split(r))
        time.sleep(2)
        rc, out = uat(parts)
        out = "(after recover) " + out
    ok = (rc != 0) if negate else (rc == 0)
    first = (out.splitlines() or [""])[-1 if rc != 0 else 0][:110]
    status = "PASS" if ok else ("OPTIONAL-FAIL" if optional else "FAIL")
    rows.append((n, line, status, f"rc {rc}: {first}", f"{time.time() - t0:.1f}s"))
    if not ok and not optional:
        failed_required += 1
        if not A.keep_going:
            stop = True

uat(["routes"])  # persist screens the app reported (no-op without the route hook)
p = sum(1 for r in rows if r[2] == "PASS")
out = [f"# flow: {title}", "",
       f"- result: **{'PASS' if failed_required == 0 else 'FAIL'}**  ({p}/{len(rows)} steps passed, {failed_required} required failed)",
       f"- duration {time.time() - t_all:.0f}s, host load {l0} -> {load()} (above ~8 timings are not app findings)", "",
       "| # | step | result | observed | time |", "|---|---|---|---|---|"]
for n, line, st, obs, t in rows:
    out.append(f"| {n} | `{line[:70]}` | {st} | {obs.replace('|', '/')} | {t} |")
text = "\n".join(out)
path = A.report or os.path.join(os.environ.get("TMPDIR", "/tmp").rstrip("/"), "flutter-uat", "flow-report.md")
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w").write(text + "\n")
print(text)
print(f"\nreport: {path}")
sys.exit(0 if failed_required == 0 else 1)
