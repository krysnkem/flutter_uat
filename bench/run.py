#!/usr/bin/env python3
"""flutter_uat benchmark runner: one headless Claude run per (arm, task, run), measured identically.

  python3 bench/run.py --arm short --task t1_dashboard --runs 3 --serial emulator-5568 [--out results.jsonl]

Each run: reset the app (stop, launch, wait for the Dashboard), call `claude -p` with a fixed model, a fixed
tool set (Bash, limited to `flutter_uat` commands; everything else is denied, no bypass of permissions), no user settings, no skills, no MCP servers, and the arm's guide appended to the system
prompt. The agent's last line must be `ANSWER: ...`; success = every expected substring is in it (case-insensitive).
Recorded per run: success, cost, turns, duration, token usage from the JSON result. Nothing here trusts the agent's
own claim of success.
"""
import argparse, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--arm", required=True)
ap.add_argument("--mcp", default="", help="marionette: drive via marionette_mcp instead of flutter_uat")
ap.add_argument("--task", required=True)
ap.add_argument("--runs", type=int, default=1)
ap.add_argument("--serial", default="emulator-5568")
ap.add_argument("--model", default="claude-sonnet-5-5")
ap.add_argument("--max-turns", type=int, default=40)
ap.add_argument("--max-budget", default="1.50")
ap.add_argument("--out", default=os.path.join(HERE, "results.jsonl"))
ap.add_argument("--tasks", default=os.path.join(HERE, "tasks.example.json"))
ap.add_argument("--assets", default=os.path.join(os.path.dirname(HERE), "lib", "src", "assets"))
A = ap.parse_args()

cfg = json.load(open(A.tasks))
task = next(t for t in cfg["tasks"] if t["id"] == A.task)
pkg = cfg["app"]["package"]
READY = cfg["app"].get("ready_label", "Total Savings")
LOGIN_FLOW = cfg["app"].get("login_flow")
LOGIN_MARK = cfg["app"].get("login_marker", "Welcome Back")
guide_file = os.path.join(HERE, "arms", f"{A.arm}.md")
if not os.path.isfile(guide_file):
    sys.exit(f"no such arm: {guide_file}")

env = dict(os.environ)
env.update({"PATH": os.path.expanduser("~/.pub-cache/bin") + ":" + env["PATH"], "FLUTTER_UAT_ASSETS": A.assets,
            "ANDROID_SERIAL": A.serial, "UAT_PACKAGE": pkg})


def fu(*args, timeout=90):
    return subprocess.run(["flutter_uat", *args], env=env, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)


def reset_app():
    if A.mcp:
        for _ in range(8):
            lab = fu("labels").stdout
            if "isn't responding" in lab:
                fu("taplabel", "Wait", "--exact"); time.sleep(5); continue
            if "While using the app" in lab:
                fu("taplabel", "While using the app", "--exact"); time.sleep(4); continue
            if READY in lab:
                return True
            if LOGIN_MARK in lab:
                if LOGIN_FLOW:
                    fu("flow", os.path.join(os.path.dirname(HERE), LOGIN_FLOW), "--quiet", "--report", "/dev/null", timeout=240)
                else:
                    fu("taplabel", "Login", "--exact"); time.sleep(5)
                continue
            if cfg["app"].get("home_tab"):
                if "Total Savings" not in lab and READY not in lab and pkg not in fu("raw", "shell", "dumpsys", "window").stdout.split("mCurrentFocus=")[-1].split("\n")[0]:
                    fu("launch"); time.sleep(6); continue
                fu("taplabel", cfg["app"]["home_tab"]); time.sleep(2)
                if READY not in fu("labels").stdout:
                    fu("raw", "shell", "input", "keyevent", "4")
                time.sleep(3)
            else:
                fu("jump", cfg["app"].get("home_path", "/rider/dashboard-screen")); time.sleep(6)
        return False
    fu("stop"); time.sleep(2); fu("launch")
    for _ in range(14):
        time.sleep(3)
        lab = fu("labels").stdout
        if READY in lab:
            return True
        if LOGIN_MARK in lab:   # an earlier run signed out: sign back in (mock login) so every run starts alike
            if LOGIN_FLOW:
                fu("flow", os.path.join(os.path.dirname(HERE), LOGIN_FLOW), "--quiet", "--report", "/dev/null", timeout=240)
            else:
                fu("taplabel", "Login", "--exact")
    return False


