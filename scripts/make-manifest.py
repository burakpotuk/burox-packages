#!/usr/bin/env python3
"""Build manifest.json (PLAN.md §3.1) from published packages.

GitHub mode (CI):
    make-manifest.py --repo OWNER/NAME --out manifest.json

    Lists every published (non-draft, non-prerelease) release except the
    "manifest" release, downloads each "<archive>.package.json" sidecar written
    by scripts/package.sh and cross-checks it against the release asset
    (name, size and, when GitHub reports one, the asset's SHA-256 digest).

Local mode (tests):
    make-manifest.py --local-dir out --base-url https://example.invalid/ --out manifest.json

Exit status is non-zero on any inconsistency, so a broken release can never be
signed into the manifest.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.request

SCHEMA_VERSION = 1
MANIFEST_TAG = "manifest"
ENTRY_KEYS = ("name", "channel", "version", "arch", "url", "sha256", "size", "minMacOS", "meta")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
VERSION_RE = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._+-]*$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")


def fail(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def warn(msg):
    prefix = "::warning::" if os.environ.get("GITHUB_ACTIONS") == "true" else "warning: "
    print(prefix + msg, file=sys.stderr)


def token():
    for var in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(var):
            return os.environ[var]
    try:
        return subprocess.run(["gh", "auth", "token"], check=True, capture_output=True,
                              text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def http_get(url, tok=None, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "burox-packages-manifest"})
    if tok:
        req.add_header("Authorization", "Bearer " + tok)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read(), resp.headers


def list_releases(repo, tok):
    url = "https://api.github.com/repos/%s/releases?per_page=100" % repo
    out = []
    while url:
        body, headers = http_get(url, tok)
        out.extend(json.loads(body))
        url = None
        for part in (headers.get("Link") or "").split(","):
            m = re.match(r'\s*<([^>]+)>;\s*rel="next"', part)
            if m:
                url = m.group(1)
    return out


def version_key(v):
    # Natural sort: "1.30.10" > "1.30.9"; revision suffix "_2" sorts after the base.
    return [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in re.split(r"[._+-]", v)]


def validate_sidecar(sc, where):
    for k in ("name", "channel", "version", "arch", "file", "sha256", "size", "minMacOS"):
        if k not in sc:
            fail("%s: sidecar is missing '%s'" % (where, k))
    if not NAME_RE.match(sc["name"]):
        fail("%s: invalid package name %r" % (where, sc["name"]))
    if not VERSION_RE.match(sc["version"]):
        fail("%s: invalid version %r" % (where, sc["version"]))
    if not SHA_RE.match(sc["sha256"]):
        fail("%s: invalid sha256" % where)
    if not isinstance(sc["size"], int) or sc["size"] <= 0:
        fail("%s: invalid size" % where)
    if sc["arch"] not in ("arm64", "noarch"):
        fail("%s: invalid arch %r" % (where, sc["arch"]))
    meta = sc.get("meta", {})
    if not isinstance(meta, dict):
        fail("%s: meta must be an object" % where)


def entry_from(sc, url):
    return {
        "name": sc["name"], "channel": sc["channel"], "version": sc["version"],
        "arch": sc["arch"], "url": url, "sha256": sc["sha256"], "size": sc["size"],
        "minMacOS": sc["minMacOS"], "meta": sc.get("meta", {}),
    }


def from_github(repo):
    tok = token()
    entries = []
    for rel in list_releases(repo, tok):
        tag = rel.get("tag_name", "")
        if tag == MANIFEST_TAG:
            continue
        if rel.get("draft") or rel.get("prerelease"):
            warn("skipping draft/prerelease %s" % tag)
            continue
        assets = {a["name"]: a for a in rel.get("assets", [])}
        sidecars = [n for n in assets if n.endswith(".package.json")]
        if not sidecars:
            warn("release %s has no .package.json sidecar; skipped" % tag)
            continue
        for name in sidecars:
            raw, _ = http_get(assets[name]["browser_download_url"], accept="application/octet-stream")
            sc = json.loads(raw)
            where = "%s/%s" % (tag, name)
            validate_sidecar(sc, where)
            if tag != "%s-%s" % (sc["name"], sc["version"]):
                fail("%s: tag does not match %s-%s" % (where, sc["name"], sc["version"]))
            archive = assets.get(sc["file"])
            if archive is None:
                fail("%s: archive asset %s is missing" % (where, sc["file"]))
            if archive["size"] != sc["size"]:
                fail("%s: size mismatch (asset %d, sidecar %d)" % (where, archive["size"], sc["size"]))
            digest = archive.get("digest") or ""
            if digest.startswith("sha256:") and digest[7:] != sc["sha256"]:
                fail("%s: sha256 mismatch (GitHub %s, sidecar %s)" % (where, digest[7:], sc["sha256"]))
            entries.append(entry_from(sc, archive["browser_download_url"]))
    return entries


def from_local(directory, base_url):
    import hashlib
    entries = []
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".package.json"):
            continue
        with open(os.path.join(directory, name)) as fh:
            sc = json.load(fh)
        validate_sidecar(sc, name)
        path = os.path.join(directory, sc["file"])
        if os.path.exists(path):
            h = hashlib.sha256()
            with open(path, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    h.update(chunk)
            if h.hexdigest() != sc["sha256"] or os.path.getsize(path) != sc["size"]:
                fail("%s: does not match %s" % (name, sc["file"]))
        entries.append(entry_from(sc, base_url.rstrip("/") + "/" + sc["file"]))
    return entries


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", help="OWNER/NAME (GitHub mode)")
    ap.add_argument("--local-dir", help="directory with *.package.json sidecars (local mode)")
    ap.add_argument("--base-url", default="https://example.invalid/", help="URL prefix in local mode")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if bool(args.repo) == bool(args.local_dir):
        fail("use exactly one of --repo or --local-dir")
    entries = from_github(args.repo) if args.repo else from_local(args.local_dir, args.base_url)

    seen = set()
    for e in entries:
        key = (e["name"], e["version"], e["arch"])
        if key in seen:
            fail("duplicate package %s %s %s" % key)
        seen.add(key)
    entries.sort(key=lambda e: (e["name"], e["channel"], version_key(e["version"])))

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "packages": [{k: e[k] for k in ENTRY_KEYS} for e in entries],
    }
    with open(args.out, "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("manifest: %d package(s) -> %s" % (len(entries), args.out), file=sys.stderr)


if __name__ == "__main__":
    main()
