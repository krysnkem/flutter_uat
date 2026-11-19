#!/usr/bin/env python3
"""flutter-uat stability: how well do selectors for UNLABELED controls survive a layout change?

  uat.sh [-s SERIAL] [-p PKG] stability --paths FILE [--perturb LIST] [--settle S] [--report FILE]

Needs a debuggable UAT_ROUTES build (it jumps to each path). For every path: jump, record the screen's
labeled nodes and unlabeled controls, then repeat under device-level changes (font scale, display size,
density) and compare. The device is always put back (wm size/density reset, font_scale 1.0).

Strategies scored for each unlabeled control (baseline = unperturbed):
  nth     `class:X --nth N`: stable if the screen still has the same number of controls of that class
  coord   the baseline pixel position, scaled by the display-size ratio: stable if a control of that
          class sits within 60 px of it
  anchor  "the control of class X nearest the label L" (L = nearest label at baseline): stable if L is
          still on screen verbatim AND the control nearest it is the same rank among its class
This is a PROXY: it measures whether a selector keeps resolving to the same relative control, not what a
tap does. "ambiguous" = the screen has 2+ unlabeled controls of that class (the only case where the
choice between selectors matters). Exit 0 always (it is a measurement).
"""
import argparse, math, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
U = os.path.join(HERE, "uat.sh")
ap = argparse.ArgumentParser()
ap.add_argument("--paths", default="")
ap.add_argument("--selftest", action="store_true")
ap.add_argument("--perturb", default="font1.3,font2.0,size900,density560")
ap.add_argument("--settle", type=float, default=3.0)
ap.add_argument("--report", default="")
A = ap.parse_args()

PERT = {  # name -> (apply shell commands, size ratio x, y)
    "font1.3": (["settings put system font_scale 1.3"], (1, 1)),
    "font2.0": (["settings put system font_scale 2.0"], (1, 1)),
    "size900": (["wm size 900x1950"], (900 / 1080, 1950 / 2340)),
    "density560": (["wm density 560"], (1, 1)),
}
RESET = ["settings put system font_scale 1.0", "wm size reset", "wm density reset"]


