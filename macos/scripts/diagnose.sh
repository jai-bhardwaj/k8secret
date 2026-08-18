#!/usr/bin/env bash
# Everything needed to place a K8Secret connection failure, in one paste.
#
# A connection that fails on one Mac and works on another is almost always
# something about the machine — its openssl, its macOS, or a kubeconfig naming
# files that live somewhere else. This gathers those, plus a live TLS trace, so
# a bug report arrives with the answer already in it.
#
#   ./macos/scripts/diagnose.sh
#
# Prints versions, hostnames, byte counts and which files exist. It never reads
# a key, a token or a secret's contents, so the output is safe to paste into an
# issue — check it yourself before you do.
APP="${1:-/Applications/K8Secret.app}"
BIN="$APP/Contents/MacOS/k8secret"
LOG="$(mktemp)"

echo "K8Secret:  $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?')"
echo "macOS:     $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "openssl:   $(/usr/bin/openssl version 2>&1)"
echo "context:   $(kubectl config current-context 2>/dev/null || echo '(kubectl not present)')"

echo
echo "--- kubeconfig shape (no secret material) ---"
python3 - <<'PY'
import os, glob, subprocess
paths = os.environ.get("KUBECONFIG") or os.path.expanduser("~/.kube/config")
for p in paths.split(":"):
    if not os.path.exists(p):
        print(f"{p}: MISSING"); continue
    try:
        import yaml
        cfg = yaml.safe_load(open(p))
    except Exception as e:
        print(f"{p}: unreadable ({e})"); continue
    cur = cfg.get("current-context")
    print(f"{p}  current-context={cur}")
    ctx = next((c for c in cfg.get("contexts", []) if c.get("name") == cur), None)
    if not ctx: continue
    want_cluster = ctx.get("context", {}).get("cluster")
    want_user = ctx.get("context", {}).get("user")
    for c in cfg.get("clusters", []):
        if c.get("name") != want_cluster: continue
        cl = c.get("cluster", {})
        print(f"  server: {cl.get('server')}")
        for k in ("certificate-authority", "certificate-authority-data"):
            if k in cl:
                v = cl[k]
                if k.endswith("-data"):
                    print(f"  {k}: <inline, {len(v)} b64 chars>")
                else:
                    print(f"  {k}: {v}  exists={os.path.exists(os.path.expanduser(v))}")
        if cl.get("insecure-skip-tls-verify"): print("  insecure-skip-tls-verify: true")
    for u in cfg.get("users", []):
        if u.get("name") != want_user: continue
        us = u.get("user", {})
        print(f"  user auth keys: {sorted(us.keys())}")
        for k in ("client-certificate", "client-key", "tokenFile"):
            if k in us:
                print(f"  {k}: {us[k]}  exists={os.path.exists(os.path.expanduser(us[k]))}")
        if "exec" in us:
            cmd = us["exec"].get("command", "")
            which = subprocess.run(["which", cmd], capture_output=True, text=True).stdout.strip()
            print(f"  exec command: {cmd}  found={which or 'NOT ON PATH'}")
PY

echo
echo "--- TLS trace ---"
K8SECRET_TLS_DEBUG=1 "$BIN" > "$LOG" 2>&1 &
PID=$!
sleep 15
kill -9 $PID 2>/dev/null
grep -E "challenge:|serverTrust:|clientCert:|createIdentity:|buildPKCS12:|request FAILED|NSError|localizedDescription" "$LOG" | head -30
echo
LINES=$(wc -l < "$LOG" | tr -d ' ')
echo "trace lines captured: $LINES"
if [ "$LINES" = "0" ]; then
  echo
  echo "No trace at all means the app never got as far as a TLS challenge —"
  echo "either it did not launch, or it is an older build without tracing."
fi
rm -f "$LOG"