def load():
    out = subprocess.run("uptime", capture_output=True, text=True).stdout
    m = re.search(r"averages?: ([0-9.]+)", out)
    return float(m.group(1)) if m else -1


MCP = '{"mcpServers":{}}'; TOOLS = "Bash"; ALLOW = "Bash(flutter_uat:*)"
if A.mcp == "marionette":
    MCP = '{"mcpServers":{"marionette":{"command":"%s"}}}' % os.path.expanduser("~/.pub-cache/bin/marionette_mcp")
    TOOLS = ""; ALLOW = "mcp__marionette"

PROMPT = (
    "A Flutter app is installed and signed in on the Android emulator "
    f"{A.serial} (package {pkg}). Use the flutter_uat command-line tool described in your instructions to look at the app. "
    "The device and package are already set in the environment, so you do not need -s or -p. Do not create, stop or delete "
    "emulators, do not modify any files, and do not submit or save anything in the app.\n\n"
    f"TASK: {task['prompt']}\n\n"
    "When you are done, end your reply with one line: `ANSWER: <what you found>`.")

os.makedirs(os.path.dirname(os.path.abspath(A.out)), exist_ok=True)
for k in range(A.runs):
    if not reset_app():
        print(f"[{A.arm} {A.task} run {k+1}] could not reset the app; skipping", file=sys.stderr); continue
    t0 = time.time(); l0 = load()
    prompt = PROMPT if not A.mcp else PROMPT.replace("Use the flutter_uat command-line tool described in your instructions to look at the app. The device and package are already set in the environment, so you do not need -s or -p. ", "Use the marionette MCP tools (connect to ws://127.0.0.1:" + str(cfg["app"].get("vm_port", 9171)) + "/ws first). ")
    cmd = ["claude", "-p", prompt, "--output-format", "json", "--model", A.model, "--max-turns", str(A.max_turns),
           "--max-budget-usd", A.max_budget, "--no-session-persistence", "--disable-slash-commands",
           "--setting-sources", "project", "--strict-mcp-config", "--mcp-config", MCP,
           "--tools", TOOLS, "--permission-mode", "dontAsk", "--allowedTools", ALLOW,
           "--append-system-prompt-file", guide_file]
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=1500, cwd="/private/tmp", stdin=subprocess.DEVNULL)
    wall = time.time() - t0
    try:
        j = json.loads(r.stdout)
    except Exception:
        j = {"is_error": True, "result": (r.stdout + r.stderr)[-300:]}
    res = j.get("result", "") or ""
    scr = fu("labels").stdout   # end state, read before the next reset
    m = re.findall(r"ANSWER:\s*(.*)", res)
    ans = m[-1] if m else ""
    low = res.lower() if not ans else ans.lower()
    ok = bool(ans) or bool(task.get("expect_any"))
    ok = ok and all(e.lower() in low for e in task.get("expect_all", []))
    if task.get("expect_any"):
        ok = ok and any(e.lower() in (res.lower()) for e in task["expect_any"])
    ok = ok and all(e.lower() in scr.lower() for e in task.get("expect_screen_after", []))
    ok = ok and not any(e.lower() in scr.lower() for e in task.get("forbid_screen_after", []))
    u = j.get("usage", {}) or {}
    rec = {"arm": A.arm, "task": A.task, "run": k + 1, "success": ok, "answer": ans[:200],
           "cost_usd": j.get("total_cost_usd"), "turns": j.get("num_turns"),
           "api_ms": j.get("duration_api_ms"), "wall_s": round(wall, 1),
           "input": u.get("input_tokens"), "cache_read": u.get("cache_read_input_tokens"),
           "cache_create": u.get("cache_creation_input_tokens"), "output": u.get("output_tokens"),
           "error": bool(j.get("is_error")), "load": l0, "model": A.model, "ts": time.strftime("%Y-%m-%d %H:%M:%S")}
    open(A.out, "a").write(json.dumps(rec) + "\n")
    print(json.dumps(rec), flush=True)
