#!/usr/bin/env python3
"""flutter-uat walk: bounded, label-driven exploration of a running app, then a report.

  uat.sh [-s SERIAL] [-p PKG] walk [--taps N] [--depth D] [--minutes M] [--root PROJECT] [--report FILE]

Taps every clickable label once per screen (depth-first), closes sheets via Scrim, returns with
`backbtn`, switches bottom tabs, relaunches if the app is left. Destructive labels are refused by
uat.sh itself (unsafe= and its defaults). Needs only python3 and uat.sh. Config in `.uat`:
  signin.when=LABEL            run signin.steps only while LABEL is on screen
  signin.steps=STEP; STEP      uat.sh subcommands, ';'-separated, shell-style quoting; a leading
                               '?' makes a step optional. `raw` is not allowed.
  nag=Maybe Later,Not now      dismissed with `uat.sh nags`
Writes a markdown report (screens, taps, refusals, unlabeled controls, merged nodes, log errors,
coverage). A walk is a LOWER BOUND on what the app can do: forms, gated flows and anything needing
typed input stay unvisited.
"""
import argparse, os, re, shlex, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
U = os.path.join(HERE, "uat.sh")
ap = argparse.ArgumentParser(add_help=True)
ap.add_argument("--taps", type=int, default=40)
ap.add_argument("--depth", type=int, default=2)
ap.add_argument("--minutes", type=float, default=10)
ap.add_argument("--root", default="")
ap.add_argument("--report", default="")
ap.add_argument("--fill", action="store_true",
                help="type test data into text fields (needs `.uat` fill.allow=mock or sandbox: submits can create data)")
ap.add_argument("--no-restart", action="store_true", help="start from the current screen instead of a fresh launch")
A = ap.parse_args()

env = dict(os.environ)
deadline = time.time() + A.minutes * 60


