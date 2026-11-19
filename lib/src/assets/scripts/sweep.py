#!/usr/bin/env python3
"""flutter-uat sweep: jump to every route of the app and classify what happened.

  uat.sh [-s SERIAL] [-p PKG] sweep [--root DIR] [--paths FILE] [--match SUBSTR] [--list]
                                    [--settle S] [--no-recheck] [--gap REGEX] [--limit N]
                                    [--report FILE] [--force]

Needs the app-side hook (snippets/uat_jump.dart + uat_route_observer.dart) in a debuggable build made
with --dart-define=UAT_ROUTES=true. Paths come from --paths FILE (one per line) or are read from the
router source: string constants / `path:` literals starting with "/" in files whose path contains
"rout" (--match narrows by file path, e.g. --match rider for one flavour). `:param` segments are
filled with 1 and marked.

Verdicts per path:
  OPEN       the jump was accepted and the screen has labels
  BLANK      accepted but nothing readable (usually a route that needs `state.extra`)
  ERROR      a framework exception was logged
  CRASH      the app process died
  NOJUMP     the hook did not answer (release build? hook not installed?)
  SKIPPED    the path looks destructive (logout, delete-account ...): --force to include it
Anything that is not OPEN is re-jumped ALONE after a clean relaunch. "alone" says whether it
reproduces; a crash that does not is ORDER-DEPENDENT (it needed the screens visited before it).

--gap REGEX (default 'no fixture for') collects matching log lines per route: the mock-backend
endpoints that still have no answer, i.e. the layers a sweep still cannot see.
Exit 0 = sweep completed, 1 = a CRASH reproduced alone, 2 = usage/environment.
"""
import argparse, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
U = os.path.join(HERE, "uat.sh")
ap = argparse.ArgumentParser()
ap.add_argument("--root", default="")
ap.add_argument("--paths", default="")
ap.add_argument("--match", default="")
ap.add_argument("--list", action="store_true")
ap.add_argument("--settle", type=float, default=3.0)
ap.add_argument("--no-recheck", action="store_true")
ap.add_argument("--gap", default="no fixture for")
ap.add_argument("--limit", type=int, default=0)
ap.add_argument("--report", default="")
ap.add_argument("--force", action="store_true")
ap.add_argument("--unlabeled", action="store_true")
A = ap.parse_args()

UNSAFE = ["logout", "log-out", "log_out", "signout", "sign-out", "sign_out",
          "delete-account", "delete_account", "deleteaccount", "remove-account", "remove_account"]


def find_root():
    d = os.path.abspath(A.root or os.getcwd())
    while d != "/" and not os.path.isfile(os.path.join(d, "pubspec.yaml")):
        d = os.path.dirname(d)
    return d if os.path.isfile(os.path.join(d, "pubspec.yaml")) else ""


ROOT = find_root()


def conf(key):
    f = os.path.join(ROOT, ".uat") if ROOT else ""
    if f and os.path.isfile(f):
        for ln in open(f):
            if ln.startswith(key + "="):
                return ln.split("=", 1)[1].strip()
    return ""


def discover():
    """(path, note) pairs from the router source."""
    out, seen = [], set()
    pat = [re.compile(r"""const\s+(?:String\s+)?\w+\s*=\s*['"](/[^'"$]*)['"]"""),
           re.compile(r"""path:\s*['"](/[^'"$]*)['"]""")]
    for dp, _, fs in os.walk(os.path.join(ROOT, "lib")):
        for f in fs:
            full = os.path.join(dp, f)
            if not f.endswith(".dart") or "rout" not in full.lower():
                continue
            if A.match and A.match.lower() not in full.lower():
                continue
            for ln in open(full, errors="ignore"):
                for p in pat:
                    for m in p.finditer(ln):
                        raw = m.group(1)
                        path = re.sub(r":[A-Za-z_]\w*", "1", raw)
                        if path not in seen:
                            seen.add(path)
                            out.append((path, "param filled with 1" if path != raw else ""))
    return sorted(out)


