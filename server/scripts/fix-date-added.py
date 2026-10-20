#!/usr/bin/env python3
"""Puts Usenet downloads back into Jellyfin's Recently Added (README.md step 6).

Files unpacked by SABnzbd keep the date the uploader packed them, often years ago, and Jellyfin
used that as "date added". Like a library book that arrived with an old "received" stamp: this
re-stamps it with the day it really reached the shelf, which is when the file appeared on the
media drive (its birth time).

Only changes Jellyfin's "date added" for movies and episodes whose date is more than a day older
than their file. Never touches the video files. Run once without --apply to see what it would do.
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

JELLYFIN = "http://localhost:8096"
ENV_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")


def read_env():
    env = {}
    with open(ENV_FILE) as f:
        for line in f:
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.rstrip("\n").split("=", 1)
                env[k.strip()] = v.strip().strip("'\"")
    return env


def api(key, method, path, body=None):
    req = urllib.request.Request(
        JELLYFIN + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f'MediaBrowser Token="{key}"', "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return json.loads(data) if data else None


def arrived(path):
    """When the file appeared on this drive: its birth time, or its change time if the drive doesn't record one."""
    out = subprocess.run(["stat", "-c", "%W %Z", path], capture_output=True, text=True)
    if out.returncode != 0:
        return None
    birth, change = (int(x) for x in out.stdout.split())
    return datetime.fromtimestamp(birth or change, timezone.utc)


def parse(date):
    # Jellyfin sends up to 7 decimal places; Python reads at most 6.
    date = date.rstrip("Z")
    if "." in date:
        head, frac = date.split(".", 1)
        date = f"{head}.{frac[:6]}"
    return datetime.fromisoformat(date).replace(tzinfo=timezone.utc)


def main():
    apply = "--apply" in sys.argv
    key = read_env().get("JELLYDASH_JELLYFIN_API_KEY")
    if not key:
        sys.exit("No JELLYDASH_JELLYFIN_API_KEY in .env (README.md step 11c makes one).")

    user = next(u for u in api(key, "GET", "/Users") if u["Policy"]["IsAdministrator"])["Id"]
    query = urllib.parse.urlencode({
        "Recursive": "true", "IncludeItemTypes": "Movie,Episode", "Fields": "Path,DateCreated",
    })
    items = api(key, "GET", f"/Items?{query}")["Items"]

    fixed = 0
    for item in items:
        path, created = item.get("Path"), item.get("DateCreated")
        if not path or not created or not os.path.exists(path):
            continue
        real = arrived(path)
        if real is None or parse(created) > real - timedelta(days=1):
            continue
        fixed += 1
        print(f"{item['Name']}: {created[:10]} -> {real:%Y-%m-%d}")
        if apply:
            full = api(key, "GET", f"/Items/{item['Id']}?userId={user}")
            full["DateCreated"] = real.strftime("%Y-%m-%dT%H:%M:%S.0000000Z")
            api(key, "POST", f"/Items/{item['Id']}", full)

    if not fixed:
        print("Nothing to fix: every date added matches when its file arrived.")
    elif apply:
        print(f"Fixed {fixed}. Refresh Jellyfin's home page to see them in Recently Added.")
    else:
        print(f"{fixed} to fix. Nothing changed yet: run again with --apply to fix them.")


if __name__ == "__main__":
    main()