def uat(args, timeout=60):
    try:
        r = subprocess.run([U, *args], capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return r.returncode, (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"


def sh(cmd):
    uat(["raw", "shell", *cmd.split()])


def anchor_of(x, y, labels):
    best = min(((math.hypot(x - lx, y - ly), t) for lx, ly, t in labels if t and not t.startswith("<")), default=None)
    return best[1] if best else None


def score(base, cur, ratio):
    """per-strategy [stable, total] for all and ambiguous controls."""
    res = {k: [0, 0, 0, 0] for k in ("nth", "coord", "anchor")}
    for p, b in base.items():
        c = cur.get(p)
        if not b or not b["unl"]:
            continue
        for i, (x, y, cl) in enumerate(b["unl"]):
            same = [u for u in b["unl"] if u[2] == cl]
            rank = [u for u in same].index((x, y, cl))
            amb = len(same) > 1
            ok = {"nth": False, "coord": False, "anchor": False}
            if c:
                cs = [u for u in c["unl"] if u[2] == cl]
                ok["nth"] = len(cs) == len(same)
                sx, sy = x * ratio[0], y * ratio[1]
                ok["coord"] = any(math.hypot(u[0] - sx, u[1] - sy) <= 60 for u in cs)
                an = anchor_of(x, y, b["labels"])
                pos = next(((lx, ly) for lx, ly, t in c["labels"] if t == an), None)
                if an and pos and cs:
                    near = min(cs, key=lambda u: math.hypot(u[0] - pos[0], u[1] - pos[1]))
                    ok["anchor"] = sorted(cs).index(near) == sorted(same).index((x, y, cl)) if len(cs) == len(same) else False
            for k, v in ok.items():
                res[k][1] += 1; res[k][0] += v
                if amb:
                    res[k][3] += 1; res[k][2] += v
    return res



def selftest():
    """Fabricated screens: no device. Proves score() counts what it claims."""
    lab = [(540, 300, "Title"), (540, 900, "Body")]
    base = {"/a": {"labels": lab, "unl": [(100, 200, "Button"), (900, 200, "Button"), (500, 1500, "EditText")]}}
    same = {"/a": {"labels": lab, "unl": list(base["/a"]["unl"])}}
    r = score(base, same, (1, 1))
    assert r["nth"][:2] == [3, 3] and r["coord"][:2] == [3, 3], r
    # nearest-label anchor cannot tell sibling controls apart: both Buttons share the anchor "Title", so even on an
    # UNCHANGED screen the first Button resolves to the second. A ceiling of the strategy, not of the layout.
    assert r["anchor"][:2] == [2, 3], r
    assert r["nth"][2:] == [2, 2], r  # the two Buttons are the ambiguous ones
    lost = {"/a": {"labels": lab, "unl": [(100, 200, "Button"), (500, 1500, "EditText")]}}
    r = score(base, lost, (1, 1))
    assert r["nth"][0] == 1 and r["nth"][2] == 0, r  # a Button vanished: nth breaks on Buttons, EditText survives
    moved = {"/a": {"labels": lab, "unl": [(100, 600, "Button"), (900, 600, "Button"), (500, 1500, "EditText")]}}
    r = score(base, moved, (1, 1))
    assert r["coord"][0] == 1 and r["nth"][0] == 3, r  # pixels miss the moved Buttons, nth still resolves
    gone = {"/a": None}
    r = score(base, gone, (1, 1))
    assert r["nth"][0] == 0 and r["nth"][1] == 3, r
    print("stability selftest ok")

if A.selftest:
    selftest(); sys.exit(0)
if not A.paths:
    print("--paths FILE is required", file=sys.stderr); sys.exit(2)

rc, doc = uat(["doctor"])
m = re.search(r"^package:\s*(\S+)", doc, re.M)
PKG = os.environ.get("UAT_PACKAGE") or (m.group(1) if m else "")
if not PKG:
    print("cannot tell the package: pass -p PKG", file=sys.stderr); sys.exit(2)
paths = [l.strip() for l in open(A.paths) if l.strip() and not l.startswith("#")]


def in_front():
    return PKG in uat(["raw", "shell", "dumpsys", "window"], 30)[1].split("mCurrentFocus=")[-1].split("\n")[0]


def dismiss_dialogs():
    for _ in range(3):
        rc, t = uat(["labels"], 40)
        if rc != 0:   # an unreadable dump is not "no dialog": a permission dialog hides the app, retry
            time.sleep(2); continue
        if re.search(r" While using the app$", t, re.M):
            uat(["taplabel", "While using the app", "--exact"])
        elif re.search(r" Allow$", t, re.M) and re.search(r" Deny$", t, re.M):
            uat(["taplabel", "Deny", "--exact"])
        else:
            return
        time.sleep(1)


def fresh():
    uat(["stop"]); uat(["raw", "shell", "run-as", PKG, "rm", "-f", "cache/uat_cmd"]); uat(["launch"])
    for _ in range(12):
        time.sleep(3)
        dismiss_dialogs()
        if in_front() and uat(["labels"], 40)[0] == 0:
            break


def nodes(text):
    out = []
    for ln in text.splitlines():
        mm = re.match(r"^(\d+) (\d+) (\d) (.*)$", ln)
        if mm:
            out.append((int(mm.group(1)), int(mm.group(2)), mm.group(4).strip()))
    return out


def read(path):
    if not in_front():
        fresh()
    uat(["jump", path], 40); time.sleep(A.settle)
    dismiss_dialogs()
    if not in_front():
        return None
    _, lab = uat(["labels"], 40); _, unl = uat(["unlabeled"], 40)
    u = [(int(a), int(b), c) for a, b, c in re.findall(r"^(\d+) (\d+) \d <(\w+)>", unl, re.M)]
    return {"labels": nodes(lab), "unl": u}


def capture(tag):
    out, bad = {}, 0
    for i, p in enumerate(paths, 1):
        out[p] = read(p)
        bad = bad + 1 if out[p] is None else 0
        print(f"[{tag}] {i}/{len(paths)} {p} {'ok' if out[p] else 'UNREADABLE'}", flush=True)
        if bad >= 4:
            print(f"[{tag}] 4 unreadable in a row: aborting (device stuck?)", flush=True)
            raise SystemExit(5)
    return out


results = {}
try:
    fresh(); base = capture('baseline')
    for name in [n for n in A.perturb.split(",") if n in PERT]:
        cmds, ratio = PERT[name]
        for c in cmds:
            sh(c)
        time.sleep(3); fresh()
        results[name] = score(base, capture(name), ratio)
        for c in RESET:
            sh(c)
        time.sleep(3)
finally:
    for c in RESET:
        sh(c)
    uat(["stop"])

nb = sum(len(v["unl"]) for v in base.values() if v)
amb = sum(1 for v in base.values() if v for u in v["unl"] if sum(1 for w in v["unl"] if w[2] == u[2]) > 1)
rep = ["# flutter-uat stability", "",
       f"- screens: {len(paths)}  readable at baseline: {sum(1 for v in base.values() if v)}  unlabeled controls: {nb}  (ambiguous: {amb})",
       "- proxy: does a selector keep resolving to the same relative control (not a tap outcome)", "",
       "| perturbation | nth | coord | anchor | nth (ambiguous) | coord (ambiguous) | anchor (ambiguous) |", "|---|---|---|---|---|---|---|"]
for name, r in results.items():
    f = lambda a, b: f"{a}/{b}"
    rep.append(f"| {name} | " + " | ".join([f(r[k][0], r[k][1]) for k in ("nth", "coord", "anchor")]
                                            + [f(r[k][2], r[k][3]) for k in ("nth", "coord", "anchor")]) + " |")
text = "\n".join(rep)
out = A.report or os.path.join(os.environ.get("TMPDIR", "/tmp").rstrip("/"), "flutter-uat", "stability-report.md")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w").write(text + "\n")
print(text); print(f"\nreport: {out}")