if A.paths:
    paths = [(l.strip(), "") for l in open(A.paths) if l.strip() and not l.startswith("#")]
else:
    if not ROOT:
        print("no pubspec.yaml found: pass --root or --paths", file=sys.stderr); sys.exit(2)
    paths = discover()
if A.limit:
    paths = paths[:A.limit]
if A.list:
    for p, n in paths:
        print(p + (f"   ({n})" if n else ""))
    print(f"{len(paths)} paths", file=sys.stderr)
    sys.exit(0)
if not paths:
    print("no routes found (try --paths FILE or --match)", file=sys.stderr); sys.exit(2)


def uat(args, timeout=90):
    try:
        r = subprocess.run([U, *args], capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return r.returncode, (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"


rc, doc = uat(["doctor"])
m = re.search(r"^package:\s*(\S+)", doc, re.M)
PKG = os.environ.get("UAT_PACKAGE") or (m.group(1) if m else "") or conf("package")
if not PKG:
    print("cannot tell the package: pass -p PKG", file=sys.stderr); sys.exit(2)


def pid():
    return uat(["raw", "shell", "pidof", PKG])[1].strip()


def labels():
    rc, out = uat(["labels"], 40)
    return out.splitlines() if rc == 0 and out.strip() else []


def dismiss_dialogs():
    """System permission dialogs sit on top of the app: take the option that grants least, except location."""
    for _ in range(3):
        ls = labels()
        if not ls:   # unreadable is not "no dialog" (a permission dialog hides the app): retry
            time.sleep(2); continue
        text = "\n".join(ls)
        if re.search(r" (While using the app)$", text, re.M):
            uat(["taplabel", "While using the app", "--exact"])
        elif re.search(r" (Deny|Don.t allow)$", text, re.M) and re.search(r"Allow", text):
            uat(["taplabel", "Deny", "--exact"])
        else:
            return
        time.sleep(1)


def foreground_is_app():
    _, out = uat(["raw", "shell", "dumpsys", "window"], 30)
    m = re.search(r"mCurrentFocus=.*?\b" + re.escape(PKG) + r"\b", out)
    return bool(m)


def fresh_app():
    uat(["stop"])
    uat(["raw", "shell", "run-as", PKG, "rm", "-f", "cache/uat_cmd"])  # a jump the dead app never read must not replay
    uat(["launch"])
    for _ in range(12):
        time.sleep(3)
        if pid() and foreground_is_app() and labels():
            break
    dismiss_dialogs()


def calm(limit=8.0, tries=12):
    for _ in range(tries):
        out = subprocess.run("uptime", capture_output=True, text=True).stdout
        mm = re.search(r"averages?: ([0-9.]+)", out)
        if not mm or float(mm.group(1)) < limit:
            return
        time.sleep(10)


def unsafe(path):
    norm = path.lower()
    terms = UNSAFE + [t.strip().lower() for t in conf("unsafe").split(",") if t.strip()]
    return next((t for t in terms if t in norm), "")


def one(path):
    """jump + classify. Returns (verdict, class, n_labels, note, gaps)."""
    if not pid() or not foreground_is_app():
        fresh_app()
    dismiss_dialogs()
    uat(["logclear"])
    jrc, jout = uat(["jump", path], 40)
    time.sleep(A.settle)
    dismiss_dialogs()
    _, full = uat(["raw", "logcat", "-d"], 60)
    classes = re.findall(r"UAT_ROUTE class=(\S+)", full)
    cls = next((c for c in reversed(classes) if c != "-"), "-")
    n = len(labels())
    if A.unlabeled and n:
        urc, uout = uat(["unlabeled"], 40)
        UNL[path] = [l for l in uout.splitlines() if re.match(r"^\d+ \d+ ", l)] if urc == 0 else None
    gaps = sorted(set(m.group(0).strip() for m in re.finditer(A.gap + r"[^\r\n]*", full))) if A.gap else []
    note = ""
    if not pid():
        v = "CRASH"
        mm = re.search(r"FATAL EXCEPTION[^\n]*\n(?:[^\n]*\n)?[^\n]*?(\w+(?:\.\w+)*(?:Exception|Error)[^\n]{0,80})", full)
        note = mm.group(1).strip() if mm else "process gone"
    elif re.search(r"EXCEPTION CAUGHT BY|Another exception", full):
        v = "ERROR"
        mm = re.search(r"(\w*Exception[^\n]{0,90})", full)
        note = mm.group(1).strip() if mm else ""
    elif jrc != 0:
        v, note = "NOJUMP", (jout.splitlines() or [""])[-1][:100]
    elif n == 0 or (n == 1 and cls == "-"):
        v = "BLANK"
    else:
        v = "OPEN"
        if n == 1:
            note = "sparse: 1 label (empty state?), screen confirmed by route log"
    return v, cls, n, note, gaps


UNL = {}
calm()
rows, allgaps = [], {}
t0 = time.time()
for path, pnote in paths:
    bad = unsafe(path)
    if bad and not A.force:
        rows.append([path, "SKIPPED", "-", 0, f"destructive-looking ({bad})", "-", pnote]); continue
    v, cls, n, note, gaps = one(path)
    for g in gaps:
        allgaps.setdefault(g, []).append(path)
    rows.append([path, v, cls, n, note, "-", pnote])

if not A.no_recheck:
    for r in rows:
        if r[1] in ("CRASH", "ERROR", "BLANK"):
            calm()
            fresh_app()
            v2, cls2, n2, note2, _ = one(r[0])
            if v2 == r[1]:
                r[5] = "yes"
            elif v2 == "OPEN":
                r[5] = "no (opens alone)"
                r[1] = r[1] + "/ORDER-DEPENDENT" if r[1] in ("CRASH", "ERROR") else r[1]
            else:
                r[5] = f"differs ({v2})"

count = {}
for r in rows:
    k = r[1].split("/")[0]
    count[k] = count.get(k, 0) + 1
distinct = sorted({r[2] for r in rows if r[1] == "OPEN" and r[2] != "-"})
unattributed = sum(1 for r in rows if r[1] == "OPEN" and r[2] == "-")
rep = [f"# flutter-uat sweep: {PKG}", "",
       f"- paths: {len(rows)}   " + "   ".join(f"{k} {v}" for k, v in sorted(count.items())),
       f"- distinct screen classes confirmed by the route log: {len(distinct)}  (OPEN with no class logged: {unattributed})",
       f"- duration {time.time() - t0:.0f}s", "",
       "| path | verdict | class | labels | note | reproduces alone | |", "|---|---|---|---|---|---|---|"]
for r in rows:
    rep.append("| " + " | ".join(str(x).replace("|", "/") for x in r) + " |")
if allgaps:
    rep += ["", f"## Log lines matching `{A.gap}` (backend layers still unanswered)", ""]
    for g, ps in sorted(allgaps.items(), key=lambda kv: -len(kv[1])):
        rep.append(f"- `{g[:120]}`  ({len(ps)} route(s), e.g. {ps[0]})")
if A.unlabeled:
    tot = sum(len(v) for v in UNL.values() if v)
    withu = sum(1 for v in UNL.values() if v)
    rep += ["", "## Unlabeled interactive controls per screen (CX CY CLICKABLE Class)", "",
            f"- screens read: {len(UNL)}   with at least one unlabeled control: {withu}   controls: {tot}", ""]
    for pth, v in sorted(UNL.items()):
        if v is None:
            rep.append(f"- `{pth}`: unreadable")
        elif v:
            rep.append(f"- `{pth}`: {len(v)}  " + "; ".join(v[:8]))
text = "\n".join(rep)
path = A.report or os.path.join(os.environ.get("TMPDIR", "/tmp").rstrip("/"), "flutter-uat", "sweep-report.md")
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w").write(text + "\n")
print(text)
print(f"\nreport: {path}")
sys.exit(1 if any(r[1] in ("CRASH", "ERROR") and r[5] == "yes" and r[1] == "CRASH" for r in rows) else 0)