def uat(*a, timeout=90):
    try:
        r = subprocess.run([U, *a], env=env, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"


def conf(key):
    d = os.getcwd()
    while d != "/":
        f = os.path.join(d, ".uat")
        if os.path.isfile(f):
            for ln in open(f):
                if ln.startswith(key + "="):
                    return ln.split("=", 1)[1].strip()
            return ""
        d = os.path.dirname(d)
    return ""


anrs = 0


def read():
    global anrs
    for _ in range(3):
        rc, out = uat("labels")
        if rc == 0 and out.strip():
            rows = []
            for ln in out.splitlines():
                m = re.match(r"^(\d+) (\d+) (\d) (.*)$", ln)
                if m:
                    rows.append((int(m[1]), int(m[2]), m[3] == "1", m[4]))
            if any("isn't responding" in r[3] for r in rows):
                anrs += 1   # system ANR dialog on top of the app: choose Wait, then read again
                uat("taplabel", "Wait", "--exact")
                time.sleep(4)
                continue
            if rows:
                return rows
        time.sleep(2)
    return None


def sig(rows):
    return "|".join(sorted({re.sub(r"\d+", "#", r[3])[:30] for r in rows if not r[2]})[:6])


def is_tab(label):
    return re.search(r"Tab \d+ of \d+", label) is not None


def lab_set(rows):
    return {re.sub(r"\d+", "#", r[3])[:30] for r in rows if not r[2]}


sets = {}  # sig -> full normalised non-clickable label set of the first visit


def same_as(rows, psig):
    """Same screen as the one recorded under psig? Exact signature, or >=60% label overlap
    (a scrolled list or a changed value must not read as 'a different screen')."""
    if rows is None:
        return False
    if sig(rows) == psig:
        return True
    ref, cur = sets.get(psig), lab_set(rows)
    if not ref or not cur:
        return False
    return len(ref & cur) / min(len(ref), len(cur)) >= 0.6


FILL_DEFAULTS = {"email": "test@example.com", "phone": "8012345678", "password": "Passw0rd-example",
                 "amount": "100", "otp": "123456", "name": "Test User", "text": "test"}
FILL_RULES = [  # first match wins; matched against the field's own label and the nearest label above it
    ("password", r"pass(word|code)?\b|pin\b|confirm"), ("email", r"e-?mail|@"),
    ("phone", r"phone|mobile|\+234|tel\b|whatsapp"), ("otp", r"\botp\b|verification code|6-digit|code"),
    ("amount", r"amount|price|\bngn\b|₦|fund|deposit|contribution|target|budget|distance|radius"),
    ("name", r"name|address|street|city"),
]
filled = set()


def fill_value(kind):
    return conf("fill." + kind) or FILL_DEFAULTS[kind]


def guess_kind(label, above):
    text = f"{label} {above}".lower()
    for kind, rx in FILL_RULES:
        if re.search(rx, text):
            return kind
    return "text"


def fill_fields(s, rows):
    """Type test data into every text field on this screen, once per screen. Returns True if it typed."""
    if not A.fill or s in filled:
        return False
    filled.add(s)
    rc, out = uat("find", "class:EditText")
    fields = []
    for ln in out.splitlines():
        m = re.match(r"^(\d+) (\d+) (\d) <EditText>\s*(.*)$", ln)
        if m:
            fields.append((int(m[2]), m[4]))
    typed = 0
    for i, (fy, flabel) in enumerate(fields, 1):
        above = " ".join(r[3] for r in rows if not r[2] and fy - 260 < r[1] < fy)
        kind = guess_kind(flabel, above)
        rc, _ = uat("typein", "class:EditText", fill_value(kind), "--nth", str(i), "--replace")
        uat("hidekb")
        if rc == 0:
            typed += 1
            log.append(f"fill: field {i} ({kind}) <- {fill_value(kind) if kind != 'password' else '***'}  [{(flabel or above)[:30]}]")
    return typed > 0


class Lost(Exception):
    pass


screens, tapped, refused, unreadable, log = {}, set(), [], 0, []
taps = 0
extras = {}  # sig -> (unlabeled lines, merged lines)


def run_signin():
    when, steps = conf("signin.when"), conf("signin.steps")
    if not steps:
        return
    rows = read() or []
    if when and not any(when.lower() in r[3].lower() for r in rows):
        return
    for raw in steps.split(";"):
        raw = raw.strip()
        if not raw:
            continue
        optional = raw.startswith("?")
        parts = shlex.split(raw.lstrip("?").strip())
        if not parts or parts[0] == "raw":
            continue
        rc, out = uat(*parts, timeout=120)
        log.append(f"signin: {' '.join(parts)[:60]} -> rc {rc}")
        if rc != 0 and not optional:
            log.append("signin step failed; continuing with what is on screen")
            return
        time.sleep(0.8)


def recover():
    """App left, or screen unreadable: relaunch, sign in again if needed, dismiss nags."""
    uat("stop")        # cold start: a plain launch resumes the app on whatever pushed screen it was on
    uat("launch")
    for _ in range(8):
        time.sleep(3)
        if read():
            break
    run_signin()
    if conf("nag"):
        uat("nags")
        time.sleep(1.5)
    log.append("recovered (relaunch)")


def leave(rows, parent):
    """Close a sheet (Scrim) or go back, then check we are on the parent screen.
    Looks first: a child's own action (Cancel, Set target) may already have closed it, and a second
    back would then leave the app."""
    now = read()
    if same_as(now, parent):
        return
    if now and any(is_tab(r[3]) for r in now):
        # a tab bar means a root screen (e.g. a list item switched tabs): back would EXIT the app
        raise Lost("landed on a tab root that is not the parent; not pressing back")
    if now:
        rows = now
    for attempt in range(2):
        if rows and any(r[3].startswith("Scrim") for r in rows):
            uat("closesheet")
        else:
            rc, _ = uat("backbtn")
            if rc == 4:
                raise Lost("back left the app")
        time.sleep(1.8)
        cur = read()
        if same_as(cur, parent):
            return
        if cur and any(is_tab(r[3]) for r in cur):
            raise Lost("at a tab root, nothing to go back to")   # backbtn here would exit the app
        rows = cur
    cur = read() or []
    ref = sets.get(parent, set()); now = lab_set(cur)
    raise Lost(f"could not return to parent (overlap {len(ref & now)}/{min(len(ref), len(now)) or 0}; only in parent: {sorted(ref - now)[:3]}; only now: {sorted(now - ref)[:3]})")


def note_screen(s, rows):
    if s in screens:
        return
    screens[s] = rows
    sets[s] = lab_set(rows)
    _, un = uat("unlabeled")
    _, mg = uat("merged")
    extras[s] = ([l for l in un.splitlines() if l.strip()], [l for l in mg.splitlines() if l.strip()])


def explore(depth, parent):
    global taps, unreadable
    rows = read()
    if rows is None:
        unreadable += 1
        raise Lost("unreadable")
    s = sig(rows)
    note_screen(s, rows)
    if fill_fields(s, rows):
        rows = read() or rows
    fields_now = {l.strip() for l in uat("find", "class:EditText")[1].splitlines()} if A.fill else set()
    cands = [r for r in rows if r[2] and len(r[3]) < 80 and not is_tab(r[3]) and not r[3].startswith(("Scrim", "Dismiss"))
             and not any(r[3] and r[3] in f for f in fields_now)]
    if depth == 0:
        log.append(f"screen `{s[:30]}`: {len(cands)} tappable, {sum(1 for c in cands if (s, c[3][:40]) in tapped)} already tapped")
    for (_, _, _, label) in cands[:12]:
        key = (s, label[:40])
        if key in tapped or taps >= A.taps or time.time() > deadline:
            continue
        cur = read()
        if cur is None or not same_as(cur, s):
            if cur:
                leave(cur, s)
            else:
                raise Lost("unreadable before tap")
        tapped.add(key)
        rc, out = uat("taplabel", label[:60], "--exact", timeout=60)
        if rc == 3:
            refused.append(label[:50]); continue
        if rc != 0:
            rc, out = uat("taplabel", label[:30], "--clickable")
            if rc == 3:
                refused.append(label[:50]); continue
            if rc != 0:
                continue
        taps += 1
        uat("hidekb")
        time.sleep(2.2)
        r2 = read()
        if r2 is None:
            unreadable += 1; raise Lost("unreadable after tap")
        s2 = sig(r2)
        if same_as(r2, s):
            continue
        if parent and same_as(r2, parent):
            log.append(f"'{label[:30]}' returned to the parent screen")
            return True   # already back on the parent: the caller must NOT go back again
        log.append(f"'{label[:30]}' -> {s2[:50]}  (depth {depth})")
        note_screen(s2, r2)
        uat("routes")   # persist what the app reported before logcat rolls over
        closed = explore(depth + 1, s) if depth < A.depth else False
        if not closed:
            leave(r2 if depth >= A.depth else (read() or r2), s)
    return False


def foreground_ok():
    rc, out = uat("doctor")
    return "FAIL: foreground" not in out


def check_fill_allowed():
    if not A.fill:
        return
    if conf("fill.allow") not in ("mock", "sandbox"):
        print("REFUSED: --fill types into forms and may submit them (real accounts, payments, messages).\n"
              "Add `fill.allow=mock` (or `sandbox`) to .uat ONLY if this build talks to a mock or sandbox backend.")
        sys.exit(3)


def wait_calm(limit=180):
    t0 = time.time()
    while time.time() - t0 < limit:
        m = re.search(r"averages?: ([0-9.]+)", subprocess.run("uptime", capture_output=True, text=True).stdout)
        if not m or float(m.group(1)) < 8:
            return True
        time.sleep(10)
    return False


def main():
    check_fill_allowed()
    calm = wait_calm()
    if not calm:
        log.append("host load stayed >= 8 for 180 s; walking anyway (findings may be load artifacts)")
    start_load = re.sub(r".*averages?: ([0-9.]+).*", r"\1", subprocess.run("uptime", capture_output=True, text=True).stdout.strip())
    uat("logclear")
    if not A.no_restart:
        uat("stop")       # a known starting point: tabs are only discovered from the root screen
        recover()
    elif not foreground_ok():
        recover()
    run_signin()
    if conf("nag"):
        uat("nags")
    rows = read()
    if rows is None:
        print("cannot read the first screen"); sys.exit(1)
    tabs = [r[3].split(" Tab ")[0] for r in rows if r[2] and is_tab(r[3]) and "[selected]" not in r[3]]
    for sweep in range(3):
        before = taps
        for root in [None] + tabs:
            if taps >= A.taps or time.time() > deadline:
                break
            try:
                if root:
                    uat("taplabel", root, "--clickable"); time.sleep(2.5)
                    log.append(f"tab: {root}")
                explore(0, "")
            except Lost as e:
                log.append(f"lost ({e}); recovering")
                if not foreground_ok() or True:
                    recover()
        if taps == before:
            break
    end_load = re.sub(r".*averages?: ([0-9.]+).*", r"\1", subprocess.run("uptime", capture_output=True, text=True).stdout.strip())
    _, lg = uat("logdump")
    errs = [l for l in lg.splitlines() if re.search(r"FATAL|Exception|ANR|isn't responding", l) and "impeller" not in l.lower()][:6]
    uat("routes")
    cov = ""
    if A.root:
        r = subprocess.run([os.path.join(HERE, "coverage.sh"), "--root", A.root], capture_output=True, text=True)
        cov = "\n".join(r.stdout.splitlines()[:4])
    out = ["# flutter-uat walk report", "",
           f"- typed input: {'ON (fill.allow=' + conf('fill.allow') + ')' if A.fill else 'off (taps only)'}",
           f"- taps: {taps} (limit {A.taps}), depth limit {A.depth}, distinct screens: {len(screens)}, unreadable dumps: {unreadable}",
           f"- host load at start/end: {start_load} / {end_load} (above ~8 timings and ANRs are not app findings)",
           f"- ANR dialogs dismissed with Wait: {anrs}",
           f"- refused (unsafe): {', '.join(refused) if refused else 'none'}", "",
           "## Screens (signature = first non-clickable labels)"]
    for s, rows in screens.items():
        un, mg = extras.get(s, ([], []))
        out.append(f"- `{s[:90]}`  unlabeled controls: {len(un)}, merged nodes: {len(mg)}")
        for l in un[:3]:
            out.append(f"    - unlabeled: {l}")
        for l in mg[:2]:
            out.append(f"    - merged: {l[:100]}")
    out += ["", "## Transitions"] + [f"- {l}" for l in log[-40:]]
    out += ["", "## Log errors"] + ([f"- {l[:160]}" for l in errs] or ["- none"])
    if cov:
        out += ["", "## Coverage (heuristic lower bound)", "```", cov, "```"]
    text = "\n".join(out)
    path = A.report or os.path.join(os.environ.get("TMPDIR", "/tmp").rstrip("/"), "flutter-uat", "walk-report.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text + "\n")
    print(text)
    print(f"\nreport: {path}")


if __name__ == "__main__":
    main()
