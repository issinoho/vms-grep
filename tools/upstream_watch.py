#!/usr/bin/env python3
"""upstream_watch.py - notice new upstream releases of the vms-* ports.

For every port in tools/upstream-watch.json:
  1. read the upstream version the port is built from (its upstream.conf,
     UPSTREAM_VERSION, on the default branch; or the file/regex in "pin");
  2. ask release-monitoring.org (Anitya) for the newest stable version,
     limited to the port's release series when "track" is set;
  3. if upstream is newer, open (or update) an issue in this repository,
     labelled "upstream" and titled "[vms-x] name N.N released (we ship M.M)";
     when the port has caught up, close its open issue.

Issues live here, not in each port, because the workflow's own token can
only write to this repository.  Standard library only.

Environment:
  GH_TOKEN / GITHUB_TOKEN   token for the GitHub API (issues: write here)
  GITHUB_REPOSITORY         this repository, owner/name (set by Actions)
  DRY_RUN=1                 report only; change no issues
  FAKE_PIN="vms-x=1.0,..."  pretend these ports pin older versions (testing)
"""
import base64
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "tools" / "upstream-watch.json").read_text())
OWNER = os.environ.get("SITE_OWNER", "issinoho")
HERE = os.environ.get("GITHUB_REPOSITORY", f"{OWNER}/vms-grep")
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
DRY = os.environ.get("DRY_RUN", "") not in ("", "0", "false")
FAKE = dict(x.split("=", 1) for x in os.environ.get("FAKE_PIN", "").split(",") if "=" in x)
LABEL = "upstream"
UA = "vms-ports-upstream-watch (github.com/issinoho/vms-grep)"


def http(method, url, body=None, github=True):
    headers = {"User-Agent": UA, "Accept": "application/json"}
    if github:
        headers["Accept"] = "application/vnd.github+json"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
        if TOKEN:
            headers["Authorization"] = f"Bearer {TOKEN}"
    data = json.dumps(body).encode() if body is not None else None
    if data:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            if e.code in (502, 503, 504) and attempt < 2:
                time.sleep(5)
                continue
            raise


def gh(method, path, body=None):
    return http(method, "https://api.github.com" + path, body)


def vkey(v):
    """'1.4.21' -> (1, 4, 21): numeric comparison of dotted versions."""
    return tuple(int(n) for n in re.findall(r"\d+", v))


def pinned(port):
    repo = port["repo"]
    if repo in FAKE:
        return FAKE[repo]
    pin = port.get("pin", {"file": "upstream.conf", "regex": r"^UPSTREAM_VERSION=\"?([^\"\s]+)"})
    meta = gh("GET", f"/repos/{OWNER}/{repo}/contents/{pin['file']}")
    text = base64.b64decode(meta["content"]).decode()
    m = re.search(pin["regex"], text, re.M)
    if not m:
        raise RuntimeError(f"no version in {repo}/{pin['file']}")
    return m.group(1)


def latest(port):
    d = http("GET", f"https://release-monitoring.org/api/v2/versions/?project_id={port['anitya']}",
             github=False)
    versions = d.get("stable_versions") or d.get("versions") or []
    # Some projects' lists hold stray tags ("CVE-2021-3541", "fuzz-corpora2",
    # "libbitset_2003_06_08", "bzip2-1.0.8"): keep plain dotted versions.
    versions = [v[1:] if v.startswith("v") else v for v in versions]
    versions = [v for v in versions if re.fullmatch(r"\d+(\.\d+)+", v)]
    track = port.get("track")
    if track:
        versions = [v for v in versions if v.startswith(track)]
    if not versions:
        raise RuntimeError("no stable versions" + (f" in series {track}" if track else ""))
    return max(versions, key=vkey)


def open_issues():
    issues, page = [], 1
    while True:
        batch = gh("GET", f"/repos/{HERE}/issues?state=open&labels={LABEL}&per_page=100&page={page}")
        issues += [i for i in batch if "pull_request" not in i]
        if len(batch) < 100:
            return issues
        page += 1


