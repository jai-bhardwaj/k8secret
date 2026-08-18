#!/usr/bin/env python3
"""What the active context is made of — names, paths and presence, never contents.

Printed by diagnose.sh. A connection that works on one Mac and not another is
usually something this shows: a file that is not there, or an exec plugin that
is not installed.
"""
import os
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("  (PyYAML not installed; skipping kubeconfig shape)")
    sys.exit(0)

paths = os.environ.get("KUBECONFIG") or os.path.expanduser("~/.kube/config")
endpoint = None

for path in paths.split(":"):
    if not os.path.exists(path):
        print(f"{path}: MISSING")
        continue
    try:
        cfg = yaml.safe_load(open(path)) or {}
    except Exception as exc:                                  # noqa: BLE001
        print(f"{path}: unreadable ({exc})")
        continue

    current = cfg.get("current-context")
    print(f"{path}  current-context={current}")
    ctx = next((c for c in cfg.get("contexts", []) if c.get("name") == current), None)
    if not ctx:
        continue
    want_cluster = ctx.get("context", {}).get("cluster")
    want_user = ctx.get("context", {}).get("user")

    for cluster in cfg.get("clusters", []):
        if cluster.get("name") != want_cluster:
            continue
        body = cluster.get("cluster", {})
        server = body.get("server", "")
        print(f"  server: {server}")
        host = server.split("://")[-1]
        endpoint = host if ":" in host else host + ":443"
        for key in ("certificate-authority-data", "certificate-authority"):
            if key not in body:
                continue
            value = body[key]
            if key.endswith("-data"):
                print(f"  {key}: <inline, {len(value)} base64 chars>")
            else:
                expanded = os.path.expanduser(value)
                print(f"  {key}: {value}  exists={os.path.exists(expanded)}")
        if body.get("insecure-skip-tls-verify"):
            print("  insecure-skip-tls-verify: true")

    for user in cfg.get("users", []):
        if user.get("name") != want_user:
            continue
        body = user.get("user", {})
        print(f"  user auth keys: {sorted(body.keys())}")
        for key in ("client-certificate", "client-key", "tokenFile"):
            if key in body:
                expanded = os.path.expanduser(body[key])
                print(f"  {key}: {body[key]}  exists={os.path.exists(expanded)}")
        if "exec" in body:
            command = body["exec"].get("command", "")
            found = subprocess.run(["which", command], capture_output=True,
                                   text=True).stdout.strip()
            print(f"  exec command: {command}  found={found or 'NOT ON PATH'}")

if endpoint:
    with open(os.environ.get("K8SECRET_ENDPOINT_OUT", "/dev/null"), "w") as handle:
        handle.write(endpoint)
