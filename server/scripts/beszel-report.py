#!/usr/bin/env python3
"""Writes a short health report from Beszel and pushes it to your private reports repo (README.md step 23).

Like a nurse copying the day's chart readings onto one page and posting it to the doctor:
Beszel keeps the full charts at home, this sends only the summary to a private GitHub repo,
where Claude reads it once a week and suggests what to change.

Cron runs it once a day. It only reads from Beszel (with a read-only login) and only writes
inside the reports folder. Nothing here opens a port or exposes Beszel to the internet.
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

HUB = "http://localhost:3003"
ENV_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")
HEALTH = {0: "", 1: "starting", 2: "healthy", 3: "unhealthy"}


def read_env():
    env = {}
    with open(ENV_FILE) as f:
        for line in f:
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.rstrip("\n").split("=", 1)
                env[k.strip()] = v.strip().strip("'\"")
    return env


def api(path, token=None, body=None, params=None):
    url = HUB + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def records(token, collection, filter_="", sort="created"):
    items, page = [], 1
    while True:
        res = api(f"/api/collections/{collection}/records", token,
                  params={"filter": filter_, "sort": sort, "perPage": 500, "page": page})
        items += res.get("items", [])
        if page >= res.get("totalPages", 1):
            return items
        page += 1


def since(hours):
    t = datetime.now(timezone.utc) - timedelta(hours=hours)
    return t.strftime("%Y-%m-%d %H:%M:%S")


def avg(xs):
    return round(sum(xs) / len(xs), 1) if xs else None


def peak(xs):
    return round(max(xs), 1) if xs else None


def summarize_system(rows):
    """rows: system_stats records, oldest first."""
    s = [r.get("stats") or {} for r in rows]
    if not s:
        return None
    gb = lambda b: round(b / 1e9, 1)
    temps = {}
    for x in s:
        for name, v in (x.get("t") or {}).items():
            temps[name] = max(temps.get(name, 0), v)
    drives = {}
    for name in (s[-1].get("efs") or {}):
        used = [x["efs"][name].get("du", 0) for x in s if name in (x.get("efs") or {})]
        total = s[-1]["efs"][name].get("d", 0)
        drives[name] = {"used_gb": round(used[-1], 1), "total_gb": round(total, 1),
                        "pct": round(100 * used[-1] / total, 1) if total else None,
                        "change_gb": round(used[-1] - used[0], 1)}
    root_used = [x.get("du", 0) for x in s]
    hours = len(s) * {"20m": 1 / 3, "120m": 2}.get(rows[0].get("type"), 1)
    bw = [x.get("b") or [0, 0] for x in s]
    return {
        "readings": len(s),
        "cpu_pct": {"avg": avg([x.get("cpu", 0) for x in s]),
                    "max": peak([x.get("cpum") or x.get("cpu", 0) for x in s])},
        "memory_pct": {"avg": avg([x.get("mp", 0) for x in s]),
                       "max": peak([100 * (x.get("mm") or x.get("mu", 0)) / x["m"] for x in s if x.get("m")])},
        "memory_total_gb": round(s[-1].get("m", 0), 1),
        "swap_used_gb": {"avg": avg([x.get("su", 0) for x in s]), "max": peak([x.get("su", 0) for x in s]),
                         "total": round(s[-1].get("s", 0), 1)},
        "load_avg_1m_max": peak([(x.get("la") or [0])[0] for x in s]),
        "cpu_iowait_pct_avg": avg([x["cpub"][2] for x in s if len(x.get("cpub") or []) > 2]),
        "temps_max_c": {k: round(v) for k, v in sorted(temps.items(), key=lambda kv: -kv[1])[:6]},
        "system_ssd": {"used_gb": round(root_used[-1], 1), "total_gb": round(s[-1].get("d", 0), 1),
                       "pct": round(s[-1].get("dp", 0), 1), "change_gb": round(root_used[-1] - root_used[0], 1)},
        "extra_drives": drives,
        # b is bytes per second, averaged over each reading's window.
        "network_gb": {"sent": gb(sum(b[0] for b in bw) * 3600 * hours / len(bw)),
                       "received": gb(sum(b[1] for b in bw) * 3600 * hours / len(bw))},
    }


def summarize_containers(rows):
    per = {}
    for r in rows:
        for c in r.get("stats") or []:
            p = per.setdefault(c.get("n", "?"), {"cpu": [], "mem": []})
            p["cpu"].append(c.get("c", 0))
            p["mem"].append(c.get("m", 0))
    out = {name: {"cpu_pct_avg": avg(p["cpu"]), "cpu_pct_max": peak(p["cpu"]),
                  "mem_mb_avg": round(avg(p["mem"]) or 0), "mem_mb_max": round(peak(p["mem"]) or 0)}
           for name, p in per.items()}
    return dict(sorted(out.items(), key=lambda kv: -kv[1]["mem_mb_avg"]))


def markdown(rep):
    lines = [f"# Server report {rep['date']}", "", f"Generated {rep['generated']} from Beszel.", ""]
    sysinfo = rep.get("system", {})
    lines += [f"- Status: {sysinfo.get('status')}, up {sysinfo.get('uptime_days')} days, "
              f"agent {sysinfo.get('agent_version')}, package updates waiting: {sysinfo.get('package_updates')}", ""]
    for label, key in (("Last 24 hours", "last_24h"), ("Last 7 days", "last_7d")):
        s = rep.get(key) or {}
        if not s:
            continue
        lines += [f"## {label}", "", "```json", json.dumps(s, indent=1), "```", ""]
    lines += ["## Containers, last 7 days (sorted by memory)", "", "| Container | CPU avg % | CPU max % | Mem avg MB | Mem max MB |",
              "| --- | --- | --- | --- | --- |"]
    for n, c in rep.get("containers_7d", {}).items():
        lines.append(f"| {n} | {c['cpu_pct_avg']} | {c['cpu_pct_max']} | {c['mem_mb_avg']} | {c['mem_mb_max']} |")
    lines += ["", "## Containers right now", ""]
    for c in rep.get("containers_now", []):
        flag = " **needs a look**" if c["attention"] else ""
        lines.append(f"- {c['name']}: {c['status']} {c['health']}{' (update available)' if c['updatable'] else ''}{flag}")
    if rep.get("alerts"):
        lines += ["", "## Beszel alerts this week", ""] + [f"- {a}" for a in rep["alerts"]]
    return "\n".join(lines) + "\n"


def main():
    env = read_env()
    email, password = env.get("BESZEL_REPORT_EMAIL"), env.get("BESZEL_REPORT_PASSWORD")
    repo = os.path.expanduser(env.get("REPORTS_REPO") or "~/server-reports")
    if not email or not password:
        sys.exit("BESZEL_REPORT_EMAIL / BESZEL_REPORT_PASSWORD are empty in .env (README.md step 23).")

    token = api("/api/collections/users/auth-with-password", body={"identity": email, "password": password})["token"]
    systems = records(token, "systems", sort="name")
    if not systems:
        sys.exit("The report login can't see any systems. Is SHARE_ALL_SYSTEMS on (README.md step 23)?")
    system = systems[0]
    sid, info = system["id"], system.get("info") or {}
    flt = lambda typ, hours: f"system='{sid}' && type='{typ}' && created>='{since(hours)}'"

    now = datetime.now().astimezone()
    rep = {
        "date": now.strftime("%Y-%m-%d"),
        "generated": now.strftime("%Y-%m-%d %H:%M %Z"),
        "system": {"name": system.get("name"), "status": system.get("status"),
                   "uptime_days": round(info.get("u", 0) / 86400, 1), "agent_version": info.get("v"),
                   "package_updates": (info.get("pu") or [None])[0]},
        "last_24h": summarize_system(records(token, "system_stats", flt("20m", 24))),
        "last_7d": summarize_system(records(token, "system_stats", flt("120m", 24 * 7))),
        "containers_7d": summarize_containers(records(token, "container_stats", flt("120m", 24 * 7))),
        "containers_now": [],
        "alerts": [],
    }
    for c in records(token, "containers", f"system='{sid}'", sort="name"):
        health = HEALTH.get(c.get("health"), "")
        rep["containers_now"].append({
            "name": c.get("name"), "status": c.get("status"), "health": health, "updatable": bool(c.get("updatable")),
            "attention": health == "unhealthy" or not str(c.get("status", "")).startswith("Up")})
    try:  # Only alerts the report login owns show up here; Beszel keeps them per user.
        for a in records(token, "alerts_history", f"created>='{since(24 * 7)}'"):
            rep["alerts"].append(f"{a.get('created', '')[:16]} {a.get('name')} {a.get('value')} "
                                 f"resolved {a.get('resolved') or 'not yet'}")
    except Exception:
        pass

    os.makedirs(os.path.join(repo, "daily"), exist_ok=True)
    with open(os.path.join(repo, "daily", rep["date"] + ".json"), "w") as f:
        json.dump(rep, f, indent=1)
    with open(os.path.join(repo, "latest.md"), "w") as f:
        f.write(markdown(rep))

    git = lambda *a: subprocess.run(["git", "-C", repo, *a], check=True, capture_output=True, text=True)
    git("add", "-A")
    if git("status", "--porcelain").stdout.strip():
        git("commit", "-q", "-m", f"Report {rep['date']}")
        git("push", "-q", "origin", "HEAD:main")
    print(f"Report {rep['date']} written to {repo}")


if __name__ == "__main__":
    main()