def ensure_label():
    try:
        gh("POST", f"/repos/{HERE}/labels",
           {"name": LABEL, "color": "d4a72c",
            "description": "A new upstream release of a vms-* port (tools/upstream_watch.py)"})
    except urllib.error.HTTPError as e:
        if e.code != 422:           # 422: it exists
            raise


def body(port, name, ours, theirs):
    repo = port["repo"]
    proj = f"https://release-monitoring.org/project/{port['anitya']}/"
    if port.get("kind") == "interface":
        todo = (f"vms-fastfetch is a rewrite, not a port: it follows fastfetch's interface.\n\n"
                f"- [ ] Read fastfetch's changes since {ours}: new modules, options, config keys, "
                f"format arguments\n"
                f"- [ ] Match what applies on OpenVMS, then set `FF_UPSTREAM_VERSION` to {theirs}\n"
                f"- [ ] Release as usual (tests, kits, install check, GitHub release)\n")
    else:
        todo = (f"- [ ] Set `UPSTREAM_VERSION={theirs}` (and the URL, SHA-256, key) in "
                f"`upstream.conf`; fetch and verify the signed tarball\n"
                f"- [ ] Rebase the patches; build, test and kit on IA64 and x86-64\n"
                f"- [ ] Install check; GitHub release; README release table here\n")
    return (f"**{name} {theirs}** is out; [{repo}](https://github.com/{OWNER}/{repo}) ships "
            f"**{ours}**.\n\n"
            + (f"Following the {port['track']}x series.\n\n" if port.get("track") else "")
            + f"Source: [release-monitoring.org]({proj})\n\n{todo}\n"
            f"_Opened by `tools/upstream_watch.py`; it closes this issue when "
            f"the port ships {theirs} or later._\n")


def main():
    if not TOKEN and not DRY:
        sys.exit("upstream_watch: set GH_TOKEN (or DRY_RUN=1)")
    issues = [] if DRY and not TOKEN else open_issues()
    by_repo = {}
    for i in issues:
        m = re.match(r"\[(vms-[^\]]+)\]", i["title"])
        if m:
            by_repo[m.group(1)] = i
    if not DRY:
        ensure_label()

    rows, failed = [], 0
    for port in CONFIG["ports"]:
        repo = port["repo"]
        try:
            ours, theirs = pinned(port), latest(port)
        except Exception as e:      # one bad port must not stop the rest
            rows.append((repo, "?", "?", f"error: {e}"))
            failed += 1
            continue
        name = repo[4:]
        issue = by_repo.get(repo)
        if vkey(theirs) > vkey(ours):
            title = f"[{repo}] {name} {theirs} released (we ship {ours})"
            if issue and issue["title"] == title:
                action = f"issue #{issue['number']} open"
            elif issue:
                action = f"update #{issue['number']}"
                if not DRY:
                    gh("PATCH", f"/repos/{HERE}/issues/{issue['number']}",
                       {"title": title, "body": body(port, name, ours, theirs)})
                    gh("POST", f"/repos/{HERE}/issues/{issue['number']}/comments",
                       {"body": f"Upstream moved on to {theirs}."})
            else:
                action = "open issue"
                if not DRY:
                    new = gh("POST", f"/repos/{HERE}/issues",
                             {"title": title, "body": body(port, name, ours, theirs), "labels": [LABEL]})
                    action = f"opened #{new['number']}"
        else:
            action = "up to date"
            if issue:
                action = f"close #{issue['number']}"
                if not DRY:
                    gh("POST", f"/repos/{HERE}/issues/{issue['number']}/comments",
                       {"body": f"{repo} now ships {ours} (upstream {theirs}): closing."})
                    gh("PATCH", f"/repos/{HERE}/issues/{issue['number']}",
                       {"state": "closed", "state_reason": "completed"})
        rows.append((repo, ours, theirs, action))
        time.sleep(0.3)             # be gentle with release-monitoring.org

    lines = ["| Port | We ship | Upstream | |", "|---|---|---|---|"]
    lines += [f"| {r} | {o} | {t} | {a} |" for r, o, t, a in rows]
    report = ("_Dry run: no issues changed._\n\n" if DRY else "") + "\n".join(lines) + "\n"
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("## Upstream releases\n\n" + report)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
