#!/usr/bin/env python3
"""flutter-uat repeat: run each flow N times and report pass rate, timing and the step that failed.

  uat.sh [-s SERIAL] [-p PKG] repeat N FLOW [FLOW...] [--report FILE] [--calm LOAD]

Waits for host load below --calm (default 8) before every run, because above that the timings and the
failures are not app findings. One row per flow; a failing run's first failed step is quoted.
Exit 0 = every run passed.
"""
import os, re, statistics, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
U = os.path.join(HERE, "uat.sh")
a = sys.argv[1:]
if len(a) < 2 or not a[0].isdigit():
    print(__doc__); sys.exit(2)
n, rest = int(a[0]), a[1:]
report, calm = "", 8.0
flows = []
i = 0
while i < len(rest):
    if rest[i] == "--report": report = rest[i + 1]; i += 2
    elif rest[i] == "--calm": calm = float(rest[i + 1]); i += 2
    else: flows.append(rest[i]); i += 1


def load():
    m = re.search(r"averages?: ([0-9.]+)", subprocess.run("uptime", capture_output=True, text=True).stdout)
    return float(m.group(1)) if m else 0.0


def wait_calm():
    for _ in range(18):
        if load() < calm: return
        time.sleep(10)


rows, allok = [], True
for f in flows:
    res = []
    for k in range(n):
        wait_calm()
        t0 = time.time()
        r = subprocess.run([U, "flow", f, "--report", "/dev/null"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
        dt = time.time() - t0
        out = r.stdout
        ok = r.returncode == 0
        bad = ""
        if not ok:
            m = re.search(r"^\| (\d+) \| `([^`]*)` \| (?:FAIL|ERROR) \| ([^|]*)\|", out, re.M)
            bad = f"step {m.group(1)} `{m.group(2)[:50]}`: {m.group(3).strip()[:60]}" if m else "no report line"
        res.append((ok, dt, bad))
    passed = sum(1 for r in res if r[0])
    allok &= passed == n
    rows.append((os.path.basename(f), passed, n, statistics.median(r[1] for r in res), min(r[1] for r in res), max(r[1] for r in res), [r[2] for r in res if r[2]]))
L = [f"# flutter-uat repeat: {n} run(s) per flow", "",
     "| flow | passed | median | min-max | first failure |", "|---|---|---|---|---|"]
for name, p, t, med, lo, hi, bad in rows:
    L.append(f"| {name} | {p}/{t} | {med:.0f}s | {lo:.0f}-{hi:.0f}s | {(bad[0] if bad else '-').replace('|', '/')} |")
tp, tt = sum(r[1] for r in rows), sum(r[2] for r in rows)
L += ["", f"**{tp}/{tt} runs passed ({100 * tp // max(tt, 1)}%)**   host load now {load():.1f}"]
text = "\n".join(L)
print(text)
if report:
    open(report, "w").write(text + "\n")
sys.exit(0 if allok else 1)
